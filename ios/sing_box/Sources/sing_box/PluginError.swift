import Flutter
import Foundation

/// An error reported to Dart as a `PlatformException` (codes from
/// `doc/platform_channel.md`).
struct PluginError: Error, LocalizedError {
    let code: String
    let message: String?

    init(_ code: String, _ message: String?) {
        self.code = code
        self.message = message
    }

    var errorDescription: String? { message }

    var flutterError: FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }

    static let notInitializedMessage = "SingBox.initialize() has not been called"

    static func notInitialized() -> PluginError {
        PluginError("NOT_INITIALIZED", notInitializedMessage)
    }

    static func invalidArgument(_ message: String) -> PluginError {
        PluginError("INVALID_ARGUMENT", message)
    }

    static func invalidConfig(_ message: String) -> PluginError {
        PluginError("INVALID_CONFIG", message)
    }

    static func permissionDenied(_ message: String) -> PluginError {
        PluginError("PERMISSION_DENIED", message)
    }

    static func serviceNotRunning(_ message: String = "The VPN service is not running") -> PluginError {
        PluginError("SERVICE_NOT_RUNNING", message)
    }

    static func startFailed(_ message: String) -> PluginError {
        PluginError("START_FAILED", message)
    }

    static func commandFailed(_ message: String) -> PluginError {
        PluginError("COMMAND_FAILED", message)
    }

    static func unsupported(_ message: String) -> PluginError {
        PluginError("UNSUPPORTED", message)
    }

    static func internalError(_ message: String) -> PluginError {
        PluginError("INTERNAL", message)
    }

    static func from(_ error: Error, code: String = "INTERNAL") -> PluginError {
        if let error = error as? PluginError {
            return error
        }
        return PluginError(code, error.localizedDescription)
    }
}

/// Runs blocking work (libbox calls) off the main thread.
func runInBackground<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: Result { try work() })
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        guard let value = self[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    func bool(_ key: String) -> Bool? {
        (self[key] as? NSNumber)?.boolValue
    }

    func int(_ key: String) -> Int? {
        (self[key] as? NSNumber)?.intValue
    }
}
