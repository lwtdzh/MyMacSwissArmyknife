import XCTest
@testable import ResourceMonitor

final class ResourceMonitorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ResourceMonitorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultSettingsAreUsable() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.showMenuBar)
        XCTAssertTrue(settings.showFloatingPanel)
        XCTAssertTrue(settings.showDownload)
        XCTAssertTrue(settings.showUpload)
        XCTAssertTrue(settings.showDiskRead)
        XCTAssertTrue(settings.showDiskWrite)
        XCTAssertTrue(settings.showCPU)
        XCTAssertTrue(settings.showMemory)
        XCTAssertEqual(settings.dataRateUnit, .bits)
        XCTAssertEqual(settings.refreshInterval, 1)
    }

    func testPresentationAlwaysKeepsOneSurfaceVisible() {
        let settings = AppSettings(defaults: defaults)

        settings.setShowFloatingPanel(false)
        settings.setShowMenuBar(false)

        XCTAssertFalse(settings.showMenuBar)
        XCTAssertTrue(settings.showFloatingPanel)
    }

    func testMetricVisibilityCannotDisableEveryMetric() {
        let settings = AppSettings(defaults: defaults)

        settings.setShowUpload(false)
        settings.setShowDiskRead(false)
        settings.setShowDiskWrite(false)
        settings.setShowCPU(false)
        settings.setShowMemory(false)
        settings.setShowDownload(false)

        XCTAssertTrue(settings.showDownload)
        XCTAssertFalse(settings.showUpload)
        XCTAssertFalse(settings.showDiskRead)
        XCTAssertFalse(settings.showDiskWrite)
        XCTAssertFalse(settings.showCPU)
        XCTAssertFalse(settings.showMemory)
    }

    func testSettingsPersistThroughInjectedDefaults() {
        let settings = AppSettings(defaults: defaults)
        settings.setShowFloatingPanel(false)
        settings.setDataRateUnit(.bytes)
        settings.setRefreshInterval(5)

        let restored = AppSettings(defaults: defaults)

        XCTAssertFalse(restored.showFloatingPanel)
        XCTAssertEqual(restored.dataRateUnit, .bytes)
        XCTAssertEqual(restored.refreshInterval, 5)
    }

    func testInvalidPersistedValuesFallBackToDefaults() {
        defaults.set("invalid", forKey: "dataRateUnit")
        defaults.set(4, forKey: "refreshInterval")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.dataRateUnit, .bits)
        XCTAssertEqual(settings.refreshInterval, 1)
    }

    func testRateFormattingUsesDecimalUnits() {
        XCTAssertEqual(TrafficMonitor.formattedRate(0, unit: .bytes).compact, "0.000B")
        XCTAssertEqual(TrafficMonitor.formattedRate(1_250, unit: .bytes).compact, "1.250KB")
        XCTAssertEqual(TrafficMonitor.formattedRate(125_000, unit: .bits).compact, "1.000Mb")
    }

    func testPercentFormattingCapsOverflow() {
        XCTAssertEqual(TrafficMonitor.formattedPercent(99), "99")
        XCTAssertEqual(TrafficMonitor.formattedPercent(100), "F")
        XCTAssertEqual(TrafficMonitor.formattedPercent(250), "F")
    }
}
