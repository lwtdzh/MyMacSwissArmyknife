import Foundation
import XCTest
@testable import MyMacSwissArmyknife

@MainActor
final class ModuleSupervisorTests: XCTestCase {
    func testEnabledMissingProcessIsLaunched() async {
        let definition = makeDefinition()
        let runtime = ModuleRuntimeSpy()
        runtime.bundleIdentifierToStart = definition.bundleIdentifier
        let launched = expectation(description: "module launched")
        runtime.onLaunch = { launched.fulfill() }
        let store = makeStore(definition: definition)
        let supervisor = ModuleSupervisor(
            definitions: [definition],
            store: store,
            runtime: runtime,
            bundleURL: { URL(fileURLWithPath: "/tmp/\($0)") }
        )

        store.setEnabled(true, for: definition.id)

        await fulfillment(of: [launched], timeout: 2)
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(runtime.launchCount, 1)
        XCTAssertEqual(supervisor.health[definition.id], .running)
    }

    func testProcessThatExitsDuringStartupIsNotReportedHealthy() async {
        let definition = makeDefinition()
        let runtime = ModuleRuntimeSpy()
        let store = makeStore(definition: definition)
        let supervisor = ModuleSupervisor(
            definitions: [definition],
            store: store,
            runtime: runtime,
            bundleURL: { URL(fileURLWithPath: "/tmp/\($0)") }
        )

        store.setEnabled(true, for: definition.id)
        try? await Task.sleep(for: .milliseconds(850))

        XCTAssertEqual(
            supervisor.health[definition.id],
            .failed("Module exited during startup")
        )
    }

    func testDisabledRunningProcessIsTerminated() {
        let definition = makeDefinition()
        let runtime = ModuleRuntimeSpy()
        runtime.runningBundleIdentifiers.insert(definition.bundleIdentifier)
        let store = makeStore(definition: definition)
        let supervisor = ModuleSupervisor(
            definitions: [definition],
            store: store,
            runtime: runtime,
            bundleURL: { URL(fileURLWithPath: "/tmp/\($0)") }
        )

        supervisor.reconcile()

        XCTAssertEqual(runtime.terminatedBundleIdentifiers, [definition.bundleIdentifier])
        XCTAssertEqual(supervisor.health[definition.id], .stopped)
    }

    func testEnabledInProcessModuleStartsWithoutLaunchingApplication() {
        let definition = makeInProcessDefinition()
        let module = InProcessModuleSpy(id: definition.id)
        let runtime = ModuleRuntimeSpy()
        let store = makeStore(definition: definition)
        let supervisor = ModuleSupervisor(
            definitions: [definition],
            store: store,
            runtime: runtime,
            inProcessModules: [definition.id: module]
        )

        store.setEnabled(true, for: definition.id)
        supervisor.reconcile()

        XCTAssertEqual(module.startCount, 1)
        XCTAssertEqual(runtime.launchCount, 0)
        XCTAssertEqual(supervisor.health[definition.id], .running)
    }

    func testInProcessSettingsApplyWithoutProcessRestart() {
        let definition = makeInProcessDefinition()
        let module = InProcessModuleSpy(id: definition.id)
        module.isRunning = true
        let store = makeStore(definition: definition)
        store.setEnabled(true, for: definition.id)
        let supervisor = ModuleSupervisor(
            definitions: [definition],
            store: store,
            inProcessModules: [definition.id: module]
        )

        supervisor.settingsDidChange(for: definition.id)

        XCTAssertEqual(module.settingsChangeCount, 1)
        XCTAssertEqual(module.stopCount, 0)
        XCTAssertEqual(supervisor.health[definition.id], .running)
    }

    private func makeDefinition() -> ModuleDefinition {
        ModuleDefinition(
            id: .scrollReverser,
            displayName: "Test",
            summary: "Test module",
            systemImage: "gear",
            execution: .bundledApplication(
                bundleIdentifier: "com.example.test-module",
                bundleName: "Test.app"
            )
        )
    }

    private func makeInProcessDefinition() -> ModuleDefinition {
        ModuleDefinition(
            id: .scrollReverser,
            displayName: "Test",
            summary: "Test module",
            systemImage: "gear",
            execution: .inProcess
        )
    }

    private func makeStore(definition: ModuleDefinition) -> ModuleStateStore {
        let name = "MyMacSwissArmyknifeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ModuleStateStore(
            definitions: [definition],
            defaults: defaults,
            bootSession: BootSessionStubForSupervisor(id: "boot-a"),
            loginItemManager: LoginItemNoop()
        )
    }
}

private extension ModuleDefinition {
    var bundleIdentifier: String {
        guard case .bundledApplication(let identifier, _) = execution else {
            return ""
        }
        return identifier
    }
}

private struct BootSessionStubForSupervisor: BootSessionProviding {
    let id: String
    var currentBootID: String { id }
}

private struct LoginItemNoop: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {}
}

private final class ModuleRuntimeSpy: ModuleRuntime {
    var runningBundleIdentifiers = Set<String>()
    private(set) var launchCount = 0
    private(set) var terminatedBundleIdentifiers: [String] = []
    var bundleIdentifierToStart: String?
    var onLaunch: (() -> Void)?

    func isRunning(bundleIdentifier: String) -> Bool {
        runningBundleIdentifiers.contains(bundleIdentifier)
    }

    func launch(bundleURL: URL) async throws {
        launchCount += 1
        if let bundleIdentifierToStart {
            runningBundleIdentifiers.insert(bundleIdentifierToStart)
        }
        onLaunch?()
    }

    func terminate(bundleIdentifier: String) {
        terminatedBundleIdentifiers.append(bundleIdentifier)
        runningBundleIdentifiers.remove(bundleIdentifier)
    }
}

@MainActor
private final class InProcessModuleSpy: InProcessModule {
    let id: ModuleID
    var isRunning = false
    var failureMessage: String?
    var onStateChange: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var settingsChangeCount = 0

    init(id: ModuleID) {
        self.id = id
    }

    func start() {
        startCount += 1
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func settingsDidChange() {
        settingsChangeCount += 1
    }
}
