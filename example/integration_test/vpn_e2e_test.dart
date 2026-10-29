// End-to-end test against real sing-box servers. Start them with
// `SING_BOX_BIN=… integration_test/server/run_e2e_server.sh` and keep
// `integration_test/server/grant_vpn_consent.sh` running (see CONTRIBUTING.md).
//
// Needs a sing-box server reachable from the device (the Android emulator
// reaches the host's loopback as 10.0.2.2) with
//   * a shadowsocks inbound on 8388 (aes-128-gcm, password "e2e-password"),
//   * a vless inbound on 10086 (uuid below, no TLS),
//   * a route rule rewriting 203.0.113.80 to 127.0.0.1 and an HTTP server on
//     127.0.0.1:18080 serving /probe.txt with "sing-box-e2e-ok".
// The VPN consent must be granted beforehand:
//   adb shell appops set com.qusadprod.sing_box_example ACTIVATE_VPN allow
//
//   flutter test integration_test/vpn_e2e_test.dart --dart-define=E2E_HOST=10.0.2.2
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sing_box/sing_box.dart';

const host = String.fromEnvironment('E2E_HOST', defaultValue: '10.0.2.2');
const uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';
const probeUrl = 'http://203.0.113.80:18080/probe.txt';

final ssLink =
    'ss://${base64Url.encode(utf8.encode('aes-128-gcm:e2e-password')).replaceAll('=', '')}'
    '@$host:8388#E2E%20SS';
const vlessLink =
    'vless://$uuid@$host:10086?security=none&type=tcp#E2E%20VLESS';

final singBox = SingBox.instance;

Future<String> fetchProbe({
  Duration timeout = const Duration(seconds: 10),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri.parse(probeUrl)).timeout(timeout);
    final response = await request.close().timeout(timeout);
    return (await response.transform(utf8.decoder).join()).trim();
  } finally {
    client.close(force: true);
  }
}

Future<T> firstWhere<T>(
  Stream<T> stream,
  bool Function(T) test, {
  Duration timeout = const Duration(seconds: 15),
}) => stream.firstWhere(test).timeout(timeout);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await singBox.initialize();
    // The consent is granted from the host (appops) right after the install.
    for (var i = 0; i < 30 && !await singBox.hasVpnPermission(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    singBox.configOptions = const SingBoxConfigOptions(
      urlTestUrl: probeUrl,
      logLevel: SingBoxConfigLogLevel.debug,
    );
    if (singBox.status != SingBoxConnectionStatus.disconnected) {
      await singBox.disconnect();
      await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);
    }
  });

  tearDownAll(() async {
    if (singBox.status != SingBoxConnectionStatus.disconnected) {
      await singBox.disconnect();
    }
  });

  testWidgets('information and validation', (tester) async {
    expect(await singBox.getSingBoxVersion(), contains('1.14'));
    expect(await singBox.getPlatformVersion(), startsWith('Android'));
    expect(await singBox.hasVpnPermission(), isTrue);
    expect(
      await singBox.validateConfig('{"outbounds": [{"type": "nope"}]}'),
      contains('nope'),
    );
    expect(
      await singBox.validateConfig(await singBox.buildConfig(ssLink)),
      isNull,
    );
  });

  testWidgets('latency of profiles without the tunnel', (tester) async {
    final servers = [
      SingBoxServerConfig.fromOutbound(
        SingBoxShareLink.parse(ssLink).json,
        id: 'ss',
      ),
      SingBoxServerConfig.fromOutbound(
        SingBoxShareLink.parse(vlessLink).json,
        id: 'vless',
      ),
      SingBoxServerConfig.fromOutbound({
        'type': 'trojan',
        'tag': 'closed',
        'server': host,
        'server_port': 9,
        'password': 'x',
      }, id: 'closed'),
    ];
    Future<Map<String?, SingBoxPingResult>> measure(
      SingBoxPingMethod method,
    ) async => {
      for (final r
          in await singBox.pingServers(servers, method: method).toList())
        r.serverId: r,
    };

    // HTTP through each server, by a probe core in the app: probe.txt is only
    // reachable through the e2e servers.
    for (final method in [
      SingBoxPingMethod.proxyHead,
      SingBoxPingMethod.proxyGet,
    ]) {
      final results = await measure(method);
      for (final id in ['ss', 'vless']) {
        expect(results[id]!.success, isTrue, reason: '${results[id]}');
        expect(results[id]!.method, method);
        expect(results[id]!.statusCode, 200);
        expect(results[id]!.url, probeUrl);
      }
      expect(results['closed']!.success, isFalse);
    }

    final tcp = await measure(SingBoxPingMethod.tcp);
    expect(tcp['ss']!.success, isTrue, reason: '${tcp['ss']}');
    expect(tcp['ss']!.method, SingBoxPingMethod.tcp);
    expect(tcp['closed']!.success, isFalse);

    // Unprivileged ICMP sockets work (the emulator network may not forward
    // ICMP to the host, so only the device's own address is required).
    final loopback = await singBox.ping(
      SingBoxServerConfig.fromOutbound({
        'type': 'socks',
        'tag': 'local',
        'server': '127.0.0.1',
        'server_port': 1,
      }, id: 'local'),
      method: SingBoxPingMethod.icmp,
    );
    expect(loopback.success, isTrue, reason: '$loopback');
    final icmp = await measure(SingBoxPingMethod.icmp);
    debugPrint('ICMP to $host: ${icmp['ss']}');
  });

  testWidgets('connects and carries traffic through the proxy', (tester) async {
    await expectLater(
      fetchProbe(timeout: const Duration(seconds: 3)),
      throwsA(anything),
    );

    final states = <SingBoxConnectionStatus>[];
    final sub = singBox.watchConnectionStatus().listen(states.add);
    await singBox.connect('$ssLink\n$vlessLink');
    expect(singBox.isConnected, isTrue);
    expect(singBox.state.startedAt, isNotNull);
    expect(
      await singBox.getConnectionStatus(),
      SingBoxConnectionStatus.connected,
    );
    expect(
      states,
      containsAllInOrder([
        SingBoxConnectionStatus.connecting,
        SingBoxConnectionStatus.connected,
      ]),
    );
    await sub.cancel();

    expect(await fetchProbe(), 'sing-box-e2e-ok');

    final stats = await firstWhere(
      singBox.watchConnectionStats(),
      (s) => s.downloadTotal > 0,
    );
    expect(stats.uploadTotal, greaterThan(0));

    final groups = await firstWhere(
      singBox.watchGroups(),
      (g) => g.any((group) => group.tag == SingBoxConfigBuilder.proxyTag),
    );
    final proxy = groups.firstWhere(
      (g) => g.tag == SingBoxConfigBuilder.proxyTag,
    );
    expect(proxy.items.map((i) => i.tag), ['auto', 'E2E SS', 'E2E VLESS']);

    // Through the probe route of the running tunnel (no local port).
    final ping = await singBox.pingOutbound('E2E SS');
    expect(ping.success, isTrue, reason: '$ping');
    expect(ping.statusCode, 200, reason: '$ping');
    final get = await singBox.pingOutbound(
      'E2E VLESS',
      method: SingBoxPingMethod.proxyGet,
    );
    expect(get.success, isTrue, reason: '$get');
    expect(get.method, SingBoxPingMethod.proxyGet);
    final running = await singBox.pingServers([
      SingBoxServerConfig.fromOutbound(
        SingBoxShareLink.parse(ssLink).json,
        id: 'ss',
      ),
    ]).toList();
    expect(running.single.success, isTrue, reason: '$running');
    // TCP bypasses the tunnel (protected socket, underlying network).
    final tcp = await singBox.pingOutbound(
      'E2E SS',
      method: SingBoxPingMethod.tcp,
    );
    expect(tcp.success, isTrue, reason: '$tcp');
    final group = await singBox.testGroup(SingBoxConfigBuilder.autoTag);
    expect(group, isNotNull);

    await singBox.selectOutbound(SingBoxConfigBuilder.proxyTag, 'E2E VLESS');
    await firstWhere(
      singBox.watchGroups(),
      (g) => g.any(
        (group) =>
            group.tag == SingBoxConfigBuilder.proxyTag &&
            group.selected == 'E2E VLESS',
      ),
    );
    expect(await fetchProbe(), 'sing-box-e2e-ok');
    expect(await singBox.currentOutboundTag(), 'E2E VLESS');

    final connections = await firstWhere(
      singBox.watchConnections(),
      (list) => list.any((c) => c.destination.contains('203.0.113.80')),
    );
    expect(connections.first.createdAt.year, DateTime.now().year);

    final mode = await singBox.watchClashMode().first.timeout(
      const Duration(seconds: 10),
    );
    expect(mode.modes, containsAll(['Rule', 'Global', 'Direct']));
    await singBox.setClashMode('Global');
    await firstWhere(singBox.watchClashMode(), (m) => m.current == 'Global');
    await singBox.setClashMode('Rule');

    final logs = await firstWhere(
      singBox.watchLogBuffer(),
      (entries) => entries.isNotEmpty,
    );
    expect(logs, isNotEmpty);
  });

  testWidgets('switches servers in place and stops', (tester) async {
    expect(singBox.isConnected, isTrue);
    await singBox.switchServer(vlessLink);
    expect(singBox.isConnected, isTrue);
    await firstWhere(
      singBox.watchOutbounds(),
      (items) => items.any((i) => i.tag == 'E2E VLESS'),
    );
    expect(await fetchProbe(), 'sing-box-e2e-ok');

    await singBox.disconnect();
    await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);
    expect(singBox.state.error, isNull);
    await expectLater(
      fetchProbe(timeout: const Duration(seconds: 3)),
      throwsA(anything),
    );
  });

  testWidgets('per-app lists are applied to the tunnel', (tester) async {
    const self = 'com.qusadprod.sing_box_example';
    // Only another app is tunnelled: our own traffic goes around the VPN.
    await singBox.connect(
      ssLink,
      rules: const SingBoxRoutingRules(proxyApps: ['com.android.chrome']),
    );
    await expectLater(
      fetchProbe(timeout: const Duration(seconds: 3)),
      throwsA(anything),
    );
    // Our app is excluded explicitly.
    await singBox.connect(
      ssLink,
      rules: const SingBoxRoutingRules(bypassApps: [self]),
    );
    await expectLater(
      fetchProbe(timeout: const Duration(seconds: 3)),
      throwsA(anything),
    );
    // An include list without any installed app must not capture every app.
    await singBox.disconnect();
    await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);
    await expectLater(
      singBox.connect(
        ssLink,
        rules: const SingBoxRoutingRules(
          proxyApps: ['com.example.not.installed'],
        ),
      ),
      throwsA(
        isA<SingBoxStartException>().having(
          (e) => e.message,
          'message',
          contains('include_package'),
        ),
      ),
    );
    // Back to everything through the tunnel.
    await singBox.connect(ssLink);
    expect(await fetchProbe(), 'sing-box-e2e-ok');
    await singBox.disconnect();
    await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);
  });

  testWidgets('downloads rule-sets on the first start', (tester) async {
    // Iran has no third-party lists with fixed URLs: both rule-sets come from
    // the local server (integration_test/server/rules).
    await singBox.connect(
      ssLink,
      rules: const SingBoxRoutingRules(bypassCountries: ['ir']),
      options: const SingBoxConfigOptions(
        urlTestUrl: probeUrl,
        geoipRuleSetUrl: 'http://$host:18080/{tag}.srs',
        geositeRuleSetUrl: 'http://$host:18080/{tag}.srs',
      ),
    );
    expect(singBox.isConnected, isTrue);
    final ruleSets = {for (final s in await singBox.getRuleSets()) s.tag: s};
    for (final tag in ['geosite-category-ir', 'geoip-ir']) {
      expect(ruleSets[tag]?.isAvailable, isTrue, reason: '${ruleSets[tag]}');
    }
    expect(await fetchProbe(), 'sing-box-e2e-ok');
    await singBox.disconnect();
    await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);
  });

  testWidgets('starts without the rules of unreachable rule-sets', (
    tester,
  ) async {
    // The plugin downloads rule-sets itself: a failed download leaves its
    // rules out instead of aborting the start (sing-box would abort).
    await singBox.connect(
      ssLink,
      rules: const SingBoxRoutingRules(bypassCountries: ['de']),
      options: const SingBoxConfigOptions(
        urlTestUrl: probeUrl,
        geoipRuleSetUrl: 'http://127.0.0.1:1/{tag}.srs',
        geositeRuleSetUrl: 'http://127.0.0.1:1/{tag}.srs',
      ),
    );
    expect(singBox.isConnected, isTrue);
    expect(singBox.state.error, isNull);
    final geoip = (await singBox.getRuleSets()).firstWhere(
      (s) => s.tag == 'geoip-de',
    );
    expect(geoip.isAvailable, isFalse);
    expect(geoip.lastError, isNotNull);
    expect(await fetchProbe(), 'sing-box-e2e-ok');
    await singBox.disconnect();
    await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);
  });

  testWidgets('rapid toggles end in the last requested state', (tester) async {
    final first = singBox.connect(ssLink);
    final firstDone = first.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    await singBox.disconnect();
    final error = await firstDone;
    expect(error, anyOf(isNull, isA<SingBoxCancelledException>()));
    await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);

    final connecting = singBox.connect(ssLink);
    final again = singBox.connect(vlessLink);
    await expectLater(connecting, throwsA(isA<SingBoxCancelledException>()));
    await again;
    expect(singBox.isConnected, isTrue);
    expect(await fetchProbe(), 'sing-box-e2e-ok');

    await singBox.restart();
    expect(singBox.isConnected, isTrue);
    await singBox.disconnect();
    await singBox.waitForStatus(SingBoxConnectionStatus.disconnected);
  });
}
