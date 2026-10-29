import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// Reported by [initialize]; enables the plugin's rule-set downloads.
  String? workingDirectory;
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

  /// The status the fake tunnel is in (updated by [emitState]).
  SingBoxConnectionStatus status = SingBoxConnectionStatus.disconnected;

  /// Whether [start] drives the fake tunnel to `connected`.
  bool connectOnStart = true;

  /// When set, a started tunnel stops with this error instead of connecting.
  String? runtimeError;

  /// When set, [start] reports [runtimeError] before it returns.
  bool failBeforeStartReturns = false;

  void emitState(
    SingBoxConnectionStatus status, {
    DateTime? startedAt,
    String? error,
  }) {
    this.status = status;
    state.add(
      SingBoxConnectionState(
        status: status,
        startedAt: startedAt,
        error: error,
      ),
    );
  }

  @override
  Future<SingBoxRuntimeInfo> initialize(SingBoxOptions options) async {
    calls.add('initialize');
    initOptions = options;
    return SingBoxRuntimeInfo(
      singBoxVersion: '1.14.4',
      status: initialStatus,
      workingDirectory: workingDirectory,
    );
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

  /// Behaves like the native side: `connecting` is reported before the call
  /// returns, the outcome (`connected` or `disconnected` with
  /// [runtimeError]) afterwards. A connected tunnel is reloaded.
  @override
  Future<void> start(String config, {bool disableMemoryLimit = false}) async {
    calls.add('start');
    if (configError != null) throw SingBoxConfigException(configError!);
    lastConfig = config;
    started.add(config);
    if (serveProbeRoutes) {
      final targets = SingBoxConfigBuilder.probeTargets(
        jsonDecode(config) as Map,
      );
      for (final MapEntry(key: tag, value: target) in targets.entries) {
        _routeServers.add(await _serve(target.port, tag));
      }
    }
    if (status == SingBoxConnectionStatus.connected) return;
    if (failBeforeStartReturns && runtimeError != null) {
      emitState(SingBoxConnectionStatus.disconnected, error: runtimeError);
      return;
    }
    emitState(SingBoxConnectionStatus.connecting);
    if (!connectOnStart) return;
    scheduleMicrotask(() {
      if (status != SingBoxConnectionStatus.connecting) return;
      if (runtimeError != null) {
        emitState(SingBoxConnectionStatus.disconnected, error: runtimeError);
      } else {
        emitState(SingBoxConnectionStatus.connected, startedAt: DateTime.now());
      }
    });
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (status == SingBoxConnectionStatus.disconnected) return;
    emitState(SingBoxConnectionStatus.disconnecting);
    scheduleMicrotask(() => emitState(SingBoxConnectionStatus.disconnected));
  }

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

  /// Configs passed to [startProbe].
  final probeConfigs = <String>[];

  /// Outbound tags whose probes fail (the fake closes the connection).
  Set<String> failingProbes = {};

  /// Error thrown by [startProbe].
  String? probeStartError;

  /// Whether [start] also serves the probe routes of the started config on
  /// their (loopback) probe address, as the tunnel would.
  bool serveProbeRoutes = false;

  final _probeServers = <ServerSocket>[];
  final _routeServers = <ServerSocket>[];

  /// Answers HTTP requests with `204` for [tag] (or closes the connection
  /// when it is in [failingProbes]).
  Future<ServerSocket> _serve(int port, String tag) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    server.listen((socket) {
      if (failingProbes.contains(tag)) {
        socket.destroy();
        return;
      }
      final request = <int>[];
      socket.listen((data) {
        request.addAll(data);
        if (String.fromCharCodes(request).contains('\r\n\r\n')) {
          socket.add('HTTP/1.1 204 No Content\r\n\r\n'.codeUnits);
          socket.destroy();
        }
      }, onError: (_) {});
    });
    return server;
  }

  @override
  Future<void> startProbe(String config) async {
    calls.add('startProbe');
    if (probeStartError != null) throw SingBoxStartException(probeStartError!);
    await stopProbe();
    calls.removeLast();
    probeConfigs.add(config);
    final decoded = jsonDecode(config) as Map<String, dynamic>;
    final outboundOf = {
      for (final rule
          in (decoded['route']['rules'] as List).cast<Map<String, dynamic>>())
        (rule['inbound'] as List).single: rule['outbound'] as String,
    };
    for (final inbound
        in (decoded['inbounds'] as List).cast<Map<String, dynamic>>()) {
      _probeServers.add(
        await _serve(
          inbound['listen_port'] as int,
          outboundOf[inbound['tag']]!,
        ),
      );
    }
  }

  @override
  Future<void> stopProbe() async {
    calls.add('stopProbe');
    final servers = [..._probeServers];
    _probeServers.clear();
    for (final server in servers) {
      await server.close();
    }
  }

  /// Answers [pingServer]; succeeds with 42 ms by default.
  SingBoxNativePingResult Function(String method, String host, int? port)?
  onPingServer;

  @override
  Future<SingBoxNativePingResult> pingServer({
    required String method,
    required String host,
    int? port,
    required Duration timeout,
  }) async {
    calls.add('pingServer:$method:$host:${port ?? ''}');
    return onPingServer?.call(method, host, port) ??
        const SingBoxNativePingResult(success: true, ping: 42);
  }

  /// Closes the sockets opened for probes.
  Future<void> closeProbes() async {
    await stopProbe();
    final servers = [..._routeServers];
    _routeServers.clear();
    for (final server in servers) {
      await server.close();
    }
  }

  @override
  Future<void> setClashMode(String mode) async =>
      calls.add('setClashMode:$mode');

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
