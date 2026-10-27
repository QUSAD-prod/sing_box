import Foundation
import os

/// File locations shared by the app and the Packet Tunnel extension.
///
/// | Purpose | Location |
/// | --- | --- |
/// | libbox base path (`command.sock`) | app group container |
/// | libbox working path | `<container>/sing-box` |
/// | libbox temp path | `<container>/Library/Caches/sing-box` |
/// | last config | `<working>/config.json` |
/// | last start/stop error | `<working>/last_error` |
public struct SingBoxPaths {
    private static let logger = Logger(subsystem: "sing_box", category: "Paths")

    /// The app group these paths belong to.
    public let appGroup: String
    /// The app group container, or a private fallback directory when the
    /// container is not available (see [isAppGroupContainer]).
    public let baseDirectory: URL
    /// `false` when the process is not entitled to [appGroup]. The app and
    /// the extension then cannot exchange the configuration, so the tunnel
    /// cannot work.
    public let isAppGroupContainer: Bool

    public init(appGroup: String, baseDirectory: URL, isAppGroupContainer: Bool) {
        self.appGroup = appGroup
        self.baseDirectory = baseDirectory
        self.isAppGroupContainer = isAppGroupContainer
    }

    /// Resolves the container of `appGroup`. When the process is not entitled
    /// to the group, a clear error is logged and a private directory is used
    /// so that configuration checks still work.
    public static func resolve(appGroup: String) -> SingBoxPaths {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return SingBoxPaths(appGroup: appGroup, baseDirectory: container, isAppGroupContainer: true)
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sing_box", isDirectory: true)
        logger.error("""
        sing_box: the app group container for "\(appGroup, privacy: .public)" is not available. \
        Add the App Groups capability with this group to BOTH the app and the Packet Tunnel \
        extension (same team), or pass the right group in SingBoxIosOptions.appGroup. \
        The VPN cannot work until this is fixed.
        """)
        NSLog("[sing_box] ERROR: app group container for \"%@\" is not available (missing App Groups entitlement or team mismatch). Falling back to %@; the tunnel extension will not see the configuration.", appGroup, fallback.path)
        return SingBoxPaths(appGroup: appGroup, baseDirectory: fallback, isAppGroupContainer: false)
    }

    public var workingDirectory: URL {
        baseDirectory.appendingPathComponent("sing-box", isDirectory: true)
    }

    public var tempDirectory: URL {
        baseDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("sing-box", isDirectory: true)
    }

    public var configFile: URL {
        workingDirectory.appendingPathComponent("config.json", isDirectory: false)
    }

    public var lastErrorFile: URL {
        workingDirectory.appendingPathComponent("last_error", isDirectory: false)
    }

    public var commandSocket: URL {
        baseDirectory.appendingPathComponent("command.sock", isDirectory: false)
    }

    /// Shared `UserDefaults` of the app group (falls back to `.standard`).
    public var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public func createDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    // MARK: Configuration

    public func readConfig() -> String? {
        guard let data = try? Data(contentsOf: configFile) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func writeConfig(_ config: String) throws {
        try createDirectories()
        try Data(config.utf8).write(to: configFile, options: [.atomic])
    }

    // MARK: Last error

    public func readLastError() -> String? {
        guard let data = try? Data(contentsOf: lastErrorFile),
              let message = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else {
            return nil
        }
        return message
    }

    public func writeLastError(_ message: String?) {
        guard let message, !message.isEmpty else {
            try? FileManager.default.removeItem(at: lastErrorFile)
            return
        }
        try? createDirectories()
        try? Data(message.utf8).write(to: lastErrorFile, options: [.atomic])
    }
}
