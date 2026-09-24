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
        button.title = display
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = onChange
        if !button.isRecording {
            button.title = display
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var onChange: ((Int?, Int?) -> Void)?
    fileprivate(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        title = "Press shortcut"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
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

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
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
