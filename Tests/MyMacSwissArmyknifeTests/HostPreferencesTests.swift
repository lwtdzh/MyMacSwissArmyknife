import Foundation
import XCTest
@testable import MyMacSwissArmyknife

final class HostPreferencesTests: XCTestCase {
    func testSettingsWindowIsHiddenByDefault() {
        let defaults = makeDefaults()

        XCTAssertFalse(
            HostPreferences.showsSettingsOnLaunch(defaults: defaults)
        )
    }

    func testSettingsWindowCanBeShownOnLaunch() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: HostPreferences.showSettingsOnLaunchKey)

        XCTAssertTrue(
            HostPreferences.showsSettingsOnLaunch(defaults: defaults)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let name = "HostPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
