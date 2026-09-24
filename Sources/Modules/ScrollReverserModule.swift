import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

protocol ScrollPermissionProviding {
    var accessibilityGranted: Bool { get }
    var inputMonitoringGranted: Bool { get }

    func requestAccessibility()
    func requestInputMonitoring()
    func openAccessibilitySettings()
    func openInputMonitoringSettings()
}

struct SystemScrollPermissionProvider: ScrollPermissionProviding {
    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    func requestAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoring() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = CGRequestListenEventAccess()
        }
    }

    func openAccessibilitySettings() {
        openPrivacySettings("Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacySettings("Privacy_ListenEvent")
    }

    private func openPrivacySettings(_ pane: String) {
        let path = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: path) {
            NSWorkspace.shared.open(url)
        }
    }
}

enum ScrollInputDevice {
    case mouse
    case trackpad
}

struct ScrollReverserPreferences {
    let reverseVertical: Bool
    let reverseHorizontal: Bool
    let reverseTrackpad: Bool
    let reverseMouse: Bool
    let discreteStepSize: Int

    init(defaults: UserDefaults) {
        reverseVertical = defaults.bool(forKey: "ReverseY")
        reverseHorizontal = defaults.bool(forKey: "ReverseX")
        reverseTrackpad = defaults.bool(forKey: "ReverseTrackpad")
        reverseMouse = defaults.bool(forKey: "ReverseMouse")
        discreteStepSize = min(max(defaults.integer(forKey: "DiscreteScrollStepSize"), 0), 100)
    }

    func shouldReverse(_ device: ScrollInputDevice) -> Bool {
        switch device {
        case .mouse: return reverseMouse
        case .trackpad: return reverseTrackpad
        }
    }

    func multipliers(
        for device: ScrollInputDevice,
        isContinuous: Bool,
        verticalDelta: Int64
    ) -> (vertical: Int64, horizontal: Int64, adjustsDiscreteStep: Bool) {
        let reverse = shouldReverse(device)
        let adjustsDiscreteStep =
            discreteStepSize > 0 && abs(verticalDelta) == 1 && !isContinuous
        let verticalStep = adjustsDiscreteStep ? Int64(discreteStepSize) : 1
        return (
            vertical: reverse && reverseVertical ? -verticalStep : verticalStep,
            horizontal: reverse && reverseHorizontal ? -1 : 1,
            adjustsDiscreteStep: adjustsDiscreteStep
        )
    }
}

private let scrollEventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let module = Unmanaged<ScrollReverserModule>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return MainActor.assumeIsolated {
        module.handleEvent(type: type, event: event)
    }
}

final class ScrollReverserModule: ObservableObject, InProcessModule {
    let id = ModuleID.scrollReverser

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var isRunning = false
    @Published private(set) var failureMessage: String?

    var onStateChange: (() -> Void)?
    var requiresUserAction: Bool {
        wantsToRun && (!accessibilityGranted || !inputMonitoringGranted)
    }

    private let defaults: UserDefaults
    private let hostDefaults: UserDefaults
    private let permissions: ScrollPermissionProviding
    private var activeTapPort: CFMachPort?
    private var activeTapSource: CFRunLoopSource?
    private var passiveTapPort: CFMachPort?
    private var passiveTapSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var wantsToRun = false
    private var touching = 0
    private var lastTouchTime: UInt64 = 0
    private var lastDevice = ScrollInputDevice.mouse

    private enum PermissionKey {
        static let requestedAccessibility =
            "scrollReverser.requestedAccessibilityPermission"
        static let requestedInputMonitoring =
            "scrollReverser.requestedInputMonitoringPermission"
    }

    init(
        defaults: UserDefaults = UserDefaults(
            suiteName: ModuleSettingsDefaults.scrollDomain
        )!,
        hostDefaults: UserDefaults = .standard,
        permissions: ScrollPermissionProviding = SystemScrollPermissionProvider()
    ) {
        self.defaults = defaults
        self.hostDefaults = hostDefaults
        self.permissions = permissions
        refreshPermissionState()
    }

    func start() {
        wantsToRun = true
        refreshPermissionState()
        guard accessibilityGranted, inputMonitoringGranted else {
            stopEventTaps()
            failureMessage = permissionFailureMessage
            requestMissingPermissionsIfNeeded()
            startPermissionPolling()
            return
        }

        permissionTimer?.invalidate()
        permissionTimer = nil
        guard !isRunning else {
            failureMessage = nil
            return
        }

        startEventTaps()
        failureMessage = isRunning ? nil : "Unable to create event tap"
    }

    func stop() {
        wantsToRun = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        stopEventTaps()
        failureMessage = nil
    }

    func settingsDidChange() {
        if wantsToRun {
            start()
        }
    }

    func requestPermissions() {
        if !accessibilityGranted {
            hostDefaults.set(true, forKey: PermissionKey.requestedAccessibility)
            permissions.requestAccessibility()
        }
        if !inputMonitoringGranted {
            hostDefaults.set(true, forKey: PermissionKey.requestedInputMonitoring)
            permissions.requestInputMonitoring()
        }
        startPermissionPolling()
    }

    func openAccessibilitySettings() {
        permissions.openAccessibilitySettings()
    }

    func openInputMonitoringSettings() {
        permissions.openInputMonitoringSettings()
    }

    func revealHostApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    fileprivate func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            enableEventTaps()
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == UInt32(NSEvent.EventType.gesture.rawValue) {
            captureTouches(from: event)
        } else if type == .scrollWheel {
            reverseScrollEvent(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private var permissionFailureMessage: String {
        switch (accessibilityGranted, inputMonitoringGranted) {
        case (false, false): "Accessibility and Input Monitoring required"
        case (false, true): "Accessibility permission required"
        case (true, false): "Input Monitoring permission required"
        case (true, true): ""
        }
    }

    private func requestMissingPermissionsIfNeeded() {
        if !accessibilityGranted,
           !hostDefaults.bool(forKey: PermissionKey.requestedAccessibility) {
            hostDefaults.set(true, forKey: PermissionKey.requestedAccessibility)
            permissions.requestAccessibility()
        }
        if !inputMonitoringGranted,
           !hostDefaults.bool(forKey: PermissionKey.requestedInputMonitoring) {
            hostDefaults.set(true, forKey: PermissionKey.requestedInputMonitoring)
            permissions.requestInputMonitoring()
        }
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshPermissionState()
                if self.wantsToRun &&
                    self.accessibilityGranted &&
                    self.inputMonitoringGranted {
                    self.start()
                }
            }
        }
    }

    private func refreshPermissionState() {
        let accessibility = permissions.accessibilityGranted
        let inputMonitoring = permissions.inputMonitoringGranted
        let changed =
            accessibility != accessibilityGranted ||
            inputMonitoring != inputMonitoringGranted
        accessibilityGranted = accessibility
        inputMonitoringGranted = inputMonitoring
        if changed {
            failureMessage = isRunning ? nil : permissionFailureMessage
            notifyStateChange()
        }
    }

    private func startEventTaps() {
        touching = 0
        lastTouchTime = 0
        lastDevice = .mouse

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let gestureType = CGEventType(
            rawValue: UInt32(NSEvent.EventType.gesture.rawValue)
        ) else {
            failureMessage = "Gesture event type is unavailable"
            return
        }
        let gestureMask = CGEventMask(1) << gestureType.rawValue
        let scrollMask = CGEventMask(1) << CGEventType.scrollWheel.rawValue

        passiveTapPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: gestureMask,
            callback: scrollEventTapCallback,
            userInfo: userInfo
        )
        activeTapPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollMask,
            callback: scrollEventTapCallback,
            userInfo: userInfo
        )

        guard let passiveTapPort, let activeTapPort else {
            stopEventTaps()
            return
        }

        passiveTapSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            passiveTapPort,
            0
        )
        activeTapSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            activeTapPort,
            0
        )
        guard let passiveTapSource, let activeTapSource else {
            stopEventTaps()
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), passiveTapSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), activeTapSource, .commonModes)
        isRunning = true
    }

    private func stopEventTaps() {
        if let activeTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), activeTapSource, .commonModes)
        }
        if let activeTapPort {
            CFMachPortInvalidate(activeTapPort)
        }
        if let passiveTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), passiveTapSource, .commonModes)
        }
        if let passiveTapPort {
            CFMachPortInvalidate(passiveTapPort)
        }
        activeTapSource = nil
        activeTapPort = nil
        passiveTapSource = nil
        passiveTapPort = nil
        isRunning = false
    }

    private func enableEventTaps() {
        if let activeTapPort, !CGEvent.tapIsEnabled(tap: activeTapPort) {
            CGEvent.tapEnable(tap: activeTapPort, enable: true)
        }
        if let passiveTapPort, !CGEvent.tapIsEnabled(tap: passiveTapPort) {
            CGEvent.tapEnable(tap: passiveTapPort, enable: true)
        }
    }

    private func captureTouches(from event: CGEvent) {
        guard let event = NSEvent(cgEvent: event) else { return }
        let count = event.touches(matching: .touching, in: nil).count
        guard count >= 2 else { return }
        touching = max(touching, count)
        lastTouchTime = DispatchTime.now().uptimeNanoseconds
    }

    private func reverseScrollEvent(_ event: CGEvent) {
        let continuous =
            event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let now = DispatchTime.now().uptimeNanoseconds
        let touchElapsed = now >= lastTouchTime ? now - lastTouchTime : .max
        let phase = NSEvent(cgEvent: event)?.momentumPhase ?? []

        let device: ScrollInputDevice
        if !continuous {
            device = .mouse
        } else if touching >= 2 && touchElapsed < 222_000_000 {
            device = .trackpad
        } else if phase.isEmpty && touchElapsed > 333_000_000 {
            device = .mouse
        } else {
            device = lastDevice
        }
        touching = 0
        lastDevice = device

        let verticalDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let horizontalDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let verticalPoint =
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let horizontalPoint =
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let verticalFixed =
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let horizontalFixed =
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

        let multipliers = ScrollReverserPreferences(defaults: defaults).multipliers(
            for: device,
            isContinuous: continuous,
            verticalDelta: verticalDelta
        )

        if multipliers.adjustsDiscreteStep || multipliers.vertical != 1 {
            event.setIntegerValueField(
                .scrollWheelEventDeltaAxis1,
                value: verticalDelta * multipliers.vertical
            )
        }
        if !multipliers.adjustsDiscreteStep && multipliers.vertical != 1 {
            event.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis1,
                value: verticalFixed * Double(multipliers.vertical)
            )
            event.setIntegerValueField(
                .scrollWheelEventPointDeltaAxis1,
                value: verticalPoint * multipliers.vertical
            )
        }
        if multipliers.horizontal != 1 {
            event.setIntegerValueField(
                .scrollWheelEventDeltaAxis2,
                value: horizontalDelta * multipliers.horizontal
            )
            event.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis2,
                value: horizontalFixed * Double(multipliers.horizontal)
            )
            event.setIntegerValueField(
                .scrollWheelEventPointDeltaAxis2,
                value: horizontalPoint * multipliers.horizontal
            )
        }
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}
