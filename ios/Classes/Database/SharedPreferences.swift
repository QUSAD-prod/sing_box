import Foundation

// Simplified version of SharedPreferences for Flutter plugin
// Uses UserDefaults instead of GRDB for simplicity

public enum SharedPreferences {
    // VPN settings
    public static let selectedProfileID = Preference<Int64>("selected_profile_id", defaultValue: -1)
    public static let ignoreMemoryLimit = Preference<Bool>("ignore_memory_limit", defaultValue: false)
    
    #if !os(tvOS)
        public static let includeAllNetworks = Preference<Bool>("include_all_networks", defaultValue: false)
        public static let excludeAPNs = Preference<Bool>("exclude_apns", defaultValue: true)
        public static let excludeLocalNetworks = Preference<Bool>("exclude_local_networks", defaultValue: true)
        public static let excludeCellularServices = Preference<Bool>("exclude_cellular_services", defaultValue: true)
        public static let enforceRoutes = Preference<Bool>("enforce_routes", defaultValue: false)
    #endif
    
    public static let maxLogLines = Preference<Int>("max_log_lines", defaultValue: 300)
    public static let systemProxyEnabled = Preference<Bool>("system_proxy_enabled", defaultValue: false)
    
    // Profile Override
    public static let excludeDefaultRoute = Preference<Bool>("exclude_default_route", defaultValue: false)
    public static let autoRouteUseSubRangesByDefault = Preference<Bool>("auto_route_use_sub_ranges_by_default", defaultValue: false)
    public static let excludeAPNsRoute = Preference<Bool>("exclude_apple_push_notification_services", defaultValue: false)
    
    // On Demand Rules
    public static let alwaysOn = Preference<Bool>("always_on", defaultValue: false)
    
    #if os(tvOS)
        public static let commandServerPort = Preference<Int32>("command_server_port", defaultValue: 0)
        public static let commandServerSecret = Preference<String>("command_server_secret", defaultValue: "")
    #endif
    
    #if DEBUG
        public static let inDebug = true
    #else
        public static let inDebug = false
    #endif
}

// Simplified Preference implementation with UserDefaults
extension SharedPreferences {
    public class Preference<T: Codable> {
        let name: String
        private let defaultValue: T
        
        init(_ name: String, defaultValue: T) {
            self.name = name
            self.defaultValue = defaultValue
        }
        
        public func get() -> T {
            guard let data = UserDefaults.standard.data(forKey: name) else {
                return defaultValue
            }
            do {
                if T.self == String.self {
                    if let string = String(data: data, encoding: .utf8) {
                        // Safe cast for String
                        guard let result = string as? T else {
                            NSLog("read preferences error: Failed to cast String to type \(T.self)")
                            return defaultValue
                        }
                        return result
                    }
                } else {
                    return try JSONDecoder().decode(T.self, from: data)
                }
            } catch {
                NSLog("read preferences error: \(error)")
            }
            return defaultValue
        }
        
        public func getBlocking() -> T {
            get()
        }
        
        public func set(_ newValue: T?) {
            if let newValue = newValue {
                do {
                    let data: Data
                    if let stringValue = newValue as? String {
                        guard let stringData = stringValue.data(using: .utf8) else {
                            NSLog("write preferences error: Failed to convert string to data")
                            return
                        }
                        data = stringData
                    } else {
                        data = try JSONEncoder().encode(newValue)
                    }
                    UserDefaults.standard.set(data, forKey: name)
                } catch {
                    NSLog("write preferences error: \(error)")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: name)
            }
        }
    }
}

