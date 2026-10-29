import Foundation
import Libbox
import NetworkExtension
import os
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

/// Packet Tunnel provider running sing-box (libbox) for the `sing_box`
/// Flutter plugin.
///
/// The host app's Network Extension target only needs:
///
/// ```swift
/// import SingBoxTunnel
///
/// class PacketTunnelProvider: SingBoxPacketTunnelProvider {}
/// ```
///
/// The provider reads the configuration that the plugin wrote to
/// `<app group container>/sing-box/config.json`, so on-demand / always-on
/// reconnects started by iOS work without the app. The app group is taken
/// from `providerConfiguration["appGroup"]` (written by the plugin), then from
/// the `SingBoxAppGroup` key of the extension's `Info.plist`.
open class SingBoxPacketTunnelProvider: NEPacketTunnelProvider {
    private static let logger = Logger(subsystem: "sing_box", category: "PacketTunnel")

    private let queue = DispatchQueue(label: "sing_box.packet-tunnel")
    private let serviceLock = NSLock()
    private lazy var platformInterface = SingBoxPlatformInterface(self)
    private var screenStateObserver: ScreenStateObserver?
    var commandServer: LibboxCommandServer?
    private(set) var paths: SingBoxPaths?

    override public init() {
        super.init()
    }

    // MARK: - Customization points

    /// The app group shared with the app.
    open var appGroupIdentifier: String? {
        let providerConfiguration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        if let group = providerConfiguration?[SingBoxKeys.providerAppGroup] as? String, !group.isEmpty {
            return group
        }
        if let group = Bundle.main.object(forInfoDictionaryKey: SingBoxKeys.infoPlistAppGroup) as? String,
           !group.isEmpty, !group.hasPrefix("$(")
        {
            return group
        }
        // Last resort: "group.<host app bundle id>" derived from
        // "<host app bundle id>.<extension name>".
        if let identifier = Bundle.main.bundleIdentifier, let dot = identifier.lastIndex(of: ".") {
            return "group." + identifier[..<dot]
        }
        return nil
    }

    /// Returns the sing-box configuration to run.
    ///
    /// `startOptions` is the dictionary passed to `startVPNTunnel(options:)`
    /// when the tunnel is being started and `nil` for reloads. The default
    /// implementation uses the `configContent` start option when present and
    /// otherwise the configuration file written by the plugin.
    open func loadConfiguration(startOptions: [String: NSObject]?) throws -> String {
        if let content = startOptions?[SingBoxKeys.startOptionConfigContent] as? String, !content.isEmpty {
            return content
        }
        guard let paths else {
            throw SingBoxError("app group is not configured")
        }
        guard let config = paths.readConfig(), !config.isEmpty else {
            throw SingBoxError("missing configuration: \(paths.configFile.path) does not exist; start the VPN from the app first")
        }
        return config
    }

    // MARK: - NEPacketTunnelProvider

    override open func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        queue.async { [self] in
            do {
                try startService(options)
                completionHandler(nil)
            } catch {
                let message = error.localizedDescription
                Self.logger.error("start tunnel: \(message, privacy: .public)")
                paths?.writeLastError(message)
                writeMessage("(packet-tunnel) \(message)")
                shutdown()
                completionHandler(SingBoxError(message))
            }
        }
    }

    override open func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async { [self] in
            if let message = Self.failureMessage(reason), paths?.readLastError() == nil {
                paths?.writeLastError(message)
            }
            writeMessage("(packet-tunnel) stopping, reason: \(reason.rawValue)", level: 4)
            shutdown()
            completionHandler()
        }
    }

    override open func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        let message = (try? JSONSerialization.jsonObject(with: messageData) as? [String: Any]) ?? [:]
        let command = message[SingBoxKeys.messageCommand] as? String
        if command == SingBoxKeys.messagePing {
            // Measurements take up to their timeout and run concurrently:
            // not on the serial queue that reloads use.
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let result = ping(message)
                completionHandler?(try? JSONSerialization.data(withJSONObject: result))
            }
            return
        }
        queue.async { [self] in
            switch command {
            case SingBoxKeys.messageReload:
                do {
                    try reloadService()
                    completionHandler?(nil)
                } catch {
                    completionHandler?(Data(error.localizedDescription.utf8))
                }
            default:
                completionHandler?(Data("unknown message".utf8))
            }
        }
    }

    /// `pingServer` sent by the app: measured on the physical interface, so
    /// it bypasses the tunnel and its DNS.
    private func ping(_ message: [String: Any]) -> [String: Any] {
        let name = message["method"] as? String ?? ""
        let host = message["host"] as? String ?? ""
        let port = (message["port"] as? NSNumber)?.intValue
        let timeoutMs = (message["timeoutMs"] as? NSNumber)?.intValue ?? 5000
        do {
            let method = try SingBoxNativePing.method(name, port: port)
            return SingBoxNativePing.ping(
                method,
                host: host,
                port: port,
                timeoutMs: timeoutMs,
                interfaceIndex: platformInterface.interfaceMonitor.defaultInterfaceIndex
            )
        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
    }

    override open func sleep(completionHandler: @escaping () -> Void) {
        commandServer?.pause()
        completionHandler()
    }

    override open func wake() {
        commandServer?.wake()
    }

    // MARK: - Service

    private func startService(_ options: [String: NSObject]?) throws {
        guard let appGroup = appGroupIdentifier else {
            throw SingBoxError("cannot determine the app group (set SingBoxAppGroup in the extension Info.plist)")
        }
        let paths = SingBoxPaths.resolve(appGroup: appGroup)
        guard paths.isAppGroupContainer else {
            throw SingBoxError("the app group container \"\(appGroup)\" is not available to the extension: add the App Groups capability with this group to the extension and the app (same team)")
        }
        self.paths = paths
        paths.writeLastError(nil)

        let providerConfiguration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        let logMaxLines = providerConfiguration?[SingBoxKeys.providerLogMaxLines] as? Int ?? SingBoxKeys.defaultLogMaxLines
        let debug = providerConfiguration?[SingBoxKeys.providerDebug] as? Bool ?? false
        let disableMemoryLimit = (options?[SingBoxKeys.startOptionDisableMemoryLimit] as? NSNumber)?.boolValue
            ?? paths.defaults.bool(forKey: SingBoxKeys.disableMemoryLimit)

        // The OOM killer / memory limit keeps the extension below the
        // Network Extension memory limit (like sing-box-for-apple).
        try SingBoxLibbox.setup(
            paths: paths,
            logMaxLines: logMaxLines,
            debug: debug,
            crashReportSource: "NetworkExtension",
            oomKillerEnabled: !disableMemoryLimit,
            force: true
        )

        var error: NSError?
        let server = LibboxNewCommandServer(platformInterface, platformInterface, &error)
        if let error {
            throw SingBoxError("create command server: \(error.localizedDescription)")
        }
        guard let server else {
            throw SingBoxError("create command server failed")
        }
        commandServer = server
        do {
            try server.start()
        } catch {
            throw SingBoxError("start command server: \(error.localizedDescription)")
        }

        let config = try loadConfiguration(startOptions: options)
        serviceLock.lock()
        defer { serviceLock.unlock() }
        do {
            try server.startOrReloadService(config, options: LibboxOverrideOptions())
        } catch {
            throw SingBoxError("start service: \(error.localizedDescription)")
        }
        screenStateObserver = ScreenStateObserver(commandServer: server)
        writeMessage("(packet-tunnel) started", level: 4)
    }

    /// Re-reads the configuration file and reloads the running service.
    func reloadService() throws {
        serviceLock.lock()
        defer { serviceLock.unlock() }
        guard let server = commandServer else {
            throw SingBoxError("service is not running")
        }
        let config = try loadConfiguration(startOptions: nil)
        writeMessage("(packet-tunnel) reloading service", level: 4)
        reasserting = true
        defer { reasserting = false }
        do {
            try server.startOrReloadService(config, options: LibboxOverrideOptions())
            paths?.writeLastError(nil)
        } catch {
            // The previous instance is already closed: do not leave a
            // "connected" tunnel without a running core.
            let message = "reload service: \(error.localizedDescription)"
            paths?.writeLastError(message)
            writeMessage("(packet-tunnel) \(message)")
            cancelTunnelWithError(SingBoxError(message))
            throw SingBoxError(message)
        }
    }

    /// The core asked to stop (`CommandClient.serviceClose`): stop the
    /// service and the tunnel.
    func handleServiceStop() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            writeMessage("(packet-tunnel) service stop requested", level: 4)
            try? commandServer?.closeService()
            cancelTunnelWithError(nil)
        }
    }

    private func shutdown() {
        screenStateObserver?.cancel()
        screenStateObserver = nil
        guard let server = commandServer else {
            platformInterface.reset()
            return
        }
        try? server.closeService()
        platformInterface.reset()
        Thread.sleep(forTimeInterval: 0.1)
        server.close()
        commandServer = nil
    }

    func writeMessage(_ message: String, level: Int32 = 2) {
        commandServer?.writeMessage(level, message: message)
    }

    private static func failureMessage(_ reason: NEProviderStopReason) -> String? {
        switch reason.rawValue {
        case 2: return "tunnel stopped: the provider failed"
        case 4: return "tunnel stopped: unrecoverable network change"
        case 6: return "tunnel stopped: authentication canceled"
        case 7: return "tunnel stopped: configuration failed"
        case 9: return "tunnel stopped: the VPN configuration was disabled"
        case 10: return "tunnel stopped: the VPN configuration was removed"
        case 11: return "tunnel stopped: superseded by another VPN"
        case 14: return "tunnel stopped: connection failed"
        case 17: return "tunnel stopped: internal error"
        default: return nil
        }
    }
}
