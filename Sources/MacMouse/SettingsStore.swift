import Foundation
import MacMouseCore

/// The settings, saved as JSON in user defaults. Observed by the settings window.
final class SettingsStore: ObservableObject {
    private static let key = "settings"
    private let defaults = UserDefaults.standard

    /// Called on the main thread after any change.
    var onChange: () -> Void = {}

    @Published var settings: MouseSettings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.key) }
            onChange()
        }
    }

    /// Pauses everything when off, restoring the mouse's own pointer settings.
    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "enabled")
            objectWillChange.send()
            onChange()
        }
    }

    init() {
        settings = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(MouseSettings.self, from: $0) }
            ?? MouseSettings()
    }

    func restoreDefaults() { settings = MouseSettings() }
}
