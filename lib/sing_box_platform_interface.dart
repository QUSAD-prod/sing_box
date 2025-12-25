import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'sing_box_method_channel.dart';

abstract class SingBoxPlatform extends PlatformInterface {
  /// Constructs a SingBoxPlatform.
  SingBoxPlatform() : super(token: _token);

  static final Object _token = Object();

  static SingBoxPlatform _instance = MethodChannelSingBox();

  /// The default instance of [SingBoxPlatform] to use.
  ///
  /// Defaults to [MethodChannelSingBox].
  static SingBoxPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SingBoxPlatform] when
  /// they register themselves.
  static set instance(SingBoxPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
