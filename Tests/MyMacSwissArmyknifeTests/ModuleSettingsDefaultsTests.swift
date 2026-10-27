import XCTest
@testable import MyMacSwissArmyknife

final class ModuleSettingsDefaultsTests: XCTestCase {
    func testClipyEnhancedDefaultsUseFiveHundredHistoryItems() {
        let defaults = makeDefaults()

        ModuleSettingsDefaults.seedClipyEnhanced(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: "kCPYPrefMaxHistorySizeKey"), 500)
    }

    func testClipyEnhancedDefaultsMigrateOldBundledHistoryLimit() {
        let defaults = makeDefaults()
        defaults.set(30, forKey: "kCPYPrefMaxHistorySizeKey")

        ModuleSettingsDefaults.seedClipyEnhanced(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: "kCPYPrefMaxHistorySizeKey"), 500)
    }

    func testClipyEnhancedDefaultsPreserveCustomizedHistoryLimit() {
        let defaults = makeDefaults()
        defaults.set(250, forKey: "kCPYPrefMaxHistorySizeKey")

        ModuleSettingsDefaults.seedClipyEnhanced(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: "kCPYPrefMaxHistorySizeKey"), 250)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "ModuleSettingsDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
