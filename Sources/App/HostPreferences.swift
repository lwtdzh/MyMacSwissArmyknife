import Foundation

enum HostPreferences {
    static let showSettingsOnLaunchKey = "showSettingsOnLaunch"

    static func showsSettingsOnLaunch(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: showSettingsOnLaunchKey)
    }
}
