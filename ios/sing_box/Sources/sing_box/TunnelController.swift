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
        Self.statusString(vpnStatus)
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
        switch status {
        case .connected:
            if lastError != nil {
                lastError = nil
            }
            if previous != .connected, previous != .reasserting {
                onServiceRestarted?()
            }
        case .disconnected, .invalid:
            if previous == .connecting || previous == .connected || previous == .reasserting || previous == .disconnecting {
                collectDisconnectError()
            }
        default:
            break
        }
        emit()
    }

    /// Reads why the last session ended: the message written by the
    /// extension, else `fetchLastDisconnectError` (iOS 16+).
    private func collectDisconnectError() {
        if let message = paths.readLastError() {
            lastError = message
            emit()
            return
        }
        guard #available(iOS 16.0, *), let connection = manager?.connection else {
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

        init() {}

        init(_ map: [String: Any]) {
            onDemand = map.bool("onDemand") ?? false
            includeAllNetworks = map.bool("includeAllNetworks") ?? false
            excludeLocalNetworks = map.bool("excludeLocalNetworks") ?? true
            excludeAPNs = map.bool("excludeAPNs") ?? true
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
            if #available(iOS 16.4, *) {
                proto.excludeAPNs = options.excludeAPNs
            }
        }
    }

    // MARK: - Control

    func start(config: String, disableMemoryLimit: Bool) async throws {
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
        paths.defaults.set(disableMemoryLimit, forKey: SingBoxKeys.disableMemoryLimit)
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
        paths.writeLastError(nil)
        do {
            try manager.connection.startVPNTunnel(options: [
                SingBoxKeys.startOptionDisableMemoryLimit: NSNumber(value: disableMemoryLimit),
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
        emit()
    }

    func stop() async throws {
        if manager == nil {
            _ = try? await load()
        }
        guard let manager else {
            return
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
        guard isActive else {
            throw PluginError.serviceNotRunning()
        }
        do {
            try await sendReload()
        } catch {
            throw PluginError.commandFailed(error.localizedDescription)
        }
    }

    /// Asks the extension to re-read the configuration file and reload.
    private func sendReload() async throws {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            throw PluginError.serviceNotRunning()
        }
        let message = try JSONSerialization.data(withJSONObject: [SingBoxKeys.messageCommand: SingBoxKeys.messageReload])
        let response: Data? = try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        if let response, !response.isEmpty {
            throw SingBoxError(String(data: response, encoding: .utf8) ?? "reload failed")
        }
        onServiceRestarted?()
    }
}
