import Flutter
import UIKit
import NetworkExtension
import Libbox
import ObjectiveC

public class SingBoxPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var statusEventChannel: FlutterEventChannel?
    private var statsEventChannel: FlutterEventChannel?
    private var notificationsEventChannel: FlutterEventChannel?
    
    // Managers for data management
    private let bypassManager = BypassManager()
    private let dnsManager = DnsManager()
    private let settingsManager = SettingsManager()
    private let serverConfigManager = ServerConfigManager()
    private let blockManager = BlockManager()
    
    // VPN Extension Profile
    private var extensionProfile: ExtensionProfile?
    private var statusObserver: Any?
    
    // Command Client for getting statistics
    private var commandClient: CommandClient?
    
    // Stream handlers for Event Channels
    private var statusStreamHandler: StatusStreamHandler?
    private var statsStreamHandler: StatsStreamHandler?
    private var notificationsStreamHandler: NotificationsStreamHandler?
    
    // Current status and statistics
    private var currentStatus: String = "disconnected"
    private var lastStats: [String: Any] = [
        "downloadSpeed": 0,
        "uploadSpeed": 0,
        "bytesSent": 0,
        "bytesReceived": 0,
        "ping": NSNull(),
        "connectionDuration": 0
    ]
    
    // Timer for periodic statistics updates
    private var statsTimer: Timer?
    
    // Connection start time for calculating duration
    private var connectionStartTime: Date?
    
    // Current configuration for getting server address
    private var currentConfig: String?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "sing_box", binaryMessenger: registrar.messenger())
        let instance = SingBoxPlugin()
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        // Event channels for status and stats streams
        instance.statusEventChannel = FlutterEventChannel(name: "sing_box/status", binaryMessenger: registrar.messenger())
        instance.statusStreamHandler = StatusStreamHandler()
        instance.statusEventChannel?.setStreamHandler(instance.statusStreamHandler)
        
        instance.statsEventChannel = FlutterEventChannel(name: "sing_box/stats", binaryMessenger: registrar.messenger())
        instance.statsStreamHandler = StatsStreamHandler()
        instance.statsEventChannel?.setStreamHandler(instance.statsStreamHandler)
        
        // Event channel for notifications
        instance.notificationsEventChannel = FlutterEventChannel(name: "sing_box/notifications", binaryMessenger: registrar.messenger())
        instance.notificationsStreamHandler = NotificationsStreamHandler()
        instance.notificationsEventChannel?.setStreamHandler(instance.notificationsStreamHandler)
        
        // Initialize Extension Profile
        Task {
            await instance.initializeExtensionProfile()
        }
        
        // Initialize Command Client for statistics
        instance.commandClient = CommandClient([.status, .connections], logMaxLines: 300)
    }
    
    private func initializeExtensionProfile() async {
        do {
            // Try to load existing profile
            if let profile = try await ExtensionProfile.load() {
                extensionProfile = profile
                profile.register()
                setupStatusObserver(profile)
            } else {
                // If profile doesn't exist, create it
                try await ExtensionProfile.install()
                if let profile = try await ExtensionProfile.load() {
                    extensionProfile = profile
                    profile.register()
                    setupStatusObserver(profile)
                }
            }
        } catch {
            NSLog("Failed to initialize ExtensionProfile: \(error.localizedDescription)")
        }
    }
    
    private func setupStatusObserver(_ profile: ExtensionProfile) {
        // Monitor VPN status changes
        statusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateConnectionStatus()
        }
        updateConnectionStatus()
    }
    
    private func updateConnectionStatus() {
        guard let profile = extensionProfile else {
            currentStatus = "disconnected"
            statusStreamHandler?.sendStatus(currentStatus)
            return
        }
        
        let newStatus: String
        switch profile.status {
        case .connected:
            newStatus = "connected"
            if connectionStartTime == nil {
                connectionStartTime = Date()
            }
            startStatsTimer()
        case .connecting:
            newStatus = "connecting"
        case .disconnecting:
            newStatus = "disconnecting"
        case .disconnected:
            newStatus = "disconnected"
            connectionStartTime = nil
            stopStatsTimer()
        case .invalid:
            newStatus = "disconnected"
            connectionStartTime = nil
            stopStatsTimer()
        case .reasserting:
            newStatus = "connecting"
        @unknown default:
            newStatus = "disconnected"
        }
        
        if currentStatus != newStatus {
            currentStatus = newStatus
            statusStreamHandler?.sendStatus(newStatus)
        }
    }
    
    private func startStatsTimer() {
        stopStatsTimer()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    private func updateStats() {
        var stats = lastStats
        
        // Get statistics from CommandClient if available
        if let client = commandClient, let status = client.status {
            // Update speed from status
            if status.trafficAvailable {
                stats["downloadSpeed"] = Int(status.downlink)
                stats["uploadSpeed"] = Int(status.uplink)
            }
            
            // Get statistics from connections
            if let connections = client.rawConnections {
                var bytesSent: Int64 = 0
                var bytesReceived: Int64 = 0
                var minRtt: Int64? = nil
                
                let iterator = connections.iterator()
                if let iter = iterator {
                    while iter.hasNext() {
                        guard let conn = iter.next() else {
                            break
                        }
                        bytesSent += conn.upload
                        bytesReceived += conn.download
                        
                        // Get RTT via reflection (like in Android)
                        // Try to get rtt() or latency() method
                        do {
                            let mirror = Mirror(reflecting: conn)
                            // Try to find rtt or latency property
                            for child in mirror.children {
                                if let label = child.label, (label == "rtt" || label == "latency") {
                                    if let rttValue = child.value as? Int64, rttValue > 0 {
                                        if let currentMinRtt = minRtt {
                                            if rttValue < currentMinRtt {
                                                minRtt = rttValue
                                            }
                                        } else {
                                            minRtt = rttValue
                                        }
                                    } else if let rttValue = child.value as? Int, rttValue > 0 {
                                        let rttLong = Int64(rttValue)
                                        if let currentMinRtt = minRtt {
                                            if rttLong < currentMinRtt {
                                                minRtt = rttLong
                                            }
                                        } else {
                                            minRtt = rttLong
                                        }
                                    }
                                    break
                                }
                            }
                            
                            // If not found via Mirror, try via runtime
                            if minRtt == nil {
                                let connType = type(of: conn)
                                // Try to get rtt() method
                                if let rttMethod = class_getInstanceMethod(connType, Selector("rtt")) {
                                    typealias RTTMethod = @convention(c) (AnyObject, Selector) -> Int64
                                    let implementation = method_getImplementation(rttMethod)
                                    let rttFunc = unsafeBitCast(implementation, to: RTTMethod.self)
                                    let rttValue = rttFunc(conn as AnyObject, Selector("rtt"))
                                    if rttValue > 0 {
                                        if let currentMinRtt = minRtt {
                                            if rttValue < currentMinRtt {
                                                minRtt = rttValue
                                            }
                                        } else {
                                            minRtt = rttValue
                                        }
                                    }
                                } else if let latencyMethod = class_getInstanceMethod(connType, Selector("latency")) {
                                    typealias LatencyMethod = @convention(c) (AnyObject, Selector) -> Int64
                                    let implementation = method_getImplementation(latencyMethod)
                                    let latencyFunc = unsafeBitCast(implementation, to: LatencyMethod.self)
                                    let latencyValue = latencyFunc(conn as AnyObject, Selector("latency"))
                                    if latencyValue > 0 {
                                        if let currentMinRtt = minRtt {
                                            if latencyValue < currentMinRtt {
                                                minRtt = latencyValue
                                            }
                                        } else {
                                            minRtt = latencyValue
                                        }
                                    }
                                }
                            }
                        } catch {
                            // Ignore reflection errors
                        }
                    }
                }
                
                stats["bytesSent"] = bytesSent
                stats["bytesReceived"] = bytesReceived
                
                // Ping from connections or from status
                if let rtt = minRtt {
                    stats["ping"] = rtt
                } else if let status = client.status, status.trafficAvailable {
                    // Use value from status if available
                    // In Libbox status may contain ping information
                    // For now leave null if no direct access
                }
            }
        }
        
        // Calculate connectionDuration
        if let startTime = connectionStartTime {
            let duration = Int(Date().timeIntervalSince(startTime))
            stats["connectionDuration"] = duration
        } else {
            stats["connectionDuration"] = 0
        }
        
        lastStats = stats
        statsStreamHandler?.sendStats(stats)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            // Initialization already done in register
            result(true)
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "connect":
            let args = call.arguments as? [String: Any]
            guard let config = args?["config"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "config is required", details: nil))
                return
            }
            
            Task {
                do {
                    // Save configuration to UserDefaults for use in Extension
                    currentConfig = config
                    if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
                        groupDefaults.set(config, forKey: "sing_box_current_config")
                    } else {
                        UserDefaults.standard.set(config, forKey: "sing_box_current_config")
                    }
                    
                    // Ensure Extension Profile is initialized
                    if extensionProfile == nil {
                        await initializeExtensionProfile()
                    }
                    
                    guard let profile = extensionProfile else {
                        await MainActor.run {
                            result(FlutterError(code: "EXTENSION_NOT_AVAILABLE", message: "VPN Extension is not available", details: nil))
                        }
                        return
                    }
                    
                    // Connect Command Client for getting statistics
                    if let client = commandClient {
                        client.connect()
                    }
                    
                    // Start VPN
                    try await profile.start()
                    
                    await MainActor.run {
                        result(true)
                    }
                } catch {
                    await MainActor.run {
                        result(FlutterError(code: "CONNECTION_FAILED", message: "Failed to connect: \(error.localizedDescription)", details: nil))
                    }
                }
            }
        case "disconnect":
            Task {
                do {
                    // Disconnect Command Client
                    if let client = commandClient {
                        client.disconnect()
                    }
                    
                    guard let profile = extensionProfile else {
                        await MainActor.run {
                            result(false)
                        }
                        return
                    }
                    
                    try await profile.stop()
                    
                    // Clear configuration
                    currentConfig = nil
                    if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
                        groupDefaults.removeObject(forKey: "sing_box_current_config")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "sing_box_current_config")
                    }
                    
                    await MainActor.run {
                        result(true)
                    }
                } catch {
                    await MainActor.run {
                        result(FlutterError(code: "DISCONNECTION_FAILED", message: "Failed to disconnect: \(error.localizedDescription)", details: nil))
                    }
                }
            }
        case "getConnectionStatus":
            result(currentStatus)
        case "getConnectionStats":
            // Update statistics before returning
            updateStats()
            result(lastStats)
        case "testSpeed":
            // Speed test uses current connection statistics
            let isConnected = currentStatus == "connected"
            let downloadSpeed = lastStats["downloadSpeed"] as? Int ?? 0
            let uploadSpeed = lastStats["uploadSpeed"] as? Int ?? 0
            
            result([
                "downloadSpeed": downloadSpeed,
                "uploadSpeed": uploadSpeed,
                "success": isConnected,
                "errorMessage": isConnected ? NSNull() : "Not connected to VPN"
            ])
        case "pingCurrentServer":
            // Ping uses current connection statistics
            let isConnected = currentStatus == "connected"
            let ping = lastStats["ping"] as? Int
            
            // Get server address from configuration
            let address: Any? = getCurrentServerAddress()
            
            result([
                "ping": ping ?? 0,
                "success": isConnected && (ping ?? 0) > 0,
                "errorMessage": !isConnected ? "Not connected to VPN" : (ping == nil ? "Ping not available" : NSNull()),
                "address": address ?? NSNull()
            ])
        case "addAppToBypass":
            let args = call.arguments as? [String: Any]
            guard let packageName = args?["packageName"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "packageName is required", details: nil))
                return
            }
            let success = bypassManager.addAppToBypass(packageName)
            result(success)
        case "removeAppFromBypass":
            let args = call.arguments as? [String: Any]
            guard let packageName = args?["packageName"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "packageName is required", details: nil))
                return
            }
            let success = bypassManager.removeAppFromBypass(packageName)
            result(success)
        case "getBypassApps":
            let apps = bypassManager.getBypassApps()
            result(apps)
        case "addDomainToBypass":
            let args = call.arguments as? [String: Any]
            guard let domain = args?["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "domain is required", details: nil))
                return
            }
            let success = bypassManager.addDomainToBypass(domain)
            result(success)
        case "removeDomainFromBypass":
            let args = call.arguments as? [String: Any]
            guard let domain = args?["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "domain is required", details: nil))
                return
            }
            let success = bypassManager.removeDomainFromBypass(domain)
            result(success)
        case "getBypassDomains":
            let domains = bypassManager.getBypassDomains()
            result(domains)
        case "switchServer":
            let args = call.arguments as? [String: Any]
            guard let config = args?["config"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "config is required", details: nil))
                return
            }
            
            Task {
                do {
                    guard let profile = extensionProfile else {
                        await MainActor.run {
                            result(FlutterError(code: "EXTENSION_NOT_AVAILABLE", message: "VPN Extension is not available", details: nil))
                        }
                        return
                    }
                    
                    // Stop current connection
                    try await profile.stop()
                    
                    // Wait for disconnection
                    var waitSeconds = 0
                    while profile.status != .disconnected && waitSeconds < 5 {
                        try await Task.sleep(nanoseconds: NSEC_PER_SEC)
                        waitSeconds += 1
                    }
                    
                    // Save new configuration
                    currentConfig = config
                    if let groupDefaults = UserDefaults(suiteName: FilePath.groupName) {
                        groupDefaults.set(config, forKey: "sing_box_current_config")
                    } else {
                        UserDefaults.standard.set(config, forKey: "sing_box_current_config")
                    }
                    
                    // Reconnect
                    try await profile.start()
                    
                    await MainActor.run {
                        result(true)
                    }
                } catch {
                    await MainActor.run {
                        result(FlutterError(code: "SWITCH_FAILED", message: "Failed to switch server: \(error.localizedDescription)", details: nil))
                    }
                }
            }
        case "saveSettings":
            let args = call.arguments as? [String: Any]
            guard let settings = args?["settings"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "settings is required", details: nil))
                return
            }
            let success = settingsManager.saveSettings(settings)
            result(success)
        case "loadSettings":
            let settings = settingsManager.loadSettings()
            result(settings)
        case "getSettings":
            let settings = settingsManager.getSettings()
            result(settings)
        case "updateSetting":
            let args = call.arguments as? [String: Any]
            guard let key = args?["key"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "key is required", details: nil))
                return
            }
            let value = args?["value"]
            let success = settingsManager.updateSetting(key, value: value)
            result(success)
        case "addServerConfig":
            let args = call.arguments as? [String: Any]
            guard let config = args?["config"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "config is required", details: nil))
                return
            }
            let success = serverConfigManager.addServerConfig(config)
            result(success)
        case "removeServerConfig":
            let args = call.arguments as? [String: Any]
            guard let configId = args?["configId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "configId is required", details: nil))
                return
            }
            let success = serverConfigManager.removeServerConfig(configId)
            result(success)
        case "updateServerConfig":
            let args = call.arguments as? [String: Any]
            guard let config = args?["config"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "config is required", details: nil))
                return
            }
            let success = serverConfigManager.updateServerConfig(config)
            result(success)
        case "getServerConfigs":
            let configs = serverConfigManager.getServerConfigs()
            result(configs)
        case "getServerConfig":
            let args = call.arguments as? [String: Any]
            guard let configId = args?["configId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "configId is required", details: nil))
                return
            }
            if let config = serverConfigManager.getServerConfig(configId) {
                result(config)
            } else {
                result(NSNull())
            }
        case "setActiveServerConfig":
            let args = call.arguments as? [String: Any]
            guard let configId = args?["configId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "configId is required", details: nil))
                return
            }
            let success = serverConfigManager.setActiveServerConfig(configId)
            result(success)
        case "getActiveServerConfig":
            if let config = serverConfigManager.getActiveServerConfig() {
                result(config)
            } else {
                result(NSNull())
            }
        case "addBlockedApp":
            let args = call.arguments as? [String: Any]
            guard let packageName = args?["packageName"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "packageName is required", details: nil))
                return
            }
            let success = blockManager.addBlockedApp(packageName)
            result(success)
        case "removeBlockedApp":
            let args = call.arguments as? [String: Any]
            guard let packageName = args?["packageName"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "packageName is required", details: nil))
                return
            }
            let success = blockManager.removeBlockedApp(packageName)
            result(success)
        case "getBlockedApps":
            let apps = blockManager.getBlockedApps()
            result(apps)
        case "addBlockedDomain":
            let args = call.arguments as? [String: Any]
            guard let domain = args?["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "domain is required", details: nil))
                return
            }
            let success = blockManager.addBlockedDomain(domain)
            result(success)
        case "removeBlockedDomain":
            let args = call.arguments as? [String: Any]
            guard let domain = args?["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "domain is required", details: nil))
                return
            }
            let success = blockManager.removeBlockedDomain(domain)
            result(success)
        case "getBlockedDomains":
            let domains = blockManager.getBlockedDomains()
            result(domains)
        case "addSubnetToBypass":
            let args = call.arguments as? [String: Any]
            guard let subnet = args?["subnet"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "subnet is required", details: nil))
                return
            }
            let success = bypassManager.addSubnetToBypass(subnet)
            result(success)
        case "removeSubnetFromBypass":
            let args = call.arguments as? [String: Any]
            guard let subnet = args?["subnet"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "subnet is required", details: nil))
                return
            }
            let success = bypassManager.removeSubnetFromBypass(subnet)
            result(success)
        case "getBypassSubnets":
            let subnets = bypassManager.getBypassSubnets()
            result(subnets)
        case "addDnsServer":
            let args = call.arguments as? [String: Any]
            guard let dnsServer = args?["dnsServer"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "dnsServer is required", details: nil))
                return
            }
            let success = dnsManager.addDnsServer(dnsServer)
            result(success)
        case "removeDnsServer":
            let args = call.arguments as? [String: Any]
            guard let dnsServer = args?["dnsServer"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "dnsServer is required", details: nil))
                return
            }
            let success = dnsManager.removeDnsServer(dnsServer)
            result(success)
        case "getDnsServers":
            let servers = dnsManager.getDnsServers()
            result(servers)
        case "setDnsServers":
            let args = call.arguments as? [String: Any]
            guard let dnsServers = args?["dnsServers"] as? [String] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "dnsServers is required", details: nil))
                return
            }
            let success = dnsManager.setDnsServers(dnsServers)
            result(success)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopStatsTimer()
        commandClient?.disconnect()
    }
    
    // MARK: - Helper methods
    
    private func getCurrentServerAddress() -> String? {
        guard let config = currentConfig else {
            // Try to get from UserDefaults
            if let groupDefaults = UserDefaults(suiteName: FilePath.groupName),
               let configStr = groupDefaults.string(forKey: "sing_box_current_config") {
                currentConfig = configStr
                return extractServerAddress(from: configStr)
            } else if let configStr = UserDefaults.standard.string(forKey: "sing_box_current_config") {
                currentConfig = configStr
                return extractServerAddress(from: configStr)
            }
            return nil
        }
        return extractServerAddress(from: config)
    }
    
    private func extractServerAddress(from configJson: String) -> String? {
        guard let data = configJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = json["outbounds"] as? [[String: Any]],
              !outbounds.isEmpty else {
            return nil
        }
        
        let firstOutbound = outbounds[0]
        
        // Try to get address from different fields
        if let server = firstOutbound["server"] as? String, !server.isEmpty {
            return server
        }
        
        if let settings = firstOutbound["settings"] as? [String: Any] {
            if let server = settings["server"] as? String, !server.isEmpty {
                return server
            }
            if let address = settings["address"] as? String, !address.isEmpty {
                return address
            }
        }
        
        return nil
    }
}

// MARK: - Stream Handlers

private class StatusStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    func sendStatus(_ status: String) {
        eventSink?(status)
    }
}

private class StatsStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    func sendStats(_ stats: [String: Any]) {
        eventSink?(stats)
    }
}

private class NotificationsStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    func sendNotification(_ notification: [String: Any]) {
        eventSink?(notification)
    }
}
