import '../config/internal/json_utils.dart';

/// A rule-set that the plugin downloads for the routing rules and the
/// configuration then reads as a local file (see `SingBox.getRuleSets()`).
///
/// sing-box aborts the start when a remote rule-set cannot be downloaded the
/// first time, so `SingBox` downloads them itself (with jsDelivr mirrors for
/// GitHub) and leaves out the rules whose rule-sets are not available yet.
///
/// ```dart
/// for (final ruleSet in await SingBox.instance.getRuleSets()) {
///   print('${ruleSet.tag}: ${ruleSet.isAvailable ? ruleSet.updatedAt : ruleSet.lastError}');
/// }
/// ```
class SingBoxRuleSetStatus {
  /// Creates a status.
  const SingBoxRuleSetStatus({
    required this.tag,
    required this.url,
    this.path,
    this.updatedAt,
    this.size,
    this.lastError,
    this.lastAttempt,
  });

  /// Rule-set tag, e.g. `geoip-ru`.
  final String tag;

  /// Download URL (mirrors are tried when it fails).
  final String url;

  /// Absolute path of the downloaded file, or `null` when it has never been
  /// downloaded.
  final String? path;

  /// When the file was last downloaded.
  final DateTime? updatedAt;

  /// Size of the file in bytes.
  final int? size;

  /// Why the last download failed, or `null` when it succeeded.
  final String? lastError;

  /// When the last download was attempted, successful or not.
  final DateTime? lastAttempt;

  /// Whether a downloaded file is available, so the rules using the
  /// rule-set are applied.
  bool get isAvailable => path != null;

  /// Converts the status to a JSON-safe map. Dates are stored as
  /// milliseconds since the epoch.
  Map<String, dynamic> toMap() => {
    'tag': tag,
    'url': url,
    if (path != null) 'path': path,
    if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
    if (size != null) 'size': size,
    if (lastError != null) 'lastError': lastError,
    if (lastAttempt != null) 'lastAttempt': lastAttempt!.millisecondsSinceEpoch,
  };

  /// Creates a status from a map produced by [toMap], or returns `null`
  /// without a tag and URL.
  static SingBoxRuleSetStatus? tryFromMap(Map<dynamic, dynamic> map) {
    final tag = readString(map['tag']);
    final url = readString(map['url']);
    if (tag == null || url == null) return null;
    DateTime? date(Object? value) {
      final ms = readInt(value);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return SingBoxRuleSetStatus(
      tag: tag,
      url: url,
      path: readString(map['path']),
      updatedAt: date(map['updatedAt']),
      size: readInt(map['size']),
      lastError: readString(map['lastError']),
      lastAttempt: date(map['lastAttempt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxRuleSetStatus &&
      other.tag == tag &&
      other.url == url &&
      other.path == path &&
      other.updatedAt == updatedAt &&
      other.size == size &&
      other.lastError == lastError &&
      other.lastAttempt == lastAttempt;

  @override
  int get hashCode =>
      Object.hash(tag, url, path, updatedAt, size, lastError, lastAttempt);

  @override
  String toString() => 'SingBoxRuleSetStatus(${toMap()})';
}
