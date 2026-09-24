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
    private let extensionBundleExists: () -> Bool
    private let installExtensions: () throws -> Void
    private var didInstallExtensions = false

    init(
        store: RightClickMenuConfigurationStore = RightClickMenuConfigurationStore(),
        extensionBundleExists: @escaping () -> Bool = {
            RightClickMenuExtensionDescriptor.all.allSatisfy {
                FileManager.default.fileExists(
                    atPath: installedExtensionURL(for: $0).path
                )
            }
        },
        installExtensions: @escaping () throws -> Void = installBundledExtensions
    ) {
        self.store = store
        self.extensionBundleExists = extensionBundleExists
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
        guard !didInstallExtensions else {
            refreshExtensionState()
            return
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

    private func refreshExtensionState() {
        guard configuration.isEnabled else {
            let changed = isRunning || failureMessage != nil
            isRunning = false
            failureMessage = nil
            if changed {
                onStateChange?()
            }
            return
        }
        let running = extensionBundleExists()
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

    nonisolated private static func installedExtensionURL(
        for descriptor: RightClickMenuExtensionDescriptor
    ) -> URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(descriptor.hostBundleName, isDirectory: true)
            .appendingPathComponent("Contents/PlugIns", isDirectory: true)
            .appendingPathComponent(
                descriptor.extensionBundleName,
                isDirectory: true
            )
    }

    nonisolated private static func installBundledExtensions() throws {
        let helpersURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
        guard FileManager.default.fileExists(atPath: helpersURL.path) else {
            return
        }

        for obsolete in [
            (
                "RightClickOpenWithHost.app",
                "RightClickOpenWithExtension.appex"
            ),
            (
                "RightClickOpenTerminalHost.app",
                "RightClickOpenTerminalExtension.appex"
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

        for descriptor in RightClickMenuExtensionDescriptor.all {
            let source = helpersURL.appendingPathComponent(
                descriptor.hostBundleName,
                isDirectory: true
            )
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let destination = URL(
                fileURLWithPath: "/Applications",
                isDirectory: true
            ).appendingPathComponent(
                descriptor.hostBundleName,
                isDirectory: true
            )
            let sourceExecutable = source
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(
                    source.deletingPathExtension().lastPathComponent
                )
            let destinationExecutable = destination
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(
                    destination.deletingPathExtension().lastPathComponent
                )
            let extensionExecutableName = URL(
                fileURLWithPath: descriptor.extensionBundleName
            ).deletingPathExtension().lastPathComponent
            let sourceExtensionExecutable = source
                .appendingPathComponent("Contents/PlugIns", isDirectory: true)
                .appendingPathComponent(
                    descriptor.extensionBundleName,
                    isDirectory: true
                )
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(extensionExecutableName)
            let destinationExtensionExecutable = destination
                .appendingPathComponent("Contents/PlugIns", isDirectory: true)
                .appendingPathComponent(
                    descriptor.extensionBundleName,
                    isDirectory: true
                )
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(extensionExecutableName)
            let needsUpdate =
                (try? Data(contentsOf: sourceExecutable)) !=
                    (try? Data(contentsOf: destinationExecutable)) ||
                (try? Data(contentsOf: sourceExtensionExecutable)) !=
                    (try? Data(contentsOf: destinationExtensionExecutable))
            if needsUpdate,
               FileManager.default.fileExists(atPath: destination.path) {
                try? run(
                    "/usr/bin/pluginkit",
                    arguments: [
                        "-r",
                        installedExtensionURL(for: descriptor).path
                    ]
                )
                try? run(
                    "/usr/bin/pkill",
                    arguments: ["-f", destination.path]
                )
                try FileManager.default.removeItem(at: destination)
            }
            if needsUpdate {
                try FileManager.default.copyItem(at: source, to: destination)
            }

            try run(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                arguments: ["-f", destination.path]
            )
            let extensionURL = installedExtensionURL(for: descriptor)
            try run("/usr/bin/pluginkit", arguments: ["-a", extensionURL.path])
            try run(
                "/usr/bin/pluginkit",
                arguments: ["-e", "use", "-i", descriptor.bundleIdentifier]
            )
            let embeddedExtensionURL = source
                .appendingPathComponent("Contents/PlugIns", isDirectory: true)
                .appendingPathComponent(
                    descriptor.extensionBundleName,
                    isDirectory: true
                )
            try? run(
                "/usr/bin/pluginkit",
                arguments: ["-r", embeddedExtensionURL.path]
            )
            try? run(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                arguments: ["-u", source.path]
            )
            try run(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                arguments: ["-f", destination.path]
            )
            if !isProcessRunning(destinationExecutable) {
                try launch(destinationExecutable)
            }
        }
    }

    nonisolated private static func isProcessRunning(
        _ executable: URL
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        let escapedPath = NSRegularExpression.escapedPattern(
            for: executable.path
        )
        process.arguments = ["-f", "^\(escapedPath)( --background)?$"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    nonisolated private static func launch(_ executable: URL) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--background"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
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
