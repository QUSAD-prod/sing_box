import Foundation
import Libbox
import NetworkExtension

// Extension Profile for managing VPN connection
// Adapted from sing-box-for-apple for Flutter plugin
public class ExtensionProfile: ObservableObject {
    public static let controlKind = "com.qusadprod.sing_box.widget.ServiceToggle"
    
    private let manager: NEVPNManager
    private var connection: NEVPNConnection
    private var observer: Any?
    
    @Published public var status: NEVPNStatus
    @Published public var connectedDate: Date?
    
    public init(_ manager: NEVPNManager) {
        self.manager = manager
        connection = manager.connection
        status = manager.connection.status
        connectedDate = manager.connection.connectedDate
    }
    
    public func register() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] notification in
            guard let self else {
                return
            }
            guard let connection = notification.object as? NEVPNConnection else {
                NSLog("ExtensionProfile: notification.object is not NEVPNConnection")
                return
            }
            self.connection = connection
            self.status = connection.status
            self.connectedDate = connection.connectedDate
        }
    }
    
    private func unregister() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setOnDemandRules() {
        let interfaceRule = NEOnDemandRuleConnect()
        interfaceRule.interfaceTypeMatch = .any
        let probeRule = NEOnDemandRuleConnect()
        probeRule.probeURL = URL(string: "http://captive.apple.com")
        manager.onDemandRules = [interfaceRule, probeRule]
    }
    
    public func updateAlwaysOn(_ newState: Bool) async throws {
        manager.isOnDemandEnabled = newState
        setOnDemandRules()
        try await manager.saveToPreferences()
    }
    
    @available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
    public func fetchLastDisconnectError() async throws {
        try await connection.fetchLastDisconnectError()
    }
    
    public func start() async throws {
        await fetchProfile()
        manager.isEnabled = true
        if SharedPreferences.alwaysOn.getBlocking() {
            manager.isOnDemandEnabled = true
            setOnDemandRules()
        }
        #if !os(tvOS)
            if let protocolConfiguration = manager.protocolConfiguration {
                let includeAllNetworks = SharedPreferences.includeAllNetworks.getBlocking()
                protocolConfiguration.includeAllNetworks = includeAllNetworks
                if #available(iOS 16.4, macOS 13.3, *) {
                    protocolConfiguration.excludeCellularServices = !includeAllNetworks
                }
            }
        #endif
        try await manager.saveToPreferences()
        try manager.connection.startVPNTunnel()
    }
    
    public func fetchProfile() async {
        // Get active profile from ServerConfigManager
        let serverConfigManager = ServerConfigManager()
        if let activeConfig = serverConfigManager.getActiveServerConfig() {
            // Save configuration to App Groups for access from Extension
            let groupDefaults = UserDefaults(suiteName: FilePath.groupName)
            if let configJson = activeConfig["config"] as? String {
                groupDefaults?.set(configJson, forKey: "sing_box_current_config")
            } else if let configData = try? JSONSerialization.data(withJSONObject: activeConfig),
                      let configJson = String(data: configData, encoding: .utf8) {
                groupDefaults?.set(configJson, forKey: "sing_box_current_config")
            }
        }
    }
    
    public func stop() async throws {
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            try await manager.saveToPreferences()
        }
        do {
            if let client = LibboxNewStandaloneCommandClient() {
                try client.serviceClose()
            }
        } catch {
            NSLog("ExtensionProfile: Error closing service: \(error.localizedDescription)")
        }
        manager.connection.stopVPNTunnel()
    }
    
    public func restart() async throws {
        try await stop()
        var waitSeconds = 0
        while await MainActor.run(body: { status }) != .disconnected {
            try await Task.sleep(nanoseconds: NSEC_PER_SEC)
            waitSeconds += 1
            if waitSeconds >= 5 {
                throw NSError(domain: "Restart service timeout", code: 0)
            }
        }
        try await start()
    }
    
    public static func load() async throws -> ExtensionProfile? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if managers.isEmpty {
            return nil
        }
        let profile = ExtensionProfile(managers[0])
        return profile
    }
    
    public static func install() async throws {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "SingBox VPN" // Variant.applicationName
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = "\(FilePath.packageName).extension"
        tunnelProtocol.serverAddress = "sing-box"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        try await manager.saveToPreferences()
    }
}

