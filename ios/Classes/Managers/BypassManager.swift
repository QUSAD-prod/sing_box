import Foundation

// Manager for managing bypass lists (apps, domains, subnets)
// Analog of Android BypassManager
public class BypassManager {
    private let userDefaults: UserDefaults
    private let bypassAppsKey = "sing_box_bypass_apps"
    private let bypassDomainsKey = "sing_box_bypass_domains"
    private let bypassSubnetsKey = "sing_box_bypass_subnets"
    
    // Bypass lists in memory for quick access
    private var bypassApps: Set<String> = []
    private var bypassDomains: Set<String> = []
    private var bypassSubnets: Set<String> = []
    
    public init() {
        // Use App Group for access from Extension
        if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
        loadFromUserDefaults()
    }
    
    // ========== Bypass Apps ==========
    
    public func addAppToBypass(_ bundleId: String) -> Bool {
        if bypassApps.insert(bundleId).inserted {
            saveAppsToUserDefaults()
            return true
        }
        return false
    }
    
    public func removeAppFromBypass(_ bundleId: String) -> Bool {
        if bypassApps.remove(bundleId) != nil {
            saveAppsToUserDefaults()
            return true
        }
        return false
    }
    
    public func getBypassApps() -> [String] {
        return Array(bypassApps)
    }
    
    // ========== Bypass Domains ==========
    
    public func addDomainToBypass(_ domain: String) -> Bool {
        let normalizedDomain = normalizeDomain(domain)
        if normalizedDomain.isEmpty {
            return false
        }
        if bypassDomains.insert(normalizedDomain).inserted {
            saveDomainsToUserDefaults()
            return true
        }
        return false
    }
    
    public func removeDomainFromBypass(_ domain: String) -> Bool {
        let normalizedDomain = normalizeDomain(domain)
        if bypassDomains.remove(normalizedDomain) != nil {
            saveDomainsToUserDefaults()
            return true
        }
        return false
    }
    
    public func getBypassDomains() -> [String] {
        return Array(bypassDomains)
    }
    
    // ========== Bypass Subnets ==========
    
    public func addSubnetToBypass(_ subnet: String) -> Bool {
        if isValidSubnet(subnet) && bypassSubnets.insert(subnet).inserted {
            saveSubnetsToUserDefaults()
            return true
        }
        return false
    }
    
    public func removeSubnetFromBypass(_ subnet: String) -> Bool {
        if bypassSubnets.remove(subnet) != nil {
            saveSubnetsToUserDefaults()
            return true
        }
        return false
    }
    
    public func getBypassSubnets() -> [String] {
        return Array(bypassSubnets)
    }
    
    // ========== Helper Methods ==========
    
    private func isValidSubnet(_ subnet: String) -> Bool {
        // Simple CIDR format check (e.g., "192.168.1.0/24")
        let pattern = "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/\\d{1,2}$"
        return subnet.range(of: pattern, options: .regularExpression) != nil
    }
    
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
        if let appsData = userDefaults.data(forKey: bypassAppsKey),
           let apps = try? JSONDecoder().decode([String].self, from: appsData) {
            bypassApps = Set(apps)
        }
        
        // Load domains
        if let domainsData = userDefaults.data(forKey: bypassDomainsKey),
           let domains = try? JSONDecoder().decode([String].self, from: domainsData) {
            bypassDomains = Set(domains)
        }
        
        // Load subnets
        if let subnetsData = userDefaults.data(forKey: bypassSubnetsKey),
           let subnets = try? JSONDecoder().decode([String].self, from: subnetsData) {
            bypassSubnets = Set(subnets)
        }
    }
    
    private func saveAppsToUserDefaults() {
        if let data = try? JSONEncoder().encode(Array(bypassApps)) {
            userDefaults.set(data, forKey: bypassAppsKey)
        }
    }
    
    private func saveDomainsToUserDefaults() {
        if let data = try? JSONEncoder().encode(Array(bypassDomains)) {
            userDefaults.set(data, forKey: bypassDomainsKey)
        }
    }
    
    private func saveSubnetsToUserDefaults() {
        if let data = try? JSONEncoder().encode(Array(bypassSubnets)) {
            userDefaults.set(data, forKey: bypassSubnetsKey)
        }
    }
}

