// Platform smoke test that needs no VPN server and no VPN consent; runs on
// the iOS simulator (where Network Extensions cannot start) and on Android.
//
//   flutter test integration_test/smoke_test.dart -d <device>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sing_box/sing_box.dart';

const link = 'ss://YWVzLTEyOC1nY206cHc@203.0.113.1:8388#Smoke';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final singBox = SingBox.instance;

  testWidgets('initializes and reports the core', (tester) async {
    await singBox.initialize();
    expect(singBox.isInitialized, isTrue);
    expect(singBox.runtimeInfo!.singBoxVersion, contains('1.14'));
    expect(await singBox.getSingBoxVersion(), contains('1.14'));
    expect(await singBox.getPlatformVersion(), isNotEmpty);
    expect(singBox.status, SingBoxConnectionStatus.disconnected);
    expect(
      await singBox.getConnectionStatus(),
      SingBoxConnectionStatus.disconnected,
    );
  });

  testWidgets('validates and formats configurations natively', (tester) async {
    final config = await singBox.buildConfig(link);
    expect(await singBox.validateConfig(config), isNull);
    expect(await singBox.formatConfig(config), contains('"outbounds"'));
    final error = await singBox.validateConfig(
      '{"outbounds": [{"type": "nope"}]}',
    );
    expect(error, contains('nope'));
  });

  testWidgets('persists settings, rules and profiles', (tester) async {
    await singBox.saveRoutingRules(
      const SingBoxRoutingRules(bypassDomains: ['example.com']),
    );
    expect((await singBox.getRoutingRules()).bypassDomains, ['example.com']);
    final imported = await singBox.importServerConfigs(link);
    expect(imported.single.name, 'Smoke');
    expect(await singBox.removeServerConfig(imported.single.id), isTrue);
    await singBox.saveRoutingRules(const SingBoxRoutingRules());
  });

  testWidgets('fails cleanly without the VPN permission', (tester) async {
    if (await singBox.hasVpnPermission()) return;
    await expectLater(
      singBox.connect(link, requestPermission: false),
      throwsA(isA<SingBoxPermissionException>()),
    );
    expect(singBox.status, SingBoxConnectionStatus.disconnected);
  });

  testWidgets('streams stay silent while stopped', (tester) async {
    final stats = <SingBoxConnectionStats>[];
    final sub = singBox.watchConnectionStats().listen(stats.add);
    await Future<void>.delayed(const Duration(seconds: 2));
    await sub.cancel();
    expect(stats, isEmpty);
    expect(await singBox.getLastConfig(), anyOf(isNull, isA<String>()));
  });
}
