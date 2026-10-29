import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelSingBox platform;
  late List<MethodCall> log;

  setUp(() {
    platform = MethodChannelSingBox();
    log = [];
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'initialize':
          return {
            'singBoxVersion': '1.14.4',
            'status': 'connected',
            'workingDirectory': '/data/sing-box',
          };
        case 'getPlatformVersion':
          return 'Android 15';
        case 'checkConfig':
          final config = (call.arguments as Map)['config'] as String;
          if (config.contains('bad')) {
            throw PlatformException(
              code: 'INVALID_CONFIG',
              message: 'decode config: unknown field "bad"',
            );
          }
          return null;
        case 'start':
          throw PlatformException(code: 'PERMISSION_DENIED', message: 'denied');
        case 'reload':
          throw PlatformException(
            code: 'SERVICE_NOT_RUNNING',
            message: 'stopped',
          );
        case 'getStatus':
          return 'connecting';
        case 'getStartedAt':
          return 1730000000000;
        case 'storageRead':
          return 'value';
        case 'hasVpnPermission':
          return true;
        case 'getSystemProxyStatus':
          return {'available': true, 'enabled': false};
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platform.methodChannel, null);
  });

  test('initialize sends options and parses the result', () async {
    final info = await platform.initialize(
      const SingBoxOptions(
        logMaxLines: 100,
        android: SingBoxAndroidOptions(notificationTitle: 'My VPN'),
        ios: SingBoxIosOptions(appGroup: 'group.test'),
      ),
    );
    expect(info.singBoxVersion, '1.14.4');
    expect(info.status, SingBoxConnectionStatus.connected);
    expect(info.workingDirectory, '/data/sing-box');
    final args = log.single.arguments as Map;
    expect(args['logMaxLines'], 100);
    expect((args['android'] as Map)['notificationTitle'], 'My VPN');
    expect((args['ios'] as Map)['appGroup'], 'group.test');
  });

  test('simple calls', () async {
    expect(await platform.getPlatformVersion(), 'Android 15');
    expect(await platform.getStatus(), SingBoxConnectionStatus.connecting);
    expect(
      await platform.getStartedAt(),
      DateTime.fromMillisecondsSinceEpoch(1730000000000),
    );
    expect(await platform.storageRead('k'), 'value');
    expect(await platform.hasVpnPermission(), isTrue);
    await platform.storageWrite('k', null);
    expect(log.last.arguments, {'key': 'k', 'value': null});
    await platform.selectOutbound('proxy', 'node');
    expect(log.last.arguments, {'groupTag': 'proxy', 'outboundTag': 'node'});
    await platform.setServiceOptions(
      const SingBoxServiceOptions(startOnBoot: true),
    );
    expect((log.last.arguments as Map)['startOnBoot'], isTrue);
    expect((log.last.arguments as Map)['excludeAPNs'], isTrue);
    expect(
      await platform.getSystemProxyStatus(),
      const SingBoxSystemProxyStatus(available: true, enabled: false),
    );
    await platform.setSystemProxyEnabled(true);
    expect(log.last.method, 'setSystemProxyEnabled');
    expect(log.last.arguments, {'enabled': true});
  });

  test('platform errors become typed exceptions', () async {
    await platform.checkConfig('{}');
    await expectLater(
      platform.checkConfig('bad'),
      throwsA(
        isA<SingBoxConfigException>().having(
          (e) => e.message,
          'message',
          contains('unknown field'),
        ),
      ),
    );
    await expectLater(
      platform.start('{}'),
      throwsA(isA<SingBoxPermissionException>()),
    );
    expect(log.last.arguments, {
      'config': '{}',
      'disableMemoryLimit': false,
      'oomKiller': 'platformDefault',
      'memoryLimit': 0,
    });
    await expectLater(
      platform.start(
        '{}',
        oomKiller: SingBoxOomKiller.reportOnly,
        memoryLimit: 1 << 20,
      ),
      throwsA(isA<SingBoxPermissionException>()),
    );
    expect(log.last.arguments, containsPair('oomKiller', 'reportOnly'));
    expect(log.last.arguments, containsPair('memoryLimit', 1 << 20));
    // The pre-1.1.0 flag still turns the monitor off.
    await expectLater(
      platform.start('{}', disableMemoryLimit: true),
      throwsA(isA<SingBoxPermissionException>()),
    );
    expect(log.last.arguments, containsPair('oomKiller', 'off'));
    expect(log.last.arguments, containsPair('disableMemoryLimit', true));
    await expectLater(
      platform.reload(),
      throwsA(isA<SingBoxServiceNotRunningException>()),
    );
  });

  test('missing implementation becomes an unsupported error', () async {
    messenger.setMockMethodCallHandler(platform.methodChannel, null);
    await expectLater(
      platform.getSingBoxVersion(),
      throwsA(isA<SingBoxUnsupportedException>()),
    );
  });

  test('event channels are parsed', () async {
    messenger.setMockStreamHandler(
      platform.statusEventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          sink.success({'status': 'connected', 'startedAt': 1730000000000});
          sink.success({'status': 'disconnected', 'error': 'boom'});
        },
      ),
    );
    final states = await platform.watchState().take(2).toList();
    expect(states.first.status, SingBoxConnectionStatus.connected);
    expect(states.first.startedAt, isNotNull);
    expect(states.last.error, 'boom');

    messenger.setMockStreamHandler(
      platform.groupsEventChannel,
      MockStreamHandler.inline(
        onListen:
            (arguments, sink) => sink.success([
              {
                'tag': 'proxy',
                'type': 'selector',
                'selectable': true,
                'selected': 'a',
                'items': [
                  {
                    'tag': 'a',
                    'type': 'vless',
                    'urlTestTime': 1,
                    'urlTestDelay': 50,
                  },
                ],
              },
            ]),
      ),
    );
    final groups = await platform.watchGroups().first;
    expect(groups.single.selectedItem?.urlTestDelay, 50);

    messenger.setMockStreamHandler(
      platform.networkQualityEventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          expect((arguments as Map)['outboundTag'], 'node');
          sink.success({'type': 'progress', 'phase': 1, 'downloadCapacity': 8});
          sink.success({'type': 'result', 'downloadCapacity': 16});
          sink.endOfStream();
        },
      ),
    );
    final quality =
        await platform.runNetworkQualityTest(outboundTag: 'node').toList();
    expect(quality.first.phase, SingBoxNetworkQualityPhase.download);
    expect(quality.last.isFinal, isTrue);
  });

  test('stream errors become typed exceptions', () async {
    messenger.setMockStreamHandler(
      platform.stunEventChannel,
      MockStreamHandler.inline(
        onListen:
            (arguments, sink) =>
                sink.error(code: 'SERVICE_NOT_RUNNING', message: 'not running'),
      ),
    );
    await expectLater(
      platform.runStunTest().first,
      throwsA(isA<SingBoxServiceNotRunningException>()),
    );
  });
}
