import AppKit
import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()

    let store: ModuleStateStore
    let supervisor: ModuleSupervisor
    let scrollReverser: ScrollReverserModule
    let rightClickMenu: RightClickMenuModule
    let clipyBridge: ClipyEnhancedBridge
    let statusMenu: AppStatusMenuController

    private init() {
        ModuleSettingsDefaults.seed()
        let store = ModuleStateStore()
        let scrollReverser = ScrollReverserModule()
        let rightClickMenu = RightClickMenuModule()
        let clipyBridge = ClipyEnhancedBridge()
        let supervisor = ModuleSupervisor(
            store: store,
            inProcessModules: [
                .scrollReverser: scrollReverser,
                .rightClickMenu: rightClickMenu
            ]
        )
        self.store = store
        self.scrollReverser = scrollReverser
        self.rightClickMenu = rightClickMenu
        self.clipyBridge = clipyBridge
        self.supervisor = supervisor
        self.statusMenu = AppStatusMenuController(
            store: store,
            bridge: clipyBridge
        )
        supervisor.start()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let openResourceMonitorSettingsNotification = Notification.Name(
        "com.mymacswissarmyknife.open-resource-monitor-settings"
    )
    private static let openClipySettingsNotification = Notification.Name(
        "com.mymacswissarmyknife.clipy.open-settings"
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openResourceMonitorSettings),
            name: Self.openResourceMonitorSettingsNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openClipySettings),
            name: Self.openClipySettingsNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        SettingsWindowController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    @objc private func openResourceMonitorSettings(_ notification: Notification) {
        SettingsWindowController.shared.show(tab: .resourceMonitor)
    }

    @objc private func openClipySettings(_ notification: Notification) {
        SettingsWindowController.shared.show(tab: .clipyEnhanced)
    }
}

@main
struct MyMacSwissArmyknifeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
