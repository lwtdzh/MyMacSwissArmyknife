import AppKit
import Combine
import Darwin
import Foundation

@MainActor
protocol InProcessModule: AnyObject {
    var id: ModuleID { get }
    var isRunning: Bool { get }
    var failureMessage: String? { get }
    var requiresUserAction: Bool { get }
    var onStateChange: (() -> Void)? { get set }

    func start()
    func stop()
    func settingsDidChange()
}

extension InProcessModule {
    var requiresUserAction: Bool { false }
}

protocol ModuleRuntime {
    func isRunning(bundleIdentifier: String) -> Bool
    func launch(bundleURL: URL) async throws
    func terminate(bundleIdentifier: String)
    func forceTerminate(bundleIdentifier: String)
}

struct WorkspaceModuleRuntime: ModuleRuntime {
    func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    func launch(bundleURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        )
    }

    func terminate(bundleIdentifier: String) {
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ) {
            application.terminate()
        }
    }

    func forceTerminate(bundleIdentifier: String) {
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ) {
            if !application.forceTerminate() {
                Darwin.kill(application.processIdentifier, SIGKILL)
            }
        }
    }
}

@MainActor
final class ModuleSupervisor: ObservableObject {
    @Published private(set) var health: [ModuleID: ModuleHealth]

    private let definitions: [ModuleDefinition]
    private let store: ModuleStateStore
    private let runtime: ModuleRuntime
    private let inProcessModules: [ModuleID: any InProcessModule]
    private let bundleURL: (String) -> URL?
    private var launching = Set<ModuleID>()
    private var pendingSettingsRestarts: [ModuleID: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var isShuttingDown = false

    init(
        definitions: [ModuleDefinition] = ModuleDefinition.builtIns,
        store: ModuleStateStore,
        runtime: ModuleRuntime = WorkspaceModuleRuntime(),
        inProcessModules: [ModuleID: any InProcessModule] = [:],
        bundleURL: @escaping (String) -> URL? = ModuleSupervisor.embeddedBundleURL
    ) {
        self.definitions = definitions
        self.store = store
        self.runtime = runtime
        self.inProcessModules = inProcessModules
        self.bundleURL = bundleURL
        health = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, .stopped) })

        for module in inProcessModules.values {
            module.onStateChange = { [weak self] in
                self?.reconcile()
            }
        }

        store.$configurations
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reconcile()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        isShuttingDown = false
        reconcile()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
    }

    func reconcile() {
        guard !isShuttingDown else { return }
        for definition in definitions {
            switch definition.execution {
            case .inProcess:
                reconcileInProcess(definition)
            case .bundledApplication(let bundleIdentifier, let bundleName):
                reconcileApplication(
                    definition,
                    bundleIdentifier: bundleIdentifier,
                    bundleName: bundleName
                )
            }
        }
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        timer?.invalidate()
        timer = nil
        pendingSettingsRestarts.values.forEach { $0.cancel() }
        pendingSettingsRestarts.removeAll()
        launching.removeAll()

        for definition in definitions {
            switch definition.execution {
            case .inProcess:
                inProcessModules[definition.id]?.stop()
            case .bundledApplication(let bundleIdentifier, _):
                runtime.forceTerminate(bundleIdentifier: bundleIdentifier)
            }
            health[definition.id] = .stopped
        }
    }

    func restart(_ id: ModuleID) {
        guard !isShuttingDown else { return }
        guard let definition = definitions.first(where: { $0.id == id }) else { return }
        guard store.configuration(for: id).isEnabled else { return }

        switch definition.execution {
        case .inProcess:
            guard let module = inProcessModules[id] else { return }
            module.stop()
            health[id] = .restarting
            module.start()
            updateHealth(for: module)
        case .bundledApplication(let bundleIdentifier, let bundleName):
            runtime.terminate(bundleIdentifier: bundleIdentifier)
            launching.remove(id)
            health[id] = .restarting

            Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !isShuttingDown else { return }
                launchApplication(
                    definition,
                    bundleIdentifier: bundleIdentifier,
                    bundleName: bundleName,
                    restarting: true
                )
            }
        }
    }

    func settingsDidChange(for id: ModuleID) {
        guard !isShuttingDown else { return }
        if let module = inProcessModules[id] {
            module.settingsDidChange()
            reconcile()
            return
        }

        pendingSettingsRestarts[id]?.cancel()
        pendingSettingsRestarts[id] = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            pendingSettingsRestarts[id] = nil
            restart(id)
        }
    }

    private func reconcileInProcess(_ definition: ModuleDefinition) {
        guard let module = inProcessModules[definition.id] else {
            health[definition.id] = .failed("Module driver is missing")
            return
        }

        if store.configuration(for: definition.id).isEnabled {
            module.start()
            updateHealth(for: module)
        } else {
            module.stop()
            health[definition.id] = .stopped
        }
    }

    private func updateHealth(for module: any InProcessModule) {
        if module.isRunning {
            health[module.id] = .running
        } else if let message = module.failureMessage {
            health[module.id] = module.requiresUserAction
                ? .actionRequired(message)
                : .failed(message)
        } else {
            health[module.id] = .starting
        }
    }

    private func reconcileApplication(
        _ definition: ModuleDefinition,
        bundleIdentifier: String,
        bundleName: String
    ) {
        let configuration = store.configuration(for: definition.id)
        let isRunning = runtime.isRunning(bundleIdentifier: bundleIdentifier)

        if !configuration.isEnabled {
            if isRunning {
                runtime.terminate(bundleIdentifier: bundleIdentifier)
            }
            health[definition.id] = .stopped
        } else if isRunning {
            launching.remove(definition.id)
            health[definition.id] = .running
        } else if !launching.contains(definition.id) {
            launchApplication(
                definition,
                bundleIdentifier: bundleIdentifier,
                bundleName: bundleName,
                restarting: health[definition.id] == .running
            )
        }
    }

    private func launchApplication(
        _ definition: ModuleDefinition,
        bundleIdentifier: String,
        bundleName: String,
        restarting: Bool
    ) {
        guard !isShuttingDown else { return }
        guard let url = bundleURL(bundleName) else {
            health[definition.id] = .failed("Module bundle is missing")
            return
        }

        launching.insert(definition.id)
        health[definition.id] = restarting ? .restarting : .starting
        Task {
            do {
                try await runtime.launch(bundleURL: url)
                guard !isShuttingDown else {
                    runtime.forceTerminate(bundleIdentifier: bundleIdentifier)
                    launching.remove(definition.id)
                    return
                }
                try await Task.sleep(for: .milliseconds(750))
                guard !isShuttingDown else {
                    runtime.forceTerminate(bundleIdentifier: bundleIdentifier)
                    launching.remove(definition.id)
                    return
                }
                if runtime.isRunning(bundleIdentifier: bundleIdentifier) {
                    health[definition.id] = .running
                } else {
                    health[definition.id] = .failed("Module exited during startup")
                }
            } catch {
                if !isShuttingDown {
                    health[definition.id] = .failed(error.localizedDescription)
                }
            }
            launching.remove(definition.id)
        }
    }

    nonisolated private static func embeddedBundleURL(
        for bundleName: String
    ) -> URL? {
        Bundle.main.resourceURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true)
    }
}
