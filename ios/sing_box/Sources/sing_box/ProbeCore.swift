import Foundation
import Libbox
import os
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

/// The probe core: a second libbox service in the app process that runs a
/// configuration without TUN (`direct` inbounds on 127.0.0.1) for latency
/// tests while the VPN is stopped. Its command server is never started, so it
/// opens no command socket next to the extension's. Blocking: call off the
/// main thread.
final class ProbeCore {
    static let shared = ProbeCore()

    private let lock = NSLock()
    private var server: LibboxCommandServer?
    private var platformInterface: ProbePlatformInterface?

    /// Starts `config`, replacing a running probe core.
    func start(config: String) throws {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
        do {
            try SingBoxLibbox.checkConfig(config)
        } catch {
            throw PluginError.invalidConfig(error.localizedDescription)
        }
        let platform = ProbePlatformInterface()
        var error: NSError?
        let created = LibboxNewCommandServer(platform, platform, &error)
        if let error {
            throw PluginError.startFailed("create command server: \(error.localizedDescription)")
        }
        guard let created else {
            throw PluginError.startFailed("create command server failed")
        }
        do {
            try created.startOrReloadService(config, options: LibboxOverrideOptions())
        } catch {
            try? created.closeService()
            created.close()
            platform.reset()
            throw PluginError.startFailed(error.localizedDescription)
        }
        server = created
        platformInterface = platform
    }

    /// Stops the probe core; no-op without one.
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        guard let current = server else {
            return
        }
        server = nil
        try? current.closeService()
        current.close()
        platformInterface?.reset()
        platformInterface = nil
    }
}

/// libbox platform interface of the probe core: no TUN, no system proxy, no
/// UI; only the default interface monitor that `auto_detect_interface` needs.
private final class ProbePlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private static let logger = Logger(subsystem: "sing_box", category: "ProbeCore")

    private let interfaceMonitor = SingBoxInterfaceMonitor()

    func reset() {
        interfaceMonitor.close()
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "sing_box.ProbeCore", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - LibboxPlatformInterfaceProtocol

    func openTun(_: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw Self.error("the probe core has no TUN")
    }

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

    func underNetworkExtension() -> Bool {
        false
    }

    func includeAllNetworks() -> Bool {
        false
    }

    func usePlatformAutoDetectControl() -> Bool {
        false
    }

    func autoDetectControl(_: Int32) throws {}

    func clearDNSCache() {}

    func readWIFIState() -> LibboxWIFIState? {
        nil
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

    func send(_: LibboxNotification?) throws {}

    func cancelNotification(_: String?, typeID _: Int32) throws {}

    // MARK: - LibboxCommandServerHandlerProtocol

    func serviceStop() throws {}

    func serviceReload() throws {}

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        LibboxSystemProxyStatus()
    }

    func setSystemProxyEnabled(_: Bool) throws {}

    func triggerNativeCrash() throws {
        throw Self.error("not supported")
    }

    func writeDebugMessage(_ message: String?) {
        guard let message else {
            return
        }
        Self.logger.debug("probe core: \(message, privacy: .public)")
    }

    func connectSSHAgent(_: UnsafeMutablePointer<Int32>?) throws {
        throw Self.error("SSH agent forwarding is not supported on iOS")
    }
}
