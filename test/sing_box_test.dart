import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';
import 'package:sing_box/sing_box_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSingBoxPlatform
    with MockPlatformInterfaceMixin
    implements SingBoxPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SingBoxPlatform initialPlatform = SingBoxPlatform.instance;

  test('$MethodChannelSingBox is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSingBox>());
  });

  test('getPlatformVersion', () async {
    SingBox singBoxPlugin = SingBox();
    MockSingBoxPlatform fakePlatform = MockSingBoxPlatform();
    SingBoxPlatform.instance = fakePlatform;

    expect(await singBoxPlugin.getPlatformVersion(), '42');
  });
}
