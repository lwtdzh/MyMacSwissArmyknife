import AppKit
import FinderSync
import Foundation

@objc(FinderSyncMenuController)
final class FinderSyncMenuController: NSObject {
    private let configurationStore = RightClickMenuConfigurationStore()
    private let commandRegistry = RightClickMenuCommandRegistry()
    private let fileCreator = RightClickFileCreator()
    private var nextActionTag = 1
    private var actionsByTag: [Int: RightClickMenuAction] = [:]
    private lazy var role: RightClickMenuProviderRole? = {
        guard let value = Bundle(for: FinderSyncMenuController.self).object(
            forInfoDictionaryKey: "RightClickMenuProviderRole"
        ) as? String else {
            return nil
        }
        return RightClickMenuProviderRole(rawValue: value)
    }()

    override init() {
        super.init()
    }

    @objc(menuForMenuKind:)
    dynamic func menu(for menuKind: FIMenuKind) -> NSMenu? {
        actionsByTag.removeAll(keepingCapacity: true)
        nextActionTag = 1

        let controller = FIFinderSyncController.default()
        let context = RightClickMenuContext(
            selectedURLs: controller.selectedItemURLs() ?? [],
            targetedURL: controller.targetedURL()
        )
        guard let role else {
            return nil
        }

        let configuration = configurationStore.load()
        let visibleCommands = visibleCommands(
            context: context,
            configuration: configuration
        )
        guard !visibleCommands.isEmpty else {
            return nil
        }

        let menu = NSMenu(title: "")
        let parentItem = NSMenuItem(
            title: "RightClickMenu",
            action: nil,
            keyEquivalent: ""
        )
        parentItem.submenu = nativeSubmenu(for: visibleCommands)
        menu.addItem(parentItem)
        return menu
    }

    private func nativeSubmenu(
        for commandGroups: [RightClickMenuCommand]
    ) -> NSMenu {
        let submenu = NSMenu(title: "RightClickMenu")

        for group in commandGroups {
            if group.children.isEmpty {
                if let item = actionItem(for: group, title: group.title) {
                    submenu.addItem(item)
                }
                continue
            }

            for command in group.children {
                let title: String
                switch group.id {
                case OpenWithCommandProvider().id:
                    title = "Open with \(command.title)"
                case NewFilesCommandProvider().id:
                    title = "New \(command.title)"
                default:
                    title = command.title
                }
                if let item = actionItem(for: command, title: title) {
                    submenu.addItem(item)
                }
            }
        }
        return submenu
    }

    private func actionItem(
        for command: RightClickMenuCommand,
        title: String
    ) -> NSMenuItem? {
        guard let action = command.action else {
            return nil
        }
        let selector: Selector
        switch action {
        case .openWith:
            selector = #selector(openWithCommand(_:))
        case .createFile:
            selector = #selector(createFileCommand(_:))
        case .openTerminal:
            selector = #selector(openTerminalCommand(_:))
        }
        let item = NSMenuItem(
            title: title,
            action: selector,
            keyEquivalent: ""
        )
        let tag = nextActionTag
        nextActionTag += 1
        item.tag = tag
        actionsByTag[tag] = action
        item.isEnabled = true
        return item
    }

    @objc(openWithCommand:)
    dynamic func openWithCommand(_ sender: Any?) {
        performCommand(sender)
    }

    @objc(createFileCommand:)
    dynamic func createFileCommand(_ sender: Any?) {
        performCommand(sender)
    }

    @objc(openTerminalCommand:)
    dynamic func openTerminalCommand(_ sender: Any?) {
        performCommand(sender)
    }

    private func performCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else {
            NSLog("RightClickMenu action sender is not an NSMenuItem")
            return
        }
        guard let action = actionsByTag[item.tag] else {
            NSLog(
                "RightClickMenu could not resolve action for tag=%ld title=%@",
                item.tag,
                item.title
            )
            return
        }
        switch action {
        case let .openWith(application, urls):
            open(
                urls,
                withApplicationAt: URL(fileURLWithPath: application.path)
            )
        case let .createFile(template, directory):
            do {
                let url = try fileCreator.createFile(
                    from: template,
                    in: directory
                )
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog(
                    "RightClickMenu could not create file: %@",
                    error.localizedDescription
                )
            }
        case let .openTerminal(directory):
            guard let terminal = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Terminal"
            ) else {
                NSLog("RightClickMenu could not resolve Terminal")
                return
            }
            open([directory], withApplicationAt: terminal)
        }
    }

    private func visibleCommands(
        context: RightClickMenuContext,
        configuration: RightClickMenuConfiguration
    ) -> [RightClickMenuCommand] {
        let commands = commandRegistry.commands(
            context: context,
            configuration: configuration
        )
        guard let role else {
            return []
        }
        return commands.filter {
            switch role {
            case .all:
                return true
            case .openWith:
                return $0.id == OpenWithCommandProvider().id
            case .newFiles:
                return $0.id == NewFilesCommandProvider().id
            case .openTerminal:
                return $0.id == OpenTerminalCommandProvider().id
            }
        }
    }

    private func open(_ urls: [URL], withApplicationAt applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = true
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("RightClickMenu could not open item: %@", error.localizedDescription)
            }
        }
    }
}
