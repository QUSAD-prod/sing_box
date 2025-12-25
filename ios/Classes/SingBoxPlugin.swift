import Flutter
import UIKit

public class SingBoxPlugin: NSObject, FlutterPlugin {
    private var statusEventSink: FlutterEventSink?
    private var statsEventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "sing_box", binaryMessenger: registrar.messenger())
        let instance = SingBoxPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let statusEventChannel = FlutterEventChannel(name: "sing_box/status", binaryMessenger: registrar.messenger())
        statusEventChannel.setStreamHandler(StatusStreamHandler(plugin: instance))
        
        let statsEventChannel = FlutterEventChannel(name: "sing_box/stats", binaryMessenger: registrar.messenger())
        statsEventChannel.setStreamHandler(StatsStreamHandler(plugin: instance))
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            // TODO: Implement initialization logic
            result(true)
        case "getPlatformVersion":
            // TODO: Implement platform version retrieval
            result("iOS \(UIDevice.current.systemVersion)")
        case "connect":
            // TODO: Implement VPN connection logic
            let args = call.arguments as? [String: Any]
            let config = args?["config"] as? String
            result(false)
        case "disconnect":
            // TODO: Implement VPN disconnection logic
            result(false)
        case "getConnectionStatus":
            // TODO: Implement connection status retrieval
            result("disconnected")
        case "getConnectionStats":
            // TODO: Implement connection statistics retrieval
            let stats: [String: Any] = [
                "downloadSpeed": 0,
                "uploadSpeed": 0,
                "bytesSent": 0,
                "bytesReceived": 0,
                "ping": NSNull(),
                "connectionDuration": 0
            ]
            result(stats)
        case "testSpeed":
            // TODO: Implement speed test logic
            let speedResult: [String: Any] = [
                "downloadSpeed": 0,
                "uploadSpeed": 0,
                "success": false,
                "errorMessage": "Not implemented"
            ]
            result(speedResult)
        case "pingCurrentServer":
            // TODO: Implement ping to current server
            let pingResult: [String: Any] = [
                "ping": 0,
                "success": false,
                "errorMessage": "Not implemented",
                "address": NSNull()
            ]
            result(pingResult)
        case "pingConfig":
            // TODO: Implement ping to config
            let args = call.arguments as? [String: Any]
            let config = args?["config"] as? String
            let pingResult: [String: Any] = [
                "ping": 0,
                "success": false,
                "errorMessage": "Not implemented",
                "address": NSNull()
            ]
            result(pingResult)
        case "addAppToBypass":
            // TODO: Implement add app to bypass list
            let args = call.arguments as? [String: Any]
            let packageName = args?["packageName"] as? String
            result(false)
        case "removeAppFromBypass":
            // TODO: Implement remove app from bypass list
            let args = call.arguments as? [String: Any]
            let packageName = args?["packageName"] as? String
            result(false)
        case "getBypassApps":
            // TODO: Implement get bypass apps list
            result([])
        case "addDomainToBypass":
            // TODO: Implement add domain to bypass list
            let args = call.arguments as? [String: Any]
            let domain = args?["domain"] as? String
            result(false)
        case "removeDomainFromBypass":
            // TODO: Implement remove domain from bypass list
            let args = call.arguments as? [String: Any]
            let domain = args?["domain"] as? String
            result(false)
        case "getBypassDomains":
            // TODO: Implement get bypass domains list
            result([])
        case "switchServer":
            // TODO: Implement server switching logic
            let args = call.arguments as? [String: Any]
            let config = args?["config"] as? String
            result(false)
        case "saveSettings":
            // TODO: Implement save settings logic
            let args = call.arguments as? [String: Any]
            let settings = args?["settings"] as? [String: Any]
            result(false)
        case "loadSettings":
            // TODO: Implement load settings logic
            let settings: [String: Any] = [
                "autoConnectOnStart": false,
                "autoReconnectOnDisconnect": false,
                "killSwitch": false,
                "blockedApps": [],
                "blockedDomains": [],
                "bypassSubnets": [],
                "dnsServers": [],
                "activeServerConfigId": NSNull(),
                "serverConfigs": []
            ]
            result(settings)
        case "getSettings":
            // TODO: Implement get settings logic
            let settings: [String: Any] = [
                "autoConnectOnStart": false,
                "autoReconnectOnDisconnect": false,
                "killSwitch": false,
                "blockedApps": [],
                "blockedDomains": [],
                "bypassSubnets": [],
                "dnsServers": [],
                "activeServerConfigId": NSNull(),
                "serverConfigs": []
            ]
            result(settings)
        case "updateSetting":
            // TODO: Implement update setting logic
            let args = call.arguments as? [String: Any]
            let key = args?["key"] as? String
            let value = args?["value"]
            result(false)
        case "addServerConfig":
            // TODO: Implement add server config logic
            let args = call.arguments as? [String: Any]
            let config = args?["config"] as? [String: Any]
            result(false)
        case "removeServerConfig":
            // TODO: Implement remove server config logic
            let args = call.arguments as? [String: Any]
            let configId = args?["configId"] as? String
            result(false)
        case "updateServerConfig":
            // TODO: Implement update server config logic
            let args = call.arguments as? [String: Any]
            let config = args?["config"] as? [String: Any]
            result(false)
        case "getServerConfigs":
            // TODO: Implement get server configs list
            result([])
        case "getServerConfig":
            // TODO: Implement get server config by ID
            let args = call.arguments as? [String: Any]
            let configId = args?["configId"] as? String
            result(NSNull())
        case "setActiveServerConfig":
            // TODO: Implement set active server config
            let args = call.arguments as? [String: Any]
            let configId = args?["configId"] as? String
            result(false)
        case "getActiveServerConfig":
            // TODO: Implement get active server config
            result(NSNull())
        case "addBlockedApp":
            // TODO: Implement add blocked app logic
            let args = call.arguments as? [String: Any]
            let packageName = args?["packageName"] as? String
            result(false)
        case "removeBlockedApp":
            // TODO: Implement remove blocked app logic
            let args = call.arguments as? [String: Any]
            let packageName = args?["packageName"] as? String
            result(false)
        case "getBlockedApps":
            // TODO: Implement get blocked apps list
            result([])
        case "addBlockedDomain":
            // TODO: Implement add blocked domain logic
            let args = call.arguments as? [String: Any]
            let domain = args?["domain"] as? String
            result(false)
        case "removeBlockedDomain":
            // TODO: Implement remove blocked domain logic
            let args = call.arguments as? [String: Any]
            let domain = args?["domain"] as? String
            result(false)
        case "getBlockedDomains":
            // TODO: Implement get blocked domains list
            result([])
        case "addSubnetToBypass":
            // TODO: Implement add subnet to bypass logic
            let args = call.arguments as? [String: Any]
            let subnet = args?["subnet"] as? String
            result(false)
        case "removeSubnetFromBypass":
            // TODO: Implement remove subnet from bypass logic
            let args = call.arguments as? [String: Any]
            let subnet = args?["subnet"] as? String
            result(false)
        case "getBypassSubnets":
            // TODO: Implement get bypass subnets list
            result([])
        case "addDnsServer":
            // TODO: Implement add DNS server logic
            let args = call.arguments as? [String: Any]
            let dnsServer = args?["dnsServer"] as? String
            result(false)
        case "removeDnsServer":
            // TODO: Implement remove DNS server logic
            let args = call.arguments as? [String: Any]
            let dnsServer = args?["dnsServer"] as? String
            result(false)
        case "getDnsServers":
            // TODO: Implement get DNS servers list
            result([])
        case "setDnsServers":
            // TODO: Implement set DNS servers logic
            let args = call.arguments as? [String: Any]
            let dnsServers = args?["dnsServers"] as? [String]
            result(false)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// Event channel stream handlers
class StatusStreamHandler: NSObject, FlutterStreamHandler {
    private let plugin: SingBoxPlugin
    
    init(plugin: SingBoxPlugin) {
        self.plugin = plugin
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // TODO: Implement connection status stream
        // Should emit status updates: "disconnected", "connecting", "connected", etc.
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // TODO: Clean up status stream
        return nil
    }
}

class StatsStreamHandler: NSObject, FlutterStreamHandler {
    private let plugin: SingBoxPlugin
    
    init(plugin: SingBoxPlugin) {
        self.plugin = plugin
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // TODO: Implement connection stats stream
        // Should emit stats updates with downloadSpeed, uploadSpeed, bytesSent, bytesReceived, ping, connectionDuration
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // TODO: Clean up stats stream
        return nil
    }
}

