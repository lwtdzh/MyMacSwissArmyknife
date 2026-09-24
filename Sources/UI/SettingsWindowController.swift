import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let selection: SettingsSelection

    private init() {
        let model = AppModel.shared
        let selection = SettingsSelection()
        self.selection = selection
        let content = CollectionSettingsView(
            selection: selection,
            store: model.store,
            supervisor: model.supervisor,
            scrollReverser: model.scrollReverser,
            rightClickMenu: model.rightClickMenu,
            clipyBridge: model.clipyBridge
        )
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MyMacSwissArmyknife"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 580))
        window.minSize = NSSize(width: 640, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(tab: SettingsTab? = nil) {
        guard let window else { return }
        if let tab {
            selection.selectedTab = tab
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
