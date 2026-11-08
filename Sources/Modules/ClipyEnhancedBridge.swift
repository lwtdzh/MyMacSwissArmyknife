import AppKit
import CryptoKit
import Foundation
import ImageIO

struct ClipyDisplayImageKey: Hashable {
    let data: Data
    let width: Double?
    let height: Double?
}

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
    var cachedDisplayImage: NSImage? = nil

    private enum CodingKeys: String, CodingKey {
        case kind, title, toolTip, keyEquivalent, imageData
        case imageWidth, imageHeight, action, children
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind &&
            lhs.title == rhs.title &&
            lhs.toolTip == rhs.toolTip &&
            lhs.keyEquivalent == rhs.keyEquivalent &&
            lhs.imageData == rhs.imageData &&
            lhs.imageWidth == rhs.imageWidth &&
            lhs.imageHeight == rhs.imageHeight &&
            lhs.action == rhs.action &&
            lhs.children == rhs.children
    }

    var displayImage: NSImage? {
        if let cachedDisplayImage { return cachedDisplayImage }
        guard let imageData,
              let source = CGImageSourceCreateWithData(
                  imageData as CFData,
                  nil
              ) else {
            return nil
        }
        let displaySize: NSSize?
        if let imageWidth, let imageHeight,
           imageWidth.isFinite, imageHeight.isFinite,
           imageWidth > 0, imageHeight > 0 {
            displaySize = NSSize(width: imageWidth, height: imageHeight)
        } else {
            displaySize = nil
        }
        let maximumPixels = min(
            512,
            ceil((displaySize.map { max($0.width, $0.height) } ?? 256) * 2)
        )
        guard let imageRepresentation = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
                      kCGImageSourceShouldCache: true,
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary
              ) else {
            return nil
        }
        let size = displaySize ?? NSSize(
            width: imageRepresentation.width,
            height: imageRepresentation.height
        )
        let image = NSImage(cgImage: imageRepresentation, size: size)
        image.cacheMode = .always
        return image
    }

    func preparingDisplayImages(
        previousImages: [ClipyDisplayImageKey: NSImage],
        images: inout [ClipyDisplayImageKey: NSImage]
    ) -> Self {
        var prepared = self
        if let imageData {
            let key = ClipyDisplayImageKey(
                data: imageData, width: imageWidth, height: imageHeight
            )
            prepared.cachedDisplayImage = images[key]
                ?? previousImages[key]
                ?? displayImage
            images[key] = prepared.cachedDisplayImage
        }
        return Self(
            kind: kind,
            title: title,
            toolTip: toolTip,
            keyEquivalent: keyEquivalent,
            imageData: imageData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            action: action,
            children: children.map {
                $0.preparingDisplayImages(
                    previousImages: previousImages,
                    images: &images
                )
            },
            cachedDisplayImage: prepared.cachedDisplayImage
        )
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

// Accessed only on the bridge's serial snapshot queue.
private final class ClipySnapshotReader: @unchecked Sendable {
    private let loadData: @Sendable (URL) -> Data?
    private var previousDigest: SHA256.Digest?
    private var previousSnapshot: ClipySnapshot?
    private var images: [ClipyDisplayImageKey: NSImage] = [:]

    init(loadData: @escaping @Sendable (URL) -> Data?) {
        self.loadData = loadData
    }

    func read(_ url: URL) -> ClipySnapshot? {
        guard let data = loadData(url) else { return nil }
        let digest = SHA256.hash(data: data)
        guard digest != previousDigest,
              let decoded = try? JSONDecoder().decode(
                  ClipySnapshot.self,
                  from: data
              ) else {
            return nil
        }
        previousDigest = digest
        guard decoded != previousSnapshot else { return nil }

        var nextImages: [ClipyDisplayImageKey: NSImage] = [:]
        let prepared = ClipySnapshot(
            items: decoded.items.map {
                $0.preparingDisplayImages(
                    previousImages: images,
                    images: &nextImages
                )
            },
            shortcuts: decoded.shortcuts,
            excludedApplications: decoded.excludedApplications
        )
        images = nextImages
        previousSnapshot = prepared
        return prepared
    }
}

@MainActor
final class ClipyEnhancedBridge: ObservableObject {
    @Published private(set) var snapshot = ClipySnapshot.empty

    static let defaultsDomain = "com.clipy-app.ClipyEnhanced"

    private let center: DistributedNotificationCenter
    private let snapshotURL: URL
    private let snapshotQueue = DispatchQueue(
        label: "com.mymacswissarmyknife.clipy.snapshot",
        qos: .userInitiated
    )
    private let snapshotReader: ClipySnapshotReader
    private var isLoadingSnapshot = false
    private var needsSnapshotReload = false
    private var observers = [NSObjectProtocol]()

    init(
        center: DistributedNotificationCenter = .default(),
        snapshotURL: URL = ClipyEnhancedBridge.defaultSnapshotURL,
        snapshotDataLoader: @escaping @Sendable (URL) -> Data? = {
            try? Data(contentsOf: $0)
        }
    ) {
        self.center = center
        self.snapshotURL = snapshotURL
        snapshotReader = ClipySnapshotReader(loadData: snapshotDataLoader)

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
        snapshotQueue.async { [center] in
            center.postNotificationName(
                ClipyBridgeNotification.requestSnapshot,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
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
        guard !isLoadingSnapshot else {
            needsSnapshotReload = true
            return
        }
        isLoadingSnapshot = true
        snapshotQueue.async { [snapshotReader, snapshotURL, weak self] in
            let decoded = autoreleasepool {
                snapshotReader.read(snapshotURL)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoadingSnapshot = false
                if let decoded {
                    self.snapshot = decoded
                }
                if self.needsSnapshotReload {
                    self.needsSnapshotReload = false
                    self.loadSnapshot()
                }
            }
        }
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
