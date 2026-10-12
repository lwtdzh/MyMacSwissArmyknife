import AppKit
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
            keepAwake: keepAwake
        )

        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)

        keepAwake.setBlockingSleep(true)
        keepAwake.setBlockingLockScreen(true)

        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .on)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .on)

        keepAwake.stop()

        XCTAssertEqual(controller.displayedKeepAwakeStates().blockSleep, .off)
        XCTAssertEqual(controller.displayedKeepAwakeStates().blockLockScreen, .off)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppStatusMenuControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private struct MenuBootSessionStub: BootSessionProviding {
    let id: String
    var currentBootID: String { id }
}

private struct MenuLoginItemNoop: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {}
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
