import Foundation
import XCTest
@testable import MyMacSwissArmyknife

final class RightClickMenuTests: XCTestCase {
    func testDefaultTemplatesContainRequestedFileTypes() {
        XCTAssertEqual(
            RightClickFileTemplate.builtIns.map(\.fileExtension),
            ["", "txt", "docx", "xlsx", "pptx", "md"]
        )
    }

    func testConfigurationRoundTripsThroughSharedStore() throws {
        let directory = temporaryDirectory()
        let store = RightClickMenuConfigurationStore(
            fileURL: directory.appendingPathComponent("configuration.json")
        )
        let application = RightClickOpenWithApplication(
            displayName: "Editor",
            bundleIdentifier: "com.example.Editor",
            path: "/Applications/Editor.app"
        )
        let expected = RightClickMenuConfiguration(
            isEnabled: true,
            openWithApplications: [application],
            fileTemplates: [.init(displayName: "Swift File", fileExtension: ".SWIFT")],
            showsOpenTerminal: false
        )

        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
        XCTAssertEqual(store.load().fileTemplates[0].fileExtension, "swift")
    }

    func testDefaultConfigurationUsesFinderExtensionContainer() {
        XCTAssertTrue(
            RightClickMenuConfigurationStore.defaultFileURL.path.contains(
                "/Library/Containers/com.mymacswissarmyknife.host.NewFiles.Extension/Data/"
            )
        )
    }

    func testFinderUsesOneAggregateExtension() {
        XCTAssertEqual(
            RightClickMenuExtensionDescriptor.all,
            [
                RightClickMenuExtensionDescriptor(
                    role: .all,
                    hostBundleName: "RightClickNewFilesHost.app",
                    extensionBundleName: "RightClickNewFilesExtension.appex",
                    bundleIdentifier:
                        "com.mymacswissarmyknife.host.NewFiles.Extension"
                )
            ]
        )
    }

    func testCommandRequestRoundTripsThroughSharedStore() throws {
        let directory = temporaryDirectory()
        let store = RightClickMenuRequestStore(
            fileURL: directory.appendingPathComponent("request.json")
        )
        let expected = RightClickMenuRequest(
            role: .all,
            context: RightClickMenuContext(
                selectedURLs: [directory.appendingPathComponent("sample.txt")],
                targetedURL: directory
            )
        )

        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testRegistryBuildsIndependentTopLevelCommands() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let selected = directory.appendingPathComponent("sample.txt")
        var configuration = RightClickMenuConfiguration.defaults
        configuration.isEnabled = true
        configuration.openWithApplications = [
            RightClickOpenWithApplication(
                displayName: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit",
                path: "/System/Applications/TextEdit.app"
            )
        ]

        let commands = RightClickMenuCommandRegistry().commands(
            context: RightClickMenuContext(
                selectedURLs: [selected],
                targetedURL: directory
            ),
            configuration: configuration
        )

        XCTAssertEqual(commands.map(\.title), [
            "Open With",
            "New Files",
            "Open Terminal Here"
        ])
        XCTAssertEqual(commands[0].children.map(\.title), ["TextEdit"])
        XCTAssertEqual(
            commands[1].children.map(\.title),
            RightClickFileTemplate.builtIns.map(\.displayName)
        )
        XCTAssertNotNil(commands[2].action)
    }

    func testDisabledConfigurationProducesNoCommands() {
        let commands = RightClickMenuCommandRegistry().commands(
            context: RightClickMenuContext(
                selectedURLs: [],
                targetedURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
            ),
            configuration: .defaults
        )

        XCTAssertTrue(commands.isEmpty)
    }

    func testFileCreatorUsesCollisionSafeNames() throws {
        let directory = temporaryDirectory()
        let creator = RightClickFileCreator()
        let template = RightClickFileTemplate(
            displayName: "Text File",
            fileExtension: "txt"
        )

        let first = try creator.createFile(from: template, in: directory)
        let second = try creator.createFile(from: template, in: directory)

        XCTAssertEqual(first.lastPathComponent, "Untitled.txt")
        XCTAssertEqual(second.lastPathComponent, "Untitled 2.txt")
    }

    func testOfficeTemplatesAreValidZipArchives() throws {
        let directory = temporaryDirectory()
        let creator = RightClickFileCreator()
        let officeTemplates = RightClickFileTemplate.builtIns.filter {
            $0.contentKind != .empty
        }

        for template in officeTemplates {
            let url = try creator.createFile(from: template, in: directory)
            let data = try Data(contentsOf: url)
            XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-t", url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, template.displayName)
        }
    }

    @MainActor
    func testModulePersistsEnablementAndEditableItems() {
        let directory = temporaryDirectory()
        let store = RightClickMenuConfigurationStore(
            fileURL: directory.appendingPathComponent("configuration.json")
        )
        let module = RightClickMenuModule(
            store: store,
            extensionBundleExists: { true },
            installExtensions: {}
        )

        module.start()
        module.addTemplate(displayName: "Swift File", fileExtension: ".swift")
        module.addApplication(
            URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        )

        XCTAssertTrue(module.isRunning)
        XCTAssertTrue(store.load().isEnabled)
        XCTAssertTrue(
            store.load().fileTemplates.contains {
                $0.displayName == "Swift File" && $0.fileExtension == "swift"
            }
        )
        XCTAssertTrue(
            store.load().openWithApplications.contains {
                $0.bundleIdentifier == "com.apple.TextEdit"
            }
        )

        module.stop()
        XCTAssertFalse(store.load().isEnabled)
    }

    @MainActor
    func testRepeatedStartInstallsFinderExtensionOnlyOnce() {
        let directory = temporaryDirectory()
        let store = RightClickMenuConfigurationStore(
            fileURL: directory.appendingPathComponent("configuration.json")
        )
        var installationCount = 0
        let module = RightClickMenuModule(
            store: store,
            extensionBundleExists: { true },
            installExtensions: {
                installationCount += 1
            }
        )

        module.start()
        module.start()
        module.start()

        XCTAssertEqual(installationCount, 1)
        XCTAssertTrue(module.isRunning)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
