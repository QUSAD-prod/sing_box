import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';

import 'support/fake_platform.dart';

const _ssOutbound = {
  'type': 'shadowsocks',
  'tag': 'my-ss',
  'server': '203.0.113.10',
  'server_port': 8388,
  'method': 'aes-128-gcm',
  'password': 'secret',
};

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

List<Map<String, dynamic>> _outboundsOf(String json) =>
    (_decode(json)['outbounds'] as List).cast<Map<String, dynamic>>();

void main() {
  late FakeSingBoxPlatform platform;
  final singBox = SingBox.instance;

  setUp(() async {
    await singBox.debugReset();
    platform = FakeSingBoxPlatform();
    SingBoxPlatform.instance = platform;
  });

  group('initialize', () {
    test('initializes once and exposes runtime info', () async {
      await singBox.initialize();
      await singBox.initialize();
      expect(platform.calls.where((c) => c == 'initialize'), hasLength(1));
      expect(singBox.isInitialized, isTrue);
      expect(singBox.runtimeInfo?.singBoxVersion, '1.14.4');
      expect(await singBox.getSingBoxVersion(), '1.14.4');
    });

    test('applies stored service options', () async {
      await singBox.saveSettings(
        const SingBoxSettings(
          killSwitch: true,
          autoReconnectOnDisconnect: true,
        ),
      );
      await singBox.initialize();
      expect(platform.serviceOptions?.includeAllNetworks, isTrue);
      expect(platform.serviceOptions?.onDemand, isTrue);
    });

    test('methods throw before initialization', () {
      expect(
        () => singBox.connect(jsonEncode(_ssOutbound)),
        throwsA(isA<SingBoxNotInitializedException>()),
      );
      expect(
        () => singBox.watchConnectionStatus().first,
        throwsA(isA<SingBoxNotInitializedException>()),
      );
    });

    test('auto-connects to the active server when enabled', () async {
      final server = SingBoxServerConfig.fromOutbound(
        Map<String, dynamic>.from(_ssOutbound),
      );
      await singBox.addServerConfig(server);
      await singBox.setActiveServerConfig(server.id);
      await singBox.saveSettings(
        const SingBoxSettings(autoConnectOnStart: true),
      );
      await singBox.initialize();
      await pumpEventQueue();
      expect(platform.started, hasLength(1));
    });
  });

  group('connect', () {
    setUp(singBox.initialize);

    test('wraps a single outbound into a complete config', () async {
      await singBox.connect(jsonEncode(_ssOutbound));
      final config = _decode(platform.started.single);
      expect(
        (config['inbounds'] as List).any((i) => (i as Map)['type'] == 'tun'),
        isTrue,
      );
      final tags = _outboundsOf(platform.started.single).map((o) => o['tag']);
      expect(tags, containsAll([SingBoxConfigBuilder.proxyTag, 'my-ss']));
    });

    test('parses share links', () async {
      await singBox.connect(
        'ss://YWVzLTEyOC1nY206c2VjcmV0@203.0.113.10:8388#Test',
      );
      final types = _outboundsOf(platform.started.single).map((o) => o['type']);
      expect(types, contains('shadowsocks'));
    });

    test('applies routing rules to a complete config', () async {
      await singBox.addDomainToBypass('example.org');
      final full = {
        'inbounds': [
          {
            'type': 'tun',
            'tag': 'tun-in',
            'address': ['172.19.0.1/30'],
          },
        ],
        'outbounds': [
          _ssOutbound,
          {'type': 'direct', 'tag': 'direct'},
        ],
        'route': {'final': 'my-ss'},
      };
      await singBox.connect(jsonEncode(full));
      expect(platform.started.single, contains('example.org'));
    });

    test('keeps a complete config unchanged with applyRules: false', () async {
      await singBox.addDomainToBypass('example.org');
      final full = jsonEncode({
        'outbounds': [_ssOutbound],
      });
      await singBox.connect(full, applyRules: false);
      expect(_decode(platform.started.single), _decode(full));
    });

    test('requests the VPN permission when missing', () async {
      platform.vpnPermission = false;
      await singBox.connect(jsonEncode(_ssOutbound));
      expect(platform.calls, contains('requestVpnPermission'));
      expect(platform.started, hasLength(1));
    });

    test('throws when the permission is denied', () async {
      platform
        ..vpnPermission = false
        ..grantOnRequest = false;
      await expectLater(
        singBox.connect(jsonEncode(_ssOutbound)),
        throwsA(isA<SingBoxPermissionException>()),
      );
      expect(platform.started, isEmpty);
    });

    test('rejects garbage input', () async {
      await expectLater(
        singBox.connect('definitely not a config'),
        throwsA(isA<SingBoxConfigException>()),
      );
      await expectLater(
        singBox.connect('{"oops":'),
        throwsA(isA<SingBoxConfigException>()),
      );
    });

    test('propagates sing-box config errors', () async {
      platform.configError = 'decode config: unknown field';
      await expectLater(
        singBox.connect(jsonEncode(_ssOutbound)),
        throwsA(
          isA<SingBoxConfigException>().having(
            (e) => e.message,
            'message',
            contains('unknown field'),
          ),
        ),
      );
    });

    test('combines several servers into one selector', () async {
      final a = SingBoxServerConfig.fromOutbound(
        Map<String, dynamic>.from(_ssOutbound),
        id: 'a',
        name: 'Server A',
      );
      final b = a.copyWith(id: 'b', name: 'Server B');
      final c = a.copyWith(id: 'c', name: 'Server C', enabled: false);
      for (final s in [a, b, c]) {
        await singBox.addServerConfig(s);
      }
      await singBox.connectToServers([a, b, c], selectedId: 'b');
      final outbounds = _outboundsOf(platform.started.single);
      final selector = outbounds.firstWhere(
        (o) => o['tag'] == SingBoxConfigBuilder.proxyTag,
      );
      expect(selector['default'], 'Server B');
      final tags = outbounds.map((o) => o['tag']);
      expect(tags, containsAll(['Server A', 'Server B']));
      expect(tags, isNot(contains('Server C')));
      expect((await singBox.getActiveServerConfig())?.id, 'b');
    });

    test('switchServer reloads a running tunnel in place', () async {
      platform.emitState(SingBoxConnectionStatus.connected);
      await pumpEventQueue();
      await singBox.switchServer(jsonEncode(_ssOutbound));
      expect(platform.started, isEmpty);
      expect(platform.reloaded.single, isNotNull);
    });

    test('rules changes reload a running tunnel', () async {
      await singBox.connect(jsonEncode(_ssOutbound));
      platform.emitState(SingBoxConnectionStatus.connected);
      await pumpEventQueue();
      expect(await singBox.addBlockedDomain('ads.example.com'), isTrue);
      expect(platform.reloaded.single, contains('ads.example.com'));
    });
  });

  group('connect result', () {
    setUp(singBox.initialize);
    final outbound = jsonEncode(_ssOutbound);

    test('completes once the tunnel is connected', () async {
      await singBox.connect(outbound);
      expect(singBox.isConnected, isTrue);
      expect(singBox.state.startedAt, isNotNull);
    });

    test('throws the core error when the tunnel stops instead', () async {
      platform.runtimeError = 'start service: initialize outbound[2]: boom';
      await expectLater(
        singBox.connect(outbound),
        throwsA(
          isA<SingBoxStartException>()
              .having((e) => e.code, 'code', SingBoxErrorCode.startFailed)
              .having((e) => e.message, 'message', platform.runtimeError),
        ),
      );
      expect(singBox.status, SingBoxConnectionStatus.disconnected);
    });

    test('reports an error emitted before start returned', () async {
      platform
        ..runtimeError = 'open tun: permission revoked'
        ..failBeforeStartReturns = true;
      await expectLater(
        singBox.connect(outbound),
        throwsA(
          isA<SingBoxStartException>().having(
            (e) => e.message,
            'message',
            'open tun: permission revoked',
          ),
        ),
      );
    });

    test('times out when the tunnel keeps connecting', () async {
      platform.connectOnStart = false;
      await expectLater(
        singBox.connect(outbound, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<SingBoxTimeoutException>()),
      );
      expect(singBox.status, SingBoxConnectionStatus.connecting);
    });

    test('can return as soon as the start was requested', () async {
      platform.connectOnStart = false;
      await singBox.connect(outbound, waitUntilConnected: false);
      expect(platform.started, hasLength(1));
      expect(singBox.isConnected, isFalse);
    });

    test('reloads a connected tunnel without waiting', () async {
      await singBox.connect(outbound);
      platform.connectOnStart = false;
      await singBox.connect(outbound, timeout: const Duration(seconds: 1));
      expect(platform.started, hasLength(2));
      expect(singBox.isConnected, isTrue);
    });

    test('disconnect cancels a pending connect and runs after it', () async {
      platform.connectOnStart = false;
      final pending = singBox.connect(outbound);
      final cancelled = expectLater(
        pending,
        throwsA(isA<SingBoxCancelledException>()),
      );
      await pumpEventQueue();
      await singBox.disconnect();
      await cancelled;
      await pumpEventQueue();
      expect(platform.calls.where((c) => c == 'start' || c == 'stop'), [
        'start',
        'stop',
      ]);
      expect(singBox.status, SingBoxConnectionStatus.disconnected);
    });

    test('rapid toggles end in the state of the last request', () async {
      final first = singBox.connect(outbound);
      final firstResult = expectLater(
        first,
        throwsA(isA<SingBoxCancelledException>()),
      );
      final stop = singBox.disconnect();
      final second = singBox.connect(outbound);
      await firstResult;
      await stop;
      await second;
      expect(singBox.isConnected, isTrue);
      // The first connect was superseded before it reached the platform.
      expect(platform.calls.where((c) => c == 'start' || c == 'stop'), [
        'stop',
        'start',
      ]);
    });

    test('a newer connect supersedes a pending one', () async {
      platform.connectOnStart = false;
      final first = singBox.connect(outbound);
      final firstResult = expectLater(
        first,
        throwsA(isA<SingBoxCancelledException>()),
      );
      await pumpEventQueue();
      platform.connectOnStart = true;
      final second = singBox.connect(outbound);
      await firstResult;
      // The fake reloads a connecting tunnel; let it connect.
      platform.emitState(
        SingBoxConnectionStatus.connected,
        startedAt: DateTime.now(),
      );
      await second;
      expect(singBox.isConnected, isTrue);
    });

    test('waits for the previous session to stop first', () async {
      await singBox.connect(outbound);
      platform.emitState(SingBoxConnectionStatus.disconnecting);
      await pumpEventQueue();
      final pending = singBox.connect(outbound);
      await pumpEventQueue();
      expect(platform.started, hasLength(1));
      // The previous session's final event must not fail the new start.
      platform.emitState(SingBoxConnectionStatus.disconnected);
      await pending;
      expect(platform.started, hasLength(2));
      expect(singBox.isConnected, isTrue);
    });

    test('connectToServer marks the profile active once requested', () async {
      final server = SingBoxServerConfig.fromOutbound(
        Map<String, dynamic>.from(_ssOutbound),
        id: 'srv',
        name: 'Server',
      );
      await singBox.addServerConfig(server);
      platform.runtimeError = 'boom';
      await expectLater(
        singBox.connectToServer(server),
        throwsA(isA<SingBoxStartException>()),
      );
      expect((await singBox.getActiveServerConfig())?.id, 'srv');
      platform.configError = 'bad';
      await singBox.setActiveServerConfig(null);
      await expectLater(
        singBox.connectToServer(server),
        throwsA(isA<SingBoxConfigException>()),
      );
      expect(await singBox.getActiveServerConfig(), isNull);
    });

    test('restart stops, waits and connects again', () async {
      await singBox.connect(outbound);
      await singBox.restart();
      expect(platform.calls.where((c) => c == 'start' || c == 'stop'), [
        'start',
        'stop',
        'start',
      ]);
      expect(singBox.isConnected, isTrue);
    });
  });

  group('status and statistics', () {
    setUp(singBox.initialize);

    test(
      'status stream starts with the current value and is distinct',
      () async {
        final events = <SingBoxConnectionStatus>[];
        final sub = singBox.watchConnectionStatus().listen(events.add);
        await pumpEventQueue();
        platform
          ..emitState(SingBoxConnectionStatus.connecting)
          ..emitState(SingBoxConnectionStatus.connecting)
          ..emitState(SingBoxConnectionStatus.connected);
        await pumpEventQueue();
        await sub.cancel();
        expect(events, [
          SingBoxConnectionStatus.disconnected,
          SingBoxConnectionStatus.connecting,
          SingBoxConnectionStatus.connected,
        ]);
        expect(singBox.status, SingBoxConnectionStatus.connected);
      },
    );

    test('statistics carry the session duration', () async {
      platform.emitState(
        SingBoxConnectionStatus.connected,
        startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      await pumpEventQueue();
      final next = singBox.watchConnectionStats().first;
      platform.stats.add(const SingBoxConnectionStats(downloadSpeed: 42));
      final stats = await next;
      expect(stats.downloadSpeed, 42);
      expect(stats.duration.inMinutes, 2);
    });

    test('getConnectionStats is empty while disconnected', () async {
      expect(await singBox.getConnectionStats(), SingBoxConnectionStats.empty);
    });

    test('log buffer handles batches, resets and clears', () async {
      final buffers = <List<SingBoxLogEntry>>[];
      final sub = singBox.watchLogBuffer(maxEntries: 2).listen(buffers.add);
      SingBoxLogEntry entry(String m) => SingBoxLogEntry(
        level: SingBoxLogLevel.info,
        message: m,
        receivedAt: DateTime(2026),
      );
      platform.logs
        ..add(SingBoxLogBatch([entry('a'), entry('b'), entry('c')]))
        ..add(SingBoxLogBatch([entry('d')], reset: true))
        ..add(const SingBoxLogCleared());
      await pumpEventQueue();
      await sub.cancel();
      expect(buffers.map((b) => b.map((e) => e.message).toList()), [
        ['b', 'c'],
        ['d'],
        <String>[],
      ]);
    });
  });

  group('pingServers', () {
    setUp(singBox.initialize);

    SingBoxServerConfig profile(
      String id,
      String type,
      String server,
      int port, [
      Map<String, dynamic> extra = const {},
    ]) => SingBoxServerConfig.fromOutbound({
      'type': type,
      'tag': id,
      'server': server,
      'server_port': port,
      ...extra,
    }, id: id);

    test('measures TCP latency while disconnected', () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(listener.close);
      listener.listen((socket) => socket.destroy());
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = closed.port;
      await closed.close();

      final results = await singBox.pingServers([
        profile('open', 'vless', '127.0.0.1', listener.port),
        profile('closed', 'trojan', '127.0.0.1', closedPort),
        profile('udp', 'hysteria2', '127.0.0.1', listener.port),
        profile('quic', 'vless', '127.0.0.1', listener.port, {
          'transport': {'type': 'quic'},
        }),
        profile('empty', 'vless', '', 0),
      ], concurrency: 2).toList();

      final byId = {for (final r in results) r.serverId!: r};
      expect(
        byId.keys,
        unorderedEquals(['open', 'closed', 'udp', 'quic', 'empty']),
      );
      expect(byId['open']!.success, isTrue);
      expect(byId['open']!.method, SingBoxPingMethod.tcp);
      expect(byId['open']!.address, '127.0.0.1');
      expect(byId['closed']!.success, isFalse);
      expect(byId['udp']!.errorMessage, contains('UDP'));
      expect(byId['quic']!.errorMessage, contains('UDP'));
      expect(byId['empty']!.errorMessage, 'The server has no address');
    });

    test('uses URL tests for servers of the running config', () async {
      platform.lastConfig = jsonEncode({
        'outbounds': [_ssOutbound],
      });
      platform.emitState(SingBoxConnectionStatus.connected);
      await pumpEventQueue();
      platform.onUrlTest = (tag) {
        Timer.run(() {
          platform.outbounds.add([
            SingBoxOutboundItem(
              tag: tag,
              type: 'shadowsocks',
              urlTestTime: DateTime.now(),
              urlTestDelay: 42,
            ),
          ]);
        });
      };
      final results = await singBox.pingServers([
        SingBoxServerConfig.fromOutbound(
          Map<String, dynamic>.from(_ssOutbound),
          id: 'running',
        ),
        profile('other', 'vless', 'other.example.com', 443),
      ]).toList();
      final byId = {for (final r in results) r.serverId!: r};
      expect(byId['running']!.success, isTrue);
      expect(byId['running']!.ping, 42);
      expect(byId['running']!.tag, 'my-ss');
      expect(byId['running']!.method, SingBoxPingMethod.urlTest);
      expect(
        byId['other']!.errorMessage,
        'Not part of the running configuration',
      );
    });

    test('validates the concurrency', () {
      expect(
        () => singBox.pingServers(const [], concurrency: 0),
        throwsArgumentError,
      );
      expect(singBox.pingServers(const []).toList(), completion(isEmpty));
    });
  });

  group('latency and speed', () {
    setUp(() async {
      await singBox.initialize();
      platform.lastConfig = jsonEncode({
        'outbounds': [_ssOutbound],
      });
      platform.emitState(SingBoxConnectionStatus.connected);
      await pumpEventQueue();
    });

    test('pingOutbound waits for a fresh URL test result', () async {
      platform.onUrlTest = (tag) {
        Timer.run(() {
          platform.outbounds.add([
            SingBoxOutboundItem(
              tag: tag,
              type: 'shadowsocks',
              urlTestTime: DateTime.now(),
              urlTestDelay: 87,
            ),
          ]);
        });
      };
      final result = await singBox.pingOutbound('my-ss');
      expect(result.success, isTrue);
      expect(result.ping, 87);
      expect(result.address, '203.0.113.10');
    });

    test(
      'pingOutbound tests through the urltest group of the outbound',
      () async {
        platform.currentGroups = const [
          SingBoxOutboundGroup(
            tag: 'auto',
            type: 'urltest',
            selectable: false,
            selected: 'my-ss',
            items: [SingBoxOutboundItem(tag: 'my-ss', type: 'shadowsocks')],
          ),
        ];
        platform.onUrlTest = (tag) {
          Timer.run(() {
            platform.outbounds.add([
              SingBoxOutboundItem(
                tag: 'my-ss',
                type: 'shadowsocks',
                urlTestTime: DateTime.now(),
                urlTestDelay: 55,
              ),
            ]);
          });
        };
        final result = await singBox.pingOutbound('my-ss');
        expect(platform.calls, contains('urlTest:auto'));
        expect(result.ping, 55);
      },
    );

    test('pingCurrentServer follows nested groups', () async {
      platform.currentGroups = const [
        SingBoxOutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selectable: true,
          selected: 'auto',
          items: [],
        ),
        SingBoxOutboundGroup(
          tag: 'auto',
          type: 'urltest',
          selectable: false,
          selected: 'my-ss',
          items: [],
        ),
      ];
      expect(await singBox.currentOutboundTag(), 'my-ss');
    });

    test('pingOutbound reports failures', () async {
      platform.onUrlTest = (tag) => Timer.run(
        () => platform.outbounds.add([
          SingBoxOutboundItem(
            tag: tag,
            type: 'shadowsocks',
            urlTestTime: DateTime.now(),
          ),
        ]),
      );
      final result = await singBox.pingOutbound('my-ss');
      expect(result.success, isFalse);
    });

    test('testSpeed summarizes the final network quality result', () async {
      platform.networkQualityEvents = const [
        SingBoxNetworkQuality(
          phase: SingBoxNetworkQualityPhase.download,
          downloadCapacity: 1000000,
        ),
        SingBoxNetworkQuality(
          downloadCapacity: 80000000,
          uploadCapacity: 16000000,
          idleLatency: Duration(milliseconds: 30),
          isFinal: true,
        ),
      ];
      final result = await singBox.testSpeed();
      expect(result.success, isTrue);
      expect(result.downloadMbps, closeTo(80, 0.01));
      expect(result.uploadSpeed, 2000000);
      expect(result.latency, const Duration(milliseconds: 30));
    });

    test('testSpeed fails gracefully without a result', () async {
      platform.networkQualityEvents = const [];
      final result = await singBox.testSpeed();
      expect(result.success, isFalse);
    });
  });

  group('routing rules', () {
    setUp(singBox.initialize);

    test('bypass and block lists are validated and persisted', () async {
      expect(
        await singBox.addDomainToBypass('https://Example.COM/path'),
        isTrue,
      );
      expect(await singBox.addDomainToBypass('example.com'), isFalse);
      expect(await singBox.addDomainToBypass('not a domain'), isFalse);
      expect(await singBox.getBypassDomains(), ['example.com']);

      expect(await singBox.addSubnetToBypass('10.0.0.0/8'), isTrue);
      expect(await singBox.addSubnetToBypass('192.168.1.1'), isTrue);
      expect(await singBox.addSubnetToBypass('10.0.0.0/33'), isFalse);
      expect(await singBox.getBypassSubnets(), [
        '10.0.0.0/8',
        '192.168.1.1/32',
      ]);
      expect(await singBox.removeSubnetFromBypass('192.168.1.1'), isTrue);

      expect(await singBox.addAppToBypass('com.example.app'), isTrue);
      expect(await singBox.addAppToBypass('not a package'), isFalse);
      expect(await singBox.addBlockedApp('com.ads.app'), isTrue);
      expect(await singBox.getBlockedApps(), ['com.ads.app']);

      await singBox.setProxyApps(['org.telegram.messenger', 'bad name']);
      expect(await singBox.getProxyApps(), ['org.telegram.messenger']);

      final rules = await singBox.getRoutingRules();
      expect(rules.bypassApps, ['com.example.app']);
    });

    test('DNS servers are validated', () async {
      expect(await singBox.addDnsServer('1.1.1.1'), isTrue);
      expect(await singBox.addDnsServer('tls://dns.google'), isTrue);
      expect(
        await singBox.setDnsServers([
          '8.8.8.8',
          'https://dns.google/dns-query',
        ]),
        isTrue,
      );
      expect(await singBox.getDnsServers(), [
        '8.8.8.8',
        'https://dns.google/dns-query',
      ]);
      expect(await singBox.removeDnsServer('8.8.8.8'), isTrue);
    });
  });

  group('settings and server profiles', () {
    setUp(singBox.initialize);

    test('updateSetting validates keys and applies service options', () async {
      expect(
        await singBox.updateSetting(SingBoxSettings.keyStartOnBoot, true),
        isTrue,
      );
      expect((await singBox.getSettings()).startOnBoot, isTrue);
      expect(platform.serviceOptions?.startOnBoot, isTrue);
      expect(await singBox.updateSetting('unknown', true), isFalse);
      expect(
        await singBox.updateSetting(SingBoxSettings.keyKillSwitch, 'yes'),
        isFalse,
      );
    });

    test('server profile CRUD and active selection', () async {
      final server = SingBoxServerConfig.fromOutbound(
        Map<String, dynamic>.from(_ssOutbound),
      );
      expect(server.protocol, 'shadowsocks');
      expect(server.port, 8388);
      expect(await singBox.addServerConfig(server), isTrue);
      expect(await singBox.addServerConfig(server), isFalse);
      expect(await singBox.setActiveServerConfig(server.id), isTrue);
      expect(await singBox.setActiveServerConfig('missing'), isFalse);
      expect(
        await singBox.updateServerConfig(server.copyWith(name: 'Renamed')),
        isTrue,
      );
      expect((await singBox.getActiveServerConfig())?.name, 'Renamed');
      expect(await singBox.removeServerConfig(server.id), isTrue);
      expect(await singBox.getActiveServerConfig(), isNull);
      expect(await singBox.getServerConfigs(), isEmpty);
    });

    test('imports share links as profiles with unique ids', () async {
      const link = 'ss://YWVzLTEyOC1nY206c2VjcmV0@203.0.113.10:8388#Same';
      final imported = await singBox.importServerConfigs(
        '$link\n$link\nnot-a-link',
        subscriptionId: 'sub-1',
      );
      expect(imported, hasLength(2));
      expect(imported.map((s) => s.id).toSet(), hasLength(2));
      expect(imported.first.subscriptionId, 'sub-1');
      expect(imported.first.link, link);
      await singBox.clearServerConfigs(subscriptionId: 'sub-1');
      expect(await singBox.getServerConfigs(), isEmpty);
    });
  });

  group('commands', () {
    setUp(singBox.initialize);

    test('forward to the platform', () async {
      await singBox.selectOutbound('proxy', 'node');
      await singBox.setClashMode('Global');
      await singBox.closeConnection('id-1');
      await singBox.closeAllConnections();
      await singBox.clearLogs();
      expect(
        platform.calls,
        containsAll([
          'selectOutbound:proxy:node',
          'setClashMode:Global',
          'closeConnection:id-1',
          'closeAllConnections',
          'clearLogs',
        ]),
      );
    });
  });
}
