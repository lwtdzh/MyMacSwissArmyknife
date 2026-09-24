import AppKit
import FinderSync
import Foundation

@MainActor
final class RightClickMenuModule: ObservableObject, InProcessModule {
    let id = ModuleID.rightClickMenu

    @Published private(set) var configuration: RightClickMenuConfiguration
    @Published private(set) var isRunning = false
    @Published private(set) var failureMessage: String?

    var onStateChange: (() -> Void)?

    private let store: RightClickMenuConfigurationStore
    private let extensionIsRegistered: () -> Bool
    private let installExtensions: () throws -> Void
    private var didInstallExtensions = false

    init(
        store: RightClickMenuConfigurationStore = RightClickMenuConfigurationStore(),
        extensionIsRegistered: @escaping () -> Bool = {
            RightClickMenuExtensionDescriptor.all.allSatisfy {
                let extensionURL = bundledExtensionURL(for: $0)
                return FileManager.default.fileExists(atPath: extensionURL.path)
                    && registeredExtensionURLs(
                        bundleIdentifier: $0.bundleIdentifier
                    ).contains {
                        $0.standardizedFileURL == extensionURL.standardizedFileURL
                    }
            }
        },
        installExtensions: @escaping () throws -> Void = installBundledExtensions
    ) {
        self.store = store
        self.extensionIsRegistered = extensionIsRegistered
        self.installExtensions = installExtensions
        configuration = store.load()
        seedInstalledApplicationsIfNeeded()
    }

    func start() {
        if !configuration.isEnabled {
            updateConfiguration {
                $0.isEnabled = true
            }
        }
        if didInstallExtensions {
            let isRegistered = extensionIsRegistered()
            guard !isRegistered else {
                refreshExtensionState(isRegistered: true)
                return
            }
        }
        do {
            try installExtensions()
            didInstallExtensions = true
        } catch {
            failureMessage = "Unable to install Finder extensions: \(error.localizedDescription)"
            isRunning = false
            onStateChange?()
            return
        }
        refreshExtensionState()
    }

    func stop() {
        if configuration.isEnabled {
            updateConfiguration {
                $0.isEnabled = false
            }
        }
        let changed = isRunning || failureMessage != nil
        isRunning = false
        failureMessage = nil
        if changed {
            onStateChange?()
        }
    }

    func settingsDidChange() {
        configuration = store.load()
        refreshExtensionState()
    }

    func addApplication(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !configuration.openWithApplications.contains(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == path
        }) else {
            return
        }
        let bundle = Bundle(url: url)
        let displayName =
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            url.deletingPathExtension().lastPathComponent
        updateConfiguration {
            $0.openWithApplications.append(
                RightClickOpenWithApplication(
                    displayName: displayName,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    path: path
                )
            )
        }
    }

    func removeApplications(at offsets: IndexSet) {
        updateConfiguration {
            for index in offsets.sorted(by: >) {
                $0.openWithApplications.remove(at: index)
            }
        }
    }

    func addTemplate(displayName: String, fileExtension: String) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        updateConfiguration {
            $0.fileTemplates.append(
                RightClickFileTemplate(
                    displayName: name,
                    fileExtension: fileExtension
                )
            )
        }
    }

    func removeTemplates(at offsets: IndexSet) {
        updateConfiguration {
            for index in offsets.sorted(by: >) {
                $0.fileTemplates.remove(at: index)
            }
        }
    }

    func setShowsOpenTerminal(_ value: Bool) {
        updateConfiguration {
            $0.showsOpenTerminal = value
        }
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    private func updateConfiguration(
        _ update: (inout RightClickMenuConfiguration) -> Void
    ) {
        var latest = store.load()
        update(&latest)
        do {
            try store.save(latest)
            configuration = latest
            failureMessage = nil
        } catch {
            failureMessage = "Unable to save settings: \(error.localizedDescription)"
        }
    }

    private func refreshExtensionState(isRegistered: Bool? = nil) {
        guard configuration.isEnabled else {
            let changed = isRunning || failureMessage != nil
            isRunning = false
            failureMessage = nil
            if changed {
                onStateChange?()
            }
            return
        }
        let running = isRegistered ?? extensionIsRegistered()
        let message = running ? nil : "Finder extension is missing"
        let changed = running != isRunning || message != failureMessage
        isRunning = running
        failureMessage = message
        if changed {
            onStateChange?()
        }
    }

    private func seedInstalledApplicationsIfNeeded() {
        guard configuration.openWithApplications.isEmpty else { return }
        let sublimeText = URL(
            fileURLWithPath: "/Applications/Sublime Text.app",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: sublimeText.path) else {
            return
        }
        addApplication(sublimeText)
    }

    nonisolated private static func bundledExtensionURL(
        for descriptor: RightClickMenuExtensionDescriptor
    ) -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns", isDirectory: true)
            .appendingPathComponent(
                descriptor.extensionBundleName,
                isDirectory: true
            )
    }

    nonisolated private static func installBundledExtensions() throws {
        for obsolete in [
            (
                "RightClickOpenWithHost.app",
                "RightClickOpenWithExtension.appex"
            ),
            (
                "RightClickOpenTerminalHost.app",
                "RightClickOpenTerminalExtension.appex"
            ),
            (
                "RightClickNewFilesHost.app",
                "RightClickNewFilesExtension.appex"
            )
        ] {
            let hostURL = URL(
                fileURLWithPath: "/Applications",
                isDirectory: true
            ).appendingPathComponent(obsolete.0, isDirectory: true)
            let extensionURL = hostURL
                .appendingPathComponent("Contents/PlugIns", isDirectory: true)
                .appendingPathComponent(obsolete.1, isDirectory: true)
            if FileManager.default.fileExists(atPath: extensionURL.path) {
                try? run(
                    "/usr/bin/pluginkit",
                    arguments: ["-r", extensionURL.path]
                )
            }
            if FileManager.default.fileExists(atPath: hostURL.path) {
                try FileManager.default.removeItem(at: hostURL)
            }
        }

        for legacyBundleIdentifier in [
            "com.mymacswissarmyknife.host.NewFiles.Extension",
            "com.mymacswissarmyknife.host.OpenWithExtension",
            "com.mymacswissarmyknife.host.NewFilesExtension",
            "com.mymacswissarmyknife.host.OpenTerminalExtension"
        ] {
            for registeredURL in registeredExtensionURLs(
                bundleIdentifier: legacyBundleIdentifier
            ) {
                try? run(
                    "/usr/bin/pluginkit",
                    arguments: ["-r", registeredURL.path]
                )
            }
        }

        for descriptor in RightClickMenuExtensionDescriptor.all {
            let extensionURL = bundledExtensionURL(for: descriptor)
            guard FileManager.default.fileExists(atPath: extensionURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }

            for registeredURL in registeredExtensionURLs(
                bundleIdentifier: descriptor.bundleIdentifier
            ) where registeredURL.standardizedFileURL !=
                extensionURL.standardizedFileURL {
                try? run(
                    "/usr/bin/pluginkit",
                    arguments: ["-r", registeredURL.path]
                )
            }

            try run(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                arguments: ["-f", Bundle.main.bundleURL.path]
            )
            try run("/usr/bin/pluginkit", arguments: ["-a", extensionURL.path])
            try run(
                "/usr/bin/pluginkit",
                arguments: ["-e", "use", "-i", descriptor.bundleIdentifier]
            )
        }
    }

    nonisolated static func unregisterBundledExtensions() {
        for descriptor in RightClickMenuExtensionDescriptor.all {
            try? run(
                "/usr/bin/pluginkit",
                arguments: ["-r", bundledExtensionURL(for: descriptor).path]
            )
        }
    }

    nonisolated private static func registeredExtensionURLs(
        bundleIdentifier: String
    ) -> [URL] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = [
            "-m", "-A", "-D", "-v", "-i", bundleIdentifier
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseRegisteredExtensionURLs(text)
    }

    nonisolated static func parseRegisteredExtensionURLs(
        _ output: String
    ) -> [URL] {
        output.split(separator: "\n").compactMap { line in
            guard let path = line.split(separator: "\t").last,
                  path.hasPrefix("/") else {
                return nil
            }
            return URL(fileURLWithPath: String(path))
        }
    }

    nonisolated private static func run(
        _ executable: String,
        arguments: [String]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableRuntimeMismatch)
        }
    }
}
