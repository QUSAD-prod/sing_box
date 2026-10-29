part of 'sing_box.dart';

/// The plugin API with the members that need the sing-box-lx core
/// ([SingBoxCore.lx]).
///
/// It is the same object as [SingBox.instance]:
///
/// ```dart
/// final singBox = SingBoxExtended.instance;
/// await singBox.initialize();
/// if (singBox.core == SingBoxCore.lx) { ... }
/// ```
///
/// Every lx-only member throws a [SingBoxUnsupportedException] ("requires
/// the sing-box-lx core") when the app links the standard core.
class SingBoxExtended extends SingBox {
  SingBoxExtended._() : super._();

  /// The single instance of the plugin API ([SingBox.instance]).
  static SingBoxExtended get instance => SingBox.instance as SingBoxExtended;
}
