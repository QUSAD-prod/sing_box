import Foundation
import Libbox
import NetworkExtension
import os
import UserNotifications
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

/// libbox platform interface and command server handler for the Packet Tunnel
/// extension. Ported from sing-box-for-apple (`ExtensionPlatformInterface`)
/// without the macOS / system extension / jailbreak specifics.
final class SingBoxPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private static let logger = Logger(subsystem: "sing_box", category: "PlatformInterface")

    private unowned let tunnel: SingBoxPacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    /// The core's default interface monitor; also tells `pingServer` which
    /// physical interface to use.
    let interfaceMonitor = SingBoxInterfaceMonitor()

    init(_ tunnel: SingBoxPacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        networkSettings = nil
        interfaceMonitor.close()
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "sing_box.PlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - TUN

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTun0(options, ret0_)
        }
    }

    private func openTun0(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else {
            throw Self.error("missing tun options")
        }
        guard let ret0_ else {
            throw Self.error("missing return pointer")
        }

        // Route overrides of sing-box-for-apple, set with setServiceOptions.
        let serviceOptions = tunnel.paths?.defaults.dictionary(forKey: SingBoxKeys.serviceOptions) ?? [:]
        let excludeDefaultRoute = (serviceOptions["excludeDefaultRoute"] as? NSNumber)?.boolValue ?? false
        let noDefaultRoute = (serviceOptions["noDefaultRoute"] as? NSNumber)?.boolValue ?? false
        let excludeAPNsRoute = (serviceOptions["excludeAPNsRoute"] as? NSNumber)?.boolValue ?? false

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            var dnsSettings: NEDNSSettings?
            if let dnsMode = options.getDNSMode(), dnsMode.value != LibboxDNSModeDisabled {
                let dnsServers = try options.getDNSServerAddress().toArray()
                if !dnsServers.isEmpty {
                    dnsSettings = NEDNSSettings(servers: dnsServers)
                }
            }

            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            if let iterator = options.getInet4Address() {
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    ipv4Address.append(prefix.address())
                    ipv4Mask.append(prefix.mask())
                }
            }
            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            var ipv4ExcludeRoutes: [NEIPv4Route] = []
            if let iterator = options.getInet4RouteAddress() {
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    ipv4Routes.append(NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask()))
                }
            }
            if ipv4Routes.isEmpty {
                if noDefaultRoute {
                    // 1.0.0.0/8, 2.0.0.0/7, … 128.0.0.0/1
                    for shift in 0 ..< 8 {
                        let first = 1 << shift
                        ipv4Routes.append(NEIPv4Route(destinationAddress: "\(first).0.0.0", subnetMask: "\(256 - first).0.0.0"))
                    }
                } else {
                    ipv4Routes.append(NEIPv4Route.default())
                }
            }
            if let iterator = options.getInet4RouteExcludeAddress() {
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask()))
                }
            }
            if excludeDefaultRoute {
                // Hides the VPN icon in the status bar (sing-box-for-apple).
                ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "255.255.255.254"))
            }
            if excludeAPNsRoute {
                ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"))
            }
            ipv4Settings.includedRoutes = ipv4Routes
            ipv4Settings.excludedRoutes = ipv4ExcludeRoutes
            settings.ipv4Settings = ipv4Settings

            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            if let iterator = options.getInet6Address() {
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    ipv6Address.append(prefix.address())
                    ipv6Prefixes.append(NSNumber(value: prefix.prefix()))
                }
            }
            // Like sing-box-for-apple, IPv6 settings are always installed so
            // that IPv6 traffic cannot bypass the tunnel.
            let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
            var ipv6Routes: [NEIPv6Route] = []
            var ipv6ExcludeRoutes: [NEIPv6Route] = []
            if let iterator = options.getInet6RouteAddress() {
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    ipv6Routes.append(NEIPv6Route(destinationAddress: prefix.address(), networkPrefixLength: NSNumber(value: prefix.prefix())))
                }
            }
            if ipv6Routes.isEmpty {
                if noDefaultRoute {
                    // 100::/8, 200::/7, … 8000::/1
                    for prefix in 1 ... 8 {
                        let first = String(0x100 << (8 - prefix), radix: 16)
                        ipv6Routes.append(NEIPv6Route(destinationAddress: "\(first)::", networkPrefixLength: NSNumber(value: prefix)))
                    }
                } else {
                    ipv6Routes.append(NEIPv6Route.default())
                }
            }
            if let iterator = options.getInet6RouteExcludeAddress() {
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: prefix.address(), networkPrefixLength: NSNumber(value: prefix.prefix())))
                }
            }
            if excludeDefaultRoute {
                ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: "::", networkPrefixLength: 127))
            }
            ipv6Settings.includedRoutes = ipv6Routes
            ipv6Settings.excludedRoutes = ipv6ExcludeRoutes
            settings.ipv6Settings = ipv6Settings

            let hasDefaultRoute = ipv4Routes.contains {
                $0.destinationAddress == "0.0.0.0" && $0.destinationSubnetMask == "0.0.0.0"
            }
            if !hasDefaultRoute {
                // Only some routes go through the tunnel: still send all DNS
                // queries to the tunnel DNS server.
                dnsSettings?.matchDomains = [""]
                dnsSettings?.matchDomainsNoSearch = true
            }
            settings.dnsSettings = dnsSettings
        }

        if options.isHTTPProxyEnabled() {
            let proxySettings = NEProxySettings()
            let proxyServer = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxySettings.httpServer = proxyServer
            proxySettings.httpsServer = proxyServer
            proxySettings.httpEnabled = true
            proxySettings.httpsEnabled = true
            var bypassDomains = options.getHTTPProxyBypassDomain()?.toArray() ?? []
            if excludeAPNsRoute, !bypassDomains.contains("push.apple.com") {
                bypassDomains.append("push.apple.com")
            }
            if !bypassDomains.isEmpty {
                proxySettings.exceptionList = bypassDomains
            }
            let matchDomains = options.getHTTPProxyMatchDomain()?.toArray() ?? []
            if !matchDomains.isEmpty {
                proxySettings.matchDomains = matchDomains
            }
            settings.proxySettings = proxySettings
        }

        networkSettings = settings
        try await tunnel.setTunnelNetworkSettings(settings)

        // Find the utun file descriptor owned by this extension (approach of
        // wireguard-apple). The private `packetFlow.socket` key is only used
        // as a fallback and only when it exists.
        let fileDescriptor = LibboxGetTunnelFileDescriptor()
        if fileDescriptor != -1 {
            ret0_.pointee = fileDescriptor
            return
        }
        let packetFlow = tunnel.packetFlow as NSObject
        if packetFlow.responds(to: NSSelectorFromString("socket")),
           let socket = packetFlow.value(forKey: "socket") as? NSObject,
           socket.responds(to: NSSelectorFromString("fileDescriptor")),
           let descriptor = socket.value(forKey: "fileDescriptor") as? Int32
        {
            ret0_.pointee = descriptor
            return
        }
        throw Self.error("missing tun file descriptor")
    }

    // MARK: - Default interface monitor

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else {
            return
        }
        interfaceMonitor.start(listener)
    }

    func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        interfaceMonitor.close()
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        try interfaceMonitor.interfaces()
    }

    // MARK: - Environment

    func underNetworkExtension() -> Bool {
        true
    }

    func includeAllNetworks() -> Bool {
        tunnel.protocolConfiguration.includeAllNetworks
    }

    func usePlatformAutoDetectControl() -> Bool {
        false
    }

    func autoDetectControl(_: Int32) throws {}

    func clearDNSCache() {
        guard let networkSettings else {
            return
        }
        runBlocking { [self] in
            tunnel.reasserting = true
            defer { tunnel.reasserting = false }
            try? await tunnel.setTunnelNetworkSettings(nil)
            try? await tunnel.setTunnelNetworkSettings(networkSettings)
        }
    }

    func readWIFIState() -> LibboxWIFIState? {
        let network = runBlocking {
            await NEHotspotNetwork.fetchCurrent()
        }
        guard let network else {
            return nil
        }
        return LibboxWIFIState(network.ssid, wifiBSSID: network.bssid)
    }

    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? {
        nil
    }

    func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32) throws -> LibboxConnectionOwner {
        throw Self.error("find connection owner is not supported on iOS")
    }

    func registerMyInterface(_: String?) {}

    func startNeighborMonitor(_: LibboxNeighborUpdateListenerProtocol?) throws {}

    func closeNeighborMonitor(_: LibboxNeighborUpdateListenerProtocol?) throws {}

    func tailscaleHostname() -> String {
        ""
    }

    func usePlatformBridge() -> Bool {
        false
    }

    func createBridge(_: LibboxBridgeOptions?) throws -> LibboxBridgeSessionProtocol {
        throw Self.error("bridge is not supported on iOS")
    }

    func usePlatformShell() -> Bool {
        false
    }

    func checkPlatformShell() throws {
        throw Self.error("SSH server is not supported on iOS")
    }

    func lookupUser(_: String?) throws -> LibboxPlatformUser {
        throw Self.error("SSH server is not supported on iOS")
    }

    func openShellSession(_: LibboxPlatformUser?, command _: String?, environ _: LibboxStringIteratorProtocol?, term _: String?, rows _: Int32, cols _: Int32) throws -> LibboxShellSessionProtocol {
        throw Self.error("SSH server is not supported on iOS")
    }

    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String {
        error?.pointee = Self.error("SSH server is not supported on iOS")
        return ""
    }

    func lookupSFTPServer(_ error: NSErrorPointer) -> String {
        error?.pointee = Self.error("SFTP server is not supported on iOS")
        return ""
    }

    // MARK: - Notifications

    func send(_ notification: LibboxNotification?) throws {
        guard let notification else {
            return
        }
        if let paths = tunnel.paths {
            SingBoxNotificationQueue.enqueue(SingBoxNotificationQueue.payload(notification), paths: paths)
        }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        if !notification.openURL.isEmpty {
            content.userInfo["OPEN_URL"] = notification.openURL
        }
        let identifier = notification.identifier.isEmpty ? UUID().uuidString : notification.identifier
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        // Best effort: only post when the app was granted permission.
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request) { error in
                    if let error {
                        Self.logger.error("post notification: \(error.localizedDescription, privacy: .public)")
                    }
                }
            default:
                break
            }
        }
    }

    func cancelNotification(_ identifier: String?, typeID _: Int32) throws {
        guard let identifier, !identifier.isEmpty else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // MARK: - LibboxCommandServerHandlerProtocol

    func serviceStop() throws {
        tunnel.handleServiceStop()
    }

    func serviceReload() throws {
        try tunnel.reloadService()
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let status = LibboxSystemProxyStatus()
        guard let proxySettings = networkSettings?.proxySettings, proxySettings.httpServer != nil else {
            return status
        }
        status.available = true
        status.enabled = proxySettings.httpEnabled
        return status
    }

    func setSystemProxyEnabled(_ isEnabled: Bool) throws {
        guard let networkSettings,
              let proxySettings = networkSettings.proxySettings,
              proxySettings.httpServer != nil,
              proxySettings.httpEnabled != isEnabled
        else {
            return
        }
        proxySettings.httpEnabled = isEnabled
        proxySettings.httpsEnabled = isEnabled
        networkSettings.proxySettings = proxySettings
        try runBlocking { [self] in
            try await tunnel.setTunnelNetworkSettings(networkSettings)
        }
    }

    func triggerNativeCrash() throws {
        throw Self.error("not supported")
    }

    func writeDebugMessage(_ message: String?) {
        guard let message else {
            return
        }
        Self.logger.debug("\(message, privacy: .public)")
    }

    func connectSSHAgent(_: UnsafeMutablePointer<Int32>?) throws {
        throw Self.error("SSH agent forwarding is not supported on iOS")
    }
}
