import AppKit
import Foundation
import ImageIO

struct ClipyMenuItemSnapshot: Codable, Equatable {
    enum Kind: String, Codable {
        case action
        case header
        case separator
        case submenu
    }

    let kind: Kind
    let title: String
    let toolTip: String?
    let keyEquivalent: String
    let imageData: Data?
    let imageWidth: Double?
    let imageHeight: Double?
    let action: ClipyMenuAction?
    let children: [ClipyMenuItemSnapshot]

    var displayImage: NSImage? {
        guard let imageData,
              let source = CGImageSourceCreateWithData(
                  imageData as CFData,
                  nil
              ),
              let imageRepresentation = CGImageSourceCreateImageAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceShouldCache: true,
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary
              ) else {
            return nil
        }
        let size =
            if let imageWidth,
               let imageHeight,
               imageWidth > 0,
               imageHeight > 0 {
                NSSize(width: imageWidth, height: imageHeight)
            } else {
                NSSize(
                    width: imageRepresentation.width,
                    height: imageRepresentation.height
                )
            }
        let image = NSImage(cgImage: imageRepresentation, size: size)
        image.cacheMode = .always
        return image
    }
}

struct ClipyMenuAction: Codable, Equatable {
    let kind: String
    let identifier: String?
    let representation: String?
}

struct ClipyShortcutSnapshot: Codable, Equatable, Identifiable {
    let kind: String
    let keyCode: Int?
    let modifiers: Int?
    let display: String

    var id: String { kind }
}

struct ClipyExcludedApplication: Codable, Equatable, Identifiable {
    let identifier: String
    let name: String

    var id: String { identifier }
}

struct ClipySnapshot: Codable, Equatable {
    let items: [ClipyMenuItemSnapshot]
    let shortcuts: [ClipyShortcutSnapshot]
    let excludedApplications: [ClipyExcludedApplication]

    static let empty = ClipySnapshot(
        items: [],
        shortcuts: [],
        excludedApplications: []
    )
}

enum ClipyBridgeNotification {
    static let requestSnapshot = Notification.Name(
        "com.mymacswissarmyknife.clipy.request-snapshot"
    )
    static let snapshotUpdated = Notification.Name(
        "com.mymacswissarmyknife.clipy.snapshot-updated"
    )
    static let performAction = Notification.Name(
        "com.mymacswissarmyknife.clipy.perform-action"
    )
    static let pasteRequested = Notification.Name(
        "com.mymacswissarmyknife.clipy.paste-requested"
    )
    static let openSettings = Notification.Name(
        "com.mymacswissarmyknife.clipy.open-settings"
    )
}

@MainActor
final class ClipyEnhancedBridge: ObservableObject {
    @Published private(set) var snapshot = ClipySnapshot.empty

    static let defaultsDomain = "com.clipy-app.ClipyEnhanced"

    private let center: DistributedNotificationCenter
    private let snapshotURL: URL
    private var observers = [NSObjectProtocol]()

    init(
        center: DistributedNotificationCenter = .default(),
        snapshotURL: URL = ClipyEnhancedBridge.defaultSnapshotURL
    ) {
        self.center = center
        self.snapshotURL = snapshotURL

        observers.append(
            center.addObserver(
                forName: ClipyBridgeNotification.snapshotUpdated,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.loadSnapshot()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: ClipyBridgeNotification.pasteRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.sendPasteCommand()
                }
            }
        )
        loadSnapshot()
    }

    deinit {
        observers.forEach(center.removeObserver)
    }

    func requestSnapshot() {
        center.postNotificationName(
            ClipyBridgeNotification.requestSnapshot,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        loadSnapshot()
    }

    func perform(_ action: ClipyMenuAction) {
        var userInfo: [String: Any] = ["kind": action.kind]
        userInfo["identifier"] = action.identifier
        userInfo["representation"] = action.representation
        postAction(userInfo)
    }

    func editSnippets() {
        postAction(["kind": "editSnippets"])
    }

    func addExcludedApplication(at url: URL) {
        postAction([
            "kind": "addExcludedApplication",
            "path": url.path
        ])
    }

    func removeExcludedApplication(identifier: String) {
        postAction([
            "kind": "removeExcludedApplication",
            "identifier": identifier
        ])
    }

    func updateShortcut(
        _ shortcut: String,
        keyCode: Int?,
        modifiers: Int?
    ) {
        var userInfo: [String: Any] = [
            "kind": "updateShortcut",
            "shortcut": shortcut
        ]
        if let keyCode, let modifiers {
            userInfo["keyCode"] = keyCode
            userInfo["modifiers"] = modifiers
        }
        postAction(userInfo)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func loadSnapshot() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let decoded = try? JSONDecoder().decode(ClipySnapshot.self, from: data) else {
            return
        }
        snapshot = decoded
    }

    nonisolated static var defaultSnapshotURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("MyMacSwissArmyknife", isDirectory: true)
            .appendingPathComponent("ClipyEnhanced", isDirectory: true)
            .appendingPathComponent("menu-snapshot.json")
    }

    private func postAction(_ userInfo: [String: Any]) {
        center.postNotificationName(
            ClipyBridgeNotification.performAction,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private func sendPasteCommand() {
        guard accessibilityGranted else {
            openAccessibilitySettings()
            return
        }

        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
            )
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
            )
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
