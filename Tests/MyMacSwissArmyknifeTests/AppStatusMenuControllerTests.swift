import AppKit
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
            bridge: bridge
        )

        XCTAssertEqual(controller.displayedModuleState(.appBlocker), .off)

        store.setEnabled(true, for: .appBlocker)

        XCTAssertTrue(store.configuration(for: .appBlocker).isEnabled)
        XCTAssertEqual(controller.displayedModuleState(.appBlocker), .on)

        store.setEnabled(false, for: .appBlocker)

        XCTAssertFalse(store.configuration(for: .appBlocker).isEnabled)
        XCTAssertEqual(controller.displayedModuleState(.appBlocker), .off)
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
