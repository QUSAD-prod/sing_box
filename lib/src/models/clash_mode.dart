/// Clash routing modes available in the running configuration.
///
/// Modes come from `clash_mode` route rules plus `experimental.clash_api`
/// (configs produced by `SingBoxConfigBuilder` provide `Rule`, `Global` and
/// `Direct`). Switch with `SingBox.setClashMode()`.
class SingBoxClashMode {
  /// Creates a clash mode state.
  const SingBoxClashMode({required this.modes, required this.current});

  /// No modes available.
  static const none = SingBoxClashMode(modes: [], current: '');

  /// Parses an event of the `sing_box/clash_mode` channel.
  factory SingBoxClashMode.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxClashMode(
      modes: (map['modes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      current: map['current'] as String? ?? '',
    );
  }

  /// Available modes, e.g. `["Rule", "Global", "Direct"]`.
  final List<String> modes;

  /// The active mode.
  final String current;

  /// Whether mode switching is available.
  bool get isAvailable => modes.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is SingBoxClashMode &&
      other.current == current &&
      other.modes.length == modes.length &&
      Iterable<int>.generate(
        modes.length,
      ).every((i) => other.modes[i] == modes[i]);

  @override
  int get hashCode => Object.hash(current, Object.hashAll(modes));

  @override
  String toString() => 'SingBoxClashMode(current: $current, modes: $modes)';
}
