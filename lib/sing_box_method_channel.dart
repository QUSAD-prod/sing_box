/// The default [SingBoxPlatform] implementation based on platform channels.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sing_box_platform_interface.dart';
import 'src/exceptions.dart';
import 'src/models/clash_mode.dart';
import 'src/models/connection.dart';
import 'src/models/connection_stats.dart';
import 'src/models/connection_status.dart';
import 'src/models/log_entry.dart';
import 'src/models/network_quality.dart';
import 'src/models/outbound_group.dart';
import 'src/models/sing_box_notification.dart';
import 'src/models/stun_result.dart';
import 'src/options.dart';

/// An implementation of [SingBoxPlatform] that uses method and event
/// channels, following `doc/platform_channel.md`.
///
/// Native [PlatformException]s are converted into [SingBoxException]s.
/// Each event channel is backed by a single cached broadcast stream, so any
/// number of Dart listeners share one native subscription.
class MethodChannelSingBox extends SingBoxPlatform {
  /// Creates the method channel implementation.
  MethodChannelSingBox();

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('sing_box');

  /// Event channel for tunnel state updates.
  @visibleForTesting
  final statusEventChannel = const EventChannel('sing_box/status');

  /// Event channel for traffic statistics.
  @visibleForTesting
  final statsEventChannel = const EventChannel('sing_box/stats');

  /// Event channel for log events.
  @visibleForTesting
  final logsEventChannel = const EventChannel('sing_box/logs');

  /// Event channel for outbound groups.
  @visibleForTesting
  final groupsEventChannel = const EventChannel('sing_box/groups');

  /// Event channel for all outbounds.
  @visibleForTesting
  final outboundsEventChannel = const EventChannel('sing_box/outbounds');

  /// Event channel for clash mode updates.
  @visibleForTesting
  final clashModeEventChannel = const EventChannel('sing_box/clash_mode');

  /// Event channel for connection snapshots.
  @visibleForTesting
  final connectionsEventChannel = const EventChannel('sing_box/connections');

  /// Event channel for core notifications.
  @visibleForTesting
  final notificationsEventChannel = const EventChannel(
    'sing_box/notifications',
  );

  /// Event channel for network quality tests.
  @visibleForTesting
  final networkQualityEventChannel = const EventChannel(
    'sing_box/network_quality',
  );

  /// Event channel for STUN tests.
  @visibleForTesting
  final stunEventChannel = const EventChannel('sing_box/stun');

  late final Stream<SingBoxConnectionState> _state = _events(
    statusEventChannel,
    (event) => SingBoxConnectionState.fromMap(event as Map),
  );

  late final Stream<SingBoxConnectionStats> _stats = _events(
    statsEventChannel,
    (event) => SingBoxConnectionStats.fromMap(event as Map),
  );

  late final Stream<SingBoxLogEvent> _logs =
      _events(
        logsEventChannel,
        (event) => SingBoxLogEvent.fromMap(event as Map),
      ).where((event) => event != null).cast<SingBoxLogEvent>();

  late final Stream<List<SingBoxOutboundGroup>> _groups = _events(
    groupsEventChannel,
    (event) => _list(event, SingBoxOutboundGroup.fromMap),
  );

  late final Stream<List<SingBoxOutboundItem>> _outbounds = _events(
    outboundsEventChannel,
    (event) => _list(event, SingBoxOutboundItem.fromMap),
  );

  late final Stream<SingBoxClashMode> _clashMode = _events(
    clashModeEventChannel,
    (event) => SingBoxClashMode.fromMap(event as Map),
  );

  late final Stream<List<SingBoxConnection>> _connections = _events(
    connectionsEventChannel,
    (event) => _list(event, SingBoxConnection.fromMap),
  );

  late final Stream<SingBoxNotification> _notifications = _events(
    notificationsEventChannel,
    (event) => SingBoxNotification.fromMap(event as Map),
  );

  static List<T> _list<T>(
    Object? event,
    T Function(Map<dynamic, dynamic>) parse,
  ) {
    if (event is! List) return const [];
    return event
        .whereType<Map<dynamic, dynamic>>()
        .map(parse)
        .toList(growable: false);
  }

  static Stream<T> _events<T>(
    EventChannel channel,
    T Function(Object? event) parse, [
    Object? arguments,
  ]) {
    return channel
        .receiveBroadcastStream(arguments)
        .map(parse)
        .transform(_convertErrors<T>());
  }

  static StreamTransformer<T, T> _convertErrors<T>() {
    return StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stackTrace, sink) {
        sink.addError(
          error is PlatformException
              ? SingBoxException.fromPlatformException(error)
              : error,
          stackTrace,
        );
      },
    );
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw SingBoxException.fromPlatformException(e);
    } on MissingPluginException {
      throw SingBoxUnsupportedException(
        'sing_box has no implementation of "$method" on this platform.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle and information
  // ---------------------------------------------------------------------------

  @override
  Future<SingBoxRuntimeInfo> initialize(SingBoxOptions options) async {
    final result = await _invoke<Map<dynamic, dynamic>>(
      'initialize',
      options.toMap(),
    );
    return SingBoxRuntimeInfo.fromMap(result ?? const {});
  }

  @override
  Future<String?> getPlatformVersion() => _invoke<String>('getPlatformVersion');

  @override
  Future<String> getSingBoxVersion() async =>
      await _invoke<String>('getSingBoxVersion') ?? '';

  @override
  Future<void> checkConfig(String config) =>
      _invoke<void>('checkConfig', {'config': config});

  @override
  Future<String> formatConfig(String config) async =>
      await _invoke<String>('formatConfig', {'config': config}) ?? config;

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  @override
  Future<bool> hasVpnPermission() async =>
      await _invoke<bool>('hasVpnPermission') ?? false;

  @override
  Future<bool> requestVpnPermission() async =>
      await _invoke<bool>('requestVpnPermission') ?? false;

  @override
  Future<bool> hasNotificationPermission() async =>
      await _invoke<bool>('hasNotificationPermission') ?? false;

  @override
  Future<bool> requestNotificationPermission() async =>
      await _invoke<bool>('requestNotificationPermission') ?? false;

  @override
  Future<void> openVpnSettings() => _invoke<void>('openVpnSettings');

  @override
  Future<SingBoxQuickTileResult> requestAddQuickSettingsTile({
    String? label,
  }) async => SingBoxQuickTileResult.fromString(
    await _invoke<String>('requestAddQuickSettingsTile', {'label': label}),
  );

  // ---------------------------------------------------------------------------
  // Service control
  // ---------------------------------------------------------------------------

  @override
  Future<void> start(String config, {bool disableMemoryLimit = false}) =>
      _invoke<void>('start', {
        'config': config,
        'disableMemoryLimit': disableMemoryLimit,
      });

  @override
  Future<void> stop() => _invoke<void>('stop');

  @override
  Future<void> reload([String? config]) =>
      _invoke<void>('reload', {'config': config});

  @override
  Future<SingBoxConnectionStatus> getStatus() async =>
      SingBoxConnectionStatus.fromString(await _invoke<String>('getStatus'));

  @override
  Future<DateTime?> getStartedAt() async {
    final value = await _invoke<int>('getStartedAt');
    return value == null || value <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value);
  }

  @override
  Future<String?> getLastConfig() => _invoke<String>('getLastConfig');

  @override
  Future<void> setServiceOptions(SingBoxServiceOptions options) =>
      _invoke<void>('setServiceOptions', options.toMap());

  // ---------------------------------------------------------------------------
  // Command client operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) =>
      _invoke<void>('selectOutbound', {
        'groupTag': groupTag,
        'outboundTag': outboundTag,
      });

  @override
  Future<void> urlTest(String tag) => _invoke<void>('urlTest', {'tag': tag});

  @override
  Future<void> startProbe(String config) =>
      _invoke<void>('startProbe', {'config': config});

  @override
  Future<void> stopProbe() => _invoke<void>('stopProbe');

  @override
  Future<SingBoxNativePingResult> pingServer({
    required String method,
    required String host,
    int? port,
    required Duration timeout,
  }) async {
    final result = await _invoke<Map<dynamic, dynamic>>('pingServer', {
      'method': method,
      'host': host,
      'port': port,
      'timeoutMs': timeout.inMilliseconds,
    });
    return result == null
        ? const SingBoxNativePingResult(success: false, error: 'No result')
        : SingBoxNativePingResult.fromMap(result);
  }

  @override
  Future<void> setClashMode(String mode) =>
      _invoke<void>('setClashMode', {'mode': mode});

  @override
  Future<void> closeConnection(String id) =>
      _invoke<void>('closeConnection', {'id': id});

  @override
  Future<void> closeAllConnections() => _invoke<void>('closeAllConnections');

  @override
  Future<void> clearLogs() => _invoke<void>('clearLogs');

  @override
  Future<void> setGroupExpand(String groupTag, bool expand) =>
      _invoke<void>('setGroupExpand', {'groupTag': groupTag, 'expand': expand});

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  @override
  Future<String?> storageRead(String key) =>
      _invoke<String>('storageRead', {'key': key});

  @override
  Future<void> storageWrite(String key, String? value) =>
      _invoke<void>('storageWrite', {'key': key, 'value': value});

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  @override
  Stream<SingBoxConnectionState> watchState() => _state;

  @override
  Stream<SingBoxConnectionStats> watchStats() => _stats;

  @override
  Stream<SingBoxLogEvent> watchLogEvents() => _logs;

  @override
  Stream<List<SingBoxOutboundGroup>> watchGroups() => _groups;

  @override
  Stream<List<SingBoxOutboundItem>> watchOutbounds() => _outbounds;

  @override
  Stream<SingBoxClashMode> watchClashMode() => _clashMode;

  @override
  Stream<List<SingBoxConnection>> watchConnections() => _connections;

  @override
  Stream<SingBoxNotification> watchNotifications() => _notifications;

  @override
  Stream<SingBoxNetworkQuality> runNetworkQualityTest({
    String? configUrl,
    String? outboundTag,
    bool serial = false,
    Duration? maxRuntime,
    bool http3 = false,
  }) {
    return _events(
      networkQualityEventChannel,
      (event) => SingBoxNetworkQuality.fromMap(event as Map),
      {
        'configUrl': configUrl,
        'outboundTag': outboundTag,
        'serial': serial,
        'maxRuntimeSeconds': maxRuntime?.inSeconds,
        'http3': http3,
      },
    );
  }

  @override
  Stream<SingBoxStunResult> runStunTest({String? server, String? outboundTag}) {
    return _events(
      stunEventChannel,
      (event) => SingBoxStunResult.fromMap(event as Map),
      {'server': server, 'outboundTag': outboundTag},
    );
  }
}
