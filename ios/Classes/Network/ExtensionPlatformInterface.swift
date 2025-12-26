import Foundation
import Libbox
import NetworkExtension
import Network
import UserNotifications
#if os(iOS)
    import NEHotspotHelper
#endif

// Platform Interface for interacting with sing-box
// Adapted from sing-box-for-apple for Flutter plugin
public class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private let tunnel: ExtensionProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    
    init(_ tunnel: ExtensionProvider) {
        self.tunnel = tunnel
    }
    
    public func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTun0(options, ret0_)
        }
    }
    
    private func openTun0(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else {
            throw NSError(domain: "nil options", code: 0)
        }
        guard let ret0_ else {
            throw NSError(domain: "nil return pointer", code: 0)
        }
        
        let autoRouteUseSubRangesByDefault = SharedPreferences.autoRouteUseSubRangesByDefault.getBlocking()
        let excludeAPNs = SharedPreferences.excludeAPNsRoute.getBlocking()
        
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())
            
            let dnsServer = try options.getDNSServerAddress()
            let dnsSettings = NEDNSSettings(servers: [dnsServer.value])
            dnsSettings.matchDomains = [""]
            dnsSettings.matchDomainsNoSearch = true
            settings.dnsSettings = dnsSettings
            
            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            guard let ipv4AddressIterator = options.getInet4Address() else {
                throw NSError(domain: "nil ipv4AddressIterator", code: 0)
            }
            while ipv4AddressIterator.hasNext() {
                guard let ipv4Prefix = ipv4AddressIterator.next() else {
                    break
                }
                ipv4Address.append(ipv4Prefix.address())
                ipv4Mask.append(ipv4Prefix.mask())
            }
            
            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            var ipv4ExcludeRoutes: [NEIPv4Route] = []
            
            guard let inet4RouteAddressIterator = options.getInet4RouteAddress() else {
                throw NSError(domain: "nil inet4RouteAddressIterator", code: 0)
            }
            if inet4RouteAddressIterator.hasNext() {
                while inet4RouteAddressIterator.hasNext() {
                    guard let ipv4RoutePrefix = inet4RouteAddressIterator.next() else {
                        break
                    }
                    ipv4Routes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
                }
            } else if autoRouteUseSubRangesByDefault {
                ipv4Routes.append(NEIPv4Route(destinationAddress: "1.0.0.0", subnetMask: "255.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "2.0.0.0", subnetMask: "254.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "4.0.0.0", subnetMask: "252.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "8.0.0.0", subnetMask: "248.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "16.0.0.0", subnetMask: "240.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "32.0.0.0", subnetMask: "224.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "64.0.0.0", subnetMask: "192.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "128.0.0.0", subnetMask: "128.0.0.0"))
            } else {
                ipv4Routes.append(NEIPv4Route.default())
            }
            
            guard let inet4RouteExcludeAddressIterator = options.getInet4RouteExcludeAddress() else {
                throw NSError(domain: "nil inet4RouteExcludeAddressIterator", code: 0)
            }
            while inet4RouteExcludeAddressIterator.hasNext() {
                guard let ipv4RoutePrefix = inet4RouteExcludeAddressIterator.next() else {
                    break
                }
                ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
            }
            if SharedPreferences.excludeDefaultRoute.getBlocking(), !ipv4Routes.isEmpty {
                if !ipv4ExcludeRoutes.contains(where: { route in
                    route.destinationAddress == "0.0.0.0" && route.destinationSubnetMask == "255.255.255.254"
                }) {
                    ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "255.255.255.254"))
                }
            }
            if excludeAPNs, !ipv4Routes.isEmpty {
                if !ipv4ExcludeRoutes.contains(where: { route in
                    route.destinationAddress == "17.0.0.0" && route.destinationSubnetMask == "255.0.0.0"
                }) {
                    ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"))
                }
            }
            
            ipv4Settings.includedRoutes = ipv4Routes
            ipv4Settings.excludedRoutes = ipv4ExcludeRoutes
            settings.ipv4Settings = ipv4Settings
            
            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            guard let ipv6AddressIterator = options.getInet6Address() else {
                throw NSError(domain: "nil ipv6AddressIterator", code: 0)
            }
            while ipv6AddressIterator.hasNext() {
                guard let ipv6Prefix = ipv6AddressIterator.next() else {
                    break
                }
                ipv6Address.append(ipv6Prefix.address())
                ipv6Prefixes.append(NSNumber(value: ipv6Prefix.prefix()))
            }
            let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
            var ipv6Routes: [NEIPv6Route] = []
            var ipv6ExcludeRoutes: [NEIPv6Route] = []
            
            guard let inet6RouteAddressIterator = options.getInet6RouteAddress() else {
                throw NSError(domain: "nil inet6RouteAddressIterator", code: 0)
            }
            if inet6RouteAddressIterator.hasNext() {
                while inet6RouteAddressIterator.hasNext() {
                    guard let ipv6RoutePrefix = inet6RouteAddressIterator.next() else {
                        break
                    }
                    ipv6Routes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
                }
            } else if autoRouteUseSubRangesByDefault {
                ipv6Routes.append(NEIPv6Route(destinationAddress: "100::", networkPrefixLength: 8))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "200::", networkPrefixLength: 7))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "400::", networkPrefixLength: 6))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "800::", networkPrefixLength: 5))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "1000::", networkPrefixLength: 4))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "2000::", networkPrefixLength: 3))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "4000::", networkPrefixLength: 2))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "8000::", networkPrefixLength: 1))
            } else {
                ipv6Routes.append(NEIPv6Route.default())
            }
            
            guard let inet6RouteExcludeAddressIterator = options.getInet6RouteExcludeAddress() else {
                throw NSError(domain: "nil inet6RouteExcludeAddressIterator", code: 0)
            }
            while inet6RouteExcludeAddressIterator.hasNext() {
                guard let ipv6RoutePrefix = inet6RouteExcludeAddressIterator.next() else {
                    break
                }
                ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
            }
            
            if SharedPreferences.excludeDefaultRoute.getBlocking(), !ipv6Routes.isEmpty {
                if !ipv6ExcludeRoutes.contains(where: { route in
                    route.destinationAddress == "::" && route.destinationNetworkPrefixLength == 127
                }) {
                    ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: "::", networkPrefixLength: 127))
                }
            }
            
            ipv6Settings.includedRoutes = ipv6Routes
            ipv6Settings.excludedRoutes = ipv6ExcludeRoutes
            settings.ipv6Settings = ipv6Settings
        }
        
        if options.isHTTPProxyEnabled() {
            let proxySettings = NEProxySettings()
            let proxyServer = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxySettings.httpServer = proxyServer
            proxySettings.httpsServer = proxyServer
            if SharedPreferences.systemProxyEnabled.getBlocking() {
                proxySettings.httpEnabled = true
                proxySettings.httpsEnabled = true
            }
            var bypassDomains: [String] = []
            if let bypassDomainIterator = options.getHTTPProxyBypassDomain() {
                while bypassDomainIterator.hasNext() {
                    if let domain = bypassDomainIterator.next() {
                        bypassDomains.append(domain)
                    } else {
                        break
                    }
                }
            }
            if excludeAPNs {
                if !bypassDomains.contains(where: { $0 == "push.apple.com" }) {
                    bypassDomains.append("push.apple.com")
                }
            }
            if !bypassDomains.isEmpty {
                proxySettings.exceptionList = bypassDomains
            }
            var matchDomains: [String] = []
            if let matchDomainIterator = options.getHTTPProxyMatchDomain() {
                while matchDomainIterator.hasNext() {
                    if let domain = matchDomainIterator.next() {
                        matchDomains.append(domain)
                    } else {
                        break
                    }
                }
            }
            if !matchDomains.isEmpty {
                proxySettings.matchDomains = matchDomains
            }
            settings.proxySettings = proxySettings
        }
        
        networkSettings = settings
        try await tunnel.setTunnelNetworkSettings(settings)
        
        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }
        
        let tunFdFromLoop = LibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            ret0_.pointee = tunFdFromLoop
        } else {
            throw NSError(domain: "missing file descriptor", code: 0)
        }
    }
    
    func reset() {
        networkSettings = nil
    }
    
    // MARK: - LibboxPlatformInterfaceProtocol
    
    public func usePlatformAutoDetectControl() -> Bool {
        false
    }
    
    public func autoDetectControl(_: Int32) throws {}
    
    public func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "not implemented", code: 0)
    }
    
    public func packageName(byUid _: Int32, error _: NSErrorPointer) -> String {
        ""
    }
    
    public func uid(byPackageName _: String?, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "not implemented", code: 0)
    }
    
    public func useProcFS() -> Bool {
        false
    }
    
    public func writeLog(_ message: String?) {
        guard let message else {
            return
        }
        tunnel.writeMessage(message)
    }
    
    private var nwMonitor: NWPathMonitor?
    
    public func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else {
            return
        }
        // Cancel previous monitor if exists
        nwMonitor?.cancel()
        
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        var initialUpdateReceived = false
        
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.onUpdateDefaultInterface(listener, path)
            if !initialUpdateReceived {
                initialUpdateReceived = true
                semaphore.signal()
                // Set permanent handler
                monitor.pathUpdateHandler = { [weak self] path in
                    self?.onUpdateDefaultInterface(listener, path)
                }
            }
        }
        monitor.start(queue: DispatchQueue.global())
        
        // Timeout for semaphore to avoid infinite waiting
        let timeout = DispatchTime.now() + .seconds(5)
        if semaphore.wait(timeout: timeout) == .timedOut {
            NSLog("ExtensionPlatformInterface: Timeout waiting for initial network path update")
            // Continue work even if timeout
        }
    }
    
    private func onUpdateDefaultInterface(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
        if path.status == .unsatisfied {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
        } else {
            guard let defaultInterface = path.availableInterfaces.first else {
                listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
                return
            }
            listener.updateDefaultInterface(defaultInterface.name, interfaceIndex: Int32(defaultInterface.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
        }
    }
    
    public func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }
    
    public func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else {
            throw NSError(domain: "NWMonitor not started", code: 0)
        }
        let path = nwMonitor.currentPath
        if path.status == .unsatisfied {
            return networkInterfaceArray([])
        }
        var interfaces: [LibboxNetworkInterface] = []
        for it in path.availableInterfaces {
            let interface = LibboxNetworkInterface()
            interface.name = it.name
            interface.index = Int32(it.index)
            switch it.type {
            case .wifi:
                interface.type = LibboxInterfaceTypeWIFI
            case .cellular:
                interface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                interface.type = LibboxInterfaceTypeEthernet
            default:
                interface.type = LibboxInterfaceTypeOther
            }
            interfaces.append(interface)
        }
        return networkInterfaceArray(interfaces)
    }
    
    class networkInterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iterator: IndexingIterator<[LibboxNetworkInterface]>
        init(_ array: [LibboxNetworkInterface]) {
            iterator = array.makeIterator()
        }
        
        private var nextValue: LibboxNetworkInterface?
        
        func hasNext() -> Bool {
            nextValue = iterator.next()
            return nextValue != nil
        }
        
        func next() -> LibboxNetworkInterface? {
            nextValue
        }
    }
    
    public func underNetworkExtension() -> Bool {
        true
    }
    
    public func includeAllNetworks() -> Bool {
        #if !os(tvOS)
            return SharedPreferences.includeAllNetworks.getBlocking()
        #else
            return false
        #endif
    }
    
    public func clearDNSCache() {
        guard let networkSettings else {
            return
        }
        tunnel.reasserting = true
        tunnel.setTunnelNetworkSettings(nil) { _ in
        }
        tunnel.setTunnelNetworkSettings(networkSettings) { _ in
        }
        tunnel.reasserting = false
    }
    
    public func readWIFIState() -> LibboxWIFIState? {
        #if os(iOS)
            let network = runBlocking {
                await NEHotspotNetwork.fetchCurrent()
            }
            guard let network else {
                return nil
            }
            guard let wifiState = LibboxWIFIState(network.ssid, wifiBSSID: network.bssid) else {
                NSLog("ExtensionPlatformInterface: Failed to create LibboxWIFIState")
                return nil
            }
            return wifiState
        #elseif os(macOS)
            // TODO: Implement for macOS
            return nil
        #else
            return nil
        #endif
    }
    
    public func serviceStop() throws {
        tunnel.stopService()
    }
    
    public func serviceReload() throws {
        try runBlocking { [self] in
            try await tunnel.reloadService()
        }
    }
    
    public func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let status = LibboxSystemProxyStatus()
        guard let networkSettings else {
            return status
        }
        guard let proxySettings = networkSettings.proxySettings else {
            return status
        }
        if proxySettings.httpServer == nil {
            return status
        }
        status.available = true
        status.enabled = proxySettings.httpEnabled
        return status
    }
    
    public func setSystemProxyEnabled(_ isEnabled: Bool) throws {
        guard let networkSettings else {
            return
        }
        guard let proxySettings = networkSettings.proxySettings else {
            return
        }
        if proxySettings.httpServer == nil {
            return
        }
        if proxySettings.httpEnabled == isEnabled {
            return
        }
        proxySettings.httpEnabled = isEnabled
        proxySettings.httpsEnabled = isEnabled
        networkSettings.proxySettings = proxySettings
        try runBlocking {
            try await self.tunnel.setTunnelNetworkSettings(networkSettings)
        }
    }
    
    public func writeDebugMessage(_ message: String?) {
        guard let message else {
            return
        }
        tunnel.writeMessage(message)
    }
    
    public func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? {
        nil
    }
    
    public func systemCertificates() -> (any LibboxStringIteratorProtocol)? {
        nil
    }
    
    // MARK: - LibboxCommandServerHandlerProtocol
    
    public func send(_ notification: LibboxNotification?) throws {
        #if !os(tvOS)
            guard let notification else {
                return
            }
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            
            content.title = notification.title
            content.subtitle = notification.subtitle
            content.body = notification.body
            if !notification.openURL.isEmpty {
                content.userInfo["OPEN_URL"] = notification.openURL
                content.categoryIdentifier = "OPEN_URL"
            }
            content.interruptionLevel = .active
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
            try runBlocking {
                try await center.requestAuthorization(options: [.alert])
                try await center.add(request)
            }
        #endif
    }
}

