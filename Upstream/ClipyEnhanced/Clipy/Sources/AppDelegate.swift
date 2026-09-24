//
//  AppDelegate.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RxCocoa
import RxSwift
import Magnet
import Screeen
import RealmSwift

@NSApplicationMain
class AppDelegate: NSObject, NSMenuItemValidation {

    // MARK: - Properties
    let screenshotObserver = ScreenShotObserver()
    let disposeBag = DisposeBag()
    private var bridgeObservers = [NSObjectProtocol]()

    // MARK: - Init
    override func awakeFromNib() {
        super.awakeFromNib()
        // Migrate Realm
        Realm.migration()
    }

    // MARK: - NSMenuItem Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.clearAllHistory) {
            let realm = try! Realm()
            return !realm.objects(CPYClip.self).isEmpty
        }
        return true
    }

    // MARK: - Class Methods
    static func storeTypesDictinary() -> [String: NSNumber] {
        var storeTypes = [String: NSNumber]()
        CPYClipData.availableTypesString.forEach { storeTypes[$0] = NSNumber(value: true) }
        return storeTypes
    }

    // MARK: - Menu Actions
    @objc func showPreferenceWindow() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.mymacswissarmyknife.clipy.open-settings"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @objc func showSnippetEditorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        CPYSnippetsEditorWindowController.sharedController.showWindow(self)
    }

    @objc func terminate() {
        terminateApplication()
    }

    @objc func clearAllHistory() {
        let isShowAlert = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
        if isShowAlert {
            let alert = NSAlert()
            alert.messageText = L10n.clearHistory
            alert.informativeText = L10n.areYouSureYouWantToClearYourClipboardHistory
            alert.addButton(withTitle: L10n.clearHistory)
            alert.addButton(withTitle: L10n.cancel)
            alert.showsSuppressionButton = true

            NSApp.activate(ignoringOtherApps: true)

            let result = alert.runModal()
            if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

            if alert.suppressionButton?.state == NSControl.StateValue.on {
                AppEnvironment.current.defaults.set(false, forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
            }
            AppEnvironment.current.defaults.synchronize()
        }

        AppEnvironment.current.clipService.clearAll()
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        let realm = try! Realm()
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: clip)
    }

    @objc func selectClipPasteOption(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? PasteMenuSelection else {
            NSSound.beep()
            return
        }
        let realm = try! Realm()
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: selection.clipHash) else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: clip, representation: selection.representation)
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
        AppEnvironment.current.pasteService.paste()
    }

    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }

}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Environments
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage())
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()
        // Binding Events
        bind()

        // Services
        AppEnvironment.current.clipService.startMonitoring()
        AppEnvironment.current.dataCleanService.startMonitoring()
        AppEnvironment.current.excludeAppService.startMonitoring()
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()

        // Managers
        AppEnvironment.current.menuManager.setup()
        setupBridge()
        // Screenshot
        screenshotObserver.delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridgeObservers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
        }
    }

}

// MARK: - Bind
private extension AppDelegate {
    func bind() {
        // Observe Screenshot
        let observerScreenshot = AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.Beta.observerScreenshot, retainSelf: false)
            .compactMap { $0 }
            .share(replay: 1)
        observerScreenshot
            .subscribe(onNext: { [weak self] enabled in
                self?.screenshotObserver.isEnabled = enabled
            })
            .disposed(by: disposeBag)
        observerScreenshot
            .filter { $0 }
            .take(1)
            .subscribe(onNext: { [weak self] _ in
                self?.screenshotObserver.start()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Host Bridge
private extension AppDelegate {
    func setupBridge() {
        let center = DistributedNotificationCenter.default()
        bridgeObservers.append(
            center.addObserver(
                forName: ClipyBridge.requestSnapshot,
                object: nil,
                queue: .main
            ) { _ in
                AppEnvironment.current.menuManager.publishHostSnapshot()
            }
        )
        bridgeObservers.append(
            center.addObserver(
                forName: ClipyBridge.performAction,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.performBridgeAction(notification.userInfo)
            }
        )
        AppEnvironment.current.menuManager.publishHostSnapshot()
    }

    func performBridgeAction(_ userInfo: [AnyHashable: Any]?) {
        guard let kind = userInfo?["kind"] as? String else { return }

        switch kind {
        case "pasteClip":
            pasteClip(
                identifier: userInfo?["identifier"] as? String,
                representation: userInfo?["representation"] as? String
            )
        case "pasteSnippet":
            pasteSnippet(identifier: userInfo?["identifier"] as? String)
        case "clearHistory":
            clearAllHistory()
        case "editSnippets":
            showSnippetEditorWindow()
        case "addExcludedApplication":
            addExcludedApplication(path: userInfo?["path"] as? String)
        case "removeExcludedApplication":
            removeExcludedApplication(identifier: userInfo?["identifier"] as? String)
        case "updateShortcut":
            updateShortcut(userInfo)
        default:
            break
        }
    }

    func pasteClip(identifier: String?, representation: String?) {
        guard let identifier = identifier else { return }
        let realm = try! Realm()
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: identifier) else {
            NSSound.beep()
            return
        }

        guard let representation = representation else {
            AppEnvironment.current.pasteService.paste(with: clip)
            return
        }
        if representation == "original" {
            AppEnvironment.current.pasteService.paste(with: clip, representation: .original)
        } else if representation == "plainText" {
            AppEnvironment.current.pasteService.paste(with: clip, representation: .plainText)
        } else if representation.hasPrefix("type:") {
            let rawValue = String(representation.dropFirst("type:".count))
            AppEnvironment.current.pasteService.paste(
                with: clip,
                representation: .pasteboardType(
                    NSPasteboard.PasteboardType(rawValue: rawValue)
                )
            )
        }
    }

    func pasteSnippet(identifier: String?) {
        guard let identifier = identifier else { return }
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: identifier) else {
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
        AppEnvironment.current.pasteService.paste()
    }

    func addExcludedApplication(path: String?) {
        guard let path = path,
              let bundle = Bundle(url: URL(fileURLWithPath: path)),
              let info = bundle.infoDictionary,
              let appInfo = CPYAppInfo(info: info as [String: AnyObject]) else {
            return
        }
        AppEnvironment.current.excludeAppService.add(with: appInfo)
        AppEnvironment.current.menuManager.publishHostSnapshot()
    }

    func removeExcludedApplication(identifier: String?) {
        guard let identifier = identifier,
              let appInfo = AppEnvironment.current.excludeAppService.applications.first(
                where: { $0.identifier == identifier }
              ) else {
            return
        }
        AppEnvironment.current.excludeAppService.delete(with: appInfo)
        AppEnvironment.current.menuManager.publishHostSnapshot()
    }

    func updateShortcut(_ userInfo: [AnyHashable: Any]?) {
        guard let shortcut = userInfo?["shortcut"] as? String else { return }

        let keyCombo: KeyCombo?
        if let keyCode = (userInfo?["keyCode"] as? NSNumber)?.intValue,
           let modifiers = (userInfo?["modifiers"] as? NSNumber)?.intValue {
            keyCombo = KeyCombo(
                QWERTYKeyCode: keyCode,
                carbonModifiers: modifiers
            )
        } else {
            keyCombo = nil
        }

        switch shortcut {
        case "main":
            AppEnvironment.current.hotKeyService.change(with: .main, keyCombo: keyCombo)
        case "history":
            AppEnvironment.current.hotKeyService.change(with: .history, keyCombo: keyCombo)
        case "snippets":
            AppEnvironment.current.hotKeyService.change(with: .snippet, keyCombo: keyCombo)
        case "clearHistory":
            AppEnvironment.current.hotKeyService.changeClearHistoryKeyCombo(keyCombo)
        default:
            return
        }
        AppEnvironment.current.menuManager.publishHostSnapshot()
    }
}

// MARK: - ScreenShotObserver Delegate
extension AppDelegate: ScreenShotObserverDelegate {
    func screenShotObserver(_ observer: ScreenShotObserver, addedItem item: NSMetadataItem) {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return }
        guard let image = NSImage(contentsOfFile: path) else { return }
        AppEnvironment.current.clipService.create(with: image)
    }
}
