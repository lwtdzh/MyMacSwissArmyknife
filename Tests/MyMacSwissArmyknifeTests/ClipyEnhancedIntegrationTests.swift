import AppKit
import Foundation
import XCTest
@testable import MyMacSwissArmyknife

@MainActor
final class ClipyEnhancedIntegrationTests: XCTestCase {
    func testClipyEnhancedIsBundledModule() {
        let definition = ModuleDefinition.builtIns.first {
            $0.id == .clipyEnhanced
        }

        XCTAssertEqual(definition?.displayName, "ClipyEnhanced")
        XCTAssertEqual(
            definition?.execution,
            .bundledApplication(
                bundleIdentifier: "com.clipy-app.ClipyEnhanced",
                bundleName: "ClipyEnhanced.app"
            )
        )
    }

    func testSnapshotLoadsRecursiveMenuShortcutsAndExcludedApps() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let action = ClipyMenuAction(
            kind: "pasteClip",
            identifier: "clip-1",
            representation: "plainText"
        )
        let snapshot = ClipySnapshot(
            items: [
                ClipyMenuItemSnapshot(
                    kind: .submenu,
                    title: "1. Example",
                    toolTip: "Example",
                    keyEquivalent: "1",
                    imageData: nil,
                    imageWidth: nil,
                    imageHeight: nil,
                    action: action,
                    children: [
                        ClipyMenuItemSnapshot(
                            kind: .action,
                            title: "Paste as Plain Text",
                            toolTip: nil,
                            keyEquivalent: "",
                            imageData: nil,
                            imageWidth: nil,
                            imageHeight: nil,
                            action: action,
                            children: []
                        )
                    ]
                )
            ],
            shortcuts: [
                ClipyShortcutSnapshot(
                    kind: "main",
                    keyCode: 9,
                    modifiers: 768,
                    display: "⇧⌘V"
                )
            ],
            excludedApplications: [
                ClipyExcludedApplication(
                    identifier: "com.example.Secret",
                    name: "Secret"
                )
            ]
        )
        try JSONEncoder().encode(snapshot).write(to: url)
        let bridge = ClipyEnhancedBridge(snapshotURL: url)

        XCTAssertEqual(bridge.snapshot, snapshot)
    }

    func testSnapshotImageRestoresClipyDisplaySize() throws {
        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 900,
                pixelsHigh: 600,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let imageData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        let item = ClipyMenuItemSnapshot(
            kind: .action,
            title: "Image",
            toolTip: nil,
            keyEquivalent: "",
            imageData: imageData,
            imageWidth: 100,
            imageHeight: 32,
            action: nil,
            children: []
        )

        XCTAssertEqual(item.displayImage?.size, NSSize(width: 100, height: 32))
    }

    func testBridgeSendsEverySupportedAction() async {
        let center = DistributedNotificationCenter.default()
        let expectation = expectation(description: "bridge actions")
        expectation.expectedFulfillmentCount = 7
        var payloads = [[AnyHashable: Any]]()
        let observer = center.addObserver(
            forName: ClipyBridgeNotification.performAction,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo {
                payloads.append(userInfo)
                expectation.fulfill()
            }
        }
        defer { center.removeObserver(observer) }

        let bridge = ClipyEnhancedBridge(
            center: center,
            snapshotURL: URL(fileURLWithPath: "/nonexistent")
        )
        bridge.perform(
            ClipyMenuAction(
                kind: "pasteClip",
                identifier: "clip-1",
                representation: "original"
            )
        )
        bridge.perform(
            ClipyMenuAction(
                kind: "pasteSnippet",
                identifier: "snippet-1",
                representation: nil
            )
        )
        bridge.perform(
            ClipyMenuAction(
                kind: "clearHistory",
                identifier: nil,
                representation: nil
            )
        )
        bridge.editSnippets()
        bridge.addExcludedApplication(
            at: URL(fileURLWithPath: "/Applications/TextEdit.app")
        )
        bridge.removeExcludedApplication(identifier: "com.example.Secret")
        bridge.updateShortcut("main", keyCode: 9, modifiers: 768)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(
            payloads.compactMap { $0["kind"] as? String },
            [
                "pasteClip",
                "pasteSnippet",
                "clearHistory",
                "editSnippets",
                "addExcludedApplication",
                "removeExcludedApplication",
                "updateShortcut"
            ]
        )
        XCTAssertEqual(payloads.last?["shortcut"] as? String, "main")
        XCTAssertEqual(payloads.last?["keyCode"] as? Int, 9)
        XCTAssertEqual(payloads.last?["modifiers"] as? Int, 768)
    }

    func testShortcutRecorderCapturesCommandKeyEquivalent() {
        let recorder = ShortcutRecorderButton()
        recorder.displayTitle = "⌃⌘V"
        var captured: (Int?, Int?)?
        recorder.onChange = { captured = ($0, $1) }
        recorder.performClick(nil)

        let consumed = recorder.performKeyEquivalent(
            with: keyEvent(keyCode: 9, modifiers: [.command, .shift])
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(captured?.0, 9)
        XCTAssertEqual(captured?.1, 768)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.title, "⌃⌘V")
    }

    func testShortcutRecorderClearsWithDelete() {
        let recorder = ShortcutRecorderButton()
        recorder.displayTitle = "⌃⌘V"
        var captured: (Int?, Int?)?
        recorder.onChange = { captured = ($0, $1) }
        recorder.beginRecording()

        recorder.keyDown(with: keyEvent(keyCode: 51))

        XCTAssertNotNil(captured)
        XCTAssertNil(captured?.0)
        XCTAssertNil(captured?.1)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.title, "⌃⌘V")
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
