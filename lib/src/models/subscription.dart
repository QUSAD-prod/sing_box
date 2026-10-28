/// A subscription: a URL that returns a list of servers, stored with the
/// metadata the provider sends in its response headers.
///
/// Created and refreshed by `SingBox.addSubscription()` and
/// `SingBox.updateSubscription()`; its servers are ordinary
/// `SingBoxServerConfig`s whose `subscriptionId` is [id].
///
/// The traffic and expiry fields come from the de facto standard
/// `subscription-userinfo` header (`upload=…; download=…; total=…;
/// expire=…`) and are `null` when the provider does not send it:
///
/// ```dart
/// final sub = await SingBox.instance.addSubscription('https://example.com/sub');
/// print('${sub.name}: ${sub.serverCount} servers');
/// if (sub.total != null) print('used ${sub.used} of ${sub.total} bytes');
/// if (sub.expire != null) print('expires ${sub.expire}');
/// ```
class SingBoxSubscription {
  /// Creates a subscription.
  const SingBoxSubscription({
    required this.id,
    required this.name,
    required this.url,
    this.userAgent,
    this.headers = const {},
    this.autoUpdate = true,
    this.updateInterval,
    this.providerUpdateInterval,
    this.lastUpdated,
    this.lastError,
    this.serverCount = 0,
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.webPageUrl,
    this.supportUrl,
    this.announce,
  });

  /// How often subscriptions are refreshed when neither [updateInterval] nor
  /// the provider ([providerUpdateInterval]) set an interval.
  static const defaultUpdateInterval = Duration(hours: 24);

  /// Unique id; also the `subscriptionId` of the subscription's servers.
  final String id;

  /// Display name: given by the app, or taken from the `profile-title` or
  /// `content-disposition` response header, or the URL host.
  final String name;

  /// The subscription URL.
  final String url;

  /// `User-Agent` sent when downloading, or `null` for
  /// `SingBox.subscriptionUserAgent`. Providers often choose the format by
  /// it.
  final String? userAgent;

  /// Extra request headers sent when downloading, e.g. device identifiers
  /// some panels require (`x-hwid`).
  final Map<String, String> headers;

  /// Whether the subscription is refreshed automatically when it is older
  /// than [effectiveUpdateInterval] (see `SingBox.updateSubscriptions`).
  final bool autoUpdate;

  /// Update interval chosen by the app; overrides
  /// [providerUpdateInterval].
  final Duration? updateInterval;

  /// Update interval suggested by the provider (`profile-update-interval`
  /// header, in hours).
  final Duration? providerUpdateInterval;

  /// When the servers were last downloaded successfully.
  final DateTime? lastUpdated;

  /// Error of the last failed update, `null` after a successful one.
  final String? lastError;

  /// Number of servers imported by the last successful update.
  final int serverCount;

  /// Uploaded bytes reported by the provider.
  final int? upload;

  /// Downloaded bytes reported by the provider.
  final int? download;

  /// Traffic limit in bytes reported by the provider (`0` or `null`:
  /// unlimited or unknown).
  final int? total;

  /// When the subscription expires, if the provider reports it.
  final DateTime? expire;

  /// Provider web page (`profile-web-page-url` header).
  final String? webPageUrl;

  /// Provider support link (`support-url` header).
  final String? supportUrl;

  /// Provider announcement (`announce` header, base64 decoded).
  final String? announce;

  /// [upload] + [download], or `null` when neither is known.
  int? get used =>
      upload == null && download == null
          ? null
          : (upload ?? 0) + (download ?? 0);

  /// Bytes left before [total] is reached, or `null` when there is no
  /// limit.
  int? get remaining {
    final limit = total;
    if (limit == null || limit <= 0) return null;
    final value = limit - (used ?? 0);
    return value < 0 ? 0 : value;
  }

  /// Whether [expire] is in the past.
  bool get isExpired => expire != null && expire!.isBefore(DateTime.now());

  /// The interval used for automatic updates: [updateInterval], else
  /// [providerUpdateInterval], else [defaultUpdateInterval].
  Duration get effectiveUpdateInterval =>
      updateInterval ?? providerUpdateInterval ?? defaultUpdateInterval;

  /// Whether the subscription was never updated or is older than
  /// [effectiveUpdateInterval] at [now] (default: the current time).
  bool isStale([DateTime? now]) {
    final updated = lastUpdated;
    if (updated == null) return true;
    return !(now ?? DateTime.now()).isBefore(
      updated.add(effectiveUpdateInterval),
    );
  }

  /// Converts the subscription to a JSON-safe map. Durations are stored in
  /// seconds and dates in milliseconds since the epoch.
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'url': url,
    if (userAgent != null) 'userAgent': userAgent,
    if (headers.isNotEmpty) 'headers': Map<String, String>.of(headers),
    'autoUpdate': autoUpdate,
    if (updateInterval != null) 'updateInterval': updateInterval!.inSeconds,
    if (providerUpdateInterval != null)
      'providerUpdateInterval': providerUpdateInterval!.inSeconds,
    if (lastUpdated != null) 'lastUpdated': lastUpdated!.millisecondsSinceEpoch,
    if (lastError != null) 'lastError': lastError,
    'serverCount': serverCount,
    if (upload != null) 'upload': upload,
    if (download != null) 'download': download,
    if (total != null) 'total': total,
    if (expire != null) 'expire': expire!.millisecondsSinceEpoch,
    if (webPageUrl != null) 'webPageUrl': webPageUrl,
    if (supportUrl != null) 'supportUrl': supportUrl,
    if (announce != null) 'announce': announce,
  };

  /// Creates a subscription from a map produced by [toMap].
  ///
  /// Missing or malformed values fall back to the defaults.
  factory SingBoxSubscription.fromMap(Map<dynamic, dynamic> map) {
    final headers = map['headers'];
    return SingBoxSubscription(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      url: map['url'] as String? ?? '',
      userAgent: map['userAgent'] as String?,
      headers: {
        if (headers is Map)
          for (final e in headers.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      autoUpdate: map['autoUpdate'] as bool? ?? true,
      updateInterval: _duration(map['updateInterval']),
      providerUpdateInterval: _duration(map['providerUpdateInterval']),
      lastUpdated: _date(map['lastUpdated']),
      lastError: map['lastError'] as String?,
      serverCount: (map['serverCount'] as num?)?.toInt() ?? 0,
      upload: (map['upload'] as num?)?.toInt(),
      download: (map['download'] as num?)?.toInt(),
      total: (map['total'] as num?)?.toInt(),
      expire: _date(map['expire']),
      webPageUrl: map['webPageUrl'] as String?,
      supportUrl: map['supportUrl'] as String?,
      announce: map['announce'] as String?,
    );
  }

  static Duration? _duration(Object? seconds) =>
      seconds is num && seconds > 0 ? Duration(seconds: seconds.toInt()) : null;

  static DateTime? _date(Object? millis) =>
      millis is num && millis > 0
          ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
          : null;

  /// Returns a copy with the given fields replaced. Use [clearUpdateInterval]
  /// to remove [updateInterval] and [clearLastError] to remove [lastError].
  SingBoxSubscription copyWith({
    String? name,
    String? url,
    String? userAgent,
    Map<String, String>? headers,
    bool? autoUpdate,
    Duration? updateInterval,
    bool clearUpdateInterval = false,
    Duration? providerUpdateInterval,
    DateTime? lastUpdated,
    String? lastError,
    bool clearLastError = false,
    int? serverCount,
    int? upload,
    int? download,
    int? total,
    DateTime? expire,
    String? webPageUrl,
    String? supportUrl,
    String? announce,
  }) {
    return SingBoxSubscription(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      userAgent: userAgent ?? this.userAgent,
      headers: headers ?? this.headers,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      updateInterval:
          clearUpdateInterval ? null : updateInterval ?? this.updateInterval,
      providerUpdateInterval:
          providerUpdateInterval ?? this.providerUpdateInterval,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      serverCount: serverCount ?? this.serverCount,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      total: total ?? this.total,
      expire: expire ?? this.expire,
      webPageUrl: webPageUrl ?? this.webPageUrl,
      supportUrl: supportUrl ?? this.supportUrl,
      announce: announce ?? this.announce,
    );
  }

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  bool operator ==(Object other) =>
      other is SingBoxSubscription &&
      other.id == id &&
      other.name == name &&
      other.url == url &&
      other.userAgent == userAgent &&
      _mapEquals(other.headers, headers) &&
      other.autoUpdate == autoUpdate &&
      other.updateInterval == updateInterval &&
      other.providerUpdateInterval == providerUpdateInterval &&
      other.lastUpdated == lastUpdated &&
      other.lastError == lastError &&
      other.serverCount == serverCount &&
      other.upload == upload &&
      other.download == download &&
      other.total == total &&
      other.expire == expire &&
      other.webPageUrl == webPageUrl &&
      other.supportUrl == supportUrl &&
      other.announce == announce;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    url,
    userAgent,
    Object.hashAllUnordered(headers.entries.map((e) => '${e.key}=${e.value}')),
    autoUpdate,
    updateInterval,
    providerUpdateInterval,
    lastUpdated,
    lastError,
    serverCount,
    upload,
    download,
    total,
    expire,
    webPageUrl,
    supportUrl,
    announce,
  ]);

  @override
  String toString() => 'SingBoxSubscription($id, $name, $url)';
}
