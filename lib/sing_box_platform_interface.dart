/// The platform interface of the `sing_box` plugin.
///
/// App developers should use `package:sing_box/sing_box.dart` instead. This
/// library is meant for alternative platform implementations and for tests,
/// which can replace [SingBoxPlatform.instance] with a fake.
library;

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'sing_box_method_channel.dart';
import 'src/models/clash_mode.dart';
import 'src/models/connection.dart';
import 'src/models/connection_stats.dart';
import 'src/models/connection_status.dart';
import 'src/models/log_entry.dart';
import 'src/models/network_quality.dart';
import 'src/models/outbound_group.dart';
import 'src/models/runtime_info.dart';
import 'src/models/sing_box_notification.dart';
import 'src/models/stun_result.dart';
import 'src/options.dart';

export 'src/models/runtime_info.dart';

/// Result of [SingBoxPlatform.pingServer].
class SingBoxNativePingResult {
  /// Creates a result.
  const SingBoxNativePingResult({
    required this.success,
    this.ping = 0,
    this.address,
    this.error,
  });

  /// Parses the map of the `pingServer` method.
  factory SingBoxNativePingResult.fromMap(Map<dynamic, dynamic> map) =>
      SingBoxNativePingResult(
        success: map['success'] == true,
        ping: (map['ping'] as num?)?.toInt() ?? 0,
        address: map['address'] as String?,
        error: map['error'] as String?,
      );

  /// Whether the server answered.
  final bool success;

  /// Latency in milliseconds.
  final int ping;

  /// The IP address that was measured.
  final String? address;

  /// Why the measurement failed.
  final String? error;
}

/// The interface that platform implementations of `sing_box` must extend.
///
/// Every method maps 1:1 to a message of the native contract described in
/// `doc/platform_channel.md`. Higher level behaviour (config generation,
/// persistence, observers) lives in `SingBox`.
///
/// Implementations must extend this class rather than implement it, so that
/// new methods added here do not break them.
abstract class SingBoxPlatform extends PlatformInterface {
  /// Constructs a SingBoxPlatform.
  SingBoxPlatform() : super(token: _token);

  static final Object _token = Object();

  static SingBoxPlatform _instance = MethodChannelSingBox();

  /// The default instance of [SingBoxPlatform] to use.
  ///
  /// Defaults to [MethodChannelSingBox].
  static SingBoxPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SingBoxPlatform] when they
  /// register themselves.
  static set instance(SingBoxPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle and information
  // ---------------------------------------------------------------------------

  /// Initializes the native side (libbox setup, notification channel, VPN
  /// profile loading).
  Future<SingBoxRuntimeInfo> initialize(SingBoxOptions options) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Returns the operating system name and version, e.g. `Android 15`.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Returns the version of the bundled sing-box core.
  Future<String> getSingBoxVersion() {
    throw UnimplementedError('getSingBoxVersion() has not been implemented.');
  }

  /// Validates [config] with sing-box. Completes normally when the config is
  /// valid and throws a configuration error otherwise.
  Future<void> checkConfig(String config) {
    throw UnimplementedError('checkConfig() has not been implemented.');
  }

  /// Returns [config] formatted by sing-box.
  Future<String> formatConfig(String config) {
    throw UnimplementedError('formatConfig() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Whether the VPN permission (Android) / VPN profile (iOS) is granted.
  Future<bool> hasVpnPermission() {
    throw UnimplementedError('hasVpnPermission() has not been implemented.');
  }

  /// Requests the VPN permission / installs the VPN profile.
  Future<bool> requestVpnPermission() {
    throw UnimplementedError(
      'requestVpnPermission() has not been implemented.',
    );
  }

  /// Whether the app may post notifications.
  Future<bool> hasNotificationPermission() {
    throw UnimplementedError(
      'hasNotificationPermission() has not been implemented.',
    );
  }

  /// Requests the notification permission.
  Future<bool> requestNotificationPermission() {
    throw UnimplementedError(
      'requestNotificationPermission() has not been implemented.',
    );
  }

  /// Opens the system VPN settings.
  Future<void> openVpnSettings() {
    throw UnimplementedError('openVpnSettings() has not been implemented.');
  }

  /// Android 13+: asks the user to add the Quick Settings tile.
  Future<SingBoxQuickTileResult> requestAddQuickSettingsTile({String? label}) {
    throw UnimplementedError(
      'requestAddQuickSettingsTile() has not been implemented.',
    );
  }

  // ---------------------------------------------------------------------------
  // Service control
  // ---------------------------------------------------------------------------

  /// Starts the tunnel with a complete sing-box [config].
  Future<void> start(String config, {bool disableMemoryLimit = false}) {
    throw UnimplementedError('start() has not been implemented.');
  }

  /// Stops the tunnel.
  Future<void> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Reloads the running service, optionally with a new [config].
  Future<void> reload([String? config]) {
    throw UnimplementedError('reload() has not been implemented.');
  }

  /// Returns the current tunnel status.
  Future<SingBoxConnectionStatus> getStatus() {
    throw UnimplementedError('getStatus() has not been implemented.');
  }

  /// Returns when the current session started, `null` when not running.
  Future<DateTime?> getStartedAt() {
    throw UnimplementedError('getStartedAt() has not been implemented.');
  }

  /// Returns the last configuration passed to [start] or [reload].
  Future<String?> getLastConfig() {
    throw UnimplementedError('getLastConfig() has not been implemented.');
  }

  /// Persists and applies native service options.
  Future<void> setServiceOptions(SingBoxServiceOptions options) {
    throw UnimplementedError('setServiceOptions() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Command client operations
  // ---------------------------------------------------------------------------

  /// Selects [outboundTag] in the selector group [groupTag].
  Future<void> selectOutbound(String groupTag, String outboundTag) {
    throw UnimplementedError('selectOutbound() has not been implemented.');
  }

  /// Starts a URL test of a group or a single outbound.
  Future<void> urlTest(String tag) {
    throw UnimplementedError('urlTest() has not been implemented.');
  }

  /// Starts (or replaces) the probe core, a libbox service without TUN in the
  /// app process that runs [config] for latency tests.
  Future<void> startProbe(String config) {
    throw UnimplementedError('startProbe() has not been implemented.');
  }

  /// Stops the probe core started by [startProbe].
  Future<void> stopProbe() {
    throw UnimplementedError('stopProbe() has not been implemented.');
  }

  /// Measures the TCP handshake (`method: 'tcp'`, needs [port]) or ICMP echo
  /// (`method: 'icmp'`) latency to [host] outside the tunnel.
  Future<SingBoxNativePingResult> pingServer({
    required String method,
    required String host,
    int? port,
    required Duration timeout,
  }) {
    throw UnimplementedError('pingServer() has not been implemented.');
  }

  /// Switches the clash mode.
  Future<void> setClashMode(String mode) {
    throw UnimplementedError('setClashMode() has not been implemented.');
  }

  /// Closes the connection with [id].
  Future<void> closeConnection(String id) {
    throw UnimplementedError('closeConnection() has not been implemented.');
  }

  /// Closes all connections.
  Future<void> closeAllConnections() {
    throw UnimplementedError('closeAllConnections() has not been implemented.');
  }

  /// Clears the log buffer of the core.
  Future<void> clearLogs() {
    throw UnimplementedError('clearLogs() has not been implemented.');
  }

  /// Persists the UI expansion state of a group.
  Future<void> setGroupExpand(String groupTag, bool expand) {
    throw UnimplementedError('setGroupExpand() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  /// Reads a persisted string value.
  Future<String?> storageRead(String key) {
    throw UnimplementedError('storageRead() has not been implemented.');
  }

  /// Persists a string value; `null` removes the key.
  Future<void> storageWrite(String key, String? value) {
    throw UnimplementedError('storageWrite() has not been implemented.');
  }

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Tunnel state updates. Emits the current state first.
  Stream<SingBoxConnectionState> watchState() {
    throw UnimplementedError('watchState() has not been implemented.');
  }

  /// Traffic statistics, about once per second while connected.
  Stream<SingBoxConnectionStats> watchStats() {
    throw UnimplementedError('watchStats() has not been implemented.');
  }

  /// Log events of the core.
  Stream<SingBoxLogEvent> watchLogEvents() {
    throw UnimplementedError('watchLogEvents() has not been implemented.');
  }

  /// Outbound groups of the running configuration.
  Stream<List<SingBoxOutboundGroup>> watchGroups() {
    throw UnimplementedError('watchGroups() has not been implemented.');
  }

  /// All outbounds with their latest URL test results.
  Stream<List<SingBoxOutboundItem>> watchOutbounds() {
    throw UnimplementedError('watchOutbounds() has not been implemented.');
  }

  /// Clash mode state.
  Stream<SingBoxClashMode> watchClashMode() {
    throw UnimplementedError('watchClashMode() has not been implemented.');
  }

  /// Connections tracked by the core.
  Stream<List<SingBoxConnection>> watchConnections() {
    throw UnimplementedError('watchConnections() has not been implemented.');
  }

  /// Notifications emitted by the core.
  Stream<SingBoxNotification> watchNotifications() {
    throw UnimplementedError('watchNotifications() has not been implemented.');
  }

  /// Runs a network quality (speed) test and streams its progress. The last
  /// event has [SingBoxNetworkQuality.isFinal] set.
  Stream<SingBoxNetworkQuality> runNetworkQualityTest({
    String? configUrl,
    String? outboundTag,
    bool serial = false,
    Duration? maxRuntime,
    bool http3 = false,
  }) {
    throw UnimplementedError(
      'runNetworkQualityTest() has not been implemented.',
    );
  }

  /// Runs a STUN (NAT type) test and streams its progress. The last event has
  /// [SingBoxStunResult.isFinal] set.
  Stream<SingBoxStunResult> runStunTest({String? server, String? outboundTag}) {
    throw UnimplementedError('runStunTest() has not been implemented.');
  }
}
