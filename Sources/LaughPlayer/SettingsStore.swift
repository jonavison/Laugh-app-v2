import Foundation

final class SettingsStore {
    static let shared = SettingsStore()

    private enum Keys {
        static let lockAspectRatioEnabled = "LockAspectRatioEnabled"
    }

    var lockAspectRatioEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.lockAspectRatioEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.lockAspectRatioEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.lockAspectRatioEnabled)
        }
    }

    private let defaults = UserDefaults.standard
}
