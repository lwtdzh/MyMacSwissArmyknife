//
//  Constants.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/04/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

struct Constants {

    struct Application {
        static let name = "ClipyEnhanced"
    }

    struct Menu {
        static let clip = "ClipyEnhanced"
        static let history = "HistoryMenu"
        static let snippet = "SnippetsMenu"
    }

    struct Common {
        static let index = "index"
        static let title = "title"
        static let snippets = "snippets"
        static let content = "content"
        static let selector = "selector"
        static let draggedDataType = "public.data"
    }

    struct UserDefaults {
        static let hotKeys = "kCPYPrefHotKeysKey"
        static let menuIconSize = "kCPYPrefMenuIconSizeKey"
        static let maxHistorySize = "kCPYPrefMaxHistorySizeKey"
        static let storeTypes = "kCPYPrefStoreTypesKey"
        static let inputPasteCommand = "kCPYPrefInputPasteCommandKey"
        static let showIconInTheMenu = "kCPYPrefShowIconInTheMenuKey"
        static let numberOfItemsPlaceInline = "kCPYPrefNumberOfItemsPlaceInlineKey"
        static let numberOfItemsPlaceInsideFolder  = "kCPYPrefNumberOfItemsPlaceInsideFolderKey"
        static let maxMenuItemTitleLength = "kCPYPrefMaxMenuItemTitleLengthKey"
        static let menuItemsTitleStartWithZero = "kCPYPrefMenuItemsTitleStartWithZeroKey"
        static let reorderClipsAfterPasting = "kCPYPrefReorderClipsAfterPasting"
        static let addClearHistoryMenuItem = "kCPYPrefAddClearHistoryMenuItemKey"
        static let showAlertBeforeClearHistory = "kCPYPrefShowAlertBeforeClearHistoryKey"
        static let menuItemsAreMarkedWithNumbers = "menuItemsAreMarkedWithNumbers"
        static let showToolTipOnMenuItem = "showToolTipOnMenuItem"
        static let showImageInTheMenu = "showImageInTheMenu"
        static let addNumericKeyEquivalents = "addNumericKeyEquivalents"
        static let maxLengthOfToolTip = "maxLengthOfToolTipKey"
        static let loginItem = "loginItem"
        static let suppressAlertForLoginItem = "suppressAlertForLoginItem"
        static let showStatusItem = "kCPYPrefShowStatusItemKey"
        static let thumbnailWidth = "thumbnailWidth"
        static let thumbnailHeight = "thumbnailHeight"
        static let overwriteSameHistory = "kCPYPrefOverwriteSameHistroy"
        static let copySameHistory = "kCPYPrefCopySameHistroy"
        static let suppressAlertForDeleteSnippet = "kCPYSuppressAlertForDeleteSnippet"
        static let excludeApplications = "kCPYExcludeApplications"
        static let showColorPreviewInTheMenu = "kCPYPrefShowColorPreviewInTheMenu"
    }

    struct Beta {
        static let pastePlainText = "kCPYBetaPastePlainText"
        static let pastePlainTextModifier = "kCPYBetaPastePlainTextModifier"
        static let deleteHistory = "kCPYBetaDeleteHistory"
        static let deleteHistoryModifier = "kCPYBetaDeleteHistoryModifier"
        static let pasteAndDeleteHistory = "kCPYBetaPasteAndDeleteHistory"
        static let pasteAndDeleteHistoryModifier = "kCPYBetapasteAndDeleteHistoryModifier"
        static let observerScreenshot = "kCPYBetaObserveScreenshot"
    }

    struct Notification {
        static let closeSnippetEditor = "kCPYSnippetEditorWillCloseNotification"
    }

    struct Xml {
        static let fileType = "xml"
        static let type = "type"
        static let rootElement = "folders"
        static let folderElement = "folder"
        static let snippetElement = "snippet"
        static let titleElement = "title"
        static let snippetsElement = "snippets"
        static let contentElement = "content"
    }

    struct HotKey {
        static let mainKeyCombo = "kCPYHotKeyMainKeyCombo"
        static let historyKeyCombo = "kCPYHotKeyHistoryKeyCombo"
        static let snippetKeyCombo = "kCPYHotKeySnippetKeyCombo"
        static let migrateNewKeyCombo = "kCPYMigrateNewKeyCombo"
        static let folderKeyCombos = "kCPYFolderKeyCombos"
        static let clearHistoryKeyCombo = "kCPYClearHistoryKeyCombo"
    }

}

struct ClipyBridgeMenuItem: Codable {
    enum Kind: String, Codable {
        case action
        case header
        case separator
        case submenu
    }

    let kind: Kind
    let title: String
    let toolTip: String?
    let keyEquivalent: String
    let imageData: Data?
    let action: ClipyBridgeAction?
    let children: [ClipyBridgeMenuItem]
}

struct ClipyBridgeAction: Codable {
    let kind: String
    let identifier: String?
    let representation: String?
}

struct ClipyBridgeShortcut: Codable {
    let kind: String
    let keyCode: Int?
    let modifiers: Int?
    let display: String
}

struct ClipyBridgeExcludedApplication: Codable {
    let identifier: String
    let name: String
}

struct ClipyBridgeSnapshot: Codable {
    let items: [ClipyBridgeMenuItem]
    let shortcuts: [ClipyBridgeShortcut]
    let excludedApplications: [ClipyBridgeExcludedApplication]
}

enum ClipyBridge {
    static let requestSnapshot = Notification.Name(
        "com.mymacswissarmyknife.clipy.request-snapshot"
    )
    static let snapshotUpdated = Notification.Name(
        "com.mymacswissarmyknife.clipy.snapshot-updated"
    )
    static let performAction = Notification.Name(
        "com.mymacswissarmyknife.clipy.perform-action"
    )
    static let pasteRequested = Notification.Name(
        "com.mymacswissarmyknife.clipy.paste-requested"
    )

    static var snapshotURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("MyMacSwissArmyknife", isDirectory: true)
            .appendingPathComponent("ClipyEnhanced", isDirectory: true)
            .appendingPathComponent("menu-snapshot.json")
    }
}
