import AppKit
import Foundation
import XCTest
@testable import MyMacSwissArmyknife

final class AppBlockerConfigurationStoreTests: XCTestCase {
    func testConfigurationRoundTrips() throws {
        let defaults = makeDefaults()
        let store = AppBlockerConfigurationStore(defaults: defaults)
        let expected = [
            BlockedApplication(
                displayName: "Focus Test",
                bundleIdentifier: "com.example.FocusTest",
                path: "/Applications/Focus Test.app"
            )
        ]

        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppBlockerConfigurationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

@MainActor
final class AppBlockerModuleTests: XCTestCase {
    func testStartTerminatesAlreadyRunningBlockedApplication() throws {
        let fixture = try makeApplication(
            name: "Blocked",
            bundleIdentifier: "com.example.Blocked"
        )
        let runtime = AppBlockerRuntimeSpy()
        runtime.applications = [
            AppBlockerRunningApplication(
                processIdentifier: 101,
                bundleIdentifier: "com.example.Blocked",
                bundleURL: fixture
            )
        ]
        let module = makeModule(runtime: runtime)
        XCTAssertEqual(module.addApplication(fixture), .added)

        module.start()

        XCTAssertEqual(runtime.terminatedProcessIdentifiers, [101])
        XCTAssertTrue(module.isRunning)
    }

    func testLaunchNotificationImmediatelyTerminatesBlockedApplication() throws {
        let fixture = try makeApplication(
            name: "Blocked",
            bundleIdentifier: "com.example.Blocked"
        )
        let runtime = AppBlockerRuntimeSpy()
        let module = makeModule(runtime: runtime)
        XCTAssertEqual(module.addApplication(fixture), .added)
        module.start()

        runtime.simulateLaunch(
            AppBlockerRunningApplication(
                processIdentifier: 202,
                bundleIdentifier: "com.example.Blocked",
                bundleURL: fixture
            )
        )

        XCTAssertEqual(runtime.terminatedProcessIdentifiers, [202])
    }

    func testUnblockedAndHostApplicationsAreNeverTerminated() throws {
        let fixture = try makeApplication(
            name: "Blocked",
            bundleIdentifier: "com.example.Blocked"
        )
        let runtime = AppBlockerRuntimeSpy()
        let module = makeModule(
            runtime: runtime,
            hostBundleIdentifier: "com.example.Host",
            hostProcessIdentifier: 303
        )
        XCTAssertEqual(module.addApplication(fixture), .added)
        module.start()

        runtime.simulateLaunch(
            AppBlockerRunningApplication(
                processIdentifier: 303,
                bundleIdentifier: "com.example.Blocked",
                bundleURL: fixture
            )
        )
        runtime.simulateLaunch(
            AppBlockerRunningApplication(
                processIdentifier: 404,
                bundleIdentifier: "com.example.Host",
                bundleURL: nil
            )
        )
        runtime.simulateLaunch(
            AppBlockerRunningApplication(
                processIdentifier: 505,
                bundleIdentifier: "com.example.Allowed",
                bundleURL: nil
            )
        )

        XCTAssertTrue(runtime.terminatedProcessIdentifiers.isEmpty)
    }

    func testStopRemovesObserverAndAllowsLaterLaunches() throws {
        let fixture = try makeApplication(
            name: "Blocked",
            bundleIdentifier: "com.example.Blocked"
        )
        let runtime = AppBlockerRuntimeSpy()
        let module = makeModule(runtime: runtime)
        XCTAssertEqual(module.addApplication(fixture), .added)
        module.start()

        module.stop()
        runtime.simulateLaunch(
            AppBlockerRunningApplication(
                processIdentifier: 606,
                bundleIdentifier: "com.example.Blocked",
                bundleURL: fixture
            )
        )

        XCTAssertEqual(runtime.removeObserverCount, 1)
        XCTAssertTrue(runtime.terminatedProcessIdentifiers.isEmpty)
        XCTAssertFalse(module.isRunning)
    }

    func testSettingsReloadImmediatelyEnforcesNewBlock() throws {
        let fixture = try makeApplication(
            name: "Blocked",
            bundleIdentifier: "com.example.Blocked"
        )
        let defaults = makeDefaults()
        let configurationStore = AppBlockerConfigurationStore(defaults: defaults)
        let runtime = AppBlockerRuntimeSpy()
        runtime.applications = [
            AppBlockerRunningApplication(
                processIdentifier: 707,
                bundleIdentifier: "com.example.Blocked",
                bundleURL: fixture
            )
        ]
        let module = AppBlockerModule(
            store: configurationStore,
            runtime: runtime,
            hostBundleIdentifier: "com.example.Host",
            hostProcessIdentifier: 1
        )
        module.start()
        XCTAssertTrue(runtime.terminatedProcessIdentifiers.isEmpty)

        try configurationStore.save([
            BlockedApplication(
                displayName: "Blocked",
                bundleIdentifier: "com.example.Blocked",
                path: fixture.path
            )
        ])
        module.settingsDidChange()

        XCTAssertEqual(runtime.terminatedProcessIdentifiers, [707])
    }

    func testDuplicateAndHostApplicationAreRejected() throws {
        let blocked = try makeApplication(
            name: "Blocked",
            bundleIdentifier: "com.example.Blocked"
        )
        let host = try makeApplication(
            name: "Host",
            bundleIdentifier: "com.example.Host"
        )
        let module = makeModule(
            runtime: AppBlockerRuntimeSpy(),
            hostBundleIdentifier: "com.example.Host"
        )

        XCTAssertEqual(module.addApplication(blocked), .added)
        XCTAssertEqual(module.addApplication(blocked), .alreadyBlocked)
        XCTAssertEqual(module.addApplication(host), .cannotBlockThisApp)
        XCTAssertEqual(module.blockedApplications.count, 1)
    }

    func testProductionRuntimeForceTerminatesRealProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        XCTAssertTrue(process.isRunning)

        let runtime = WorkspaceAppBlockerRuntime()
        let terminated = runtime.forceTerminate(
            AppBlockerRunningApplication(
                processIdentifier: process.processIdentifier,
                bundleIdentifier: nil,
                bundleURL: nil
            )
        )
        process.waitUntilExit()

        XCTAssertTrue(terminated)
        XCTAssertFalse(process.isRunning)
        XCTAssertNotEqual(process.terminationStatus, 0)
    }

    private func makeModule(
        runtime: AppBlockerRuntimeSpy,
        hostBundleIdentifier: String = "com.example.Host",
        hostProcessIdentifier: pid_t = 1
    ) -> AppBlockerModule {
        AppBlockerModule(
            store: AppBlockerConfigurationStore(defaults: makeDefaults()),
            runtime: runtime,
            hostBundleIdentifier: hostBundleIdentifier,
            hostProcessIdentifier: hostProcessIdentifier
        )
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppBlockerModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeApplication(
        name: String,
        bundleIdentifier: String
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return bundleURL
    }
}

@MainActor
private final class AppBlockerRuntimeSpy: AppBlockerRuntime {
    var applications: [AppBlockerRunningApplication] = []
    var terminationSucceeds = true
    private(set) var terminatedProcessIdentifiers: [pid_t] = []
    private(set) var removeObserverCount = 0

    private var launchHandler: ((AppBlockerRunningApplication) -> Void)?
    private let observer = NSObject()

    var runningApplications: [AppBlockerRunningApplication] {
        applications
    }

    func observeLaunches(
        _ handler: @escaping (AppBlockerRunningApplication) -> Void
    ) -> NSObjectProtocol {
        launchHandler = handler
        return observer
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        launchHandler = nil
        removeObserverCount += 1
    }

    func forceTerminate(_ application: AppBlockerRunningApplication) -> Bool {
        terminatedProcessIdentifiers.append(application.processIdentifier)
        return terminationSucceeds
    }

    func simulateLaunch(_ application: AppBlockerRunningApplication) {
        launchHandler?(application)
    }
}
