import Foundation

enum ModuleExecution: Hashable {
    case inProcess
    case bundledApplication(bundleIdentifier: String, bundleName: String)
}

enum ModuleID: String, CaseIterable, Codable, Hashable, Identifiable {
    case scrollReverser
    case resourceMonitor
    case rightClickMenu
    case clipyEnhanced
    case appBlocker

    var id: String { rawValue }
}

struct ModuleDefinition: Identifiable, Hashable {
    let id: ModuleID
    let displayName: String
    let summary: String
    let systemImage: String
    let execution: ModuleExecution

    static let builtIns: [ModuleDefinition] = [
        ModuleDefinition(
            id: .scrollReverser,
            displayName: "ScrollReverser",
            summary: "Independent mouse and trackpad scrolling",
            systemImage: "arrow.up.and.down",
            execution: .inProcess
        ),
        ModuleDefinition(
            id: .resourceMonitor,
            displayName: "ResourceMonitor",
            summary: "Network, disk, CPU, and memory activity",
            systemImage: "gauge.with.dots.needle.67percent",
            execution: .bundledApplication(
                bundleIdentifier: "com.mymacswissarmyknife.ResourceMonitor",
                bundleName: "ResourceMonitor.app"
            )
        ),
        ModuleDefinition(
            id: .rightClickMenu,
            displayName: "RightClickMenu",
            summary: "Configurable Finder context-menu commands",
            systemImage: "cursorarrow.click.2",
            execution: .inProcess
        ),
        ModuleDefinition(
            id: .clipyEnhanced,
            displayName: "ClipyEnhanced",
            summary: "Clipboard history and reusable snippets",
            systemImage: "clipboard",
            execution: .bundledApplication(
                bundleIdentifier: "com.clipy-app.ClipyEnhanced",
                bundleName: "ClipyEnhanced.app"
            )
        ),
        ModuleDefinition(
            id: .appBlocker,
            displayName: "AppBlocker",
            summary: "Immediately stop selected applications",
            systemImage: "nosign.app",
            execution: .inProcess
        )
    ]
}

struct ModuleConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var startsAtLogin: Bool

    static let disabled = ModuleConfiguration(isEnabled: false, startsAtLogin: false)
}

enum ModuleHealth: Equatable {
    case stopped
    case starting
    case running
    case restarting
    case actionRequired(String)
    case failed(String)
}
