//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Carbon.HIToolbox
import Magnet
import PINCache
import RealmSwift
import RxCocoa
import RxSwift

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    fileprivate var snippetMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    fileprivate let snippetIcon = Asset.iconText.image
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    fileprivate let previewPadding: CGFloat = 8
    fileprivate let previewMaxWidth: CGFloat = 280
    fileprivate let previewMaxHeight: CGFloat = 220
    fileprivate var previewPanel: NSPanel?
    fileprivate var previewImageView: NSImageView?
    fileprivate var previewClipHash: String?
    fileprivate var menuEventMonitor: Any?
    fileprivate var openMenuIDs = Set<ObjectIdentifier>()
    // Realm
    fileprivate let realm = try! Realm()
    fileprivate var clipToken: NotificationToken?
    fileprivate var snippetToken: NotificationToken?

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
    }

    func setup() {
        bind()
        installMenuEventMonitor()
        createClipMenu()
        removeStatusItem()
    }

    deinit {
        if let monitor = menuEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

}

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType) {
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        case .snippet:
            menu = snippetMenu
        }
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func popUpSnippetFolder(_ folder: CPYFolder) {
        let folderMenu = NSMenu(title: folder.title)
        // Folder title
        let labelItem = NSMenuItem(title: folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        // Snippets
        var index = firstIndexOfMenuItems()
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index)
                folderMenu.addItem(subMenuItem)
                index += 1
            }
        folderMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // Realm Notification
        clipToken = realm.objects(CPYClip.self)
                        .observe { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                self?.createClipMenu()
                            }
                        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                self?.createClipMenu()
                            }
                        }
        // Sort clips
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.reorderClipsAfterPasting, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                guard let wSelf = self else { return }
                wSelf.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings
        let defaults = AppEnvironment.current.defaults
        var menuChangedObservables = [Observable<Void>]()
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addClearHistoryMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showIconInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInline, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInsideFolder, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxMenuItemTitleLength, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsTitleStartWithZero, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsAreMarkedWithNumbers, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showToolTipOnMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showImageInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addNumericKeyEquivalents, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxLengthOfToolTip, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showColorPreviewInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        Observable.merge(menuChangedObservables)
            .throttle(.seconds(1), scheduler: MainScheduler.instance)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Menus
private extension MenuManager {
    func installMenuEventMonitor() {
        menuEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .leftMouseUp,
                event.window?.level == .popUpMenu,
                let item = self.highlightedClipItem(),
                item.submenu != nil {
                self.performPrimaryAction(for: item)
                return nil
            }

            if event.type == .keyDown,
                let characters = event.charactersIgnoringModifiers {
                if characters == "\r", let item = self.highlightedClipItem() {
                    self.performPrimaryAction(for: item)
                    return nil
                }
                if let item = self.openRootMenu()?.items.first(where: { $0.keyEquivalent == characters && $0.submenu != nil }) {
                    self.performPrimaryAction(for: item)
                    return nil
                }
            }

            return event
        }
    }

    func visibleRootMenu() -> NSMenu? {
        return openRootMenu().flatMap { $0.highlightedItem == nil ? nil : $0 }
    }

    func openRootMenu() -> NSMenu? {
        return [clipMenu, historyMenu].compactMap { $0 }.first { openMenuIDs.contains(ObjectIdentifier($0)) }
    }

    func highlightedClipItem() -> NSMenuItem? {
        guard let menu = visibleRootMenu(), let item = deepestHighlightedItem(in: menu) else { return nil }
        guard item.action == #selector(AppDelegate.selectClipMenuItem(_:)) else { return nil }
        return item
    }

    func deepestHighlightedItem(in menu: NSMenu) -> NSMenuItem? {
        guard let item = menu.highlightedItem else { return nil }
        if let submenu = item.submenu, let nestedItem = deepestHighlightedItem(in: submenu) {
            return nestedItem
        }
        return item
    }

    func performPrimaryAction(for item: NSMenuItem) {
        item.menu?.cancelTracking()
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(AppDelegate.selectClipMenuItem(_:)), to: nil, from: item)
        }
    }

     func createClipMenu() {
        hidePreviewPanel()
        clipMenu = NSMenu(title: Constants.Application.name)
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)
        clipMenu?.delegate = self
        historyMenu?.delegate = self
        snippetMenu?.delegate = self

        addHistoryItems(clipMenu!)
        addHistoryItems(historyMenu!)

        addSnippetItems(clipMenu!, separateMenu: true)
        addSnippetItems(snippetMenu!, separateMenu: false)

        clipMenu?.addItem(NSMenuItem.separator())

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            clipMenu?.addItem(NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory)))
        }

        clipMenu?.addItem(NSMenuItem(title: L10n.editSnippets, action: #selector(AppDelegate.showSnippetEditorWindow)))

        statusItem?.menu = clipMenu
        publishHostSnapshot()
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func makeSubmenuItem(_ count: Int, start: Int, end: Int, numberOfItems: Int) -> NSMenuItem {
        var count = count
        if start == 0 {
            count -= 1
        }
        var lastNumber = count + numberOfItems
        if end < lastNumber {
            lastNumber = end
        }
        let menuItemTitle = "\(count + 1) - \(lastNumber)"
        return makeSubmenuItem(menuItemTitle)
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        subMenu.delegate = self
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return subMenuItem
    }

    func makeFolderHeaderMenuItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: trimTitle(title), action: nil)
        menuItem.isEnabled = false
        menuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return menuItem
    }

    func incrementListNumber(_ listNumber: NSInteger, max: NSInteger, start: NSInteger) -> NSInteger {
        var listNumber = listNumber + 1
        if listNumber == max && max == 10 && start == 1 {
            listNumber = 0
        }
        return listNumber
    }

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }

    func displayTitle(_ title: String?, preservingGeneratedTitle preserveGeneratedTitle: Bool) -> String {
        guard preserveGeneratedTitle else { return trimTitle(title) }
        return title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func isGeneratedPasteboardTitle(_ title: String) -> Bool {
        if title.hasPrefix("Binary Data on ") { return true }
        return title.range(
            of: #"^[A-Z0-9]+ Image on \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#,
            options: .regularExpression
        ) != nil
    }
}

// MARK: - Clips
private extension MenuManager {
    func addHistoryItems(_ menu: NSMenu) {
        let placeInLine = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        let placeInsideFolder = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // History title
        let labelItem = NSMenuItem(title: L10n.history, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        // History
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        var subMenuCount = placeInLine
        var subMenuIndex = 1 + placeInLine

        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipResults = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        let currentSize = Int(clipResults.count)
        var i = 0
        for clip in clipResults {
            if placeInLine < 1 || placeInLine - 1 < i {
                // Folder
                if i == subMenuCount {
                    let subMenuItem = makeSubmenuItem(subMenuCount, start: firstIndex, end: currentSize, numberOfItems: placeInsideFolder)
                    menu.addItem(subMenuItem)
                    listNumber = firstIndex
                }

                // Clip
                if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                    let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                    subMenu.addItem(menuItem)
                    listNumber = incrementListNumber(listNumber, max: placeInsideFolder, start: firstIndex)
                }
            } else {
                // Clip
                let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                menu.addItem(menuItem)
                listNumber = incrementListNumber(listNumber, max: placeInLine, start: firstIndex)
            }

            i += 1
            if i == subMenuCount + placeInsideFolder {
                subMenuCount += placeInsideFolder
                subMenuIndex += 1
            }

            if maxHistory <= i { break }
        }
    }

    func makeClipMenuItem(_ clip: CPYClip, index: Int, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowToolTip = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        let isShowImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)

        var keyEquivalent = ""

        if addNumbericKeyEquivalents && (index <= kMaxKeyEquivalents) {
            let isStartFromZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)

            var shortCutNumber = (isStartFromZero) ? index : index + 1
            if shortCutNumber == kMaxKeyEquivalents {
                shortCutNumber = 0
            }
            keyEquivalent = "\(shortCutNumber)"
        }

        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipString = clip.title
        let title = displayTitle(clipString, preservingGeneratedTitle: isGeneratedPasteboardTitle(clipString))
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: keyEquivalent)
        menuItem.representedObject = clip.dataHash
        menuItem.submenu = makePasteOptionsMenu(for: clip)

        if isShowToolTip {
            let maxLengthOfToolTip = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
            let toIndex = (clipString.count < maxLengthOfToolTip) ? clipString.count : maxLengthOfToolTip
            menuItem.toolTip = (clipString as NSString).substring(to: toIndex)
        }

        if primaryPboardType == .deprecatedTIFF && title.isEmpty {
            menuItem.title = menuItemTitle("(Image)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        } else if primaryPboardType == .deprecatedPDF {
            menuItem.title = menuItemTitle("(PDF)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        } else if primaryPboardType == .deprecatedFilenames && title.isEmpty {
            menuItem.title = menuItemTitle("(Filenames)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        }

        if !clip.thumbnailPath.isEmpty && !clip.isColorCode && isShowImage {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }
        if !clip.thumbnailPath.isEmpty && clip.isColorCode && isShowColorCode {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }

        return menuItem
    }

    func makePasteOptionsMenu(for clip: CPYClip) -> NSMenu {
        let menu = NSMenu(title: clip.title)
        menu.delegate = self

        let originalItem = NSMenuItem(
            title: L10n.pasteOriginalAllFormats,
            action: #selector(AppDelegate.selectClipPasteOption(_:)),
            keyEquivalent: ""
        )
        originalItem.representedObject = PasteMenuSelection(clipHash: clip.dataHash, representation: .original)
        menu.addItem(originalItem)

        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return menu }

        if !data.stringValue.isEmpty {
            let plainTextItem = NSMenuItem(
                title: L10n.pasteAsPlainText,
                action: #selector(AppDelegate.selectClipPasteOption(_:)),
                keyEquivalent: ""
            )
            plainTextItem.representedObject = PasteMenuSelection(clipHash: clip.dataHash, representation: .plainText)
            menu.addItem(plainTextItem)
        }

        var addedTitles = Set<String>()
        data.types.filter { !CPYClipData.isPlainTextType($0) }.forEach { type in
            let representationTitle = CPYClipData.pasteOptionTitle(for: type)
            guard addedTitles.insert(representationTitle).inserted else { return }

            let itemTitle = L10n.pasteAs(representationTitle)
            let item = NSMenuItem(
                title: itemTitle,
                action: #selector(AppDelegate.selectClipPasteOption(_:)),
                keyEquivalent: ""
            )
            item.representedObject = PasteMenuSelection(
                clipHash: clip.dataHash,
                representation: .pasteboardType(type)
            )
            menu.addItem(item)
        }

        return menu
    }
}

// MARK: - Snippets
private extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        guard !folderResults.isEmpty else { return }
        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        // Snippet title
        let labelItem = NSMenuItem(title: L10n.snippet, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        let firstIndex = firstIndexOfMenuItems()

        folderResults
            .filter { $0.enable }
            .forEach { folder in
                var i = firstIndex
                let snippets = folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                    .filter { $0.enable }

                if folder.showsContentsInMenu {
                    menu.addItem(makeFolderHeaderMenuItem(folder.title))
                    snippets.forEach { snippet in
                        menu.addItem(makeSnippetMenuItem(snippet, listNumber: i))
                        i += 1
                    }
                    return
                }

                let subMenuItem = makeSubmenuItem(folder.title)
                menu.addItem(subMenuItem)
                snippets
                    .forEach { snippet in
                        subMenuItem.submenu?.addItem(makeSnippetMenuItem(snippet, listNumber: i))
                        i += 1
                    }
            }
    }

    func makeSnippetMenuItem(_ snippet: CPYSnippet, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.identifier
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil

        return menuItem
    }
}

// MARK: - Status Item
private extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        if type == .none { return }

        let image: NSImage?
        switch type {
        case .black:
            image = Asset.statusbarMenuBlack.image
        case .white:
            image = Asset.statusbarMenuWhite.image
        case .none: return
        }
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        statusItem?.image = image
        statusItem?.highlightMode = true
        statusItem?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.menu = clipMenu
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
private extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}

// MARK: - Host Bridge
extension MenuManager {
    func publishHostSnapshot() {
        guard let clipMenu = clipMenu else { return }

        let snapshot = ClipyBridgeSnapshot(
            items: clipMenu.items.compactMap(makeBridgeItem),
            shortcuts: [
                makeBridgeShortcut(
                    kind: "main",
                    keyCombo: AppEnvironment.current.hotKeyService.mainKeyCombo
                ),
                makeBridgeShortcut(
                    kind: "history",
                    keyCombo: AppEnvironment.current.hotKeyService.historyKeyCombo
                ),
                makeBridgeShortcut(
                    kind: "snippets",
                    keyCombo: AppEnvironment.current.hotKeyService.snippetKeyCombo
                ),
                makeBridgeShortcut(
                    kind: "clearHistory",
                    keyCombo: AppEnvironment.current.hotKeyService.clearHistoryKeyCombo
                )
            ],
            excludedApplications: AppEnvironment.current.excludeAppService.applications.map {
                ClipyBridgeExcludedApplication(identifier: $0.identifier, name: $0.name)
            }
        )

        do {
            let url = ClipyBridge.snapshotURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            DistributedNotificationCenter.default().postNotificationName(
                ClipyBridge.snapshotUpdated,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        } catch {
            NSLog("ClipyEnhanced could not publish its host menu: %@", error.localizedDescription)
        }
    }

    private func makeBridgeItem(_ item: NSMenuItem) -> ClipyBridgeMenuItem? {
        if item.action == #selector(AppDelegate.showPreferenceWindow)
            || item.action == #selector(AppDelegate.terminate) {
            return nil
        }
        if item.isSeparatorItem {
            return ClipyBridgeMenuItem(
                kind: .separator,
                title: "",
                toolTip: nil,
                keyEquivalent: "",
                imageData: nil,
                action: nil,
                children: []
            )
        }

        let children = item.submenu?.items.compactMap(makeBridgeItem) ?? []
        let action = makeBridgeAction(item)
        let kind: ClipyBridgeMenuItem.Kind
        if item.submenu != nil {
            kind = .submenu
        } else if !item.isEnabled || action == nil {
            kind = .header
        } else {
            kind = .action
        }

        return ClipyBridgeMenuItem(
            kind: kind,
            title: item.title,
            toolTip: item.toolTip,
            keyEquivalent: item.keyEquivalent,
            imageData: makeBridgeImageData(item.image),
            action: action,
            children: children
        )
    }

    private func makeBridgeImageData(_ image: NSImage?) -> Data? {
        guard let data = image?.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    private func makeBridgeAction(_ item: NSMenuItem) -> ClipyBridgeAction? {
        switch item.action {
        case #selector(AppDelegate.selectClipMenuItem(_:)):
            guard let identifier = item.representedObject as? String else { return nil }
            return ClipyBridgeAction(
                kind: "pasteClip",
                identifier: identifier,
                representation: nil
            )
        case #selector(AppDelegate.selectClipPasteOption(_:)):
            guard let selection = item.representedObject as? PasteMenuSelection else { return nil }
            let representation: String
            switch selection.representation {
            case .original:
                representation = "original"
            case .plainText:
                representation = "plainText"
            case .pasteboardType(let type):
                representation = "type:\(type.rawValue)"
            }
            return ClipyBridgeAction(
                kind: "pasteClip",
                identifier: selection.clipHash,
                representation: representation
            )
        case #selector(AppDelegate.selectSnippetMenuItem(_:)):
            guard let identifier = item.representedObject as? String else { return nil }
            return ClipyBridgeAction(
                kind: "pasteSnippet",
                identifier: identifier,
                representation: nil
            )
        case #selector(AppDelegate.clearAllHistory):
            return ClipyBridgeAction(
                kind: "clearHistory",
                identifier: nil,
                representation: nil
            )
        case #selector(AppDelegate.showSnippetEditorWindow):
            return ClipyBridgeAction(
                kind: "editSnippets",
                identifier: nil,
                representation: nil
            )
        default:
            return nil
        }
    }

    private func makeBridgeShortcut(kind: String, keyCombo: KeyCombo?) -> ClipyBridgeShortcut {
        guard let keyCombo = keyCombo else {
            return ClipyBridgeShortcut(
                kind: kind,
                keyCode: nil,
                modifiers: nil,
                display: "None"
            )
        }

        var display = ""
        if keyCombo.modifiers & controlKey != 0 { display += "⌃" }
        if keyCombo.modifiers & optionKey != 0 { display += "⌥" }
        if keyCombo.modifiers & shiftKey != 0 { display += "⇧" }
        if keyCombo.modifiers & cmdKey != 0 { display += "⌘" }
        display += keyCombo.keyEquivalent.uppercased()

        return ClipyBridgeShortcut(
            kind: kind,
            keyCode: Int(keyCombo.QWERTYKeyCode),
            modifiers: Int(keyCombo.modifiers),
            display: display
        )
    }
}

// MARK: - Image Preview
extension MenuManager: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        openMenuIDs.insert(ObjectIdentifier(menu))
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let primaryKey = item?.representedObject as? String else {
            hidePreviewPanel()
            return
        }
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey), !clip.isInvalidated else {
            hidePreviewPanel()
            return
        }
        showPreviewPanel(for: clip)
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenuIDs.remove(ObjectIdentifier(menu))
        hidePreviewPanel()
    }
}

private extension MenuManager {
    func showPreviewPanel(for clip: CPYClip) {
        guard previewClipHash != clip.dataHash else {
            positionPreviewPanel()
            return
        }
        guard let image = previewImage(for: clip) else {
            hidePreviewPanel()
            return
        }

        previewClipHash = clip.dataHash
        let panel = previewPanel ?? makePreviewPanel()
        previewPanel = panel
        previewImageView?.image = image

        let imageSize = image.size
        let panelSize = NSSize(width: imageSize.width + previewPadding * 2, height: imageSize.height + previewPadding * 2)
        panel.contentView?.frame = NSRect(origin: .zero, size: panelSize)
        previewImageView?.frame = NSRect(x: previewPadding, y: previewPadding, width: imageSize.width, height: imageSize.height)
        positionPreviewPanel(size: panelSize)
        panel.orderFrontRegardless()
    }

    func hidePreviewPanel() {
        previewClipHash = nil
        previewPanel?.orderOut(nil)
        previewImageView?.image = nil
    }

    func previewImage(for clip: CPYClip) -> NSImage? {
        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return nil }
        return data.previewImage(maxWidth: previewMaxWidth, maxHeight: previewMaxHeight)
    }

    func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: previewMaxWidth, height: previewMaxHeight),
                            styleMask: [.borderless],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]

        let contentView = NSView(frame: panel.frame)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        panel.contentView = contentView

        let imageView = NSImageView(frame: contentView.bounds.insetBy(dx: previewPadding, dy: previewPadding))
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        contentView.addSubview(imageView)
        previewImageView = imageView

        return panel
    }

    func positionPreviewPanel(size: NSSize? = nil) {
        guard let panel = previewPanel else { return }
        let panelSize = size ?? panel.frame.size
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.screens.first { $0.visibleFrame.contains(mouseLocation) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let originX = min(mouseLocation.x + 24, screenFrame.maxX - panelSize.width - 8)
        let originY = min(max(mouseLocation.y - panelSize.height / 2, screenFrame.minY + 8), screenFrame.maxY - panelSize.height - 8)
        panel.setFrame(NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height), display: true)
    }
}
