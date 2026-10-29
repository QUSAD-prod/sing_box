import Foundation

/// Identifiers shared by the Flutter plugin (app process) and the Packet
/// Tunnel extension. They are part of the contract between both processes,
/// see `doc/platform_channel.md`.
public enum SingBoxKeys {
    /// `NETunnelProviderProtocol.providerConfiguration` key with the app group.
    public static let providerAppGroup = "appGroup"
    /// `providerConfiguration` key with the libbox log buffer size.
    public static let providerLogMaxLines = "logMaxLines"
    /// `providerConfiguration` key enabling libbox debug mode.
    public static let providerDebug = "debug"

    /// Extension `Info.plist` key with the app group (fallback).
    public static let infoPlistAppGroup = "SingBoxAppGroup"

    /// App group `UserDefaults` key with the persisted service options.
    public static let serviceOptions = "sing_box.service_options"
    /// App group `UserDefaults` key: `true` disables the libbox memory limit.
    public static let disableMemoryLimit = "sing_box.disable_memory_limit"
    /// App group `UserDefaults` key with notifications the extension posted
    /// that the app has not consumed yet.
    public static let pendingNotifications = "sing_box.pending_notifications"

    /// `startVPNTunnel(options:)` key mirroring `disableMemoryLimit`.
    public static let startOptionDisableMemoryLimit = "disableMemoryLimit"
    /// `startVPNTunnel(options:)` key with an inline configuration that takes
    /// precedence over the configuration file.
    public static let startOptionConfigContent = "configContent"

    /// Provider message (`sendProviderMessage`) JSON key.
    public static let messageCommand = "command"
    /// Provider message command: re-read the configuration file and reload.
    public static let messageReload = "reload"
    /// Provider message command: `pingServer` outside the tunnel. The message
    /// also has the `pingServer` arguments (`method`, `host`, `port`,
    /// `timeoutMs`); the reply is the JSON result map.
    public static let messagePing = "ping"

    /// Darwin notification posted by the extension when it queued a core
    /// notification for the app.
    public static func notificationDarwinName(appGroup: String) -> String {
        "\(appGroup).sing_box.notification"
    }

    /// Maximum number of queued notifications kept for the app.
    public static let maxPendingNotifications = 32

    /// Default libbox log buffer size.
    public static let defaultLogMaxLines = 3000
}
