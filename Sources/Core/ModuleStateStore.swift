import Combine
import Darwin
import Foundation
import ServiceManagement

protocol BootSessionProviding {
    var currentBootID: String { get }
}

struct SystemBootSessionProvider: BootSessionProviding {
    var currentBootID: String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        let result = sysctlbyname("kern.boottime", &bootTime, &size, nil, 0)
        return result == 0 ? String(bootTime.tv_sec) : "unknown"
    }
}

protocol LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}

@MainActor
final class ModuleStateStore: ObservableObject {
    @Published private(set) var configurations: [ModuleID: ModuleConfiguration]
    @Published private(set) var loginItemError: String?

    private enum Key {
        static let configurations = "moduleConfigurations.v1"
        static let bootID = "lastBootID"
    }

    private let defaults: UserDefaults
    private let loginItemManager: LoginItemManaging
    private let definitions: [ModuleDefinition]

    init(
        definitions: [ModuleDefinition] = ModuleDefinition.builtIns,
        defaults: UserDefaults = .standard,
        bootSession: BootSessionProviding = SystemBootSessionProvider(),
        loginItemManager: LoginItemManaging = MainAppLoginItemManager()
    ) {
        self.definitions = definitions
        self.defaults = defaults
        self.loginItemManager = loginItemManager

        let decoded = defaults.data(forKey: Key.configurations)
            .flatMap { try? JSONDecoder().decode([String: ModuleConfiguration].self, from: $0) }
            ?? [:]
        configurations = Dictionary(
            uniqueKeysWithValues: definitions.map {
                ($0.id, decoded[$0.id.rawValue] ?? .disabled)
            }
        )

        applyBootPolicy(currentBootID: bootSession.currentBootID)
        reconcileLoginItem()
    }

    func configuration(for id: ModuleID) -> ModuleConfiguration {
        configurations[id] ?? .disabled
    }

    func setEnabled(_ enabled: Bool, for id: ModuleID) {
        var configuration = configuration(for: id)
        configuration.isEnabled = enabled
        if !enabled {
            configuration.startsAtLogin = false
        }
        configurations[id] = configuration
        persist()
        reconcileLoginItem()
    }

    func setStartsAtLogin(_ enabled: Bool, for id: ModuleID) {
        var configuration = configuration(for: id)
        configuration.startsAtLogin = enabled
        if enabled {
            configuration.isEnabled = true
        }
        configurations[id] = configuration
        persist()
        reconcileLoginItem()
    }

    private func applyBootPolicy(currentBootID: String) {
        guard defaults.string(forKey: Key.bootID) != currentBootID else { return }
        for definition in definitions {
            var configuration = configuration(for: definition.id)
            configuration.isEnabled = configuration.startsAtLogin
            configurations[definition.id] = configuration
        }
        defaults.set(currentBootID, forKey: Key.bootID)
        persist()
    }

    private func persist() {
        let encoded = Dictionary(
            uniqueKeysWithValues: configurations.map { ($0.key.rawValue, $0.value) }
        )
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: Key.configurations)
        }
    }

    private func reconcileLoginItem() {
        do {
            try loginItemManager.setEnabled(configurations.values.contains { $0.startsAtLogin })
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
    }
}
