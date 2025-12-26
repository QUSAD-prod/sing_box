import Foundation

// Manager for managing plugin settings
// Analog of Android SettingsManager
// Uses UserDefaults for simplicity (can be replaced with CoreData/SQLite)
public class SettingsManager {
    private let userDefaults: UserDefaults
    private let settingsKey = "sing_box_settings"
    
    // Cache for current settings
    private var cachedSettings: [String: Any]?
    
    public init() {
        // Use App Group for access from Extension
        if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
    }
    
    /**
     * Save settings
     */
    public func saveSettings(_ settings: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [])
            userDefaults.set(data, forKey: settingsKey)
            cachedSettings = settings
            return true
        } catch {
            NSLog("SettingsManager saveSettings error: \(error)")
            return false
        }
    }
    
    /**
     * Load settings
     */
    public func loadSettings() -> [String: Any] {
        // Check cache
        if let cached = cachedSettings {
            return cached
        }
        
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            let defaultSettings = getDefaultSettings()
            cachedSettings = defaultSettings
            return defaultSettings
        }
        
        cachedSettings = settings
        return settings
    }
    
    /**
     * Get current settings
     */
    public func getSettings() -> [String: Any] {
        return loadSettings()
    }
    
    /**
     * Update individual setting
     */
    public func updateSetting(_ key: String, value: Any?) -> Bool {
        var currentSettings = loadSettings()
        currentSettings[key] = value
        return saveSettings(currentSettings)
    }
    
    /**
     * Get default settings
     */
    private func getDefaultSettings() -> [String: Any] {
        return [
            "autoConnectOnStart": false,
            "autoReconnectOnDisconnect": false,
            "killSwitch": false,
            "blockedApps": [] as [String],
            "blockedDomains": [] as [String],
            "bypassSubnets": [
                "192.168.0.0/16",
                "10.0.0.0/8",
                "172.16.0.0/12",
                "127.0.0.0/8",
                "169.254.0.0/16"
            ] as [String],
            "dnsServers": ["8.8.8.8", "1.1.1.1"] as [String],
            "activeServerConfigId": NSNull(),
            "serverConfigs": [] as [[String: Any]],
            "systemProxyEnabled": false
        ]
    }
    
    /**
     * Clear cache
     */
    public func clearCache() {
        cachedSettings = nil
    }
}

