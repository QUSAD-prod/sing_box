import Foundation
import Darwin

// Manager for managing DNS servers
// Analog of Android DnsManager
public class DnsManager {
    private let userDefaults: UserDefaults
    private let dnsServersKey = "sing_box_dns_servers"
    
    // DNS servers in memory for quick access
    private var dnsServers: Set<String> = []
    
    public init() {
        // Use App Group for access from Extension
        if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
        loadFromUserDefaults()
        
        // If list is empty after loading, add default values
        if dnsServers.isEmpty {
            addDnsServer("8.8.8.8") // Google DNS
            addDnsServer("1.1.1.1") // Cloudflare DNS
        }
    }
    
    /**
     * Add DNS server
     */
    public func addDnsServer(_ dnsServer: String) -> Bool {
        if isValidDnsServer(dnsServer) && dnsServers.insert(dnsServer).inserted {
            saveToUserDefaults()
            return true
        }
        return false
    }
    
    /**
     * Remove DNS server
     */
    public func removeDnsServer(_ dnsServer: String) -> Bool {
        if dnsServers.remove(dnsServer) != nil {
            saveToUserDefaults()
            return true
        }
        return false
    }
    
    /**
     * Get list of DNS servers
     */
    public func getDnsServers() -> [String] {
        return Array(dnsServers)
    }
    
    /**
     * Set DNS servers (replace all)
     */
    public func setDnsServers(_ servers: [String]) -> Bool {
        // Validate all servers
        let validServers = servers.filter { isValidDnsServer($0) }
        if validServers.count != servers.count {
            return false // Invalid servers found
        }
        
        dnsServers = Set(validServers)
        saveToUserDefaults()
        return true
    }
    
    /**
     * Validate DNS server (IPv4 or IPv6)
     */
    private func isValidDnsServer(_ dnsServer: String) -> Bool {
        // Simple IP address check via regular expression
        // IPv4: xxx.xxx.xxx.xxx
        let ipv4Pattern = "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        if dnsServer.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }
        
        // IPv6: simplified check (contains colons)
        if dnsServer.contains(":") {
            // More detailed IPv6 check can be added later
            return true
        }
        
        return false
    }
    
    /**
     * Load DNS servers from UserDefaults
     */
    private func loadFromUserDefaults() {
        if let data = userDefaults.data(forKey: dnsServersKey),
           let servers = try? JSONDecoder().decode([String].self, from: data) {
            dnsServers = Set(servers)
        }
    }
    
    /**
     * Save DNS servers to UserDefaults
     */
    private func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(Array(dnsServers)) {
            userDefaults.set(data, forKey: dnsServersKey)
        }
    }
}

