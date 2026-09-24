import Foundation

struct RightClickMenuContext: Codable, Equatable {
    let selectedURLs: [URL]
    let targetedURL: URL?

    var destinationDirectory: URL? {
        if let targetedURL, targetedURL.hasDirectoryPath {
            return targetedURL
        }
        if selectedURLs.count == 1, selectedURLs[0].hasDirectoryPath {
            return selectedURLs[0]
        }
        return selectedURLs.first?.deletingLastPathComponent()
    }
}

enum RightClickMenuAction: Equatable {
    case openWith(application: RightClickOpenWithApplication, urls: [URL])
    case createFile(template: RightClickFileTemplate, directory: URL)
    case openTerminal(directory: URL)
}

struct RightClickMenuCommand: Equatable, Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let action: RightClickMenuAction?
    let children: [RightClickMenuCommand]

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        action: RightClickMenuAction? = nil,
        children: [RightClickMenuCommand] = []
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.action = action
        self.children = children
    }
}

protocol RightClickMenuCommandProvider {
    var id: String { get }

    func commands(
        context: RightClickMenuContext,
        configuration: RightClickMenuConfiguration
    ) -> [RightClickMenuCommand]
}

enum RightClickMenuProviderRole: String, CaseIterable, Codable {
    case all
    case openWith = "open-with"
    case newFiles = "new-files"
    case openTerminal = "open-terminal"
}

struct RightClickMenuExtensionDescriptor: Equatable {
    static let commandNotification = Notification.Name(
        "com.mymacswissarmyknife.right-click-menu.show"
    )

    let role: RightClickMenuProviderRole
    let hostBundleName: String
    let extensionBundleName: String
    let bundleIdentifier: String

    static let all: [RightClickMenuExtensionDescriptor] = [
        .init(
            role: .all,
            hostBundleName: "RightClickNewFilesHost.app",
            extensionBundleName: "RightClickNewFilesExtension.appex",
            bundleIdentifier: "com.mymacswissarmyknife.host.NewFiles.Extension"
        )
    ]
}

struct OpenWithCommandProvider: RightClickMenuCommandProvider {
    let id = "open-with"

    func commands(
        context: RightClickMenuContext,
        configuration: RightClickMenuConfiguration
    ) -> [RightClickMenuCommand] {
        guard !context.selectedURLs.isEmpty else { return [] }
        let applications = configuration.openWithApplications.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !applications.isEmpty else { return [] }

        let children = applications.map { application in
            RightClickMenuCommand(
                id: "\(id).\(application.id.uuidString)",
                title: application.displayName,
                action: .openWith(
                    application: application,
                    urls: context.selectedURLs
                )
            )
        }
        return [
            RightClickMenuCommand(
                id: id,
                title: "Open With",
                systemImage: "square.and.arrow.up",
                children: children
            )
        ]
    }
}

struct NewFilesCommandProvider: RightClickMenuCommandProvider {
    let id = "new-files"

    func commands(
        context: RightClickMenuContext,
        configuration: RightClickMenuConfiguration
    ) -> [RightClickMenuCommand] {
        guard let directory = context.destinationDirectory,
              !configuration.fileTemplates.isEmpty else {
            return []
        }
        let children = configuration.fileTemplates.map { template in
            RightClickMenuCommand(
                id: "\(id).\(template.id.uuidString)",
                title: template.displayName,
                action: .createFile(template: template, directory: directory)
            )
        }
        return [
            RightClickMenuCommand(
                id: id,
                title: "New Files",
                systemImage: "doc.badge.plus",
                children: children
            )
        ]
    }
}

struct OpenTerminalCommandProvider: RightClickMenuCommandProvider {
    let id = "open-terminal"

    func commands(
        context: RightClickMenuContext,
        configuration: RightClickMenuConfiguration
    ) -> [RightClickMenuCommand] {
        guard configuration.showsOpenTerminal,
              let directory = context.destinationDirectory else {
            return []
        }
        return [
            RightClickMenuCommand(
                id: id,
                title: "Open Terminal Here",
                systemImage: "terminal",
                action: .openTerminal(directory: directory)
            )
        ]
    }
}

struct RightClickMenuCommandRegistry {
    let providers: [any RightClickMenuCommandProvider]

    init(
        providers: [any RightClickMenuCommandProvider] = [
            OpenWithCommandProvider(),
            NewFilesCommandProvider(),
            OpenTerminalCommandProvider()
        ]
    ) {
        self.providers = providers
    }

    func commands(
        context: RightClickMenuContext,
        configuration: RightClickMenuConfiguration
    ) -> [RightClickMenuCommand] {
        guard configuration.isEnabled else { return [] }
        return providers.flatMap {
            $0.commands(context: context, configuration: configuration)
        }
    }
}
