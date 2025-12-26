import Foundation

// Manager for managing server configurations
// Analog of Android ServerConfigManager
// Uses UserDefaults for simplicity (can be replaced with CoreData/SQLite)
public class ServerConfigManager {
    private let userDefaults: UserDefaults
    private let serverConfigsKey = "sing_box_server_configs"
    private let activeConfigIdKey = "sing_box_active_config_id"
    
    public init() {
        // Use App Group for access from Extension
        if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
    }
    
    /**
     * Add new server configuration
     */
    public func addServerConfig(_ config: [String: Any]) -> Bool {
        guard let configId = config["id"] as? String,
              let name = config["name"] as? String else {
            return false
        }
        
        var configs = getServerConfigs()
        configs.append(config)
        
        return saveServerConfigs(configs)
    }
    
    /**
     * Remove server configuration by ID
     */
    public func removeServerConfig(_ configId: String) -> Bool {
        var configs = getServerConfigs()
        configs.removeAll { ($0["id"] as? String) == configId }
        
        // If removed configuration was active, reset activeServerConfigId
        if getActiveServerConfigId() == configId {
            setActiveServerConfigId(nil)
        }
        
        return saveServerConfigs(configs)
    }
    
    /**
     * Update existing server configuration
     */
    public func updateServerConfig(_ config: [String: Any]) -> Bool {
        guard let configId = config["id"] as? String,
              let name = config["name"] as? String else {
            return false
        }
        
        var configs = getServerConfigs()
        if let index = configs.firstIndex(where: { ($0["id"] as? String) == configId }) {
            configs[index] = config
            return saveServerConfigs(configs)
        }
        
        return false
    }
    
    /**
     * Get all saved server configurations
     */
    public func getServerConfigs() -> [[String: Any]] {
        guard let data = userDefaults.data(forKey: serverConfigsKey),
              let configs = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            return []
        }
        return configs
    }
    
    /**
     * Get server configuration by ID
     */
    public func getServerConfig(_ configId: String) -> [String: Any]? {
        let configs = getServerConfigs()
        return configs.first { ($0["id"] as? String) == configId }
    }
    
    /**
     * Set active server configuration
     */
    public func setActiveServerConfig(_ configId: String) -> Bool {
        // Check if such configuration exists
        if getServerConfig(configId) == nil {
            return false
        }
        return setActiveServerConfigId(configId)
    }
    
    /**
     * Get active server configuration
     */
    public func getActiveServerConfig() -> [String: Any]? {
        guard let activeConfigId = getActiveServerConfigId() else {
            return nil
        }
        return getServerConfig(activeConfigId)
    }
    
    // ========== Helper Methods ==========
    
    private func saveServerConfigs(_ configs: [[String: Any]]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: configs, options: [])
            userDefaults.set(data, forKey: serverConfigsKey)
            return true
        } catch {
            NSLog("ServerConfigManager saveServerConfigs error: \(error)")
            return false
        }
    }
    
    private func getActiveServerConfigId() -> String? {
        return userDefaults.string(forKey: activeConfigIdKey)
    }
    
    private func setActiveServerConfigId(_ configId: String?) -> Bool {
        if let configId = configId {
            userDefaults.set(configId, forKey: activeConfigIdKey)
        } else {
            userDefaults.removeObject(forKey: activeConfigIdKey)
        }
        return true
    }
}

