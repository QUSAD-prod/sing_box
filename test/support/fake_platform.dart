import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';

/// In-memory [SingBoxPlatform] used by the unit tests.
class FakeSingBoxPlatform extends SingBoxPlatform
    with MockPlatformInterfaceMixin {
  final calls = <String>[];
  final storage = <String, String>{};
  bool vpnPermission = true;
  bool grantOnRequest = true;
  bool notificationPermission = true;
  String? configError;
  String? lastConfig;
  SingBoxServiceOptions? serviceOptions;
  SingBoxOptions? initOptions;
  SingBoxConnectionStatus initialStatus = SingBoxConnectionStatus.disconnected;
  final List<String> started = [];
  final List<String?> reloaded = [];

  final state = StreamController<SingBoxConnectionState>.broadcast();
  final stats = StreamController<SingBoxConnectionStats>.broadcast();
  final logs = StreamController<SingBoxLogEvent>.broadcast();
  final groups = StreamController<List<SingBoxOutboundGroup>>.broadcast();
  final outbounds = StreamController<List<SingBoxOutboundItem>>.broadcast();
  final clashMode = StreamController<SingBoxClashMode>.broadcast();
  final connections = StreamController<List<SingBoxConnection>>.broadcast();
  final notifications = StreamController<SingBoxNotification>.broadcast();

  /// Events replayed by [runNetworkQualityTest].
  List<SingBoxNetworkQuality> networkQualityEvents = const [];

  /// Called when `urlTest` is invoked, to simulate results.
  void Function(String tag)? onUrlTest;

  /// Groups returned by the first event of [watchGroups].
  List<SingBoxOutboundGroup> currentGroups = const [];

  void emitState(SingBoxConnectionStatus status, {DateTime? startedAt}) {
    state.add(SingBoxConnectionState(status: status, startedAt: startedAt));
  }

  @override
  Future<SingBoxRuntimeInfo> initialize(SingBoxOptions options) async {
    calls.add('initialize');
    initOptions = options;
    return SingBoxRuntimeInfo(singBoxVersion: '1.14.4', status: initialStatus);
  }

  @override
  Future<String?> getPlatformVersion() async => 'Fake 1.0';

  @override
  Future<String> getSingBoxVersion() async => '1.14.4';

  @override
  Future<void> checkConfig(String config) async {
    calls.add('checkConfig');
    if (configError != null) throw SingBoxConfigException(configError!);
  }

  @override
  Future<String> formatConfig(String config) async => config;

  @override
  Future<bool> hasVpnPermission() async => vpnPermission;

  @override
  Future<bool> requestVpnPermission() async {
    calls.add('requestVpnPermission');
    if (grantOnRequest) vpnPermission = true;
    return vpnPermission;
  }

  @override
  Future<bool> hasNotificationPermission() async => notificationPermission;

  @override
  Future<bool> requestNotificationPermission() async => notificationPermission;

  @override
  Future<void> openVpnSettings() async => calls.add('openVpnSettings');

  @override
  Future<SingBoxQuickTileResult> requestAddQuickSettingsTile({
    String? label,
  }) async => SingBoxQuickTileResult.added;

  @override
  Future<void> start(String config, {bool disableMemoryLimit = false}) async {
    calls.add('start');
    if (configError != null) throw SingBoxConfigException(configError!);
    lastConfig = config;
    started.add(config);
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> reload([String? config]) async {
    calls.add('reload');
    if (config != null) lastConfig = config;
    reloaded.add(config);
  }

  @override
  Future<SingBoxConnectionStatus> getStatus() async => initialStatus;

  @override
  Future<DateTime?> getStartedAt() async => null;

  @override
  Future<String?> getLastConfig() async => lastConfig;

  @override
  Future<void> setServiceOptions(SingBoxServiceOptions options) async {
    calls.add('setServiceOptions');
    serviceOptions = options;
  }

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async =>
      calls.add('selectOutbound:$groupTag:$outboundTag');

  @override
  Future<void> urlTest(String tag) async {
    calls.add('urlTest:$tag');
    onUrlTest?.call(tag);
  }

  @override
  Future<void> setClashMode(String mode) async => calls.add('setClashMode:$mode');

  @override
  Future<void> closeConnection(String id) async =>
      calls.add('closeConnection:$id');

  @override
  Future<void> closeAllConnections() async => calls.add('closeAllConnections');

  @override
  Future<void> clearLogs() async => calls.add('clearLogs');

  @override
  Future<void> setGroupExpand(String groupTag, bool expand) async =>
      calls.add('setGroupExpand:$groupTag:$expand');

  @override
  Future<String?> storageRead(String key) async => storage[key];

  @override
  Future<void> storageWrite(String key, String? value) async {
    if (value == null) {
      storage.remove(key);
    } else {
      storage[key] = value;
    }
  }

  @override
  Stream<SingBoxConnectionState> watchState() => state.stream;

  @override
  Stream<SingBoxConnectionStats> watchStats() => stats.stream;

  @override
  Stream<SingBoxLogEvent> watchLogEvents() => logs.stream;

  @override
  Stream<List<SingBoxOutboundGroup>> watchGroups() async* {
    yield currentGroups;
    yield* groups.stream;
  }

  @override
  Stream<List<SingBoxOutboundItem>> watchOutbounds() => outbounds.stream;

  @override
  Stream<SingBoxClashMode> watchClashMode() => clashMode.stream;

  @override
  Stream<List<SingBoxConnection>> watchConnections() => connections.stream;

  @override
  Stream<SingBoxNotification> watchNotifications() => notifications.stream;

  @override
  Stream<SingBoxNetworkQuality> runNetworkQualityTest({
    String? configUrl,
    String? outboundTag,
    bool serial = false,
    Duration? maxRuntime,
    bool http3 = false,
  }) => Stream.fromIterable(networkQualityEvents);

  @override
  Stream<SingBoxStunResult> runStunTest({
    String? server,
    String? outboundTag,
  }) => Stream.fromIterable(const [
    SingBoxStunResult(externalAddress: '1.2.3.4:5678', isFinal: true),
  ]);
}
