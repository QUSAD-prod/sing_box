import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/tool/pbxproj.dart';
import 'package:sing_box/src/tool/setup_ios.dart';

void main() {
  late Directory ios;
  late String project;

  setUp(() async {
    final app = await Directory.systemTemp.createTemp('sing_box_setup_ios');
    ios = await Directory('${app.path}/ios').create();
    project = '${ios.path}/Runner.xcodeproj';
    await Directory(project).create();
    await File(
      'test/tool/fixtures/flutter_3_47.pbxproj',
    ).copy('$project/project.pbxproj');
  });

  tearDown(() => ios.parent.delete(recursive: true));

  Future<void> generatedPackage({required bool withPlugin}) async {
    final file = File(
      '${ios.path}/Flutter/ephemeral/Packages/'
      'FlutterGeneratedPluginSwiftPackage/Package.swift',
    );
    await file.create(recursive: true);
    await file.writeAsString(
      withPlugin
          ? '.product(name: "sing-box", package: "sing_box"),'
          : 'dependencies: [],',
    );
  }

  PbxProject read() =>
      PbxProject(File('$project/project.pbxproj').readAsStringSync());

  TunnelLinking run() => setupIos(SetupIosOptions(project: project), (_) {});

  test(
    'Swift Package Manager: links SingBoxTunnel without CocoaPods',
    () async {
      await generatedPackage(withPlugin: true);
      expect(run(), TunnelLinking.swiftPackageManager);

      final pbx = read();
      final all = pbx.objects;
      final targetId = pbx.targetId('PacketTunnel')!;
      final target = all[targetId]!;
      expect(target['productType'], 'com.apple.product-type.app-extension');
      final products =
          (target['packageProductDependencies']! as List).cast<String>();
      expect(all[products.single]!['productName'], 'SingBoxTunnel');
      expect(
        all[products.single]!['package'],
        pbx.localPackageId('FlutterGeneratedPluginSwiftPackage'),
      );
      final configs = pbx.configurations(
        target['buildConfigurationList']! as String,
      );
      expect(configs.keys, unorderedEquals(['Debug', 'Release', 'Profile']));
      expect(
        configs['Release']!['PRODUCT_BUNDLE_IDENTIFIER'],
        'com.example.spmapp.PacketTunnel',
      );
      expect(configs['Release']!['DEVELOPMENT_TEAM'], 'ABCDE12345');

      // The Runner embeds the extension before Flutter's "Thin Binary" phase
      // and depends on it.
      final runner = all[pbx.targetId('Runner')]!;
      final phases = [
        for (final id in (runner['buildPhases']! as List).cast<String>())
          all[id]!['name'] ?? all[id]!['isa'],
      ];
      expect(
        phases.indexOf('Embed Foundation Extensions'),
        phases.indexOf('Thin Binary') - 1,
      );
      expect((runner['dependencies']! as List), hasLength(1));
      final runnerConfigs = pbx.configurations(
        runner['buildConfigurationList']! as String,
      );
      for (final settings in runnerConfigs.values) {
        expect(
          settings['CODE_SIGN_ENTITLEMENTS'],
          'Runner/Runner.entitlements',
        );
      }

      // Files.
      final entitlements =
          File('${ios.path}/Runner/Runner.entitlements').readAsStringSync();
      expect(entitlements, contains('packet-tunnel-provider'));
      expect(entitlements, contains('group.com.example.spmapp'));
      expect(
        File('${ios.path}/PacketTunnel/Info.plist').readAsStringSync(),
        contains('com.apple.networkextension.packet-tunnel'),
      );
      expect(
        File('${ios.path}/PacketTunnel/Release.xcconfig').readAsStringSync(),
        contains('SING_BOX_APP_GROUP = group.com.example.spmapp'),
      );

      // Idempotent.
      final before = File('$project/project.pbxproj').readAsStringSync();
      expect(run(), TunnelLinking.swiftPackageManager);
      expect(File('$project/project.pbxproj').readAsStringSync(), before);
    },
  );

  test(
    'CocoaPods: adds the pod when Flutter links plugins with pods',
    () async {
      await generatedPackage(withPlugin: false);
      await File('${ios.path}/Podfile').writeAsString(
        "target 'Runner' do\nend\n\npost_install do |installer|\nend\n",
      );
      expect(run(), TunnelLinking.cocoaPods);
      final podfile = File('${ios.path}/Podfile').readAsStringSync();
      expect(podfile, contains("pod 'SingBoxTunnel'"));
      expect(
        podfile.indexOf("target 'PacketTunnel'"),
        lessThan(podfile.indexOf('post_install do')),
      );
      expect(read().targetId('PacketTunnel'), isNotNull);
      // An existing pod is kept (no second copy through Swift packages).
      await generatedPackage(withPlugin: true);
      expect(run(), TunnelLinking.cocoaPods);
      expect(
        read().objects[read().targetId(
          'PacketTunnel',
        )]!['packageProductDependencies'],
        isNull,
      );
    },
  );

  test('not linked before the first Flutter build', () {
    expect(run(), TunnelLinking.none);
    expect(read().targetId('PacketTunnel'), isNotNull);
  });

  test('custom ids', () async {
    await generatedPackage(withPlugin: true);
    setupIos(
      SetupIosOptions(
        project: project,
        target: 'Tunnel',
        bundleId: 'com.acme.vpn.tunnel',
        appGroup: 'group.acme',
        team: 'TEAM123456',
      ),
      (_) {},
    );
    final pbx = read();
    final target = pbx.objects[pbx.targetId('Tunnel')]!;
    final settings =
        pbx.configurations(
          target['buildConfigurationList']! as String,
        )['Debug']!;
    expect(settings['PRODUCT_BUNDLE_IDENTIFIER'], 'com.acme.vpn.tunnel');
    expect(settings['DEVELOPMENT_TEAM'], 'TEAM123456');
    expect(settings['INFOPLIST_FILE'], 'Tunnel/Info.plist');
    expect(
      File('${ios.path}/Tunnel/Tunnel.entitlements').readAsStringSync(),
      contains('group.acme'),
    );
  });

  test('mergeEntitlements keeps existing values', () async {
    final file = File('${ios.path}/x.entitlements');
    await file.writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.other</string>
	</array>
</dict>
</plist>
''');
    mergeEntitlements(file, 'group.mine');
    mergeEntitlements(file, 'group.mine');
    final text = file.readAsStringSync();
    expect(text, contains('group.other'));
    expect('group.mine'.allMatches(text), hasLength(1));
    expect(text, contains('packet-tunnel-provider'));
  });

  test('PbxProject parses quoted strings and comments', () {
    final pbx = PbxProject('''
// !\$*UTF8*\$!
{
	objects = {
		A /* a */ = {isa = PBXProject; targets = (); name = "x \\"y\\""; };
	};
	rootObject = A /* a */;
}
''');
    expect(pbx.project['name'], 'x "y"');
    expect(PbxProject.quote(r'$(TARGET_NAME)'), r'"$(TARGET_NAME)"');
    expect(PbxProject.quote('YES'), 'YES');
  });
}
