import AppKit
import Darwin
import Foundation

struct BlockedApplication: Codable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let bundleIdentifier: String
    let path: String

    init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String,
        path: String
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}

struct AppBlockerConfigurationStore {
    static let defaultKey = "appBlocker.blockedApplications.v1"

    let defaults: UserDefaults
    let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = Self.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [BlockedApplication] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BlockedApplication].self, from: data)) ?? []
    }

    func save(_ applications: [BlockedApplication]) throws {
        defaults.set(try JSONEncoder().encode(applications), forKey: key)
    }
}

struct AppBlockerRunningApplication: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let bundleURL: URL?
}

@MainActor
protocol AppBlockerRuntime: AnyObject {
    var runningApplications: [AppBlockerRunningApplication] { get }

    func observeLaunches(
        _ handler: @escaping (AppBlockerRunningApplication) -> Void
    ) -> NSObjectProtocol
    func removeObserver(_ observer: NSObjectProtocol)
    func forceTerminate(_ application: AppBlockerRunningApplication) -> Bool
}

@MainActor
final class WorkspaceAppBlockerRuntime: AppBlockerRuntime {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var runningApplications: [AppBlockerRunningApplication] {
        workspace.runningApplications.map(Self.snapshot)
    }

    func observeLaunches(
        _ handler: @escaping (AppBlockerRunningApplication) -> Void
    ) -> NSObjectProtocol {
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }
            handler(Self.snapshot(application))
        }
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        workspace.notificationCenter.removeObserver(observer)
    }

    func forceTerminate(_ application: AppBlockerRunningApplication) -> Bool {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        if let expectedBundleIdentifier = application.bundleIdentifier {
            guard let running = NSRunningApplication(
                processIdentifier: application.processIdentifier
            ), running.bundleIdentifier?.caseInsensitiveCompare(
                expectedBundleIdentifier
            ) == .orderedSame else {
                return false
            }
        }
        if Darwin.kill(application.processIdentifier, SIGKILL) == 0 {
            return true
        }
        guard let running = NSRunningApplication(
            processIdentifier: application.processIdentifier
        ), running.bundleIdentifier == application.bundleIdentifier else {
            return false
        }
        return running.forceTerminate()
    }

    nonisolated private static func snapshot(
        _ application: NSRunningApplication
    ) -> AppBlockerRunningApplication {
        AppBlockerRunningApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            bundleURL: application.bundleURL
        )
    }
}

enum AppBlockerAddResult: Equatable {
    case added
    case alreadyBlocked
    case invalidApplication
    case cannotBlockThisApp
}

@MainActor
final class AppBlockerModule: ObservableObject, InProcessModule {
    let id = ModuleID.appBlocker

    @Published private(set) var blockedApplications: [BlockedApplication]
    @Published private(set) var isRunning = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var lastBlockError: String?

    var onStateChange: (() -> Void)?

    private let store: AppBlockerConfigurationStore
    private let runtime: any AppBlockerRuntime
    private let hostBundleIdentifier: String?
    private let hostProcessIdentifier: pid_t
    private var launchObserver: NSObjectProtocol?
    private var sweepTimer: Timer?

    init(
        store: AppBlockerConfigurationStore = AppBlockerConfigurationStore(),
        runtime: (any AppBlockerRuntime)? = nil,
        hostBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        hostProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.store = store
        self.runtime = runtime ?? WorkspaceAppBlockerRuntime()
        self.hostBundleIdentifier = hostBundleIdentifier
        self.hostProcessIdentifier = hostProcessIdentifier
        blockedApplications = store.load()
    }

    func start() {
        guard !isRunning else {
            enforceBlockList()
            return
        }

        launchObserver = runtime.observeLaunches { [weak self] application in
            self?.blockIfNeeded(application)
        }
        sweepTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.enforceBlockList()
            }
        }
        isRunning = true
        failureMessage = nil
        enforceBlockList()
        onStateChange?()
    }

    func stop() {
        guard isRunning || launchObserver != nil || sweepTimer != nil else { return }
        if let launchObserver {
            runtime.removeObserver(launchObserver)
        }
        launchObserver = nil
        sweepTimer?.invalidate()
        sweepTimer = nil
        isRunning = false
        failureMessage = nil
        lastBlockError = nil
        onStateChange?()
    }

    func settingsDidChange() {
        blockedApplications = store.load()
        if isRunning {
            enforceBlockList()
        }
    }

    @discardableResult
    func addApplication(_ url: URL) -> AppBlockerAddResult {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: standardizedURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return .invalidApplication
        }
        guard bundleIdentifier.caseInsensitiveCompare(
            hostBundleIdentifier ?? ""
        ) != .orderedSame else {
            return .cannotBlockThisApp
        }
        guard !blockedApplications.contains(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }) else {
            return .alreadyBlocked
        }

        let displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            standardizedURL.deletingPathExtension().lastPathComponent
        var updated = blockedApplications
        updated.append(
            BlockedApplication(
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                path: standardizedURL.path
            )
        )
        updated.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        save(updated)
        if isRunning {
            enforceBlockList()
        }
        return .added
    }

    func removeApplications(at offsets: IndexSet) {
        var updated = blockedApplications
        for index in offsets.sorted(by: >) where updated.indices.contains(index) {
            updated.remove(at: index)
        }
        save(updated)
    }

    func enforceBlockList() {
        for application in runtime.runningApplications {
            blockIfNeeded(application)
        }
    }

    private func blockIfNeeded(_ application: AppBlockerRunningApplication) {
        guard isRunning,
              application.processIdentifier != hostProcessIdentifier,
              let bundleIdentifier = application.bundleIdentifier,
              bundleIdentifier.caseInsensitiveCompare(
                hostBundleIdentifier ?? ""
              ) != .orderedSame,
              let blocked = blockedApplications.first(where: {
                  $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier)
                      == .orderedSame
              }) else {
            return
        }

        if runtime.forceTerminate(application) {
            lastBlockError = nil
        } else {
            lastBlockError = "Unable to stop \(blocked.displayName)."
        }
    }

    private func save(_ applications: [BlockedApplication]) {
        do {
            try store.save(applications)
            blockedApplications = applications
            failureMessage = nil
        } catch {
            failureMessage = "Unable to save settings: \(error.localizedDescription)"
        }
    }
}
