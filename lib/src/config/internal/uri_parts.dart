// Internal tolerant URI helpers for share links. Not exported.
//
// `Uri.parse` is too strict for real world share links (unencoded spaces,
// emoji, `|` or `%` in names, base64 `/` and `+` in user info, multi-port
// hosts like `host:443,1000-2000`), so links are split by hand.

import 'dart:convert';

/// A host and an optional port.
class HostPort {
  /// Creates a host/port pair.
  const HostPort(this.host, this.port, this.portText);

  /// Host name or IP address (IPv6 without brackets).
  final String host;

  /// Port, or `null` when absent or not a single number.
  final int? port;

  /// Raw port text (may be a list/range such as `443,1000-2000`).
  final String portText;
}

/// Splits `host`, `host:port`, `[v6]` or `[v6]:port`. An IPv6 address
/// without brackets is returned as host without port.
///
/// Throws a [FormatException] when the port is present but not a number in
/// `1..65535` and [allowPortList] is `false`.
HostPort splitHostPort(String value, {bool allowPortList = false}) {
  final input = value.trim();
  String host;
  var portText = '';
  if (input.startsWith('[')) {
    final close = input.indexOf(']');
    if (close < 0) throw FormatException('Unclosed "[" in host', value);
    host = input.substring(1, close);
    final after = input.substring(close + 1);
    if (after.startsWith(':')) {
      portText = after.substring(1);
    } else if (after.isNotEmpty) {
      throw FormatException('Unexpected text after IPv6 address', value);
    }
  } else {
    final colons = ':'.allMatches(input).length;
    if (colons == 1) {
      final colon = input.indexOf(':');
      host = input.substring(0, colon);
      portText = input.substring(colon + 1);
    } else {
      host = input;
    }
  }
  host = percentDecode(host).trim();
  if (host.endsWith('.') && host.length > 1) {
    host = host.substring(0, host.length - 1);
  }
  portText = portText.trim();
  int? port;
  if (portText.isNotEmpty) {
    port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      if (!allowPortList) {
        throw FormatException('Invalid port "$portText"', value);
      }
      port = null;
    }
  }
  return HostPort(host, port, portText);
}

/// The parts of a share link `scheme://userinfo@host:port/path?query#name`.
class LinkParts {
  LinkParts._({
    required this.scheme,
    required this.body,
    required this.userInfo,
    required this.hostPort,
    required this.path,
    required this.query,
    required this.fragment,
  });

  /// Lower case scheme without `://`.
  final String scheme;

  /// Everything between `://` and `#` (raw).
  final String body;

  /// Raw (still percent-encoded) user info, or `null` without `@`.
  final String? userInfo;

  /// Host and port.
  final HostPort hostPort;

  /// Raw path (starting with `/`), possibly empty.
  final String path;

  /// Decoded query parameters with lower case keys (first value wins).
  final Map<String, String> query;

  /// Decoded fragment (`#name`), or `null`.
  final String? fragment;

  /// Host name or address.
  String get host => hostPort.host;

  /// Port number, or `null`.
  int? get port => hostPort.port;

  /// Returns the first non-empty query value of [keys] (case-insensitive).
  String? param(List<String> keys) {
    for (final key in keys) {
      final value = query[key.toLowerCase()];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// Whether the first present query value of [keys] is truthy
  /// (`1`, `true`, `yes`, `on`).
  bool flag(List<String> keys) {
    final value = param(keys)?.toLowerCase();
    return value == '1' || value == 'true' || value == 'yes' || value == 'on';
  }
}

/// Splits [link] into [LinkParts]. With [allowPortList] the port may be a
/// list or range (Hysteria 2 port hopping).
LinkParts splitLink(String link, {bool allowPortList = false}) {
  final input = link.trim();
  final schemeEnd = input.indexOf('://');
  if (schemeEnd <= 0) throw FormatException('Missing "://" in link', link);
  final scheme = input.substring(0, schemeEnd).toLowerCase();
  var rest = input.substring(schemeEnd + 3);
  String? fragment;
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    fragment = percentDecode(rest.substring(hash + 1)).trim();
    if (fragment.isEmpty) fragment = null;
    rest = rest.substring(0, hash);
  }
  final body = rest;
  final question = rest.indexOf('?');
  final searchEnd = question < 0 ? rest.length : question;
  final at = searchEnd == 0 ? -1 : rest.lastIndexOf('@', searchEnd - 1);
  String? userInfo;
  if (at >= 0) {
    userInfo = rest.substring(0, at);
    rest = rest.substring(at + 1);
  }
  var end = rest.length;
  for (final c in const ['/', '?']) {
    final i = rest.indexOf(c);
    if (i >= 0 && i < end) end = i;
  }
  final authority = rest.substring(0, end);
  final tail = rest.substring(end);
  var path = '';
  var queryText = '';
  final q = tail.indexOf('?');
  if (q >= 0) {
    path = tail.substring(0, q);
    queryText = tail.substring(q + 1);
  } else {
    path = tail;
  }
  return LinkParts._(
    scheme: scheme,
    body: body,
    userInfo: userInfo,
    hostPort: splitHostPort(authority, allowPortList: allowPortList),
    path: path,
    query: parseQuery(queryText),
    fragment: fragment,
  );
}

/// Parses `a=1&b=2` into a map with decoded values and lower case keys.
/// The first occurrence of a key wins.
Map<String, String> parseQuery(String query) {
  final result = <String, String>{};
  for (final pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    final key = percentDecode(eq < 0 ? pair : pair.substring(0, eq));
    final value = eq < 0 ? '' : percentDecode(pair.substring(eq + 1));
    result.putIfAbsent(key.trim().toLowerCase(), () => value);
  }
  return result;
}

/// Decodes `%XX` escapes as UTF-8. Invalid escapes are kept literally and
/// `+` is kept as is (`decodeURIComponent` semantics).
String percentDecode(String value) {
  if (!value.contains('%')) return value;
  final bytes = <int>[];
  final out = StringBuffer();
  void flush() {
    if (bytes.isEmpty) return;
    out.write(utf8.decode(bytes, allowMalformed: true));
    bytes.clear();
  }

  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c == 0x25 && i + 2 < value.length) {
      final byte = int.tryParse(value.substring(i + 1, i + 3), radix: 16);
      if (byte != null) {
        bytes.add(byte);
        i += 2;
        continue;
      }
    }
    flush();
    out.writeCharCode(c);
  }
  flush();
  return out.toString();
}

/// Percent-encodes [value] for use in a share link component.
String percentEncode(String value) => Uri.encodeComponent(value);

final _base64Chars = RegExp(r'^[A-Za-z0-9+/_\-=]+$');

/// Decodes standard or URL-safe base64, padded or not, ignoring whitespace.
/// Returns `null` when [value] is not valid base64 or not valid UTF-8.
String? tryDecodeBase64(String value) {
  var compact = value.replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty || !_base64Chars.hasMatch(compact)) return null;
  compact = compact.replaceAll('-', '+').replaceAll('_', '/');
  compact = compact.replaceAll('=', '');
  if (compact.length % 4 == 1) return null;
  compact = compact.padRight((compact.length + 3) ~/ 4 * 4, '=');
  try {
    return utf8.decode(base64.decode(compact));
  } on FormatException {
    return null;
  }
}

/// Encodes [value] as URL-safe base64 without padding.
String encodeBase64UrlNoPadding(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

/// Encodes [value] as standard padded base64.
String encodeBase64(String value) => base64.encode(utf8.encode(value));

/// Formats [host] for a URL authority (brackets around IPv6).
String formatHost(String host) => host.contains(':') ? '[$host]' : host;
