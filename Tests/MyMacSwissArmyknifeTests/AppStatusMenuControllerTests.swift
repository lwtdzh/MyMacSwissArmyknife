import AppKit
import Combine
import IOKit.pwr_mgt
import XCTest
@testable import MyMacSwissArmyknife

@MainActor
final class AppStatusMenuControllerTests: XCTestCase {
    func testAppBlockerMenuStateMatchesPublishedConfiguration() {
        let defaults = makeDefaults()
        let store = ModuleStateStore(
            defaults: defaults,
            bootSession: MenuBootSessionStub(id: "boot-a"),
            loginItemManager: MenuLoginItemNoop()
        )
        let bridge = ClipyEnhancedBridge(
            center: DistributedNotificationCenter(),
            snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
        )
        let controller = AppStatusMenuController(
            store: store,
            bridge: bridge,
            appBlocker: makeAppBlocker(),
            keepAwake: KeepAwakeModule(
                powerManager: MenuKeepAwakePowerManager()
            )
        )

        XCTAssertEqual(controller.displayedModuleState(.appBlocker), .off)

        store.setEnabled(true, for: .appBlocker)

        XCTAssertTrue(store.configuration(for: .appBlocker).isEnabled)
        XCTAssertEqual(controller.displayedModuleState(.appBlocker), .on)

        store.setEnabled(false, for: .appBlocker)

        XCTAssertFalse(store.configuration(for: .appBlocker).isEnabled)
        XCTAssertEqual(controller.displayedModuleState(.appBlocker), .off)
    }

    func testKeepAwakeMenuTracksTemporaryModuleState() {
        let store = ModuleStateStore(
            defaults: makeDefaults(),
            bootSession: MenuBootSessionStub(id: "boot-a"),
            loginItemManager: MenuLoginItemNoop()
        )
        let bridge = ClipyEnhancedBridge(
            center: DistributedNotificationCenter(),
            snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
        )
        let keepAwake = KeepAwakeModule(
            powerManager: MenuKeepAwakePowerManager()
        )
        let controller = AppStatusMenuController(
            store: store,
            bridge: bridge,
            appBlocker: makeAppBlocker(),
            keepAwake: keepAwake
        )

        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)

        keepAwake.setBlockingSleep(true)

        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)

        keepAwake.setBlockingLockScreen(true)

        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .on)

        keepAwake.stop()

        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)
    }

    func testKeepAwakePrimaryActionEnablesAndDisablesAllControls() {
        let store = ModuleStateStore(
            defaults: makeDefaults(),
            bootSession: MenuBootSessionStub(id: "boot-a"),
            loginItemManager: MenuLoginItemNoop()
        )
        let bridge = ClipyEnhancedBridge(
            center: DistributedNotificationCenter(),
            snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
        )
        let keepAwake = KeepAwakeModule(
            powerManager: MenuKeepAwakePowerManager()
        )
        let controller = AppStatusMenuController(
            store: store,
            bridge: bridge,
            appBlocker: makeAppBlocker(),
            keepAwake: keepAwake
        )

        controller.performKeepAwakePrimaryAction()

        XCTAssertTrue(keepAwake.isBlockingSleep)
        XCTAssertTrue(keepAwake.isBlockingLockScreen)
        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .on)

        controller.performKeepAwakePrimaryAction()

        XCTAssertFalse(keepAwake.isBlockingSleep)
        XCTAssertFalse(keepAwake.isBlockingLockScreen)
        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)
    }

    func testKeepAwakeChildActionsEnforceDependencyAndUpdateAllCheckmarks() {
        let keepAwake = KeepAwakeModule(
            powerManager: MenuKeepAwakePowerManager()
        )
        let controller = makeController(
            appBlocker: makeAppBlocker(),
            keepAwake: keepAwake
        )
        let lockScreenAction = NSSelectorFromString("toggleBlockLockScreen:")
        let sleepAction = NSSelectorFromString("toggleBlockSleep:")

        controller.perform(lockScreenAction, with: NSMenuItem())
        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .on)

        controller.perform(lockScreenAction, with: NSMenuItem())
        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)

        controller.performKeepAwakePrimaryAction()
        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)

        controller.perform(sleepAction, with: NSMenuItem())
        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)

        controller.perform(lockScreenAction, with: NSMenuItem())
        controller.perform(sleepAction, with: NSMenuItem())
        XCTAssertEqual(controller.displayedKeepAwakeStates().parent, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)
    }

    func testEmptyAppBlockerSubmenuShowsDisabledPlaceholder() {
        let controller = makeController(appBlocker: makeAppBlocker())

        let items = controller.displayedAppBlockerItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "No Apps Added")
        XCTAssertFalse(items.first?.isEnabled == true)
    }

    func testAppBlockerSubmenuTracksAndTogglesApplicationState() throws {
        let defaults = makeDefaults()
        let configurationStore = AppBlockerConfigurationStore(defaults: defaults)
        let application = BlockedApplication(
            displayName: "Focus App",
            bundleIdentifier: "com.example.FocusApp",
            path: "/Applications/Focus App.app"
        )
        try configurationStore.save([application])
        let appBlocker = AppBlockerModule(
            store: configurationStore,
            runtime: MenuAppBlockerRuntime(),
            hostBundleIdentifier: "com.example.Host",
            hostProcessIdentifier: 1
        )
        let controller = makeController(appBlocker: appBlocker)

        XCTAssertEqual(controller.displayedAppBlockerItems().count, 1)
        XCTAssertEqual(controller.displayedAppBlockerItems().first?.title, "Focus App")
        XCTAssertEqual(controller.displayedAppBlockerItems().first?.state, .on)

        controller.toggleAppBlockerApplication(id: application.id)

        XCTAssertFalse(appBlocker.blockedApplications[0].isEnabled)
        XCTAssertEqual(controller.displayedAppBlockerItems().first?.state, .off)
        XCTAssertFalse(configurationStore.load()[0].isEnabled)
    }

    func testMenuReusesClipySubmenuAndDefersChangesUntilClose() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        func writeSnapshot(title: String) throws {
            let snapshot = ClipySnapshot(
                items: [
                    ClipyMenuItemSnapshot(
                        kind: .action, title: title, toolTip: nil,
                        keyEquivalent: "", imageData: nil,
                        imageWidth: nil, imageHeight: nil,
                        action: nil, children: []
                    )
                ],
                shortcuts: [], excludedApplications: []
            )
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
        try writeSnapshot(title: "Initial")
        let store = ModuleStateStore(
            defaults: makeDefaults(),
            bootSession: MenuBootSessionStub(id: "boot-a"),
            loginItemManager: MenuLoginItemNoop()
        )
        store.setEnabled(true, for: .clipyEnhanced)
        let bridge = ClipyEnhancedBridge(
            center: ClipyRecordingNotificationCenter(),
            snapshotURL: url
        )
        let controller = AppStatusMenuController(
            store: store, bridge: bridge,
            appBlocker: makeAppBlocker(),
            keepAwake: KeepAwakeModule(powerManager: MenuKeepAwakePowerManager())
        )
        let loaded = expectation(description: "initial snapshot")
        let subscription = bridge.$snapshot.dropFirst().sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 3)
        subscription.cancel()

        let root = try XCTUnwrap(
            Mirror(reflecting: controller).descendant("rootMenu") as? NSMenu
        )
        let clipy = try XCTUnwrap(root.items.first { $0.title == "ClipyEnhanced" })
        let submenu = try XCTUnwrap(clipy.submenu)
        XCTAssertEqual(submenu.items.first?.title, "Initial")
        controller.menuWillOpen(root)
        XCTAssertTrue(clipy.submenu === submenu)

        try writeSnapshot(title: "Updated")
        let updated = expectation(description: "updated snapshot")
        let updateSubscription = bridge.$snapshot.dropFirst().sink { _ in
            updated.fulfill()
        }
        defer { updateSubscription.cancel() }
        bridge.loadSnapshot()
        await fulfillment(of: [updated], timeout: 3)
        XCTAssertTrue(clipy.submenu === submenu)
        XCTAssertEqual(submenu.items.first?.title, "Initial")

        controller.menuDidClose(root)
        let updatedMenu = try XCTUnwrap(clipy.submenu)
        XCTAssertEqual(updatedMenu.items.first?.title, "Updated")
        controller.menuWillOpen(root)
        XCTAssertTrue(clipy.submenu === updatedMenu)
        controller.menuDidClose(root)
        store.setEnabled(false, for: .clipyEnhanced)
        XCTAssertNil(root.items.first { $0.title == "ClipyEnhanced" }?.submenu)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppStatusMenuControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeAppBlocker() -> AppBlockerModule {
        AppBlockerModule(
            store: AppBlockerConfigurationStore(defaults: makeDefaults()),
            runtime: MenuAppBlockerRuntime(),
            hostBundleIdentifier: "com.example.Host",
            hostProcessIdentifier: 1
        )
    }

    private func makeController(
        appBlocker: AppBlockerModule,
        keepAwake: KeepAwakeModule? = nil
    ) -> AppStatusMenuController {
        AppStatusMenuController(
            store: ModuleStateStore(
                defaults: makeDefaults(),
                bootSession: MenuBootSessionStub(id: "boot-a"),
                loginItemManager: MenuLoginItemNoop()
            ),
            bridge: ClipyEnhancedBridge(
                center: DistributedNotificationCenter(),
                snapshotURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
            ),
            appBlocker: appBlocker,
            keepAwake: keepAwake ?? KeepAwakeModule(
                powerManager: MenuKeepAwakePowerManager()
            )
        )
    }
}

private struct MenuBootSessionStub: BootSessionProviding {
    let id: String
    var currentBootID: String { id }
}

private struct MenuLoginItemNoop: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {}
}

@MainActor
private final class MenuAppBlockerRuntime: AppBlockerRuntime {
    var runningApplications: [AppBlockerRunningApplication] { [] }

    func observeLaunches(
        _ handler: @escaping (AppBlockerRunningApplication) -> Void
    ) -> NSObjectProtocol {
        NSObject()
    }

    func removeObserver(_ observer: NSObjectProtocol) {}

    func forceTerminate(_ application: AppBlockerRunningApplication) -> Bool {
        true
    }
}

private final class MenuKeepAwakePowerManager: KeepAwakePowerManaging {
    private var nextAssertion = IOPMAssertionID(1)

    func createAssertion(
        _ kind: KeepAwakeAssertionKind,
        reason: String
    ) throws -> IOPMAssertionID {
        takeAssertion()
    }

    func declareUserActivity(
        reason: String,
        existingAssertion: IOPMAssertionID?
    ) throws -> IOPMAssertionID {
        takeAssertion()
    }

    func releaseAssertion(_ assertion: IOPMAssertionID) {}

    private func takeAssertion() -> IOPMAssertionID {
        defer { nextAssertion += 1 }
        return nextAssertion
    }
}
