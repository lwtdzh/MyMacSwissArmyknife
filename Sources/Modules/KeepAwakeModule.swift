import Foundation
import IOKit.pwr_mgt

enum KeepAwakeAssertionKind: Equatable {
    case systemSleep
    case displaySleep
}

protocol KeepAwakePowerManaging {
    func createAssertion(
        _ kind: KeepAwakeAssertionKind,
        reason: String
    ) throws -> IOPMAssertionID
    func declareUserActivity(
        reason: String,
        existingAssertion: IOPMAssertionID?
    ) throws -> IOPMAssertionID
    func releaseAssertion(_ assertion: IOPMAssertionID)
}

struct SystemKeepAwakePowerManager: KeepAwakePowerManaging {
    func createAssertion(
        _ kind: KeepAwakeAssertionKind,
        reason: String
    ) throws -> IOPMAssertionID {
        let assertionType: CFString = switch kind {
        case .systemSleep:
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .displaySleep:
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        }
        var assertion = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertion
        )
        guard result == kIOReturnSuccess else {
            throw KeepAwakePowerError(operation: "create assertion", code: result)
        }
        return assertion
    }

    func declareUserActivity(
        reason: String,
        existingAssertion: IOPMAssertionID?
    ) throws -> IOPMAssertionID {
        var assertion = existingAssertion ?? IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity(
            reason as CFString,
            kIOPMUserActiveLocal,
            &assertion
        )
        guard result == kIOReturnSuccess else {
            throw KeepAwakePowerError(operation: "declare user activity", code: result)
        }
        return assertion
    }

    func releaseAssertion(_ assertion: IOPMAssertionID) {
        IOPMAssertionRelease(assertion)
    }
}

struct KeepAwakePowerError: LocalizedError {
    let operation: String
    let code: IOReturn

    var errorDescription: String? {
        "Unable to \(operation) (IOKit error \(code))."
    }
}

@MainActor
final class KeepAwakeModule: ObservableObject {
    @Published private(set) var isBlockingSleep = false
    @Published private(set) var isBlockingLockScreen = false
    @Published private(set) var lastError: String?

    private static let userActivityRefreshInterval: TimeInterval = 30
    private let powerManager: any KeepAwakePowerManaging
    private var systemSleepAssertion: IOPMAssertionID?
    private var displaySleepAssertion: IOPMAssertionID?
    private var userActivityAssertion: IOPMAssertionID?
    private var userActivityTimer: Timer?

    init(powerManager: any KeepAwakePowerManaging = SystemKeepAwakePowerManager()) {
        self.powerManager = powerManager
    }

    @discardableResult
    func setBlockingSleep(_ enabled: Bool) -> Bool {
        guard enabled != isBlockingSleep else { return true }
        if enabled {
            do {
                systemSleepAssertion = try powerManager.createAssertion(
                    .systemSleep,
                    reason: "MyMacSwissArmyknife: Block Sleep"
                )
                isBlockingSleep = true
                lastError = nil
                return true
            } catch {
                lastError = error.localizedDescription
                return false
            }
        }

        if let systemSleepAssertion {
            powerManager.releaseAssertion(systemSleepAssertion)
        }
        systemSleepAssertion = nil
        isBlockingSleep = false
        lastError = nil
        return true
    }

    @discardableResult
    func setBlockingLockScreen(_ enabled: Bool) -> Bool {
        guard enabled != isBlockingLockScreen else { return true }
        if enabled {
            return enableLockScreenBlocking()
        }

        stopUserActivity()
        if let displaySleepAssertion {
            powerManager.releaseAssertion(displaySleepAssertion)
        }
        displaySleepAssertion = nil
        isBlockingLockScreen = false
        lastError = nil
        return true
    }

    func stop() {
        userActivityTimer?.invalidate()
        userActivityTimer = nil
        releaseAssertions()
        isBlockingSleep = false
        isBlockingLockScreen = false
        lastError = nil
    }

    private func enableLockScreenBlocking() -> Bool {
        do {
            let displayAssertion = try powerManager.createAssertion(
                .displaySleep,
                reason: "MyMacSwissArmyknife: Block Lock Screen"
            )
            do {
                userActivityAssertion = try powerManager.declareUserActivity(
                    reason: "MyMacSwissArmyknife: Keep User Active",
                    existingAssertion: nil
                )
            } catch {
                powerManager.releaseAssertion(displayAssertion)
                throw error
            }
            displaySleepAssertion = displayAssertion
            isBlockingLockScreen = true
            startUserActivityTimer()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func startUserActivityTimer() {
        userActivityTimer?.invalidate()
        let timer = Timer(
            timeInterval: Self.userActivityRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshUserActivity()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        userActivityTimer = timer
    }

    private func refreshUserActivity() {
        guard isBlockingLockScreen else { return }
        do {
            userActivityAssertion = try powerManager.declareUserActivity(
                reason: "MyMacSwissArmyknife: Keep User Active",
                existingAssertion: userActivityAssertion
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stopUserActivity() {
        userActivityTimer?.invalidate()
        userActivityTimer = nil
        if let userActivityAssertion {
            powerManager.releaseAssertion(userActivityAssertion)
        }
        userActivityAssertion = nil
    }

    private func releaseAssertions() {
        if let systemSleepAssertion {
            powerManager.releaseAssertion(systemSleepAssertion)
        }
        if let displaySleepAssertion {
            powerManager.releaseAssertion(displaySleepAssertion)
        }
        if let userActivityAssertion {
            powerManager.releaseAssertion(userActivityAssertion)
        }
        systemSleepAssertion = nil
        displaySleepAssertion = nil
        userActivityAssertion = nil
    }
}
