import Darwin
import Foundation

struct RightClickOpenWithApplication: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var bundleIdentifier: String?
    var path: String

    init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String?,
        path: String
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}

enum RightClickFileContentKind: String, Codable, CaseIterable {
    case empty
    case wordDocument
    case excelWorkbook
    case powerpointPresentation
}

struct RightClickFileTemplate: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var fileExtension: String
    var contentKind: RightClickFileContentKind

    init(
        id: UUID = UUID(),
        displayName: String,
        fileExtension: String,
        contentKind: RightClickFileContentKind = .empty
    ) {
        self.id = id
        self.displayName = displayName
        self.fileExtension = Self.normalize(fileExtension)
        self.contentKind = contentKind
    }

    var suggestedFileName: String {
        fileExtension.isEmpty ? "Untitled" : "Untitled.\(fileExtension)"
    }

    static func normalize(_ fileExtension: String) -> String {
        fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    static let builtIns: [RightClickFileTemplate] = [
        RightClickFileTemplate(displayName: "Empty File", fileExtension: ""),
        RightClickFileTemplate(displayName: "Text File", fileExtension: "txt"),
        RightClickFileTemplate(
            displayName: "Microsoft Word Document",
            fileExtension: "docx",
            contentKind: .wordDocument
        ),
        RightClickFileTemplate(
            displayName: "Microsoft Excel Spreadsheet",
            fileExtension: "xlsx",
            contentKind: .excelWorkbook
        ),
        RightClickFileTemplate(
            displayName: "Microsoft PowerPoint Presentation",
            fileExtension: "pptx",
            contentKind: .powerpointPresentation
        ),
        RightClickFileTemplate(displayName: "Markdown File", fileExtension: "md")
    ]
}

struct RightClickMenuConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var openWithApplications: [RightClickOpenWithApplication]
    var fileTemplates: [RightClickFileTemplate]
    var showsOpenTerminal: Bool

    static let defaults = RightClickMenuConfiguration(
        isEnabled: false,
        openWithApplications: [],
        fileTemplates: RightClickFileTemplate.builtIns,
        showsOpenTerminal: true
    )
}

struct RightClickMenuConfigurationStore {
    let fileURL: URL
    private let fallbackFileURLs: [URL]

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
        let usesDefaultLocation =
            fileURL.standardizedFileURL == Self.defaultFileURL.standardizedFileURL
        fallbackFileURLs = usesDefaultLocation ? Self.defaultFallbackFileURLs : []
    }

    func load() -> RightClickMenuConfiguration {
        for candidateURL in [fileURL] + fallbackFileURLs {
            guard let data = try? Data(contentsOf: candidateURL),
                  let configuration = try? JSONDecoder().decode(
                    RightClickMenuConfiguration.self,
                    from: data
                  ) else {
                continue
            }
            if candidateURL != fileURL {
                try? save(configuration)
            }
            return configuration
        }
        return .defaults
    }

    func save(_ configuration: RightClickMenuConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    static var defaultFileURL: URL {
        return containerFileURL(
            bundleIdentifier: RightClickMenuExtensionDescriptor.all[0]
                .bundleIdentifier
        )
    }

    static func containerFileURL(bundleIdentifier: String) -> URL {
        realHomeDirectory
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("MyMacSwissArmyknife", isDirectory: true)
            .appendingPathComponent("RightClickMenu", isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    private static var defaultFallbackFileURLs: [URL] {
        let previousProviderFiles = [
            "com.mymacswissarmyknife.host.OpenWithExtension",
            "com.mymacswissarmyknife.host.NewFilesExtension",
            "com.mymacswissarmyknife.host.OpenTerminalExtension"
        ].map(containerFileURL(bundleIdentifier:))
        return previousProviderFiles + [legacyFileURL]
    }

    private static var legacyFileURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("MyMacSwissArmyknife", isDirectory: true)
            .appendingPathComponent("RightClickMenu", isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    private static var realHomeDirectory: URL {
        guard let password = getpwuid(getuid()),
              let home = String(validatingUTF8: password.pointee.pw_dir) else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: home, isDirectory: true)
    }
}

struct RightClickMenuRequest: Codable, Equatable {
    let role: RightClickMenuProviderRole
    let context: RightClickMenuContext
}

struct RightClickMenuRequestStore {
    let fileURL: URL

    init(
        role: RightClickMenuProviderRole = .all,
        fileURL: URL? = nil
    ) {
        self.fileURL = fileURL ??
            RightClickMenuConfigurationStore.defaultFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("request-\(role.rawValue).json")
    }

    func load() -> RightClickMenuRequest? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(RightClickMenuRequest.self, from: data)
    }

    func save(_ request: RightClickMenuRequest) throws {
        let data = try JSONEncoder().encode(request)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
