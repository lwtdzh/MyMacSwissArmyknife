import AppKit
import Combine
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

    func testSnapshotLoadsRecursiveMenuShortcutsAndExcludedApps() async throws {
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
        defer { try? FileManager.default.removeItem(at: url) }
        let bridge = ClipyEnhancedBridge(snapshotURL: url)
        let loaded = expectation(description: "snapshot loaded")
        let subscription = bridge.$snapshot.dropFirst().sink { _ in loaded.fulfill() }
        defer { subscription.cancel() }

        await fulfillment(of: [loaded], timeout: 3)
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

        let image = try XCTUnwrap(item.displayImage)
        var imageRect = NSRect(origin: .zero, size: image.size)

        XCTAssertEqual(image.size, NSSize(width: 100, height: 32))
        let pixels = try XCTUnwrap(
            image.cgImage(
                forProposedRect: &imageRect,
                context: nil,
                hints: nil
            )
        )
        XCTAssertLessThanOrEqual(pixels.width, 200)
        XCTAssertLessThanOrEqual(pixels.height, 200)
    }

    func testBlockedSnapshotReadDoesNotBlockMainThread() async throws {
        let data = try JSONEncoder().encode(ClipySnapshot.empty)
        let readStarted = expectation(description: "read started off main")
        let releaseRead = DispatchSemaphore(value: 0)
        defer { releaseRead.signal() }
        let started = Date()
        let bridge = ClipyEnhancedBridge(
            snapshotDataLoader: { _ in
                XCTAssertFalse(Thread.isMainThread)
                readStarted.fulfill()
                _ = releaseRead.wait(timeout: .now() + 2)
                return data
            }
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)

        let loaded = expectation(description: "blocked read completes")
        let subscription = bridge.$snapshot.dropFirst().sink { _ in loaded.fulfill() }
        defer { subscription.cancel() }
        await fulfillment(of: [readStarted], timeout: 1)
        releaseRead.signal()
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(bridge.snapshot, .empty)
    }

    func testUnchangedSnapshotDoesNotPublishAgain() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let data = try JSONEncoder().encode(ClipySnapshot.empty)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let bridge = ClipyEnhancedBridge(snapshotURL: url)
        let loaded = expectation(description: "initial snapshot")
        let subscription = bridge.$snapshot.dropFirst().sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 3)
        subscription.cancel()

        let duplicate = expectation(description: "no duplicate snapshot")
        duplicate.isInverted = true
        let duplicateSubscription = bridge.$snapshot.dropFirst().sink { _ in
            duplicate.fulfill()
        }
        defer { duplicateSubscription.cancel() }
        try data.write(to: url, options: .atomic)
        for _ in 0..<30 {
            bridge.loadSnapshot()
        }
        await fulfillment(of: [duplicate], timeout: 0.3)
    }

    func testBridgeSendsEverySupportedAction() {
        let center = ClipyRecordingNotificationCenter()

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

        let payloads = center.actionPayloads
        XCTAssertEqual(payloads.count, 7)
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

final class ClipyRecordingNotificationCenter:
    DistributedNotificationCenter, @unchecked Sendable {
    var actionPayloads: [[AnyHashable: Any]] = []

    override func postNotificationName(
        _ name: Notification.Name,
        object: String?,
        userInfo: [AnyHashable: Any]?,
        deliverImmediately: Bool
    ) {
        if name == ClipyBridgeNotification.performAction, let userInfo {
            actionPayloads.append(userInfo)
        }
    }
}
