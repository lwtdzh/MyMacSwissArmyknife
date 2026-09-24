import AppKit
import SwiftUI

struct ClipyShortcutRecorder: NSViewRepresentable {
    let display: String
    let onChange: (Int?, Int?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.onChange = onChange
        button.displayTitle = display
        button.title = display
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = onChange
        button.displayTitle = display
        if !button.isRecording {
            button.title = display
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var onChange: ((Int?, Int?) -> Void)?
    var displayTitle = ""
    fileprivate(set) var isRecording = false
    private var eventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecordingAction)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        target = self
        action = #selector(beginRecordingAction)
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    @objc
    func beginRecordingAction() {
        beginRecording()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = "Press shortcut"
        window?.makeFirstResponder(self)
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.record(event)
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 {
            finishRecording()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            onChange?(nil, nil)
            finishRecording()
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        onChange?(Int(event.keyCode), modifiers)
        finishRecording()
    }

    private func finishRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        title = displayTitle
        needsDisplay = true
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.command) { modifiers |= 256 }
        if flags.contains(.shift) { modifiers |= 512 }
        if flags.contains(.option) { modifiers |= 2048 }
        if flags.contains(.control) { modifiers |= 4096 }
        return modifiers
    }
}
