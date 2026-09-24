import Quick
import Nimble
import XCTest
@testable import ClipyEnhanced

class DraggedDataSpec: QuickSpec {
    override func spec() {

        describe("NSCoding") {

            it("Archive data") {
                let draggedData = CPYDraggedData(type: .folder, folderIdentifier: NSUUID().uuidString, snippetIdentifier: nil, index: 10)
                let data = NSKeyedArchiver.archivedData(withRootObject: draggedData)

                let unarchiveData = NSKeyedUnarchiver.unarchiveObject(with: data) as? CPYDraggedData
                expect(unarchiveData).toNot(beNil())
                expect(unarchiveData?.type) == draggedData.type
                expect(unarchiveData?.folderIdentifier) == draggedData.folderIdentifier
                expect(unarchiveData?.snippetIdentifier).to(beNil())
                expect(unarchiveData?.index) == draggedData.index
            }

        }

    }
}

final class ClipyBridgeTests: XCTestCase {
    func testSnapshotRoundTripPreservesNestedAction() throws {
        let action = ClipyBridgeAction(
            kind: "pasteClip",
            identifier: "clip-1",
            representation: "plainText"
        )
        let child = ClipyBridgeMenuItem(
            kind: .action,
            title: "Paste as Plain Text",
            toolTip: nil,
            keyEquivalent: "",
            imageData: nil,
            imageWidth: 100,
            imageHeight: 32,
            action: action,
            children: []
        )
        let snapshot = ClipyBridgeSnapshot(
            items: [
                ClipyBridgeMenuItem(
                    kind: .submenu,
                    title: "Example",
                    toolTip: "Full example",
                    keyEquivalent: "1",
                    imageData: nil,
                    imageWidth: nil,
                    imageHeight: nil,
                    action: action,
                    children: [child]
                )
            ],
            shortcuts: [
                ClipyBridgeShortcut(
                    kind: "main",
                    keyCode: 9,
                    modifiers: 768,
                    display: "⇧⌘V"
                )
            ],
            excludedApplications: [
                ClipyBridgeExcludedApplication(
                    identifier: "com.example.Secret",
                    name: "Secret"
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(
            ClipyBridgeSnapshot.self,
            from: data
        )

        XCTAssertEqual(decoded.items.first?.action?.kind, "pasteClip")
        XCTAssertEqual(decoded.items.first?.children.first?.action?.representation, "plainText")
        XCTAssertEqual(decoded.items.first?.children.first?.imageWidth, 100)
        XCTAssertEqual(decoded.items.first?.children.first?.imageHeight, 32)
        XCTAssertEqual(decoded.shortcuts.first?.keyCode, 9)
        XCTAssertEqual(
            decoded.excludedApplications.first?.identifier,
            "com.example.Secret"
        )
    }

    func testAllGlobalShortcutDefaultsRemainAvailable() {
        let defaults = HotKeyService.defaultKeyCombos

        XCTAssertNotNil(defaults[Constants.Menu.clip])
        XCTAssertNotNil(defaults[Constants.Menu.history])
        XCTAssertNotNil(defaults[Constants.Menu.snippet])
    }
}
