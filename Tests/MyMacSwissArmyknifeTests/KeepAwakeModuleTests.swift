import IOKit.pwr_mgt
import XCTest
@testable import MyMacSwissArmyknife

@MainActor
final class KeepAwakeModuleTests: XCTestCase {
    func testNewModuleStartsWithBothControlsDisabled() {
        let powerManager = KeepAwakePowerManagerSpy()
        let module = KeepAwakeModule(powerManager: powerManager)

        XCTAssertFalse(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertTrue(powerManager.createdKinds.isEmpty)
    }

    func testBlockSleepCreatesAndReleasesSystemAssertion() {
        let powerManager = KeepAwakePowerManagerSpy()
        let module = KeepAwakeModule(powerManager: powerManager)

        XCTAssertTrue(module.setBlockingSleep(true))
        XCTAssertTrue(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(powerManager.createdKinds, [.systemSleep])

        XCTAssertTrue(module.setBlockingSleep(false))
        XCTAssertFalse(module.isBlockingSleep)
        XCTAssertEqual(powerManager.releasedAssertions, [1])
    }

    func testBlockLockScreenKeepsDisplayAndUserActive() {
        let powerManager = KeepAwakePowerManagerSpy()
        let module = KeepAwakeModule(powerManager: powerManager)

        XCTAssertTrue(module.setBlockingLockScreen(true))
        XCTAssertTrue(module.isBlockingSleep)
        XCTAssertTrue(module.isBlockingLockScreen)
        XCTAssertEqual(powerManager.createdKinds, [.systemSleep, .displaySleep])
        XCTAssertEqual(powerManager.userActivityInputs, [nil])

        XCTAssertTrue(module.setBlockingLockScreen(false))
        XCTAssertTrue(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(Set(powerManager.releasedAssertions), [2, 3])
        module.stop()
    }

    func testDisablingBlockSleepAlsoDisablesBlockLockScreen() {
        let powerManager = KeepAwakePowerManagerSpy()
        let module = KeepAwakeModule(powerManager: powerManager)
        XCTAssertTrue(module.setBlockingLockScreen(true))

        XCTAssertTrue(module.setBlockingSleep(false))

        XCTAssertFalse(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(Set(powerManager.releasedAssertions), [1, 2, 3])

        XCTAssertTrue(module.setBlockingSleep(false))
        XCTAssertTrue(module.setBlockingLockScreen(false))
        XCTAssertEqual(powerManager.releasedAssertions.count, 3)
    }

    func testEnablingBlockLockScreenReusesExistingSystemAssertion() {
        let powerManager = KeepAwakePowerManagerSpy()
        let module = KeepAwakeModule(powerManager: powerManager)
        XCTAssertTrue(module.setBlockingSleep(true))

        XCTAssertTrue(module.setBlockingLockScreen(true))
        XCTAssertTrue(module.setBlockingLockScreen(true))

        XCTAssertTrue(module.isBlockingSleep)
        XCTAssertTrue(module.isBlockingLockScreen)
        XCTAssertEqual(powerManager.createdKinds, [.systemSleep, .displaySleep])
        XCTAssertEqual(powerManager.userActivityInputs.count, 1)
        module.stop()
    }

    func testStopReleasesEveryAssertionAndResetsState() {
        let powerManager = KeepAwakePowerManagerSpy()
        let module = KeepAwakeModule(powerManager: powerManager)
        module.setBlockingSleep(true)
        module.setBlockingLockScreen(true)

        module.stop()

        XCTAssertFalse(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(Set(powerManager.releasedAssertions), [1, 2, 3])
    }

    func testUserActivityFailureRollsBackBothNewAssertions() {
        let powerManager = KeepAwakePowerManagerSpy()
        powerManager.userActivityError = TestPowerError()
        let module = KeepAwakeModule(powerManager: powerManager)

        XCTAssertFalse(module.setBlockingLockScreen(true))
        XCTAssertFalse(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(powerManager.createdKinds, [.systemSleep, .displaySleep])
        XCTAssertEqual(Set(powerManager.releasedAssertions), [1, 2])
        XCTAssertNotNil(module.lastError)
    }

    func testLockScreenFailurePreservesPreviouslyEnabledBlockSleep() {
        let powerManager = KeepAwakePowerManagerSpy()
        powerManager.userActivityError = TestPowerError()
        let module = KeepAwakeModule(powerManager: powerManager)
        XCTAssertTrue(module.setBlockingSleep(true))

        XCTAssertFalse(module.setBlockingLockScreen(true))

        XCTAssertTrue(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(powerManager.releasedAssertions, [2])
        XCTAssertNotNil(module.lastError)
        module.stop()
    }

    func testSystemAssertionFailureDoesNotEnableBlockLockScreen() {
        let powerManager = KeepAwakePowerManagerSpy()
        powerManager.assertionErrorKind = .systemSleep
        let module = KeepAwakeModule(powerManager: powerManager)

        XCTAssertFalse(module.setBlockingLockScreen(true))

        XCTAssertFalse(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(powerManager.createdKinds, [.systemSleep])
        XCTAssertTrue(powerManager.userActivityInputs.isEmpty)
        XCTAssertTrue(powerManager.releasedAssertions.isEmpty)
        XCTAssertNotNil(module.lastError)
    }

    func testDisplayAssertionFailureReleasesNewSystemAssertion() {
        let powerManager = KeepAwakePowerManagerSpy()
        powerManager.assertionErrorKind = .displaySleep
        let module = KeepAwakeModule(powerManager: powerManager)

        XCTAssertFalse(module.setBlockingLockScreen(true))

        XCTAssertFalse(module.isBlockingSleep)
        XCTAssertFalse(module.isBlockingLockScreen)
        XCTAssertEqual(powerManager.createdKinds, [.systemSleep, .displaySleep])
        XCTAssertEqual(powerManager.releasedAssertions, [1])
        XCTAssertNotNil(module.lastError)
    }
}

private final class KeepAwakePowerManagerSpy: KeepAwakePowerManaging {
    private var nextAssertion = IOPMAssertionID(1)
    var assertionErrorKind: KeepAwakeAssertionKind?
    var userActivityError: Error?
    private(set) var createdKinds: [KeepAwakeAssertionKind] = []
    private(set) var userActivityInputs: [IOPMAssertionID?] = []
    private(set) var releasedAssertions: [IOPMAssertionID] = []

    func createAssertion(
        _ kind: KeepAwakeAssertionKind,
        reason: String
    ) throws -> IOPMAssertionID {
        createdKinds.append(kind)
        if kind == assertionErrorKind {
            throw TestPowerError()
        }
        return takeAssertion()
    }

    func declareUserActivity(
        reason: String,
        existingAssertion: IOPMAssertionID?
    ) throws -> IOPMAssertionID {
        userActivityInputs.append(existingAssertion)
        if let userActivityError {
            throw userActivityError
        }
        return takeAssertion()
    }

    func releaseAssertion(_ assertion: IOPMAssertionID) {
        releasedAssertions.append(assertion)
    }

    private func takeAssertion() -> IOPMAssertionID {
        defer { nextAssertion += 1 }
        return nextAssertion
    }
}

private struct TestPowerError: LocalizedError {
    var errorDescription: String? { "Test power assertion failure." }
}
