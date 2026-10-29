import Foundation
import Libbox

/// Error with a plain message (shown as `localizedDescription`).
public struct SingBoxError: LocalizedError, CustomNSError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
    public static var errorDomain: String { "sing_box" }
    public var errorCode: Int { 1 }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: message] }
}

/// Thin helpers around the libbox C API shared by the app and the extension.
public enum SingBoxLibbox {
    private static let lock = NSLock()
    private static var setupBasePath: String?

    /// Calls `LibboxSetup` with the shared directory layout.
    ///
    /// - Parameters:
    ///   - force: run setup again even if this process already did (the
    ///     extension does this for every tunnel session).
    ///   - oomKillerEnabled: enables libbox's memory limit / OOM killer, which
    ///     keeps the extension below the Network Extension memory limit.
    ///   - platformMetadata: extra JSON fields for crash and OOM reports.
    public static func setup(
        paths: SingBoxPaths,
        logMaxLines: Int,
        debug: Bool,
        crashReportSource: String,
        oomKillerEnabled: Bool,
        platformMetadata: [String: Any] = [:],
        force: Bool
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        if !force, setupBasePath != nil {
            return
        }
        try paths.createDirectories()
        let options = LibboxSetupOptions()
        options.basePath = paths.baseDirectory.path
        options.workingPath = paths.workingDirectory.path
        options.tempPath = paths.tempDirectory.path
        options.logMaxLines = logMaxLines > 0 ? logMaxLines : SingBoxKeys.defaultLogMaxLines
        options.debug = debug
        options.crashReportSource = crashReportSource
        options.oomKillerEnabled = oomKillerEnabled
        options.platformMetadata = Self.platformMetadata(platformMetadata)
        let info = Bundle.main.infoDictionary
        if let build = info?["CFBundleVersion"] as? String {
            options.appVersion = build
        }
        if let version = info?["CFBundleShortVersionString"] as? String {
            options.appMarketingVersion = version
        }
        var error: NSError?
        LibboxSetup(options, &error)
        if let error {
            throw SingBoxError("libbox setup: \(error.localizedDescription)")
        }
        setupBasePath = paths.baseDirectory.path
    }

    /// Platform description stored in crash and OOM reports.
    private static func platformMetadata(_ extra: [String: Any]) -> String {
        var metadata = extra
        let os = ProcessInfo.processInfo.operatingSystemVersion
        metadata["os"] = "iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        var system = utsname()
        uname(&system)
        metadata["model"] = withUnsafeBytes(of: system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether `setup` ran in this process.
    public static var isSetUp: Bool {
        lock.lock()
        defer { lock.unlock() }
        return setupBasePath != nil
    }

    public static var version: String {
        LibboxVersion()
    }

    /// Validates a configuration; throws the sing-box error.
    public static func checkConfig(_ config: String) throws {
        var error: NSError?
        LibboxCheckConfig(config, &error)
        if let error {
            throw SingBoxError(error.localizedDescription)
        }
    }

    /// Pretty-prints a configuration; throws the sing-box error.
    public static func formatConfig(_ config: String) throws -> String {
        var error: NSError?
        let result = LibboxFormatConfig(config, &error)
        if let error {
            throw SingBoxError(error.localizedDescription)
        }
        return result?.value ?? config
    }
}

// MARK: - Iterators

public extension LibboxStringIteratorProtocol {
    func toArray() -> [String] {
        var array: [String] = []
        while hasNext() {
            array.append(next())
        }
        return array
    }
}

public final class SingBoxStringIterator: NSObject, LibboxStringIteratorProtocol {
    private let array: [String]
    private var index = 0
    private var current = ""

    public init(_ array: [String]) {
        self.array = array
    }

    public func len() -> Int32 {
        Int32(array.count - index)
    }

    public func hasNext() -> Bool {
        guard index < array.count else { return false }
        current = array[index]
        index += 1
        return true
    }

    public func next() -> String {
        current
    }
}

// MARK: - Notifications forwarded from the extension to the app

/// Notifications that the extension received from the core
/// (`PlatformInterface.sendNotification`) and queued for the app.
public enum SingBoxNotificationQueue {
    public static func payload(_ notification: LibboxNotification) -> [String: Any] {
        [
            "identifier": notification.identifier,
            "typeName": notification.typeName,
            "typeId": Int(notification.typeID),
            "title": notification.title,
            "subtitle": notification.subtitle,
            "body": notification.body,
            "openUrl": notification.openURL,
        ]
    }

    /// Appends a payload (extension side) and posts the Darwin notification.
    public static func enqueue(_ payload: [String: Any], paths: SingBoxPaths) {
        let defaults = paths.defaults
        var queue = defaults.array(forKey: SingBoxKeys.pendingNotifications) as? [[String: Any]] ?? []
        queue.append(payload)
        if queue.count > SingBoxKeys.maxPendingNotifications {
            queue.removeFirst(queue.count - SingBoxKeys.maxPendingNotifications)
        }
        defaults.set(queue, forKey: SingBoxKeys.pendingNotifications)
        defaults.synchronize()
        let name = SingBoxKeys.notificationDarwinName(appGroup: paths.appGroup) as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }

    /// Removes and returns all queued payloads (app side).
    public static func drain(paths: SingBoxPaths) -> [[String: Any]] {
        let defaults = paths.defaults
        defaults.synchronize()
        let queue = defaults.array(forKey: SingBoxKeys.pendingNotifications) as? [[String: Any]] ?? []
        if !queue.isEmpty {
            defaults.removeObject(forKey: SingBoxKeys.pendingNotifications)
        }
        return queue
    }
}
