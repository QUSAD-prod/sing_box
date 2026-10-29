import Foundation
import NetworkExtension
import os
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

/// Snapshot emitted on `sing_box/status`.
struct TunnelState: Equatable {
    var status: String
    var startedAt: Int64?
    var error: String?

    var payload: [String: Any] {
        [
            "status": status,
            "startedAt": startedAt.map { NSNumber(value: $0) } ?? NSNull(),
            "error": error ?? NSNull(),
        ]
    }
}

/// Settings of the plugin resolved by `initialize`.
struct PluginConfiguration {
    var appGroup: String
    var tunnelBundleIdentifier: String
    var profileName: String
    var serverAddress: String
    var logMaxLines: Int
    var debug: Bool
}

/// Owns the `NETunnelProviderManager` of the Packet Tunnel extension:
/// profile installation, start/stop/reload, service options and status.
@MainActor
final class TunnelController {
    private static let logger = Logger(subsystem: "sing_box", category: "TunnelController")

    var configuration: PluginConfiguration
    let paths: SingBoxPaths
    private(set) var manager: NETunnelProviderManager?
    private(set) var lastError: String?
    private var lastStatus: NEVPNStatus = .invalid
    private var observers: [NSObjectProtocol] = []
    private var listeners: [UUID: (TunnelState) -> Void] = [:]
    private var lastEmitted: TunnelState?
    /// `startVPNTunnel` succeeded but iOS has not reported a status change
    /// yet. Reported as `connecting` (the contract emits `connecting` before
    /// the `start` result), and the next `disconnected` ends this attempt.
    private var startPending = false
    private var startToken = UUID()
    /// `stop()` was called: the following disconnect is not a failure.
    private var stopRequested = false
    /// Called after a successful reload and when the tunnel became connected.
    var onServiceRestarted: (() -> Void)?

    init(configuration: PluginConfiguration, paths: SingBoxPaths) {
        self.configuration = configuration
        self.paths = paths
        lastError = paths.readLastError()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] notification in
            let connection = notification.object as? NEVPNConnection
            MainActor.assumeIsolated {
                self?.handleStatusNotification(connection)
            }
        })
        observers.append(center.addObserver(forName: .NEVPNConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor in
                    _ = try? await self.load()
                }
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Status

    var vpnStatus: NEVPNStatus {
        manager?.connection.status ?? .disconnected
    }

    var isActive: Bool {
        switch vpnStatus {
        case .connecting, .connected, .reasserting:
            return true
        default:
            return false
        }
    }

    var isConnected: Bool {
        vpnStatus == .connected || vpnStatus == .reasserting
    }

    static func statusString(_ status: NEVPNStatus) -> String {
        switch status {
        case .connecting, .reasserting:
            return "connecting"
        case .connected:
            return "connected"
        case .disconnecting:
            return "disconnecting"
        case .invalid, .disconnected:
            return "disconnected"
        @unknown default:
            return "disconnected"
        }
    }

    var statusString: String {
        let status = vpnStatus
        if startPending, status == .disconnected || status == .invalid {
            return "connecting"
        }
        return Self.statusString(status)
    }

    var startedAt: Int64? {
        guard isConnected, let date = manager?.connection.connectedDate else {
            return nil
        }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    var state: TunnelState {
        TunnelState(status: statusString, startedAt: startedAt, error: lastError)
    }

    func addListener(_ listener: @escaping (TunnelState) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        listener(state)
        return id
    }

    func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    private func emit(force: Bool = false) {
        let current = state
        if !force, current == lastEmitted {
            return
        }
        lastEmitted = current
        for listener in listeners.values {
            listener(current)
        }
    }

    private func matches(_ manager: NEVPNManager?) -> Bool {
        guard let proto = manager?.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }
        return proto.providerBundleIdentifier == configuration.tunnelBundleIdentifier
    }

    private func handleStatusNotification(_ connection: NEVPNConnection?) {
        if let connection {
            if let current = manager, connection !== current.connection, !matches(connection.manager) {
                return
            }
            if manager == nil, !matches(connection.manager) {
                return
            }
        }
        statusChanged()
    }

    private func statusChanged() {
        let status = vpnStatus
        let previous = lastStatus
        lastStatus = status
        // iOS reported on the requested start (the status is read live, so a
        // start failing fast may already read `disconnected` here).
        let endsStart = startPending
        startPending = false
        switch status {
        case .connected:
            if lastError != nil {
                lastError = nil
            }
            if previous != .connected, previous != .reasserting {
                onServiceRestarted?()
            }
        case .disconnected, .invalid:
            if endsStart || previous == .connecting || previous == .connected || previous == .reasserting || previous == .disconnecting {
                collectDisconnectError(userStopped: stopRequested)
                stopRequested = false
            }
        default:
            break
        }
        emit()
    }

    /// Reads why the last session ended: the message written by the
    /// extension, else `fetchLastDisconnectError` (iOS 16+). The latter may
    /// still hold the error of an earlier session, so it is not consulted
    /// after `stop()`.
    private func collectDisconnectError(userStopped: Bool) {
        if let message = paths.readLastError() {
            lastError = message
            emit()
            return
        }
        guard !userStopped, #available(iOS 16.0, *), let connection = manager?.connection else {
            return
        }
        Task { @MainActor in
            do {
                try await connection.fetchLastDisconnectError()
            } catch {
                let nsError = error as NSError
                // Ignore "no error" style results.
                if nsError.domain == NEVPNConnectionErrorDomain || !nsError.localizedDescription.isEmpty {
                    if let message = self.paths.readLastError() {
                        self.lastError = message
                    } else {
                        self.lastError = nsError.localizedDescription
                    }
                    self.emit()
                }
            }
        }
    }

    // MARK: - Profile

    /// Loads the manager of the configured extension from preferences.
    @discardableResult
    func load() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let found = managers.first { matches($0) }
        if let found, let manager, found !== manager {
            // Keep observing the same connection semantics.
            self.manager = found
        } else {
            manager = found
        }
        lastStatus = vpnStatus
        emit()
        return found
    }

    /// Installs (or updates) the VPN profile. iOS shows the "Add VPN
    /// Configurations" alert the first time. Returns `false` when the user
    /// declined.
    func install() async throws -> Bool {
        if manager == nil {
            _ = try? await load()
        }
        let target = manager ?? NETunnelProviderManager()
        configure(target)
        applyServiceOptions(to: target, starting: false)
        do {
            try await target.saveToPreferences()
            try await target.loadFromPreferences()
        } catch {
            if Self.isPermissionDenied(error) {
                return false
            }
            throw PluginError.internalError("Saving the VPN configuration failed: \(error.localizedDescription)")
        }
        manager = target
        lastStatus = vpnStatus
        emit()
        return true
    }

    private func configure(_ manager: NETunnelProviderManager) {
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = configuration.tunnelBundleIdentifier
        proto.serverAddress = configuration.serverAddress
        var providerConfiguration = proto.providerConfiguration ?? [:]
        providerConfiguration[SingBoxKeys.providerAppGroup] = configuration.appGroup
        providerConfiguration[SingBoxKeys.providerLogMaxLines] = configuration.logMaxLines
        providerConfiguration[SingBoxKeys.providerDebug] = configuration.debug
        proto.providerConfiguration = providerConfiguration
        proto.disconnectOnSleep = false
        manager.protocolConfiguration = proto
        manager.localizedDescription = configuration.profileName
        manager.isEnabled = true
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NEVPNErrorDomain && nsError.code == NEVPNError.configurationReadWriteFailed.rawValue
    }

    // MARK: - Service options

    struct ServiceOptions {
        var onDemand = false
        var includeAllNetworks = false
        var excludeLocalNetworks = true
        var excludeAPNs = true
        var enforceRoutes = false
        var excludeCellularServices = false
        var excludeDeviceCommunication = false

        init() {}

        init(_ map: [String: Any]) {
            onDemand = map.bool("onDemand") ?? false
            includeAllNetworks = map.bool("includeAllNetworks") ?? false
            excludeLocalNetworks = map.bool("excludeLocalNetworks") ?? true
            excludeAPNs = map.bool("excludeAPNs") ?? true
            enforceRoutes = map.bool("enforceRoutes") ?? false
            excludeCellularServices = map.bool("excludeCellularServices") ?? false
            excludeDeviceCommunication = map.bool("excludeDeviceCommunication") ?? false
        }
    }

    var serviceOptions: ServiceOptions {
        guard let map = paths.defaults.dictionary(forKey: SingBoxKeys.serviceOptions) else {
            return ServiceOptions()
        }
        return ServiceOptions(map)
    }

    func setServiceOptions(_ map: [String: Any]) async throws {
        var stored: [String: Any] = [:]
        for (key, value) in map where !(value is NSNull) {
            stored[key] = value
        }
        paths.defaults.set(stored, forKey: SingBoxKeys.serviceOptions)
        guard let manager else {
            return
        }
        applyServiceOptions(to: manager, starting: false)
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } catch {
            throw PluginError.internalError("Saving the VPN configuration failed: \(error.localizedDescription)")
        }
    }

    /// Applies the persisted service options. On-demand is only switched on
    /// while starting or running, so that changing the setting does not start
    /// the VPN by itself.
    private func applyServiceOptions(to manager: NETunnelProviderManager, starting: Bool) {
        let options = serviceOptions
        let enableOnDemand = options.onDemand && (starting || isActive || manager.isOnDemandEnabled)
        if enableOnDemand {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
        }
        manager.isOnDemandEnabled = enableOnDemand
        if let proto = manager.protocolConfiguration {
            proto.includeAllNetworks = options.includeAllNetworks
            proto.excludeLocalNetworks = options.excludeLocalNetworks
            proto.enforceRoutes = options.enforceRoutes
            if #available(iOS 16.4, *) {
                proto.excludeAPNs = options.excludeAPNs
                proto.excludeCellularServices = options.excludeCellularServices
            }
            if #available(iOS 17.4, *) {
                proto.excludeDeviceCommunication = options.excludeDeviceCommunication
            }
        }
    }

    // MARK: - Control

    func start(config: String, oomKiller: String, memoryLimit: Int64) async throws {
        do {
            try await runInBackground { try SingBoxLibbox.checkConfig(config) }
        } catch {
            throw PluginError.invalidConfig(error.localizedDescription)
        }
        do {
            try paths.writeConfig(config)
        } catch {
            throw PluginError.internalError("Writing the configuration failed: \(error.localizedDescription)")
        }
        paths.defaults.set(oomKiller, forKey: SingBoxKeys.oomKiller)
        paths.defaults.set(NSNumber(value: memoryLimit), forKey: SingBoxKeys.memoryLimit)
        paths.defaults.removeObject(forKey: SingBoxKeys.disableMemoryLimit)
        if !paths.isAppGroupContainer {
            Self.logger.error("starting without an app group container: the extension will not find the configuration")
        }

        if manager == nil {
            _ = try? await load()
        }
        guard let manager else {
            throw PluginError.permissionDenied("The VPN profile is not installed. Call requestVpnPermission() first.")
        }

        if isActive {
            do {
                try await sendReload()
            } catch let error as PluginError {
                throw error
            } catch {
                throw PluginError.startFailed(error.localizedDescription)
            }
            return
        }
        if vpnStatus == .disconnecting {
            for _ in 0 ..< 50 where vpnStatus == .disconnecting {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        configure(manager)
        applyServiceOptions(to: manager, starting: true)
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } catch {
            if Self.isPermissionDenied(error) {
                throw PluginError.permissionDenied("The VPN configuration could not be saved: \(error.localizedDescription)")
            }
            throw PluginError.startFailed("Saving the VPN configuration failed: \(error.localizedDescription)")
        }

        lastError = nil
        stopRequested = false
        paths.writeLastError(nil)
        do {
            try manager.connection.startVPNTunnel(options: [
                SingBoxKeys.startOptionOomKiller: oomKiller as NSString,
                SingBoxKeys.startOptionMemoryLimit: NSNumber(value: memoryLimit),
            ])
        } catch {
            let nsError = error as NSError
            if nsError.domain == NEVPNErrorDomain,
               nsError.code == NEVPNError.configurationDisabled.rawValue || nsError.code == NEVPNError.configurationInvalid.rawValue
            {
                throw PluginError.permissionDenied("Starting the VPN failed: \(error.localizedDescription)")
            }
            throw PluginError.startFailed("Starting the VPN failed: \(error.localizedDescription)")
        }
        lastStatus = vpnStatus
        if vpnStatus == .disconnected || vpnStatus == .invalid {
            startPending = true
            let token = UUID()
            startToken = token
            // Safety net: report the real status if iOS never reacts.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, self.startToken == token, self.startPending else { return }
                self.startPending = false
                self.emit()
            }
        }
        emit()
    }

    func stop() async throws {
        if manager == nil {
            _ = try? await load()
        }
        guard let manager else {
            return
        }
        stopRequested = isActive || startPending || vpnStatus == .disconnecting
        if startPending {
            startPending = false
            emit()
        }
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            do {
                try await manager.saveToPreferences()
            } catch {
                Self.logger.error("disable on-demand: \(error.localizedDescription, privacy: .public)")
            }
        }
        manager.connection.stopVPNTunnel()
    }

    func reload(config: String?) async throws {
        // A failed call leaves the last config untouched (as on Android).
        guard isActive else {
            throw PluginError.serviceNotRunning()
        }
        if let config {
            do {
                try await runInBackground { try SingBoxLibbox.checkConfig(config) }
            } catch {
                throw PluginError.invalidConfig(error.localizedDescription)
            }
            do {
                try paths.writeConfig(config)
            } catch {
                throw PluginError.internalError("Writing the configuration failed: \(error.localizedDescription)")
            }
        }
        do {
            try await sendReload()
        } catch let error as PluginError {
            throw error
        } catch {
            // As on Android: a failed reload stops the tunnel (the extension
            // cancels it) and is reported as a start failure.
            throw PluginError.startFailed(error.localizedDescription)
        }
    }

    /// Asks the extension to re-read the configuration file and reload.
    private func sendReload() async throws {
        let response = try await sendMessage([SingBoxKeys.messageCommand: SingBoxKeys.messageReload])
        if let response, !response.isEmpty {
            throw SingBoxError(String(data: response, encoding: .utf8) ?? "reload failed")
        }
        onServiceRestarted?()
    }

    /// `pingServer` in the extension, whose sockets bypass the tunnel. A
    /// failure to reach the extension is a failed measurement.
    func ping(method: String, host: String, port: Int?, timeoutMs: Int) async -> [String: Any] {
        var message: [String: Any] = [
            SingBoxKeys.messageCommand: SingBoxKeys.messagePing,
            "method": method,
            "host": host,
            "timeoutMs": timeoutMs,
        ]
        message["port"] = port
        do {
            let response = try await sendMessage(message)
            if let response,
               let result = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
            {
                return result
            }
            let text = response.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return ["success": false, "error": "The tunnel did not measure: \(text.isEmpty ? "no reply" : text)"]
        } catch {
            return ["success": false, "error": "The tunnel did not measure: \(error.localizedDescription)"]
        }
    }

    private func sendMessage(_ object: [String: Any]) async throws -> Data? {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            throw PluginError.serviceNotRunning()
        }
        let message = try JSONSerialization.data(withJSONObject: object)
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
