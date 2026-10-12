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
    private let appBlocker: AppBlockerModule
    private let keepAwake: KeepAwakeModule
    private let statusItem: NSStatusItem
    private let rootMenu = NSMenu(title: "MyMacSwissArmyknife")
    private var moduleItems: [ModuleID: NSMenuItem] = [:]
    private var clipyItem: NSMenuItem?
    private var appBlockerItem: NSMenuItem?
    private var keepAwakeItem: NSMenuItem?
    private var blockSleepItem: NSMenuItem?
    private var blockLockScreenItem: NSMenuItem?
    private var isRootMenuOpen = false
    private var pendingConfigurations: [ModuleID: ModuleConfiguration]?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    init(
        store: ModuleStateStore,
        bridge: ClipyEnhancedBridge,
        appBlocker: AppBlockerModule,
        keepAwake: KeepAwakeModule
    ) {
        self.store = store
        self.bridge = bridge
        self.appBlocker = appBlocker
        self.keepAwake = keepAwake
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
            .sink { [weak self] configurations in
                self?.configurationsDidChange(configurations)
            }
            .store(in: &cancellables)
        bridge.$snapshot
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshClipySubmenu()
            }
            .store(in: &cancellables)
        appBlocker.$blockedApplications
            .dropFirst()
            .sink { [weak self] applications in
                self?.appBlockerApplicationsDidChange(applications)
            }
            .store(in: &cancellables)
        keepAwake.$isBlockingSleep
            .combineLatest(keepAwake.$isBlockingLockScreen)
            .sink { [weak self] blockSleep, blockLockScreen in
                self?.updateKeepAwakeItemStates(
                    blockSleep: blockSleep,
                    blockLockScreen: blockLockScreen
                )
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
        isRootMenuOpen = true
        updateModuleItemStates(using: store.configurations)
        updateKeepAwakeItemStates()
        bridge.requestSnapshot()
        refreshClipySubmenu()
        refreshAppBlockerSubmenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === rootMenu else { return }
        isRootMenuOpen = false
        guard let configurations = pendingConfigurations else { return }
        pendingConfigurations = nil
        rebuildRootMenu(using: configurations)
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let id = ModuleID(rawValue: sender.representedObject as? String ?? "") else {
            return
        }
        let enabled = store.configuration(for: id).isEnabled
        sender.state = enabled ? .off : .on
        store.setEnabled(!enabled, for: id)
    }

    @objc private func performClipyAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        rootMenu.cancelTracking()
        bridge.perform(box.action)
    }

    @objc private func toggleBlockedApplication(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let id = UUID(uuidString: identifier) else {
            return
        }
        toggleAppBlockerApplication(id: id)
        sender.state = appBlocker.blockedApplications.first(where: {
            $0.id == id
        })?.isEnabled == true ? .on : .off
    }

    @objc private func toggleKeepAwake(_ sender: NSMenuItem) {
        performKeepAwakePrimaryAction()
    }

    @objc private func toggleBlockSleep(_ sender: NSMenuItem) {
        let enabled = !keepAwake.isBlockingSleep
        if !keepAwake.setBlockingSleep(enabled) {
            NSSound.beep()
        }
        sender.state = keepAwake.isBlockingSleep ? .on : .off
    }

    @objc private func toggleBlockLockScreen(_ sender: NSMenuItem) {
        let enabled = !keepAwake.isBlockingLockScreen
        if !keepAwake.setBlockingLockScreen(enabled) {
            NSSound.beep()
        }
        sender.state = keepAwake.isBlockingLockScreen ? .on : .off
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func configurationsDidChange(
        _ configurations: [ModuleID: ModuleConfiguration]
    ) {
        if isRootMenuOpen {
            pendingConfigurations = configurations
            updateModuleItemStates(using: configurations)
        } else {
            rebuildRootMenu(using: configurations)
        }
    }

    private func rebuildRootMenu(
        using configurations: [ModuleID: ModuleConfiguration]? = nil
    ) {
        let configurations = configurations ?? store.configurations
        rootMenu.removeAllItems()
        moduleItems.removeAll()
        clipyItem = nil
        appBlockerItem = nil
        keepAwakeItem = nil
        blockSleepItem = nil
        blockLockScreenItem = nil

        for definition in ModuleDefinition.builtIns {
            let item = NSMenuItem(
                title: definition.displayName,
                action: #selector(toggleModule(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = definition.id.rawValue
            item.state = configurations[definition.id]?.isEnabled == true ? .on : .off
            moduleItems[definition.id] = item

            if definition.id == .clipyEnhanced {
                clipyItem = item
                if configurations[.clipyEnhanced]?.isEnabled == true {
                    item.submenu = makeClipyMenu()
                }
            } else if definition.id == .appBlocker {
                appBlockerItem = item
                item.submenu = makeAppBlockerMenu(
                    applications: appBlocker.blockedApplications
                )
            }
            rootMenu.addItem(item)
        }

        let keepAwakeItem = NSMenuItem(
            title: "Keep Awake",
            action: #selector(toggleKeepAwake(_:)),
            keyEquivalent: ""
        )
        keepAwakeItem.target = self
        self.keepAwakeItem = keepAwakeItem
        rootMenu.addItem(keepAwakeItem)

        let blockSleepItem = NSMenuItem(
            title: "Block Sleep",
            action: #selector(toggleBlockSleep(_:)),
            keyEquivalent: ""
        )
        blockSleepItem.target = self
        blockSleepItem.indentationLevel = 1
        self.blockSleepItem = blockSleepItem
        rootMenu.addItem(blockSleepItem)

        let blockLockScreenItem = NSMenuItem(
            title: "Block Lock Screen",
            action: #selector(toggleBlockLockScreen(_:)),
            keyEquivalent: ""
        )
        blockLockScreenItem.target = self
        blockLockScreenItem.indentationLevel = 1
        self.blockLockScreenItem = blockLockScreenItem
        rootMenu.addItem(blockLockScreenItem)
        updateKeepAwakeItemStates()

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

    private func updateModuleItemStates(
        using configurations: [ModuleID: ModuleConfiguration]
    ) {
        for (id, item) in moduleItems {
            item.state = configurations[id]?.isEnabled == true ? .on : .off
        }
    }

    private func refreshClipySubmenu() {
        guard let clipyItem else { return }
        clipyItem.state = store.configuration(for: .clipyEnhanced).isEnabled ? .on : .off
        clipyItem.submenu = store.configuration(for: .clipyEnhanced).isEnabled
            ? makeClipyMenu()
            : nil
    }

    private func appBlockerApplicationsDidChange(
        _ applications: [BlockedApplication]
    ) {
        if isRootMenuOpen {
            updateAppBlockerSubmenuStates(using: applications)
        } else {
            refreshAppBlockerSubmenu(using: applications)
        }
    }

    private func refreshAppBlockerSubmenu(
        using applications: [BlockedApplication]? = nil
    ) {
        appBlockerItem?.submenu = makeAppBlockerMenu(
            applications: applications ?? appBlocker.blockedApplications
        )
    }

    private func updateAppBlockerSubmenuStates(
        using applications: [BlockedApplication]
    ) {
        guard let items = appBlockerItem?.submenu?.items else { return }
        let enabledByID = Dictionary(
            uniqueKeysWithValues: applications.map {
                ($0.id.uuidString, $0.isEnabled)
            }
        )
        for item in items {
            guard let identifier = item.representedObject as? String,
                  let isEnabled = enabledByID[identifier] else {
                continue
            }
            item.state = isEnabled ? .on : .off
        }
    }

    private func updateKeepAwakeItemStates(
        blockSleep: Bool? = nil,
        blockLockScreen: Bool? = nil
    ) {
        let blocksSleep = blockSleep ?? keepAwake.isBlockingSleep
        let blocksLockScreen = blockLockScreen ?? keepAwake.isBlockingLockScreen
        keepAwakeItem?.state = blocksSleep || blocksLockScreen ? .on : .off
        blockSleepItem?.state = blocksSleep ? .on : .off
        blockLockScreenItem?.state = blocksLockScreen ? .on : .off
    }

    func displayedModuleState(_ id: ModuleID) -> NSControl.StateValue? {
        moduleItems[id]?.state
    }

    func displayedAppBlockerItems() -> [
        (title: String, state: NSControl.StateValue, isEnabled: Bool)
    ] {
        appBlockerItem?.submenu?.items.map {
            ($0.title, $0.state, $0.isEnabled)
        } ?? []
    }

    func toggleAppBlockerApplication(id: UUID) {
        appBlocker.toggleApplication(id: id)
    }

    func displayedKeepAwakeStates() -> (
        parent: NSControl.StateValue?,
        blockSleep: NSControl.StateValue?,
        blockLockScreen: NSControl.StateValue?
    ) {
        (
            keepAwakeItem?.state,
            blockSleepItem?.state,
            blockLockScreenItem?.state
        )
    }

    func performKeepAwakePrimaryAction() {
        if keepAwake.isBlockingSleep || keepAwake.isBlockingLockScreen {
            keepAwake.stop()
            return
        }

        guard keepAwake.setBlockingSleep(true),
              keepAwake.setBlockingLockScreen(true) else {
            keepAwake.stop()
            NSSound.beep()
            return
        }
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

    private func makeAppBlockerMenu(
        applications: [BlockedApplication]
    ) -> NSMenu {
        let menu = NSMenu(title: "AppBlocker")
        guard !applications.isEmpty else {
            let emptyItem = NSMenuItem(
                title: "No Apps Added",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        for application in applications {
            let item = NSMenuItem(
                title: application.displayName,
                action: #selector(toggleBlockedApplication(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = application.id.uuidString
            item.state = application.isEnabled ? .on : .off
            item.image = NSWorkspace.shared.icon(forFile: application.path)
            if #available(macOS 27.0, *) {
                item.preferredImageVisibility = .visible
            }
            menu.addItem(item)
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
        item.image = snapshot.displayImage
        if #available(macOS 27.0, *), item.image != nil {
            item.preferredImageVisibility = .visible
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
                if let item = self.highlightedModuleItem() {
                    self.rootMenu.cancelTracking()
                    self.toggleModule(item)
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
                if characters == "\r",
                   let item = self.highlightedModuleItem() {
                    self.rootMenu.cancelTracking()
                    self.toggleModule(item)
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

    private func highlightedModuleItem() -> NSMenuItem? {
        guard let item = rootMenu.highlightedItem,
              ModuleID(rawValue: item.representedObject as? String ?? "") != nil else {
            return nil
        }
        if item.submenu?.highlightedItem != nil {
            return nil
        }
        return item
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
