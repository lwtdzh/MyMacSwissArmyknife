//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import Sauce

enum PasteRepresentation {
    case original
    case plainText
    case pasteboardType(NSPasteboard.PasteboardType)
}

final class PasteMenuSelection: NSObject {
    let clipHash: String
    let representation: PasteRepresentation

    init(clipHash: String, representation: PasteRepresentation) {
        self.clipHash = clipHash
        self.representation = representation
    }
}

final class PasteService {

    // MARK: - Properties
    fileprivate let lock = NSRecursiveLock(name: "com.clipy-app.ClipyEnhanced.Pastable")
    fileprivate var isPastePlainText: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pastePlainText) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pastePlainTextModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.deleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.deleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isPasteAndDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pasteAndDeleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pasteAndDeleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }

    // MARK: - Modifiers
    private func isPressedModifier(_ flag: Int) -> Bool {
        let flags = NSEvent.modifierFlags
        if flag == 0 && flags.contains(.command) {
            return true
        } else if flag == 1 && flags.contains(.shift) {
            return true
        } else if flag == 2 && flags.contains(.control) {
            return true
        } else if flag == 3 && flags.contains(.option) {
            return true
        }
        return false
    }
}

// MARK: - Copy
extension PasteService {
    func paste(with clip: CPYClip, representation: PasteRepresentation) {
        guard !clip.isInvalidated else { return }
        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return }

        switch representation {
        case .original:
            copyOriginalToPasteboard(with: data)
        case .plainText:
            copyToPasteboard(with: data.stringValue)
        case .pasteboardType(let type):
            guard copyToPasteboard(with: data, type: type) else { return }
        }
        paste()
    }

    func paste(with clip: CPYClip) {
        guard !clip.isInvalidated else { return }
        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return }

        // Handling modifier actions
        let isPastePlainText = self.isPastePlainText
        let isPasteAndDeleteHistory = self.isPasteAndDeleteHistory
        let isDeleteHistory = self.isDeleteHistory
        guard isPastePlainText || isPasteAndDeleteHistory || isDeleteHistory else {
            copyToPasteboard(with: clip)
            paste()
            return
        }

        // Increment change count for don't copy paste item
        if isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.incrementChangeCount()
        }
        // Paste history
        if isPastePlainText {
            copyToPasteboard(with: data.stringValue)
            paste()
        } else if isPasteAndDeleteHistory {
            copyToPasteboard(with: clip)
            paste()
        }
        // Delete clip
        if isDeleteHistory || isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.delete(with: clip)
        }
    }

    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.deprecatedString], owner: nil)
        pasteboard.setString(string, forType: .deprecatedString)
    }

    func copyToPasteboard(with clip: CPYClip) {
        lock.lock(); defer { lock.unlock() }

        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return }

        if isPastePlainText {
            copyToPasteboard(with: data.stringValue)
            return
        }

        copyOriginalToPasteboard(with: data)
    }

    private func copyOriginalToPasteboard(with data: CPYClipData) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        let types = data.types
        pasteboard.declareTypes(types, owner: nil)
        types.forEach { type in
            switch type {
            case .deprecatedString:
                let pbString = data.stringValue
                pasteboard.setString(pbString, forType: .deprecatedString)
            case .deprecatedRTFD:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTFD)
            case .deprecatedRTF:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTF)
            case .deprecatedPDF:
                guard let pdfData = data.PDF, let pdfRep = NSPDFImageRep(data: pdfData) else { return }
                pasteboard.setData(pdfRep.pdfRepresentation, forType: .deprecatedPDF)
            case .deprecatedFilenames:
                let fileNames = data.fileNames
                pasteboard.setPropertyList(fileNames, forType: .deprecatedFilenames)
            case .deprecatedURL:
                let url = data.URLs
                pasteboard.setPropertyList(url, forType: .deprecatedURL)
            case .deprecatedTIFF:
                guard let image = data.image, let imageData = image.tiffRepresentation else { return }
                pasteboard.setData(imageData, forType: .deprecatedTIFF)
            default:
                guard let rawData = data.rawTypeData[type.rawValue] else { return }
                pasteboard.setData(rawData, forType: type)
            }
        }
    }

    private func copyToPasteboard(with data: CPYClipData, type: NSPasteboard.PasteboardType) -> Bool {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([type], owner: nil)

        if let rawData = data.rawTypeData[type.rawValue] {
            return pasteboard.setData(rawData, forType: type)
        }

        switch type {
        case .deprecatedString:
            return pasteboard.setString(data.stringValue, forType: type)
        case .deprecatedRTF, .deprecatedRTFD:
            guard let rtfData = data.RTFData else { return false }
            return pasteboard.setData(rtfData, forType: type)
        case .deprecatedPDF:
            guard let pdfData = data.PDF else { return false }
            return pasteboard.setData(pdfData, forType: type)
        case .deprecatedFilenames:
            return pasteboard.setPropertyList(data.fileNames, forType: type)
        case .deprecatedURL:
            return pasteboard.setPropertyList(data.URLs, forType: type)
        case .deprecatedTIFF:
            guard let imageData = data.image?.tiffRepresentation else { return false }
            return pasteboard.setData(imageData, forType: type)
        default:
            return false
        }
    }
}

// MARK: - Paste
extension PasteService {
    func paste() {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            ClipyBridge.pasteRequested,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
