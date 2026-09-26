import SwiftUI

enum SettingsTab: Hashable {
    case scrollReverser
    case resourceMonitor
    case rightClickMenu
    case clipyEnhanced
    case appBlocker
}

@MainActor
final class SettingsSelection: ObservableObject {
    @Published var selectedTab: SettingsTab = .scrollReverser
}

struct CollectionSettingsView: View {
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var store: ModuleStateStore
    @ObservedObject var supervisor: ModuleSupervisor
    @ObservedObject var scrollReverser: ScrollReverserModule
    @ObservedObject var rightClickMenu: RightClickMenuModule
    @ObservedObject var clipyBridge: ClipyEnhancedBridge
    @ObservedObject var appBlocker: AppBlockerModule

    var body: some View {
        TabView(selection: $selection.selectedTab) {
            ScrollReverserSettingsView(
                store: store,
                supervisor: supervisor,
                scrollReverser: scrollReverser
            )
                .tabItem {
                    Label("ScrollReverser", systemImage: "arrow.up.and.down")
                }
                .tag(SettingsTab.scrollReverser)

            ResourceMonitorSettingsView(store: store, supervisor: supervisor)
                .tabItem {
                    Label("ResourceMonitor", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(SettingsTab.resourceMonitor)

            RightClickMenuSettingsView(
                store: store,
                supervisor: supervisor,
                rightClickMenu: rightClickMenu
            )
                .tabItem {
                    Label("RightClickMenu", systemImage: "cursorarrow.click.2")
                }
                .tag(SettingsTab.rightClickMenu)

            ClipyEnhancedSettingsView(
                store: store,
                supervisor: supervisor,
                bridge: clipyBridge
            )
                .tabItem {
                    Label("ClipyEnhanced", systemImage: "clipboard")
                }
                .tag(SettingsTab.clipyEnhanced)

            AppBlockerSettingsView(
                store: store,
                supervisor: supervisor,
                appBlocker: appBlocker
            )
                .tabItem {
                    Label("AppBlocker", systemImage: "nosign.app")
                }
                .tag(SettingsTab.appBlocker)
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 700, minHeight: 520, idealHeight: 580)
    }
}

struct ModuleLifecycleSection: View {
    let definition: ModuleDefinition
    @ObservedObject var store: ModuleStateStore
    @ObservedObject var supervisor: ModuleSupervisor

    var body: some View {
        Section("Module") {
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { store.configuration(for: definition.id).isEnabled },
                    set: { store.setEnabled($0, for: definition.id) }
                )
            )
            Toggle(
                "Start at login",
                isOn: Binding(
                    get: { store.configuration(for: definition.id).startsAtLogin },
                    set: { store.setStartsAtLogin($0, for: definition.id) }
                )
            )
            HStack {
                Text("Status")
                Spacer()
                HealthLabel(health: supervisor.health[definition.id] ?? .stopped)
            }
            if let error = store.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct HealthLabel: View {
    let health: ModuleHealth

    var body: some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(color)
    }

    private var title: String {
        switch health {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Healthy"
        case .restarting: "Restarting"
        case .actionRequired(let message): message
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var symbol: String {
        switch health {
        case .stopped: "stop.circle"
        case .starting, .restarting: "arrow.clockwise.circle"
        case .running: "checkmark.circle.fill"
        case .actionRequired: "exclamationmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch health {
        case .stopped: .secondary
        case .starting, .restarting: .orange
        case .running: .green
        case .actionRequired: .orange
        case .failed: .red
        }
    }
}
