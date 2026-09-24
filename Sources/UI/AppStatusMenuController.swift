import AppKit
import Combine

@MainActor
final class AppStatusMenuController: NSObject, NSMenuDelegate {
    private final class ActionBox: NSObject {
        let action: ClipyMenuAction

        init(_ action: ClipyMenuAction) {
            self.action = action
        }
    }

    private let store: ModuleStateStore
    private let bridge: ClipyEnhancedBridge
    private let statusItem: NSStatusItem
    private let rootMenu = NSMenu(title: "MyMacSwissArmyknife")
    private var clipyItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    init(store: ModuleStateStore, bridge: ClipyEnhancedBridge) {
        self.store = store
        self.bridge = bridge
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "wrench.and.screwdriver",
            accessibilityDescription: "MyMacSwissArmyknife"
        )
        statusItem.button?.toolTip = "MyMacSwissArmyknife"
        statusItem.menu = rootMenu
        rootMenu.delegate = self

        store.$configurations
            .sink { [weak self] _ in
                self?.rebuildRootMenu()
            }
            .store(in: &cancellables)
        bridge.$snapshot
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshClipySubmenu()
            }
            .store(in: &cancellables)

        installEventMonitor()
        rebuildRootMenu()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === rootMenu else { return }
        bridge.requestSnapshot()
        refreshClipySubmenu()
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let id = ModuleID(rawValue: sender.representedObject as? String ?? "") else {
            return
        }
        let enabled = store.configuration(for: id).isEnabled
        store.setEnabled(!enabled, for: id)
    }

    @objc private func performClipyAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        rootMenu.cancelTracking()
        bridge.perform(box.action)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func rebuildRootMenu() {
        rootMenu.removeAllItems()

        for definition in ModuleDefinition.builtIns {
            let item = NSMenuItem(
                title: definition.displayName,
                action: #selector(toggleModule(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = definition.id.rawValue
            item.state = store.configuration(for: definition.id).isEnabled ? .on : .off

            if definition.id == .clipyEnhanced {
                clipyItem = item
                if store.configuration(for: .clipyEnhanced).isEnabled {
                    item.submenu = makeClipyMenu()
                }
            }
            rootMenu.addItem(item)
        }

        rootMenu.addItem(.separator())
        let settings = NSMenuItem(
            title: "Open Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        rootMenu.addItem(settings)

        let quitItem = NSMenuItem(
            title: "Quit MyMacSwissArmyknife",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        rootMenu.addItem(quitItem)
    }

    private func refreshClipySubmenu() {
        guard let clipyItem else { return }
        clipyItem.state = store.configuration(for: .clipyEnhanced).isEnabled ? .on : .off
        clipyItem.submenu = store.configuration(for: .clipyEnhanced).isEnabled
            ? makeClipyMenu()
            : nil
    }

    private func makeClipyMenu() -> NSMenu {
        let menu = NSMenu(title: "ClipyEnhanced")
        for snapshot in bridge.snapshot.items {
            menu.addItem(makeMenuItem(snapshot))
        }
        if menu.items.isEmpty {
            let loading = NSMenuItem(
                title: "Loading...",
                action: nil,
                keyEquivalent: ""
            )
            loading.isEnabled = false
            menu.addItem(loading)
        }
        return menu
    }

    private func makeMenuItem(_ snapshot: ClipyMenuItemSnapshot) -> NSMenuItem {
        if snapshot.kind == .separator {
            return .separator()
        }

        let item = NSMenuItem(
            title: snapshot.title,
            action: snapshot.action == nil ? nil : #selector(performClipyAction(_:)),
            keyEquivalent: snapshot.keyEquivalent
        )
        item.target = self
        item.toolTip = snapshot.toolTip
        item.isEnabled = snapshot.kind != .header
        if let imageData = snapshot.imageData {
            item.image = NSImage(data: imageData)
        }
        if let action = snapshot.action {
            item.representedObject = ActionBox(action)
        }
        if snapshot.kind == .submenu {
            let submenu = NSMenu(title: snapshot.title)
            snapshot.children.forEach {
                submenu.addItem(makeMenuItem($0))
            }
            item.submenu = submenu
        }
        return item
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .leftMouseUp,
               event.window?.level == .popUpMenu {
                if self.shouldToggleClipyItem() {
                    self.rootMenu.cancelTracking()
                    self.toggleModule(self.clipyItem!)
                    return nil
                }
                if let item = self.highlightedClipyActionItem(),
                   item.submenu != nil {
                    self.performClipyAction(item)
                    return nil
                }
            }

            if event.type == .keyDown,
               let characters = event.charactersIgnoringModifiers {
                if characters == "\r", self.shouldToggleClipyItem() {
                    self.rootMenu.cancelTracking()
                    self.toggleModule(self.clipyItem!)
                    return nil
                }
                if characters == "\r",
                   let item = self.highlightedClipyActionItem() {
                    self.performClipyAction(item)
                    return nil
                }
                if let submenu = self.clipyItem?.submenu,
                   let item = self.menuItem(
                       withKeyEquivalent: characters,
                       in: submenu
                   ) {
                    self.performClipyAction(item)
                    return nil
                }
            }
            return event
        }
    }

    private func shouldToggleClipyItem() -> Bool {
        guard rootMenu.highlightedItem === clipyItem else { return false }
        return clipyItem?.submenu?.highlightedItem == nil
    }

    private func highlightedClipyActionItem() -> NSMenuItem? {
        guard let clipyItem,
              rootMenu.highlightedItem === clipyItem,
              let submenu = clipyItem.submenu else {
            return nil
        }
        let item = deepestHighlightedItem(in: submenu)
        return item?.representedObject is ActionBox ? item : nil
    }

    private func deepestHighlightedItem(in menu: NSMenu) -> NSMenuItem? {
        guard let item = menu.highlightedItem else { return nil }
        if let submenu = item.submenu,
           let nested = deepestHighlightedItem(in: submenu) {
            return nested
        }
        return item
    }

    private func menuItem(
        withKeyEquivalent keyEquivalent: String,
        in menu: NSMenu
    ) -> NSMenuItem? {
        for item in menu.items {
            if item.keyEquivalent == keyEquivalent,
               item.representedObject is ActionBox {
                return item
            }
            if let submenu = item.submenu,
               let nested = menuItem(
                   withKeyEquivalent: keyEquivalent,
                   in: submenu
               ) {
                return nested
            }
        }
        return nil
    }
}
