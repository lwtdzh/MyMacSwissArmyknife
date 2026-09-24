import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import MyMacSwissArmyknife

final class ScrollReverserModuleTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ScrollReverserModuleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "ReverseY")
        defaults.set(false, forKey: "ReverseX")
        defaults.set(true, forKey: "ReverseTrackpad")
        defaults.set(true, forKey: "ReverseMouse")
        defaults.set(3, forKey: "DiscreteScrollStepSize")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testContinuousVerticalScrollIsReversed() {
        let multipliers = ScrollReverserPreferences(defaults: defaults).multipliers(
            for: .trackpad,
            isContinuous: true,
            verticalDelta: 4
        )

        XCTAssertEqual(multipliers.vertical, -1)
        XCTAssertEqual(multipliers.horizontal, 1)
        XCTAssertFalse(multipliers.adjustsDiscreteStep)
    }

    func testDiscreteMouseScrollUsesConfiguredStep() {
        let multipliers = ScrollReverserPreferences(defaults: defaults).multipliers(
            for: .mouse,
            isContinuous: false,
            verticalDelta: 1
        )

        XCTAssertEqual(multipliers.vertical, -3)
        XCTAssertTrue(multipliers.adjustsDiscreteStep)
    }

    func testDevicePreferenceCanExcludeTrackpad() {
        defaults.set(false, forKey: "ReverseTrackpad")

        let multipliers = ScrollReverserPreferences(defaults: defaults).multipliers(
            for: .trackpad,
            isContinuous: true,
            verticalDelta: 2
        )

        XCTAssertEqual(multipliers.vertical, 1)
    }

    func testHorizontalDirectionCanBeReversedIndependently() {
        defaults.set(true, forKey: "ReverseX")

        let multipliers = ScrollReverserPreferences(defaults: defaults).multipliers(
            for: .mouse,
            isContinuous: true,
            verticalDelta: 2
        )

        XCTAssertEqual(multipliers.vertical, -1)
        XCTAssertEqual(multipliers.horizontal, -1)
    }

    @MainActor
    func testHostModuleRequestsMissingPermissions() {
        let permissions = ScrollPermissionSpy()
        let hostSuite = "ScrollReverserHostTests.\(UUID().uuidString)"
        let hostDefaults = UserDefaults(suiteName: hostSuite)!
        hostDefaults.removePersistentDomain(forName: hostSuite)
        let module = ScrollReverserModule(
            defaults: defaults,
            hostDefaults: hostDefaults,
            permissions: permissions
        )

        module.start()

        XCTAssertFalse(module.isRunning)
        XCTAssertEqual(
            module.failureMessage,
            "Accessibility and Input Monitoring required"
        )
        XCTAssertEqual(permissions.accessibilityRequestCount, 1)
        XCTAssertEqual(permissions.inputMonitoringRequestCount, 1)

        module.stop()
        hostDefaults.removePersistentDomain(forName: hostSuite)
    }

    func testAppBundleDragSourceExportsFileURL() {
        let provider = AppBundleDragSource.itemProvider(
            bundleURL: URL(fileURLWithPath: "/Applications/MyMacSwissArmyknife.app")
        )

        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        )
    }
}

private final class ScrollPermissionSpy: ScrollPermissionProviding {
    var accessibilityGranted = false
    var inputMonitoringGranted = false
    private(set) var accessibilityRequestCount = 0
    private(set) var inputMonitoringRequestCount = 0

    func requestAccessibility() {
        accessibilityRequestCount += 1
    }

    func requestInputMonitoring() {
        inputMonitoringRequestCount += 1
    }

    func openAccessibilitySettings() {}
    func openInputMonitoringSettings() {}
}
