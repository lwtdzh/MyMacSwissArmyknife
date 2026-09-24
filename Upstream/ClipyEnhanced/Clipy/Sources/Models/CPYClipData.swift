//
//  CPYClipData.swift
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
import SwiftHEXColors

final class CPYClipData: NSObject {

    // MARK: - Properties
    fileprivate let kTypesKey       = "types"
    fileprivate let kStringValueKey = "stringValue"
    fileprivate let kRTFDataKey     = "RTFData"
    fileprivate let kPDFKey         = "PDF"
    fileprivate let kFileNamesKey   = "filenames"
    fileprivate let kURLsKey        = "URL"
    fileprivate let kImageKey       = "image"
    fileprivate let kRawTypeDataKey = "rawTypeData"

    var types          = [NSPasteboard.PasteboardType]()
    var fileNames      = [String]()
    var URLs           = [String]()
    var stringValue    = ""
    var RTFData: Data?
    var PDF: Data?
    var image: NSImage?
    var rawTypeData    = [String: Data]()

    override var hash: Int {
        var hash = types.map { $0.rawValue }.joined().hash
        rawTypeData.forEach { item in
            hash ^= item.key.hash
            hash ^= (item.value as NSData).hash
        }
        if let image = self.image, let imageData = image.tiffRepresentation {
            hash ^= imageData.count
        } else if let image = self.image {
            hash ^= image.hash
        }
        if !fileNames.isEmpty {
            fileNames.forEach { hash ^= $0.hash }
        } else if !self.URLs.isEmpty {
            URLs.forEach { hash ^= $0.hash }
        } else if let pdf = PDF {
            hash ^= pdf.count
        } else if !stringValue.isEmpty {
            hash ^= stringValue.hash
        }
        if let data = RTFData {
            hash ^= data.count
        }
        return hash
    }
    var primaryType: NSPasteboard.PasteboardType? {
        return types.first
    }
    var isOnlyStringType: Bool {
        return !types.isEmpty && types.allSatisfy { CPYClipData.stringTypeNames.contains($0.rawValue) }
    }
    var thumbnailImage: NSImage? {
        let defaults = UserDefaults.standard
        let width = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        let height = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)

        if let image = image {
            return image.resizeImage(CGFloat(width), CGFloat(height))
        } else if let fileName = fileNames.first, let path = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: path) {
             // In the case of the local file correct data is not included in the image variable
             // Judge the image from the path and create a thumbnail
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp":
                return NSImage(contentsOfFile: fileName)?.resizeImage(CGFloat(width), CGFloat(height))
            default: break
            }
        }
        return nil
    }
    var colorCodeImage: NSImage? {
        guard let color = NSColor(hexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
    }
    var imageFormatName: String? {
        for type in types {
            if let formatName = CPYClipData.imageFormatName(forTypeName: type.rawValue) {
                return formatName
            }
        }
        for data in rawTypeData.values {
            if let formatName = CPYClipData.imageFormatName(forImageData: data) {
                return formatName
            }
        }
        return nil
    }
    var isImageData: Bool {
        return image != nil || imageFormatName != nil
    }
    var isUnrecognizedBinaryData: Bool {
        return !rawTypeData.isEmpty
            && stringValue.isEmpty
            && RTFData == nil
            && PDF == nil
            && fileNames.isEmpty
            && URLs.isEmpty
            && image == nil
    }

    static var availableTypes: [NSPasteboard.PasteboardType] {
        return [.deprecatedString,
                .deprecatedRTF,
                .deprecatedRTFD,
                .deprecatedPDF,
                .deprecatedFilenames,
                .deprecatedURL,
                .deprecatedTIFF]
    }
    static let binaryStoreTypeName = "Binary"
    static var availableTypesString: [String] {
        return ["String",
                "RTF",
                "RTFD",
                "PDF",
                "Filenames",
                "URL",
                "TIFF",
                binaryStoreTypeName]
    }
    static var availableTypesDictinary: [NSPasteboard.PasteboardType: String] {
        var availableTypes = [NSPasteboard.PasteboardType: String]()
        zip(CPYClipData.availableTypes, CPYClipData.availableTypesString).forEach { availableTypes[$0] = $1 }
        CPYClipData.stringTypeNames.forEach { availableTypes[NSPasteboard.PasteboardType(rawValue: $0)] = "String" }
        CPYClipData.rtfTypeNames.forEach { availableTypes[NSPasteboard.PasteboardType(rawValue: $0)] = "RTF" }
        CPYClipData.rtfdTypeNames.forEach { availableTypes[NSPasteboard.PasteboardType(rawValue: $0)] = "RTFD" }
        CPYClipData.pdfTypeNames.forEach { availableTypes[NSPasteboard.PasteboardType(rawValue: $0)] = "PDF" }
        CPYClipData.filenameTypeNames.forEach { availableTypes[NSPasteboard.PasteboardType(rawValue: $0)] = "Filenames" }
        CPYClipData.urlTypeNames.forEach { availableTypes[NSPasteboard.PasteboardType(rawValue: $0)] = "URL" }
        CPYClipData.imageTypeFormatNames.keys.forEach { availableTypes[NSPasteboard.PasteboardType(rawValue: $0)] = "TIFF" }
        return availableTypes
    }

    static func isPlainTextType(_ type: NSPasteboard.PasteboardType) -> Bool {
        return stringTypeNames.contains(type.rawValue)
    }

    static func pasteOptionTitle(for type: NSPasteboard.PasteboardType) -> String {
        if rtfdTypeNames.contains(type.rawValue) { return L10n.richTextWithAttachments }
        if rtfTypeNames.contains(type.rawValue) { return L10n.richText }
        if pdfTypeNames.contains(type.rawValue) { return "PDF" }
        if filenameTypeNames.contains(type.rawValue) { return L10n.files }
        if urlTypeNames.contains(type.rawValue) { return "URL" }
        if let formatName = imageFormatName(forTypeName: type.rawValue) { return "\(formatName) Image" }
        return L10n.rawData(type.rawValue)
    }

    private static let stringTypeNames: Set<String> = [
        NSPasteboard.PasteboardType.deprecatedString.rawValue,
        "public.utf8-plain-text",
        "public.utf16-plain-text",
        "public.utf16-external-plain-text",
        "public.plain-text",
        "NSStringPboardType"
    ]
    private static let rtfTypeNames: Set<String> = [
        NSPasteboard.PasteboardType.deprecatedRTF.rawValue,
        "public.rtf",
        "NSRTFPboardType"
    ]
    private static let rtfdTypeNames: Set<String> = [
        NSPasteboard.PasteboardType.deprecatedRTFD.rawValue,
        "com.apple.flat-rtfd",
        "com.apple.rtfd",
        "NSRTFDPboardType"
    ]
    private static let pdfTypeNames: Set<String> = [
        NSPasteboard.PasteboardType.deprecatedPDF.rawValue,
        "com.adobe.pdf",
        "NSPDFPboardType"
    ]
    private static let filenameTypeNames: Set<String> = [
        NSPasteboard.PasteboardType.deprecatedFilenames.rawValue,
        "NSFilenamesPboardType",
        "public.file-url"
    ]
    private static let urlTypeNames: Set<String> = [
        NSPasteboard.PasteboardType.deprecatedURL.rawValue,
        "NSURLPboardType",
        "public.url"
    ]
    private static let imageTypeFormatNames: [String: String] = [
        NSPasteboard.PasteboardType.deprecatedTIFF.rawValue: "TIFF",
        "public.tiff": "TIFF",
        "public.jpeg": "JPG",
        "public.jpg": "JPG",
        "public.png": "PNG",
        "com.compuserve.gif": "GIF",
        "public.gif": "GIF",
        "com.microsoft.bmp": "BMP",
        "public.bmp": "BMP",
        "public.heic": "HEIC",
        "public.heif": "HEIF",
        "org.webmproject.webp": "WEBP",
        "com.google.webp": "WEBP",
        "public.webp": "WEBP",
        "com.apple.icns": "ICNS"
    ]

    // MARK: - Init
    init(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        super.init()
        self.types = types
        types.forEach { type in
            if let data = pasteboard.data(forType: type) {
                rawTypeData[type.rawValue] = data
            }

            if CPYClipData.stringTypeNames.contains(type.rawValue), let string = pasteboard.string(forType: type) {
                stringValue = string
            } else if CPYClipData.rtfdTypeNames.contains(type.rawValue) {
                RTFData = pasteboard.data(forType: .deprecatedRTFD)
                    ?? pasteboard.data(forType: type)
            } else if CPYClipData.rtfTypeNames.contains(type.rawValue), RTFData == nil {
                RTFData = pasteboard.data(forType: .deprecatedRTF)
                    ?? pasteboard.data(forType: type)
            } else if CPYClipData.pdfTypeNames.contains(type.rawValue) {
                PDF = pasteboard.data(forType: .deprecatedPDF)
                    ?? pasteboard.data(forType: type)
            } else if type == .deprecatedFilenames {
                guard let filenames = pasteboard.propertyList(forType: .deprecatedFilenames) as? [String] else { return }
                self.fileNames = filenames
            } else if type.rawValue == "public.file-url" {
                if let urlString = pasteboard.string(forType: type) {
                    fileNames = [URL(string: urlString)?.path ?? urlString]
                }
            } else if type == .deprecatedURL {
                guard let urls = pasteboard.propertyList(forType: .deprecatedURL) as? [String] else { return }
                URLs = urls
            } else if type.rawValue == "public.url", let urlString = pasteboard.string(forType: type) {
                URLs = [urlString]
            }
        }

        image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
        if image == nil {
            image = rawTypeData.values.compactMap { NSImage(data: $0) }.first
        }
    }

    init(image: NSImage) {
        self.types = [.deprecatedTIFF]
        self.image = image
        if let data = image.tiffRepresentation {
            rawTypeData[NSPasteboard.PasteboardType.deprecatedTIFF.rawValue] = data
        }
    }

    deinit {
        self.RTFData = nil
        self.PDF = nil
        self.image = nil
    }

    // MARK: - NSCoding
    @objc func encodeWithCoder(_ aCoder: NSCoder) {
        aCoder.encode(types.map { $0.rawValue }, forKey: kTypesKey)
        aCoder.encode(stringValue, forKey: kStringValueKey)
        aCoder.encode(RTFData, forKey: kRTFDataKey)
        aCoder.encode(PDF, forKey: kPDFKey)
        aCoder.encode(fileNames, forKey: kFileNamesKey)
        aCoder.encode(URLs, forKey: kURLsKey)
        aCoder.encode(image, forKey: kImageKey)
        aCoder.encode(rawTypeData, forKey: kRawTypeDataKey)
    }

    @objc required init(coder aDecoder: NSCoder) {
        types = (aDecoder.decodeObject(forKey: kTypesKey) as? [String])?.compactMap { NSPasteboard.PasteboardType(rawValue: $0) } ?? []
        fileNames = aDecoder.decodeObject(forKey: kFileNamesKey) as? [String] ?? [String]()
        URLs = aDecoder.decodeObject(forKey: kURLsKey) as? [String] ?? [String]()
        stringValue = aDecoder.decodeObject(forKey: kStringValueKey) as? String ?? ""
        RTFData = aDecoder.decodeObject(forKey: kRTFDataKey) as? Data
        PDF = aDecoder.decodeObject(forKey: kPDFKey) as? Data
        image = aDecoder.decodeObject(forKey: kImageKey) as? NSImage
        if let rawData = aDecoder.decodeObject(forKey: kRawTypeDataKey) as? [String: Data] {
            rawTypeData = rawData
        } else if let rawData = aDecoder.decodeObject(forKey: kRawTypeDataKey) as? [String: NSData] {
            rawTypeData = rawData.mapValues { $0 as Data }
        } else {
            rawTypeData = [String: Data]()
        }
        super.init()
    }

    func displayTitle(savedAt unixTime: Int) -> String {
        if isImageData {
            let imageTitle = imageFormatName.map { "\($0) Image" } ?? "Image"
            return "\(imageTitle) on \(CPYClipData.formattedTime(unixTime))"
        }
        if isUnrecognizedBinaryData {
            return "Binary Data on \(CPYClipData.formattedTime(unixTime))"
        }
        return stringValue[0...10000]
    }

    func previewImage(maxWidth: CGFloat, maxHeight: CGFloat) -> NSImage? {
        guard let image = image else { return nil }
        return image.resizeImage(maxWidth, maxHeight) ?? image
    }

    private static func imageFormatName(forTypeName typeName: String) -> String? {
        return imageTypeFormatNames[typeName]
    }

    private static func imageFormatName(forImageData data: Data) -> String? {
        let bytes = [UInt8](data.prefix(16))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "JPG" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "PNG" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "GIF" }
        if bytes.starts(with: [0x42, 0x4D]) { return "BMP" }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "TIFF" }
        if bytes.count >= 12 && Array(bytes[4...7]) == [0x66, 0x74, 0x79, 0x70] {
            let brand = String(bytes: Array(bytes[8...11]), encoding: .ascii) ?? ""
            if brand.hasPrefix("hei") { return "HEIC" }
            if brand.hasPrefix("mif") { return "HEIF" }
        }
        if bytes.count >= 12
            && Array(bytes[0...3]) == [0x52, 0x49, 0x46, 0x46]
            && Array(bytes[8...11]) == [0x57, 0x45, 0x42, 0x50] {
            return "WEBP"
        }
        return nil
    }

    private static func formattedTime(_ unixTime: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unixTime)))
    }
}
