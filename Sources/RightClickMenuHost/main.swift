import AppKit

final class RightClickMenuHostController: NSObject, NSApplicationDelegate {
    private let configurationStore = RightClickMenuConfigurationStore()
    private let fileCreator = RightClickFileCreator()
    private var request: RightClickMenuRequest?
    private var activeMenu: NSMenu?

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showChooserNotification(_:)),
            name: RightClickMenuExtensionDescriptor.commandNotification,
            object: nil
        )
    }

    private var role: RightClickMenuProviderRole? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "RightClickMenuProviderRole"
        ) as? String else {
            return nil
        }
        return RightClickMenuProviderRole(rawValue: value)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showChooser()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ProcessInfo.processInfo.arguments.contains("--background") {
            showChooser()
        }
    }

    @objc
    private func showChooserNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.showChooser()
        }
    }

    func showChooser() {
        guard let role,
              let request = RightClickMenuRequestStore(role: role).load(),
              request.role == role else {
            return
        }
        self.request = request

        let configuration = configurationStore.load()
        let menu = NSMenu(title: "RightClickMenu")
        menu.autoenablesItems = false

        switch role {
        case .all:
            addOpenWithItems(to: menu, configuration: configuration)
            if !menu.items.isEmpty,
               !configuration.fileTemplates.isEmpty {
                menu.addItem(.separator())
            }
            addNewFileItems(to: menu, configuration: configuration)
            if configuration.showsOpenTerminal {
                if !menu.items.isEmpty {
                    menu.addItem(.separator())
                }
                menu.addItem(commandItem(
                    title: "Open Terminal Here",
                    imageName: "terminal",
                    action: #selector(openTerminal(_:))
                ))
            }
        case .openWith:
            addOpenWithItems(to: menu, configuration: configuration)
        case .newFiles:
            addNewFileItems(to: menu, configuration: configuration)
        case .openTerminal:
            return
        }

        guard !menu.items.isEmpty else {
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        activeMenu = menu
        menu.popUp(
            positioning: nil,
            at: NSEvent.mouseLocation,
            in: nil
        )
        activeMenu = nil
    }

    private func addOpenWithItems(
        to menu: NSMenu,
        configuration: RightClickMenuConfiguration
    ) {
        for application in configuration.openWithApplications where
            FileManager.default.fileExists(atPath: application.path) {
            let item = commandItem(
                title: "Open with \(application.displayName)",
                imageName: nil,
                action: #selector(openWithApplication(_:))
            )
            item.representedObject = application.path
            item.image = NSWorkspace.shared.icon(forFile: application.path)
            menu.addItem(item)
        }
    }

    private func addNewFileItems(
        to menu: NSMenu,
        configuration: RightClickMenuConfiguration
    ) {
        for (index, template) in configuration.fileTemplates.enumerated() {
            let item = commandItem(
                title: "New \(template.displayName)",
                imageName: "doc.badge.plus",
                action: #selector(createFile(_:))
            )
            item.tag = index
            menu.addItem(item)
        }
    }

    private func commandItem(
        title: String,
        imageName: String?,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = true
        if let imageName {
            item.image = NSImage(
                systemSymbolName: imageName,
                accessibilityDescription: title
            )
        }
        return item
    }

    @objc
    private func openWithApplication(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let urls = request?.context.selectedURLs,
              !urls.isEmpty else {
            return
        }
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        openConfiguration.addsToRecentItems = true
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: URL(fileURLWithPath: path),
            configuration: openConfiguration
        )
    }

    @objc
    private func createFile(_ sender: NSMenuItem) {
        let configuration = configurationStore.load()
        guard configuration.fileTemplates.indices.contains(sender.tag),
              let directory = request?.context.destinationDirectory else {
            return
        }
        do {
            let url = try fileCreator.createFile(
                from: configuration.fileTemplates[sender.tag],
                in: directory
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSLog(
                "RightClickMenu could not create file: %@",
                error.localizedDescription
            )
        }
    }

    @objc
    private func openTerminal(_ sender: NSMenuItem) {
        guard let directory = request?.context.destinationDirectory,
              let terminal = NSWorkspace.shared.urlForApplication(
                  withBundleIdentifier: "com.apple.Terminal"
              ) else {
            return
        }
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: terminal,
            configuration: openConfiguration
        )
    }
}

let application = NSApplication.shared
let controller = RightClickMenuHostController()
application.delegate = controller
application.setActivationPolicy(.accessory)
ProcessInfo.processInfo.disableAutomaticTermination(
    "Waiting for Finder commands"
)
application.finishLaunching()
application.run()
