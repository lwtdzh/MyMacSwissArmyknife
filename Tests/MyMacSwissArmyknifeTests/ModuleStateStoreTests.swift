import XCTest
@testable import MyMacSwissArmyknife

@MainActor
final class ModuleStateStoreTests: XCTestCase {
    func testNewBootKeepsOnlyLoginModulesEnabled() {
        let defaults = makeDefaults()
        let loginManager = LoginItemManagerSpy()
        let firstStore = ModuleStateStore(
            defaults: defaults,
            bootSession: BootSessionStub(id: "boot-a"),
            loginItemManager: loginManager
        )

        firstStore.setStartsAtLogin(true, for: .scrollReverser)
        firstStore.setEnabled(true, for: .resourceMonitor)

        let nextBootStore = ModuleStateStore(
            defaults: defaults,
            bootSession: BootSessionStub(id: "boot-b"),
            loginItemManager: loginManager
        )

        XCTAssertTrue(nextBootStore.configuration(for: .scrollReverser).isEnabled)
        XCTAssertTrue(nextBootStore.configuration(for: .scrollReverser).startsAtLogin)
        XCTAssertFalse(nextBootStore.configuration(for: .resourceMonitor).isEnabled)
        XCTAssertFalse(nextBootStore.configuration(for: .resourceMonitor).startsAtLogin)
    }

    func testRelaunchInSameBootPreservesEnabledState() {
        let defaults = makeDefaults()
        let firstStore = ModuleStateStore(
            defaults: defaults,
            bootSession: BootSessionStub(id: "boot-a"),
            loginItemManager: LoginItemManagerSpy()
        )
        firstStore.setEnabled(true, for: .resourceMonitor)

        let relaunchedStore = ModuleStateStore(
            defaults: defaults,
            bootSession: BootSessionStub(id: "boot-a"),
            loginItemManager: LoginItemManagerSpy()
        )

        XCTAssertTrue(relaunchedStore.configuration(for: .resourceMonitor).isEnabled)
    }

    func testDisablingModuleAlsoClearsLoginStartup() {
        let store = ModuleStateStore(
            defaults: makeDefaults(),
            bootSession: BootSessionStub(id: "boot-a"),
            loginItemManager: LoginItemManagerSpy()
        )

        store.setStartsAtLogin(true, for: .scrollReverser)
        store.setEnabled(false, for: .scrollReverser)

        XCTAssertEqual(store.configuration(for: .scrollReverser), .disabled)
    }

    func testLoginItemFollowsAnyModuleStartupSelection() {
        let loginManager = LoginItemManagerSpy()
        let store = ModuleStateStore(
            defaults: makeDefaults(),
            bootSession: BootSessionStub(id: "boot-a"),
            loginItemManager: loginManager
        )

        store.setStartsAtLogin(true, for: .resourceMonitor)
        store.setStartsAtLogin(false, for: .resourceMonitor)

        XCTAssertEqual(loginManager.values.suffix(2), [true, false])
    }

    private func makeDefaults() -> UserDefaults {
        let name = "MyMacSwissArmyknifeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private struct BootSessionStub: BootSessionProviding {
    let id: String
    var currentBootID: String { id }
}

private final class LoginItemManagerSpy: LoginItemManaging {
    private(set) var values: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        values.append(enabled)
    }
}
