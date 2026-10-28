import Flutter
import Foundation
import Libbox
import NetworkExtension
import os
import UIKit
import UserNotifications
#if SWIFT_PACKAGE
    import SingBoxShared
#endif

/// Flutter plugin entry point. Implements `doc/platform_channel.md`.
public class SingBoxPlugin: NSObject, FlutterPlugin {
    private static let logger = Logger(subsystem: "sing_box", category: "Plugin")

    // Main thread only.
    private var controller: TunnelController?
    private var paths: SingBoxPaths?
    private var commandStreams: [CommandStreamHandler] = []
    private var eventChannels: [FlutterEventChannel] = []
    private var statusListener: UUID?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SingBoxPlugin()
        let messenger = registrar.messenger()
        let channel = FlutterMethodChannel(name: "sing_box", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.registerEventChannels(messenger)
    }

    public func detachFromEngine(for _: FlutterPluginRegistrar) {
        for channel in eventChannels {
            channel.setStreamHandler(nil)
        }
        eventChannels.removeAll()
        commandStreams.removeAll()
    }

    // MARK: - Event channels

    private func registerEventChannels(_ messenger: FlutterBinaryMessenger) {
        let isActive: () -> Bool = { [weak self] in
            MainActor.assumeIsolated {
                self?.controller?.isActive ?? false
            }
        }
        func add(_ name: String, _ handler: FlutterStreamHandler & NSObjectProtocol) {
            let channel = FlutterEventChannel(name: "sing_box/\(name)", binaryMessenger: messenger)
            channel.setStreamHandler(handler)
            eventChannels.append(channel)
        }
        add("status", StatusStreamHandler(controller: { [weak self] in self?.controller }))
        let streams: [(String, CommandStreamHandler.Kind)] = [
            ("stats", .stats),
            ("logs", .logs),
            ("groups", .groups),
            ("outbounds", .outbounds),
            ("clash_mode", .clashMode),
            ("connections", .connections),
        ]
        for (name, kind) in streams {
            let handler = CommandStreamHandler(kind: kind, isServiceActive: isActive)
            commandStreams.append(handler)
            add(name, handler)
        }
        add("notifications", NotificationStreamHandler(paths: { [weak self] in self?.paths }))
        add("network_quality", OneShotTestStreamHandler(kind: .networkQuality, isServiceActive: isActive))
        add("stun", OneShotTestStreamHandler(kind: .stun, isServiceActive: isActive))
    }

    // MARK: - Method channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task { @MainActor in
            do {
                let value = try await self.dispatch(call)
                result(value)
            } catch let error as PluginError {
                result(error.flutterError)
            } catch {
                result(FlutterError(code: "INTERNAL", message: error.localizedDescription, details: nil))
            }
        }
    }

    @MainActor
    private func dispatch(_ call: FlutterMethodCall) async throws -> Any? {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "getPlatformVersion":
            return "iOS " + UIDevice.current.systemVersion
        case "initialize":
            return try await initialize(args)
        default:
            break
        }

        guard let controller, let paths else {
            if Self.knownMethods.contains(call.method) {
                throw PluginError.notInitialized()
            }
            return FlutterMethodNotImplemented
        }

        switch call.method {
        case "getSingBoxVersion":
            return SingBoxLibbox.version
        case "checkConfig":
            let config = try requireString(args, "config")
            do {
                try await runInBackground { try SingBoxLibbox.checkConfig(config) }
            } catch {
                throw PluginError.invalidConfig(error.localizedDescription)
            }
            return nil
        case "formatConfig":
            let config = try requireString(args, "config")
            do {
                return try await runInBackground { try SingBoxLibbox.formatConfig(config) }
            } catch {
                throw PluginError.invalidConfig(error.localizedDescription)
            }

        // Permissions
        case "hasVpnPermission":
            do {
                try await controller.load()
            } catch {
                Self.logger.error("load VPN preferences: \(error.localizedDescription, privacy: .public)")
            }
            return controller.manager != nil
        case "requestVpnPermission":
            return try await controller.install()
        case "hasNotificationPermission":
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            default:
                return false
            }
        case "requestNotificationPermission":
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                throw PluginError.internalError(error.localizedDescription)
            }
        case "openVpnSettings":
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                throw PluginError.unsupported("Settings URL is not available")
            }
            await UIApplication.shared.open(url)
            return nil

        // Service control
        case "start":
            let config = try requireString(args, "config")
            try await controller.start(config: config, disableMemoryLimit: args.bool("disableMemoryLimit") ?? false)
            return nil
        case "stop":
            try await controller.stop()
            return nil
        case "reload":
            try await controller.reload(config: args.string("config"))
            return nil
        case "getStatus":
            return controller.statusString
        case "getStartedAt":
            return controller.startedAt.map { NSNumber(value: $0) }
        case "getLastConfig":
            return paths.readConfig()
        case "setServiceOptions":
            try await controller.setServiceOptions(args)
            return nil

        // Command client
        case "selectOutbound":
            let group = try requireString(args, "groupTag")
            let outbound = try requireString(args, "outboundTag")
            try await command { try $0.selectOutbound(group, outboundTag: outbound) }
            return nil
        case "urlTest":
            let tag = try requireString(args, "tag")
            try await command { try $0.urlTest(tag) }
            return nil
        case "setClashMode":
            let mode = try requireString(args, "mode")
            try await command { try $0.setClashMode(mode) }
            return nil
        case "closeConnection":
            let id = try requireString(args, "id")
            try await command { try $0.closeConnection(id) }
            return nil
        case "closeAllConnections":
            try await command { try $0.closeConnections() }
            return nil
        case "clearLogs":
            try await command { try $0.clearLogs() }
            return nil
        case "setGroupExpand":
            let group = try requireString(args, "groupTag")
            guard let expand = args.bool("expand") else {
                throw PluginError.invalidArgument("Missing argument: expand")
            }
            try await command { try $0.setGroupExpand(group, isExpand: expand) }
            return nil

        // Storage
        case "storageRead":
            let key = try requireString(args, "key")
            return paths.defaults.string(forKey: key)
        case "storageWrite":
            let key = try requireString(args, "key")
            if let value = args["value"] as? String {
                paths.defaults.set(value, forKey: key)
            } else {
                paths.defaults.removeObject(forKey: key)
            }
            return nil

        default:
            return FlutterMethodNotImplemented
        }
    }

    private static let knownMethods: Set<String> = [
        "getSingBoxVersion", "checkConfig", "formatConfig",
        "hasVpnPermission", "requestVpnPermission", "hasNotificationPermission",
        "requestNotificationPermission", "openVpnSettings",
        "start", "stop", "reload", "getStatus", "getStartedAt", "getLastConfig", "setServiceOptions",
        "selectOutbound", "urlTest", "setClashMode", "closeConnection", "closeAllConnections",
        "clearLogs", "setGroupExpand", "storageRead", "storageWrite",
    ]

    private func requireString(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String else {
            throw PluginError.invalidArgument("Missing argument: \(key)")
        }
        return value
    }

    // MARK: - initialize

    @MainActor
    private func initialize(_ args: [String: Any]) async throws -> [String: Any] {
        let ios = args["ios"] as? [String: Any] ?? [:]
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app"
        let info = Bundle.main.infoDictionary
        let displayName = (info?["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info?["CFBundleName"] as? String)
            ?? "sing-box"
        let configuration = PluginConfiguration(
            appGroup: ios.string("appGroup") ?? "group.\(bundleIdentifier)",
            tunnelBundleIdentifier: ios.string("tunnelBundleIdentifier") ?? "\(bundleIdentifier).PacketTunnel",
            profileName: ios.string("profileName") ?? displayName,
            serverAddress: ios.string("serverAddress") ?? "sing-box",
            logMaxLines: args.int("logMaxLines") ?? SingBoxKeys.defaultLogMaxLines,
            debug: args.bool("debug") ?? false
        )

        let controller: TunnelController
        if let existing = self.controller, existing.configuration.appGroup == configuration.appGroup {
            existing.configuration = configuration
            controller = existing
        } else {
            let paths = SingBoxPaths.resolve(appGroup: configuration.appGroup)
            let force = self.paths != nil && self.paths?.baseDirectory != paths.baseDirectory
            do {
                try SingBoxLibbox.setup(
                    paths: paths,
                    logMaxLines: configuration.logMaxLines,
                    debug: configuration.debug,
                    crashReportSource: "Application",
                    oomKillerEnabled: false,
                    force: force
                )
            } catch {
                throw PluginError.internalError(error.localizedDescription)
            }
            if let previous = self.controller, let statusListener {
                previous.removeListener(statusListener)
            }
            controller = TunnelController(configuration: configuration, paths: paths)
            controller.onServiceRestarted = { [weak self] in
                self?.commandStreams.forEach { $0.serviceRestarted() }
            }
            statusListener = controller.addListener { [weak self] _ in
                self?.commandStreams.forEach { $0.serviceStateChanged() }
            }
            self.paths = paths
            self.controller = controller
        }

        do {
            try await controller.load()
        } catch {
            Self.logger.error("load VPN preferences: \(error.localizedDescription, privacy: .public)")
        }

        let paths = controller.paths
        NSLog(
            "[sing_box] initialized: sing-box %@, app group %@ (container %@), tunnel bundle id %@, VPN profile %@",
            SingBoxLibbox.version,
            configuration.appGroup,
            paths.isAppGroupContainer ? "available" : "NOT AVAILABLE",
            configuration.tunnelBundleIdentifier,
            controller.manager == nil ? "not installed" : "installed"
        )
        return [
            "singBoxVersion": SingBoxLibbox.version,
            "status": controller.statusString,
            "workingDirectory": paths.workingDirectory.path,
            "appGroup": configuration.appGroup,
            "appGroupAvailable": paths.isAppGroupContainer,
            "tunnelBundleIdentifier": configuration.tunnelBundleIdentifier,
        ]
    }

    // MARK: - Command client calls

    @MainActor
    private func command(_ work: @escaping (LibboxCommandClient) throws -> Void) async throws {
        guard controller?.isActive == true else {
            throw PluginError.serviceNotRunning()
        }
        do {
            try await runInBackground {
                guard let client = LibboxNewStandaloneCommandClient() else {
                    throw SingBoxError("cannot create command client")
                }
                defer { try? client.disconnect() }
                try work(client)
            }
        } catch {
            throw PluginError.commandFailed(error.localizedDescription)
        }
    }
}
