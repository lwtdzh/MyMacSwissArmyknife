import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let scrollDefaults = UserDefaults(
    suiteName: ModuleSettingsDefaults.scrollDomain
)!
private let resourceDefaults = UserDefaults(
    suiteName: ModuleSettingsDefaults.resourceDomain
)!
private let clipyDefaults = UserDefaults(
    suiteName: ModuleSettingsDefaults.clipyDomain
)!

struct ScrollReverserSettingsView: View {
    @ObservedObject var store: ModuleStateStore
    @ObservedObject var supervisor: ModuleSupervisor
    @ObservedObject var scrollReverser: ScrollReverserModule

    @AppStorage("ReverseY", store: scrollDefaults) private var reverseVertical = true
    @AppStorage("ReverseX", store: scrollDefaults) private var reverseHorizontal = false
    @AppStorage("ReverseTrackpad", store: scrollDefaults) private var reverseTrackpad = true
    @AppStorage("ReverseMouse", store: scrollDefaults) private var reverseMouse = true
    @AppStorage("DiscreteScrollStepSize", store: scrollDefaults) private var stepSize = 3

    private let definition = ModuleDefinition.builtIns.first {
        $0.id == .scrollReverser
    }!

    var body: some View {
        Form {
            ModuleLifecycleSection(
                definition: definition,
                store: store,
                supervisor: supervisor
            )

            if !scrollReverser.accessibilityGranted ||
                !scrollReverser.inputMonitoringGranted {
                Section("Permission Setup") {
                    PermissionRow(
                        title: "Accessibility",
                        isGranted: scrollReverser.accessibilityGranted
                    ) {
                        scrollReverser.openAccessibilitySettings()
                    }
                    PermissionRow(
                        title: "Input Monitoring",
                        isGranted: scrollReverser.inputMonitoringGranted
                    ) {
                        scrollReverser.openInputMonitoringSettings()
                    }

                    HStack {
                        Button {
                            scrollReverser.requestPermissions()
                        } label: {
                            Label("Request permissions", systemImage: "hand.raised")
                        }
                        Spacer()
                        Button {
                            scrollReverser.revealHostApplication()
                        } label: {
                            Label("Show App in Finder", systemImage: "folder")
                        }
                    }

                    DraggableAppPermissionItem()
                }
            }

            Group {
                Section("Direction") {
                    Toggle("Vertical", isOn: $reverseVertical)
                    Toggle("Horizontal", isOn: $reverseHorizontal)
                }

                Section("Devices") {
                    Toggle("Mouse", isOn: $reverseMouse)
                    Toggle("Trackpad", isOn: $reverseTrackpad)
                }

                Section("Scroll wheel") {
                    Stepper("Step size: \(stepSize)", value: $stepSize, in: 0...100)
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            supervisor.restart(.scrollReverser)
                        } label: {
                            Label("Restart scrolling", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .disabled(!store.configuration(for: .scrollReverser).isEnabled)
        }
        .formStyle(.grouped)
        .onChange(of: settingsFingerprint) { _ in
            supervisor.settingsDidChange(for: .scrollReverser)
        }
    }

    private var settingsFingerprint: String {
        [
            String(reverseVertical),
            String(reverseHorizontal),
            String(reverseTrackpad),
            String(reverseMouse),
            String(stepSize)
        ].joined(separator: ":")
    }
}

enum AppBundleDragSource {
    static func itemProvider(
        bundleURL: URL = Bundle.main.bundleURL
    ) -> NSItemProvider {
        NSItemProvider(object: bundleURL as NSURL)
    }
}

private struct DraggableAppPermissionItem: View {
    private let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("MyMacSwissArmyknife")
                    .fontWeight(.medium)
                Text("Drag this app into the allowed-app list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "hand.draw")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onDrag {
            AppBundleDragSource.itemProvider()
        }
        .help("Drag MyMacSwissArmyknife into the macOS permission list")
    }
}

private struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Label(
                isGranted ? "Granted" : "Required",
                systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .foregroundStyle(isGranted ? .green : .orange)
            if !isGranted {
                Button("Open \(title) Settings", action: openSettings)
            }
        }
    }
}

struct ResourceMonitorSettingsView: View {
    @ObservedObject var store: ModuleStateStore
    @ObservedObject var supervisor: ModuleSupervisor

    @AppStorage("showMenuBar", store: resourceDefaults) private var showMenuBar = true
    @AppStorage("showFloatingPanel", store: resourceDefaults) private var showFloatingPanel = true
    @AppStorage("floatingPanelAlwaysOnTop", store: resourceDefaults) private var alwaysOnTop = true
    @AppStorage("showDownload", store: resourceDefaults) private var showDownload = true
    @AppStorage("showUpload", store: resourceDefaults) private var showUpload = true
    @AppStorage("showDiskRead", store: resourceDefaults) private var showDiskRead = true
    @AppStorage("showDiskWrite", store: resourceDefaults) private var showDiskWrite = true
    @AppStorage("showCPU", store: resourceDefaults) private var showCPU = true
    @AppStorage("showMemory", store: resourceDefaults) private var showMemory = true
    @AppStorage("dataRateUnit", store: resourceDefaults) private var dataRateUnit = "bits"
    @AppStorage("refreshInterval", store: resourceDefaults) private var refreshInterval = 1

    private let definition = ModuleDefinition.builtIns.first {
        $0.id == .resourceMonitor
    }!

    var body: some View {
        Form {
            ModuleLifecycleSection(
                definition: definition,
                store: store,
                supervisor: supervisor
            )

            Group {
                Section("Presentation") {
                    Toggle("Menu bar", isOn: $showMenuBar)
                        .disabled(!showFloatingPanel)
                    Toggle("Floating panel", isOn: $showFloatingPanel)
                        .disabled(!showMenuBar)
                    Toggle("Keep panel above other windows", isOn: $alwaysOnTop)
                        .disabled(!showFloatingPanel)
                }

                Section("Metrics") {
                    Toggle("Download", isOn: $showDownload)
                        .disabled(isOnlyMetric(showDownload))
                    Toggle("Upload", isOn: $showUpload)
                        .disabled(isOnlyMetric(showUpload))
                    Toggle("Disk read", isOn: $showDiskRead)
                        .disabled(isOnlyMetric(showDiskRead))
                    Toggle("Disk write", isOn: $showDiskWrite)
                        .disabled(isOnlyMetric(showDiskWrite))
                    Toggle("CPU", isOn: $showCPU)
                        .disabled(isOnlyMetric(showCPU))
                    Toggle("Memory", isOn: $showMemory)
                        .disabled(isOnlyMetric(showMemory))
                }

                Section("Sampling") {
                    Picker("Rate unit", selection: $dataRateUnit) {
                        Text("Bits/s").tag("bits")
                        Text("Bytes/s").tag("bytes")
                    }
                    .pickerStyle(.segmented)

                    Picker("Refresh interval", selection: $refreshInterval) {
                        ForEach([1, 2, 3, 5, 10], id: \.self) {
                            Text("\($0) s").tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            supervisor.restart(.resourceMonitor)
                        } label: {
                            Label("Restart module", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .disabled(!store.configuration(for: .resourceMonitor).isEnabled)
        }
        .formStyle(.grouped)
        .onChange(of: settingsFingerprint) { _ in
            supervisor.settingsDidChange(for: .resourceMonitor)
        }
    }

    private var settingsFingerprint: String {
        [
            String(showMenuBar),
            String(showFloatingPanel),
            String(alwaysOnTop),
            String(showDownload),
            String(showUpload),
            String(showDiskRead),
            String(showDiskWrite),
            String(showCPU),
            String(showMemory),
            dataRateUnit,
            String(refreshInterval)
        ].joined(separator: ":")
    }

    private func isOnlyMetric(_ metric: Bool) -> Bool {
        metric && [
            showDownload,
            showUpload,
            showDiskRead,
            showDiskWrite,
            showCPU,
            showMemory
        ].filter { $0 }.count == 1
    }
}

struct RightClickMenuSettingsView: View {
    @ObservedObject var store: ModuleStateStore
    @ObservedObject var supervisor: ModuleSupervisor
    @ObservedObject var rightClickMenu: RightClickMenuModule

    @State private var isAddingTemplate = false

    private let definition = ModuleDefinition.builtIns.first {
        $0.id == .rightClickMenu
    }!

    var body: some View {
        Form {
            ModuleLifecycleSection(
                definition: definition,
                store: store,
                supervisor: supervisor
            )

            Section("Finder Extension") {
                HStack {
                    Label(
                        "RightClickMenu",
                        systemImage: "puzzlepiece.extension"
                    )
                    Spacer()
                    Button {
                        rightClickMenu.openExtensionSettings()
                    } label: {
                        Label("Manage Extensions", systemImage: "gear")
                    }
                }
            }

            Section("Open With") {
                ForEach(
                    Array(rightClickMenu.configuration.openWithApplications.enumerated()),
                    id: \.element.id
                ) { index, application in
                    HStack {
                        Image(
                            nsImage: NSWorkspace.shared.icon(
                                forFile: application.path
                            )
                        )
                        .resizable()
                        .frame(width: 24, height: 24)
                        Text(application.displayName)
                        Spacer()
                        Button {
                            rightClickMenu.removeApplications(
                                at: IndexSet(integer: index)
                            )
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(application.displayName)")
                    }
                }

                Button {
                    chooseApplication()
                } label: {
                    Label("Add Application", systemImage: "plus")
                }
            }

            Section("New Files") {
                ForEach(
                    Array(rightClickMenu.configuration.fileTemplates.enumerated()),
                    id: \.element.id
                ) { index, template in
                    HStack {
                        Image(systemName: "doc")
                            .frame(width: 24)
                        Text(template.displayName)
                        Spacer()
                        Text(template.fileExtension.isEmpty ? "no extension" : ".\(template.fileExtension)")
                            .foregroundStyle(.secondary)
                        Button {
                            rightClickMenu.removeTemplates(
                                at: IndexSet(integer: index)
                            )
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(template.displayName)")
                    }
                }

                Button {
                    isAddingTemplate = true
                } label: {
                    Label("Add File Type", systemImage: "plus")
                }
            }

            Section("Commands") {
                Toggle(
                    "Open Terminal Here",
                    isOn: Binding(
                        get: {
                            rightClickMenu.configuration.showsOpenTerminal
                        },
                        set: rightClickMenu.setShowsOpenTerminal
                    )
                )
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isAddingTemplate) {
            AddFileTemplateSheet { name, fileExtension in
                rightClickMenu.addTemplate(
                    displayName: name,
                    fileExtension: fileExtension
                )
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        )
        if panel.runModal() == .OK, let url = panel.url {
            rightClickMenu.addApplication(url)
        }
    }
}

private struct AddFileTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var fileExtension = ""

    let onAdd: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add File Type")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Name", text: $displayName)
                TextField("Extension", text: $fileExtension)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    onAdd(displayName, fileExtension)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    displayName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct ClipyEnhancedSettingsView: View {
    @ObservedObject var store: ModuleStateStore
    @ObservedObject var supervisor: ModuleSupervisor
    @ObservedObject var bridge: ClipyEnhancedBridge

    @AppStorage("kCPYPrefMaxHistorySizeKey", store: clipyDefaults)
    private var maxHistorySize = 30
    @AppStorage("kCPYPrefInputPasteCommandKey", store: clipyDefaults)
    private var inputPasteCommand = true
    @AppStorage("kCPYPrefReorderClipsAfterPasting", store: clipyDefaults)
    private var reorderAfterPasting = true

    @AppStorage("kCPYPrefNumberOfItemsPlaceInlineKey", store: clipyDefaults)
    private var inlineItemCount = 0
    @AppStorage("kCPYPrefNumberOfItemsPlaceInsideFolderKey", store: clipyDefaults)
    private var folderItemCount = 10
    @AppStorage("kCPYPrefMaxMenuItemTitleLengthKey", store: clipyDefaults)
    private var titleLength = 20
    @AppStorage("kCPYPrefMenuItemsTitleStartWithZeroKey", store: clipyDefaults)
    private var startsWithZero = false
    @AppStorage("menuItemsAreMarkedWithNumbers", store: clipyDefaults)
    private var marksItemsWithNumbers = true
    @AppStorage("addNumericKeyEquivalents", store: clipyDefaults)
    private var numericKeyEquivalents = false
    @AppStorage("kCPYPrefShowIconInTheMenuKey", store: clipyDefaults)
    private var showsMenuIcons = true
    @AppStorage("showToolTipOnMenuItem", store: clipyDefaults)
    private var showsToolTips = true
    @AppStorage("maxLengthOfToolTipKey", store: clipyDefaults)
    private var toolTipLength = 200
    @AppStorage("showImageInTheMenu", store: clipyDefaults)
    private var showsImages = true
    @AppStorage("kCPYPrefShowColorPreviewInTheMenu", store: clipyDefaults)
    private var showsColorPreview = true
    @AppStorage("thumbnailWidth", store: clipyDefaults)
    private var thumbnailWidth = 100
    @AppStorage("thumbnailHeight", store: clipyDefaults)
    private var thumbnailHeight = 32
    @AppStorage("kCPYPrefCopySameHistroy", store: clipyDefaults)
    private var copiesDuplicateHistory = true
    @AppStorage("kCPYPrefOverwriteSameHistroy", store: clipyDefaults)
    private var movesDuplicateToTop = true
    @AppStorage("kCPYPrefAddClearHistoryMenuItemKey", store: clipyDefaults)
    private var addsClearHistoryItem = true
    @AppStorage("kCPYPrefShowAlertBeforeClearHistoryKey", store: clipyDefaults)
    private var confirmsClearHistory = true

    @AppStorage("kCPYBetaPastePlainText", store: clipyDefaults)
    private var enablesPlainTextModifier = true
    @AppStorage("kCPYBetaPastePlainTextModifier", store: clipyDefaults)
    private var plainTextModifier = 0
    @AppStorage("kCPYBetaDeleteHistory", store: clipyDefaults)
    private var enablesDeleteModifier = false
    @AppStorage("kCPYBetaDeleteHistoryModifier", store: clipyDefaults)
    private var deleteModifier = 0
    @AppStorage("kCPYBetaPasteAndDeleteHistory", store: clipyDefaults)
    private var enablesPasteDeleteModifier = false
    @AppStorage("kCPYBetapasteAndDeleteHistoryModifier", store: clipyDefaults)
    private var pasteDeleteModifier = 0
    @AppStorage("kCPYBetaObserveScreenshot", store: clipyDefaults)
    private var savesScreenshots = false

    @State private var storeTypes: [String: Bool]

    private let definition = ModuleDefinition.builtIns.first {
        $0.id == .clipyEnhanced
    }!
    private let typeNames = [
        "String", "RTF", "RTFD", "PDF",
        "Filenames", "URL", "TIFF", "Binary"
    ]

    init(
        store: ModuleStateStore,
        supervisor: ModuleSupervisor,
        bridge: ClipyEnhancedBridge
    ) {
        self.store = store
        self.supervisor = supervisor
        self.bridge = bridge
        let stored = clipyDefaults.dictionary(
            forKey: "kCPYPrefStoreTypesKey"
        ) ?? [:]
        _storeTypes = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: [
                    "String", "RTF", "RTFD", "PDF",
                    "Filenames", "URL", "TIFF", "Binary"
                ].map { name in
                    (name, (stored[name] as? NSNumber)?.boolValue ?? true)
                }
            )
        )
    }

    var body: some View {
        Form {
            ModuleLifecycleSection(
                definition: definition,
                store: store,
                supervisor: supervisor
            )

            Group {
                clipboardSection
                typesSection
                menuSection
                excludedApplicationsSection
                shortcutsSection
                advancedSection
            }
            .disabled(!store.configuration(for: .clipyEnhanced).isEnabled)
        }
        .formStyle(.grouped)
        .onAppear {
            bridge.requestSnapshot()
        }
        .onChange(of: settingsFingerprint) { _ in
            clipyDefaults.set(storeTypes, forKey: "kCPYPrefStoreTypesKey")
            supervisor.settingsDidChange(for: .clipyEnhanced)
        }
    }

    private var clipboardSection: some View {
        Section("Clipboard History") {
            Stepper(
                "Maximum items: \(maxHistorySize)",
                value: $maxHistorySize,
                in: 1...10_000
            )
            Toggle(
                "Paste after choosing an item",
                isOn: $inputPasteCommand
            )
            Picker("Sort history by", selection: $reorderAfterPasting) {
                Text("Date Created").tag(false)
                Text("Last Used").tag(true)
            }
            .pickerStyle(.segmented)

            if inputPasteCommand && !bridge.accessibilityGranted {
                HStack {
                    Label(
                        "Accessibility permission is required for automatic paste",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Accessibility Settings") {
                        bridge.openAccessibilitySettings()
                    }
                }
                DraggableAppPermissionItem()
            }
        }
    }

    private var typesSection: some View {
        Section("Stored Clipboard Types") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                alignment: .leading
            ) {
                ForEach(typeNames, id: \.self) { name in
                    Toggle(name, isOn: typeBinding(name))
                }
            }
        }
    }

    private var menuSection: some View {
        Section("Menu") {
            Stepper(
                "Items shown inline: \(inlineItemCount)",
                value: $inlineItemCount,
                in: 0...100
            )
            Stepper(
                "Items per folder: \(folderItemCount)",
                value: $folderItemCount,
                in: 1...100
            )
            Stepper(
                "Maximum title length: \(titleLength)",
                value: $titleLength,
                in: 3...500
            )
            Toggle("Mark items with numbers", isOn: $marksItemsWithNumbers)
            Toggle("Number from zero", isOn: $startsWithZero)
                .disabled(!marksItemsWithNumbers)
            Toggle("Use number keys", isOn: $numericKeyEquivalents)
            Toggle("Show item icons", isOn: $showsMenuIcons)
            Toggle("Show tooltips", isOn: $showsToolTips)
            Stepper(
                "Maximum tooltip length: \(toolTipLength)",
                value: $toolTipLength,
                in: 1...10_000
            )
            .disabled(!showsToolTips)
            Toggle("Show image previews", isOn: $showsImages)
            Toggle("Show color previews", isOn: $showsColorPreview)
            HStack {
                Stepper(
                    "Thumbnail width: \(thumbnailWidth)",
                    value: $thumbnailWidth,
                    in: 1...500
                )
                Stepper(
                    "Height: \(thumbnailHeight)",
                    value: $thumbnailHeight,
                    in: 1...500
                )
            }
            .disabled(!showsImages)
            Toggle(
                "Keep repeated clipboard items",
                isOn: $copiesDuplicateHistory
            )
            Toggle(
                "Move repeated items to the top",
                isOn: $movesDuplicateToTop
            )
            .disabled(!copiesDuplicateHistory)
            Toggle("Show Clear History", isOn: $addsClearHistoryItem)
            Toggle("Confirm before clearing", isOn: $confirmsClearHistory)
                .disabled(!addsClearHistoryItem)
        }
    }

    private var excludedApplicationsSection: some View {
        Section("Excluded Applications") {
            ForEach(bridge.snapshot.excludedApplications) { application in
                HStack {
                    Text(application.name)
                    Spacer()
                    Button {
                        bridge.removeExcludedApplication(
                            identifier: application.identifier
                        )
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(application.name)")
                }
            }
            Button {
                chooseExcludedApplications()
            } label: {
                Label("Add Application", systemImage: "plus")
            }
        }
    }

    private var shortcutsSection: some View {
        Section("Keyboard Shortcuts") {
            shortcutRow("Main menu", kind: "main", fallback: "⇧⌘V")
            shortcutRow("History", kind: "history", fallback: "⌃⌘V")
            shortcutRow("Snippets", kind: "snippets", fallback: "⇧⌘B")
            shortcutRow("Clear history", kind: "clearHistory", fallback: "None")

            HStack {
                Text("Per-folder shortcuts are edited with their snippet folder.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    bridge.editSnippets()
                } label: {
                    Label("Edit Snippets", systemImage: "text.badge.plus")
                }
            }
        }
    }

    private var advancedSection: some View {
        Section("Modifier Actions") {
            modifierAction(
                "Paste as plain text",
                enabled: $enablesPlainTextModifier,
                modifier: $plainTextModifier
            )
            modifierAction(
                "Delete history item",
                enabled: $enablesDeleteModifier,
                modifier: $deleteModifier
            )
            modifierAction(
                "Paste and delete history item",
                enabled: $enablesPasteDeleteModifier,
                modifier: $pasteDeleteModifier
            )
            Toggle("Save screenshots in history", isOn: $savesScreenshots)
        }
    }

    private func typeBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { storeTypes[name] ?? true },
            set: { storeTypes[name] = $0 }
        )
    }

    private func shortcutRow(
        _ title: String,
        kind: String,
        fallback: String
    ) -> some View {
        let shortcut = bridge.snapshot.shortcuts.first { $0.kind == kind }
        return HStack {
            Text(title)
            Spacer()
            ClipyShortcutRecorder(display: shortcut?.display ?? fallback) {
                keyCode,
                modifiers in
                bridge.updateShortcut(
                    kind,
                    keyCode: keyCode,
                    modifiers: modifiers
                )
            }
            .frame(width: 150, height: 26)
        }
    }

    private func modifierAction(
        _ title: String,
        enabled: Binding<Bool>,
        modifier: Binding<Int>
    ) -> some View {
        HStack {
            Toggle(title, isOn: enabled)
            Spacer()
            Picker("", selection: modifier) {
                Text("Command").tag(0)
                Text("Shift").tag(1)
                Text("Control").tag(2)
                Text("Option").tag(3)
            }
            .labelsHidden()
            .frame(width: 120)
            .disabled(!enabled.wrappedValue)
        }
    }

    private func chooseExcludedApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(bridge.addExcludedApplication)
    }

    private var settingsFingerprint: String {
        [
            String(maxHistorySize),
            String(inputPasteCommand),
            String(reorderAfterPasting),
            String(inlineItemCount),
            String(folderItemCount),
            String(titleLength),
            String(startsWithZero),
            String(marksItemsWithNumbers),
            String(numericKeyEquivalents),
            String(showsMenuIcons),
            String(showsToolTips),
            String(toolTipLength),
            String(showsImages),
            String(showsColorPreview),
            String(thumbnailWidth),
            String(thumbnailHeight),
            String(copiesDuplicateHistory),
            String(movesDuplicateToTop),
            String(addsClearHistoryItem),
            String(confirmsClearHistory),
            String(enablesPlainTextModifier),
            String(plainTextModifier),
            String(enablesDeleteModifier),
            String(deleteModifier),
            String(enablesPasteDeleteModifier),
            String(pasteDeleteModifier),
            String(savesScreenshots),
            storeTypes.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
        ].joined(separator: "|")
    }
}
