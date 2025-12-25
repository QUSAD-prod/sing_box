import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sing_box_platform_interface.dart';

/// An implementation of [SingBoxPlatform] that uses method channels.
class MethodChannelSingBox extends SingBoxPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('sing_box');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
