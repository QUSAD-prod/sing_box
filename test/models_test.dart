import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';

void main() {
  group('SingBoxConnectionStatus', () {
    test('parses wire values', () {
      expect(
        SingBoxConnectionStatus.fromString('connected'),
        SingBoxConnectionStatus.connected,
      );
      expect(
        SingBoxConnectionStatus.fromString('reasserting'),
        SingBoxConnectionStatus.connecting,
      );
      expect(
        SingBoxConnectionStatus.fromString('???'),
        SingBoxConnectionStatus.disconnected,
      );
      expect(SingBoxConnectionStatus.connecting.isActive, isTrue);
      expect(SingBoxConnectionStatus.disconnecting.isTransitioning, isTrue);
    });

    test('state duration is zero unless connected', () {
      final start = DateTime.now().subtract(const Duration(seconds: 90));
      expect(
        SingBoxConnectionState(
          status: SingBoxConnectionStatus.connected,
          startedAt: start,
        ).duration.inSeconds,
        greaterThanOrEqualTo(89),
      );
      expect(
        SingBoxConnectionState(
          status: SingBoxConnectionStatus.disconnected,
          startedAt: start,
        ).duration,
        Duration.zero,
      );
    });
  });

  test('connection stats read new and legacy keys', () {
    final stats = SingBoxConnectionStats.fromMap({
      'uplink': 1,
      'downlink': 2,
      'uplinkTotal': 3,
      'downlinkTotal': 4,
      'connectionsIn': 5,
      'connectionsOut': 6,
      'memory': 7,
      'goroutines': 8,
      'trafficAvailable': true,
    });
    expect(stats.uploadSpeed, 1);
    expect(stats.downloadTotal, 4);
    expect(stats.trafficAvailable, isTrue);
    final legacy = SingBoxConnectionStats.fromMap({
      'uploadSpeed': 10,
      'bytesReceived': 20,
    });
    expect(legacy.uploadSpeed, 10);
    expect(legacy.downloadTotal, 20);
  });

  test('log entries strip ANSI codes and map levels', () {
    final event = SingBoxLogEvent.fromMap({
      'type': 'logs',
      'reset': true,
      'entries': [
        {'level': 2, 'message': '\x1B[31mERROR\x1B[0m failed'},
      ],
    });
    expect(event, isA<SingBoxLogBatch>());
    final batch = event! as SingBoxLogBatch;
    expect(batch.reset, isTrue);
    expect(batch.entries.single.level, SingBoxLogLevel.error);
    expect(batch.entries.single.plainMessage, 'ERROR failed');
    expect(SingBoxLogLevel.error.isAtLeast(SingBoxLogLevel.warn), isTrue);
    expect(SingBoxLogEvent.fromMap({'type': 'clear'}), isA<SingBoxLogCleared>());
    expect(SingBoxLogEvent.fromMap({'type': 'unknown'}), isNull);
  });

  test('outbound items treat zero as unknown', () {
    final item = SingBoxOutboundItem.fromMap({
      'tag': 'a',
      'type': 'vless',
      'urlTestTime': 1730000000000,
      'urlTestDelay': 0,
    });
    expect(item.urlTestTime, isNotNull);
    expect(item.urlTestDelay, isNull);
    expect(item.urlTestFailed, isTrue);
  });

  test('connections expose a display destination', () {
    final c = SingBoxConnection.fromMap({
      'id': '1',
      'network': 'tcp',
      'destination': '1.1.1.1:443',
      'domain': 'one.one.one.one',
      'createdAt': 1730000000000,
      'chain': ['proxy', 'node'],
      'processName': '',
    });
    expect(c.displayDestination, 'one.one.one.one:443');
    expect(c.isActive, isTrue);
    expect(c.chain, ['proxy', 'node']);
    expect(c.processName, isNull);
  });

  test('STUN NAT values follow sing-box numbering', () {
    final r = SingBoxStunResult.fromMap({
      'type': 'result',
      'externalAddr': '1.2.3.4:1',
      'natMapping': 2,
      'natFiltering': 3,
      'latencyMs': 40,
    });
    expect(r.natMapping, SingBoxNatMapping.endpointIndependent);
    expect(r.natFiltering, SingBoxNatFiltering.addressAndPortDependent);
    expect(r.isFinal, isTrue);
    expect(SingBoxNatMapping.fromValue(1), SingBoxNatMapping.unknown);
  });

  test('network quality converts units', () {
    final q = SingBoxNetworkQuality.fromMap({
      'type': 'result',
      'downloadCapacity': 50000000,
      'uploadCapacity': 10000000,
      'idleLatencyMs': 25,
      'downloadRPMAccuracy': 2,
    });
    expect(q.isFinal, isTrue);
    expect(q.downloadMbps, 50);
    expect(q.idleLatency, const Duration(milliseconds: 25));
    expect(q.downloadRpmAccuracy, SingBoxMeasurementAccuracy.high);
    final speed = SingBoxSpeedTestResult.fromNetworkQuality(q);
    expect(speed.downloadSpeed, 6250000);
    expect(speed.uploadMbps, closeTo(10, 0.001));
  });

  test('settings round trip and map to service options', () {
    const settings = SingBoxSettings(killSwitch: true, startOnBoot: true);
    expect(SingBoxSettings.fromMap(settings.toMap()), settings);
    final options = settings.toServiceOptions();
    expect(options.includeAllNetworks, isTrue);
    expect(options.startOnBoot, isTrue);
    expect(
      () => settings.withValue('nope', true),
      throwsArgumentError,
    );
  });

  test('server config detects complete configs', () {
    final outbound = SingBoxServerConfig.fromOutbound({
      'type': 'trojan',
      'tag': 't',
      'server': 'example.com',
      'server_port': 443,
    });
    expect(outbound.isFullConfig, isFalse);
    expect(outbound.outbound?['type'], 'trojan');
    final full = SingBoxServerConfig.fromFullConfig(
      '{"outbounds":[{"type":"direct","tag":"d"},{"type":"vless","tag":"v","server":"h","server_port":1}]}',
      id: 'f',
      name: 'Full',
    );
    expect(full.isFullConfig, isTrue);
    expect(full.protocol, 'vless');
    expect(full.port, 1);
    expect(SingBoxServerConfig.fromMap(full.toMap()), full);
  });

  group('validators', () {
    test('IP and CIDR', () {
      expect(SingBoxValidators.isIpv4('192.168.1.1'), isTrue);
      expect(SingBoxValidators.isIpv4('256.1.1.1'), isFalse);
      expect(SingBoxValidators.isIpv6('fe80::1%wlan0'), isTrue);
      expect(SingBoxValidators.isCidr('fd00::/8'), isTrue);
      expect(SingBoxValidators.isCidr('10.0.0.0/33'), isFalse);
      expect(SingBoxValidators.normalizeCidr('::1'), '::1/128');
    });

    test('domains and packages', () {
      expect(SingBoxValidators.normalizeDomain('*.Example.com.'), 'example.com');
      expect(
        SingBoxValidators.normalizeDomain('https://user@sub.example.com:8443/x'),
        'sub.example.com',
      );
      expect(SingBoxValidators.normalizeDomain('1.2.3.4'), isNull);
      expect(SingBoxValidators.isPackageName('com.example.app'), isTrue);
      expect(SingBoxValidators.isPackageName('example'), isFalse);
    });
  });

  test('exceptions map platform codes', () {
    expect(
      SingBoxException.fromPlatformException(
        PlatformException(code: 'UNSUPPORTED', message: 'no'),
      ),
      isA<SingBoxUnsupportedException>(),
    );
  });
}
