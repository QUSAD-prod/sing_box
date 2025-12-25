import '../models/connection_stats.dart';

/// Interface for observing SingBox events
/// Allows logging events and tracking plugin operation
abstract class SingBoxObserver {
  /// Log informational message
  void info(String message, [Map<String, dynamic>? data]);

  /// Log warning
  void warning(String message, [Map<String, dynamic>? data]);

  /// Log error
  void error(String message, [Object? error, StackTrace? stackTrace]);

  /// Log debug message
  void debug(String message, [Map<String, dynamic>? data]);

  /// Log connection event
  void onConnect(String config);

  /// Log disconnection event
  void onDisconnect();

  /// Log connection status change
  void onStatusChanged(String status);

  /// Log connection error
  void onConnectionError(String error);

  /// Log connection statistics update
  /// Includes download/upload speed, bytes sent/received, ping, connection duration
  void onConnectionStatsChanged(SingBoxConnectionStats stats);

  /// Log settings change
  void onSettingsChanged(String key, dynamic value);

  /// Log server configuration addition
  void onServerConfigAdded(String configId, String name);

  /// Log server configuration removal
  void onServerConfigRemoved(String configId);

  /// Log active configuration change
  void onActiveServerConfigChanged(String configId);
}

/// Empty observer implementation (default)
class SingBoxNoOpObserver implements SingBoxObserver {
  const SingBoxNoOpObserver();

  @override
  void info(String message, [Map<String, dynamic>? data]) {}

  @override
  void warning(String message, [Map<String, dynamic>? data]) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void debug(String message, [Map<String, dynamic>? data]) {}

  @override
  void onConnect(String config) {}

  @override
  void onDisconnect() {}

  @override
  void onStatusChanged(String status) {}

  @override
  void onConnectionError(String error) {}

  @override
  void onConnectionStatsChanged(SingBoxConnectionStats stats) {}

  @override
  void onSettingsChanged(String key, dynamic value) {}

  @override
  void onServerConfigAdded(String configId, String name) {}

  @override
  void onServerConfigRemoved(String configId) {}

  @override
  void onActiveServerConfigChanged(String configId) {}
}
