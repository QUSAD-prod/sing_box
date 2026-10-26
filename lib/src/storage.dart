import 'dart:convert';

import '../sing_box_platform_interface.dart';

/// JSON persistence on top of the native key/value store
/// (`SharedPreferences` on Android, app-group `UserDefaults` on iOS).
class SingBoxStorage {
  /// Creates a storage using [platform] (resolved lazily so tests can swap
  /// `SingBoxPlatform.instance`).
  SingBoxStorage([SingBoxPlatform Function()? platform])
    : _platform = platform ?? (() => SingBoxPlatform.instance);

  final SingBoxPlatform Function() _platform;

  /// Key of the persisted `SingBoxSettings`.
  static const keySettings = 'sing_box.settings';

  /// Key of the persisted `SingBoxRoutingRules`.
  static const keyRoutingRules = 'sing_box.routing_rules';

  /// Key of the persisted list of `SingBoxServerConfig`s.
  static const keyServerConfigs = 'sing_box.server_configs';

  /// Key of the active server configuration id.
  static const keyActiveServerConfig = 'sing_box.active_server_config_id';

  /// Key of the last connect input (used to re-apply rules while connected).
  static const keyLastInput = 'sing_box.last_input';

  /// Reads a raw string.
  Future<String?> readString(String key) => _platform().storageRead(key);

  /// Writes a raw string (`null` removes the key).
  Future<void> writeString(String key, String? value) =>
      _platform().storageWrite(key, value);

  /// Reads a JSON object, returning `null` when missing or corrupt.
  Future<Map<String, dynamic>?> readMap(String key) async {
    final decoded = _decode(await readString(key));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  /// Reads a JSON array, returning `null` when missing or corrupt.
  Future<List<dynamic>?> readList(String key) async {
    final decoded = _decode(await readString(key));
    return decoded is List ? decoded : null;
  }

  /// Writes [value] encoded as JSON (`null` removes the key).
  Future<void> writeJson(String key, Object? value) =>
      writeString(key, value == null ? null : jsonEncode(value));

  static Object? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
