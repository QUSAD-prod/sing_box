import Foundation

// Manager for managing blocking lists of applications and domains
// Analog of Android BlockManager
public class BlockManager {
    private let userDefaults: UserDefaults
    private let blockedAppsKey = "sing_box_blocked_apps"
    private let blockedDomainsKey = "sing_box_blocked_domains"
    
    // Blocking lists in memory for quick access
    private var blockedApps: Set<String> = []
    private var blockedDomains: Set<String> = []
    
    public init() {
        // Use App Group for access from Extension
        if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
        loadFromUserDefaults()
    }
    
    // ========== Blocked Apps ==========
    
    /**
     * Add application to blocking list
     */
    public func addBlockedApp(_ bundleId: String) -> Bool {
        if blockedApps.insert(bundleId).inserted {
            saveAppsToUserDefaults()
            return true
        }
        return false
    }
    
    /**
     * Remove application from blocking list
     */
    public func removeBlockedApp(_ bundleId: String) -> Bool {
        if blockedApps.remove(bundleId) != nil {
            saveAppsToUserDefaults()
            return true
        }
        return false
    }
    
    /**
     * Get list of blocked applications
     */
    public func getBlockedApps() -> [String] {
        return Array(blockedApps)
    }
    
    // ========== Blocked Domains ==========
    
    /**
     * Add domain to blocking list
     */
    public func addBlockedDomain(_ domain: String) -> Bool {
        let normalizedDomain = normalizeDomain(domain)
        if normalizedDomain.isEmpty {
            return false
        }
        if blockedDomains.insert(normalizedDomain).inserted {
            saveDomainsToUserDefaults()
            return true
        }
        return false
    }
    
    /**
     * Remove domain from blocking list
     */
    public func removeBlockedDomain(_ domain: String) -> Bool {
        let normalizedDomain = normalizeDomain(domain)
        if blockedDomains.remove(normalizedDomain) != nil {
            saveDomainsToUserDefaults()
            return true
        }
        return false
    }
    
    /**
     * Get list of blocked domains
     */
    public func getBlockedDomains() -> [String] {
        return Array(blockedDomains)
    }
    
    // ========== Helper Methods ==========
    
    /**
     * Normalize domain string: remove protocol (http/https), "www.", trailing slashes
     */
    private func normalizeDomain(_ domain: String) -> String {
        var result = domain.lowercased()
        
        // Remove protocol
        result = result.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
        
        // Remove "www."
        result = result.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        
        // Remove everything after first slash
        if let slashIndex = result.firstIndex(of: "/") {
            result = String(result[..<slashIndex])
        }
        
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    private func loadFromUserDefaults() {
        // Load apps
        if let appsData = userDefaults.data(forKey: blockedAppsKey),
           let apps = try? JSONDecoder().decode([String].self, from: appsData) {
            blockedApps = Set(apps)
        }
        
        // Load domains
        if let domainsData = userDefaults.data(forKey: blockedDomainsKey),
           let domains = try? JSONDecoder().decode([String].self, from: domainsData) {
            blockedDomains = Set(domains)
        }
    }
    
    private func saveAppsToUserDefaults() {
        if let data = try? JSONEncoder().encode(Array(blockedApps)) {
            userDefaults.set(data, forKey: blockedAppsKey)
        }
    }
    
    private func saveDomainsToUserDefaults() {
        if let data = try? JSONEncoder().encode(Array(blockedDomains)) {
            userDefaults.set(data, forKey: blockedDomainsKey)
        }
    }
}

