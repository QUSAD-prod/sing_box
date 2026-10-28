import '../models/connection_stats.dart';
import '../models/connection_status.dart';
import '../models/sing_box_notification.dart';

/// Receives diagnostic events from the `sing_box` plugin.
///
/// Register an observer with `SingBox.instance.setObserver()` to forward the
/// plugin's activity to your logging solution. Every method has an empty
/// default implementation, so extend this class and override only what you
/// need:
///
/// ```dart
/// class PrintObserver extends SingBoxObserver {
///   @override
///   void info(String message, [Map<String, dynamic>? data]) =>
///       print('[sing_box] $message ${data ?? ''}');
///
///   @override
///   void error(String message, [Object? error, StackTrace? stackTrace]) =>
///       print('[sing_box] ERROR $message: $error');
/// }
///
/// SingBox.instance.setObserver(PrintObserver());
/// ```
///
/// See also [SingBoxNoOpObserver] and `SingBoxTalkerObserver`.
abstract class SingBoxObserver {
  /// Allows subclasses to have `const` constructors.
  const SingBoxObserver();

  /// Logs an informational message.
  void info(String message, [Map<String, dynamic>? data]) {}

  /// Logs a warning.
  void warning(String message, [Map<String, dynamic>? data]) {}

  /// Logs an error.
  void error(String message, [Object? error, StackTrace? stackTrace]) {}

  /// Logs a debug message.
  void debug(String message, [Map<String, dynamic>? data]) {}

  /// Called right before the tunnel is started with [config] (the final,
  /// generated configuration; it contains credentials, do not log it in
  /// production).
  void onConnect(String config) {}

  /// Called right before the tunnel is stopped.
  void onDisconnect() {}

  /// Called when the tunnel status changes; [status] is the
  /// `SingBoxConnectionStatus.name`.
  void onStatusChanged(String status) {}

  /// Called with the full state whenever it changes.
  void onConnectionStateChanged(SingBoxConnectionState state) {}

  /// Called when connecting fails or the tunnel stops because of an error.
  void onConnectionError(String error) {}

  /// Called when new traffic statistics are received.
  void onConnectionStatsChanged(SingBoxConnectionStats stats) {}

  /// Called when a setting is changed.
  void onSettingsChanged(String key, dynamic value) {}

  /// Called when a server configuration is added.
  void onServerConfigAdded(String configId, String name) {}

  /// Called when a server configuration is removed.
  void onServerConfigRemoved(String configId) {}

  /// Called when the active server configuration changes.
  void onActiveServerConfigChanged(String configId) {}

  /// Called when the sing-box core emits a notification.
  void onNotification(SingBoxNotification notification) {}
}

/// An observer that ignores every event. This is the default.
class SingBoxNoOpObserver extends SingBoxObserver {
  /// Creates the no-op observer.
  const SingBoxNoOpObserver();
}
