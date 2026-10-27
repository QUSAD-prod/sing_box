// Internal share link parsers. Not exported; see SingBoxShareLink.

import 'dart:convert';

import '../../utils/validators.dart';
import '../outbound.dart';
import 'json_utils.dart';
import 'uri_parts.dart';

/// Schemes understood by [parseShareLink].
const supportedSchemes = {
  'vless',
  'vmess',
  'trojan',
  'ss',
  'hysteria2',
  'hy2',
  'hysteria',
  'tuic',
  'socks',
  'socks5',
  'socks5h',
  'socks4',
  'socks4a',
  'http',
  'https',
  'anytls',
  'wireguard',
  'wg',
};

/// Shadowsocks methods supported by the sing-box outbound.
const shadowsocksMethods = {
  'none',
  'aes-128-gcm',
  'aes-192-gcm',
  'aes-256-gcm',
  'chacha20-ietf-poly1305',
  'xchacha20-ietf-poly1305',
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
  'aes-128-ctr',
  'aes-192-ctr',
  'aes-256-ctr',
  'aes-128-cfb',
  'aes-192-cfb',
  'aes-256-cfb',
  'rc4-md5',
  'chacha20-ietf',
  'xchacha20',
};

const _shadowsocksMethodAliases = {
  'chacha20-poly1305': 'chacha20-ietf-poly1305',
  'xchacha20-poly1305': 'xchacha20-ietf-poly1305',
  'plain': 'none',
};

/// uTLS fingerprints accepted by sing-box.
const utlsFingerprints = {
  'chrome',
  'chrome_psk',
  'chrome_psk_shuffle',
  'chrome_padding_psk_shuffle',
  'chrome_pq',
  'chrome_pq_psk',
  'firefox',
  'edge',
  'safari',
  '360',
  'qq',
  'ios',
  'android',
  'random',
  'randomized',
};

/// Returns the lower case scheme of [link] or `null`.
String? schemeOf(String link) {
  final trimmed = link.trim();
  final end = trimmed.indexOf('://');
  if (end <= 0) return null;
  return trimmed.substring(0, end).toLowerCase();
}

/// Parses a share link. Throws [FormatException] with a descriptive
/// message when the link is malformed or unsupported.
SingBoxOutbound parseShareLink(String link, {String? tag}) {
  final trimmed = link.trim();
  if (trimmed.isEmpty) throw const FormatException('Share link is empty');
  final scheme = schemeOf(trimmed);
  if (scheme == null) {
    throw FormatException('Not a share link (missing "scheme://")', link);
  }
  final _Parsed parsed;
  switch (scheme) {
    case 'vless':
      parsed = _vless(trimmed);
    case 'vmess':
      parsed = _vmess(trimmed);
    case 'trojan':
      parsed = _trojan(trimmed);
    case 'ss':
      parsed = _shadowsocks(trimmed);
    case 'hysteria2' || 'hy2':
      parsed = _hysteria2(trimmed);
    case 'hysteria':
      parsed = _hysteria(trimmed);
    case 'tuic':
      parsed = _tuic(trimmed);
    case 'socks' || 'socks5' || 'socks5h' || 'socks4' || 'socks4a':
      parsed = _socks(trimmed, scheme);
    case 'http' || 'https':
      parsed = _http(trimmed, scheme);
    case 'anytls':
      parsed = _anytls(trimmed);
    case 'wireguard' || 'wg':
      parsed = _wireguard(trimmed);
    case 'ssr':
      throw FormatException('ShadowsocksR is not supported by sing-box', link);
    case 'vmess+ws' || 'naive+https' || 'naive+quic':
      throw FormatException('Unsupported share link scheme "$scheme"', link);
    default:
      throw FormatException('Unsupported share link scheme "$scheme"', link);
  }
  final resolvedTag = _nonEmpty(tag) ?? parsed.name ?? parsed.defaultTag;
  final json = <String, dynamic>{
    'type': parsed.json['type'],
    'tag': resolvedTag,
    for (final entry in parsed.json.entries)
      if (entry.key != 'type' && entry.key != 'tag') entry.key: entry.value,
  };
  return SingBoxOutbound.fromJson(json, name: parsed.name, link: trimmed);
}

class _Parsed {
  _Parsed(this.json, this.name, String host, int? port)
    : defaultTag = '${json['type']}-$host${port == null ? '' : '-$port'}';

  final Map<String, dynamic> json;
  final String? name;
  final String defaultTag;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _requireHost(String host, String link) {
  final h = host.trim();
  if (h.isEmpty) {
    throw FormatException('Share link has no server address', link);
  }
  if (h.contains(RegExp(r'[\s/\\?#@]'))) {
    throw FormatException('Invalid server address "$h"', link);
  }
  final ascii = !h.codeUnits.any((c) => c > 0x7f);
  if (ascii &&
      !SingBoxValidators.isIp(h) &&
      !SingBoxValidators.isDomain(h) &&
      !h.contains(':')) {
    throw FormatException('Invalid server address "$h"', link);
  }
  if (h.contains(':') && !SingBoxValidators.isIpv6(h)) {
    throw FormatException('Invalid IPv6 server address "$h"', link);
  }
  return h;
}

int _port(int? port, int fallback) => port ?? fallback;

List<String> _splitList(String? value) => [
  for (final item in (value ?? '').split(','))
    if (item.trim().isNotEmpty) item.trim(),
];

/// Normalizes a share link `fp` value to a sing-box uTLS fingerprint.
String? normalizeFingerprint(String? value) {
  final fp = value?.trim().toLowerCase();
  if (fp == null || fp.isEmpty || fp == 'none' || fp == 'disable') return null;
  if (utlsFingerprints.contains(fp)) return fp;
  if (fp.startsWith('randomized')) return 'randomized';
  if (fp.startsWith('random')) return 'random';
  if (fp.startsWith('chrome')) return 'chrome';
  if (fp.startsWith('firefox')) return 'firefox';
  if (fp.startsWith('safari')) return 'safari';
  if (fp.startsWith('edge')) return 'edge';
  return 'chrome';
}

/// Builds the sing-box `tls` object of a V2Ray style link.
Map<String, dynamic>? buildTls({
  required String security,
  required String link,
  String? sni,
  String? fallbackSni,
  List<String> alpn = const [],
  String? fingerprint,
  bool insecure = false,
  String? publicKey,
  String? shortId,
  bool disableSni = false,
}) {
  switch (security) {
    case '' || 'none':
      return null;
    case 'tls' || 'xtls' || 'reality':
      break;
    default:
      throw FormatException('Unsupported security "$security"', link);
  }
  final reality = security == 'reality';
  var serverName = _nonEmpty(sni);
  if (serverName == null) {
    final fallback = _nonEmpty(fallbackSni);
    if (fallback != null && SingBoxValidators.isDomain(fallback)) {
      serverName = fallback;
    }
  }
  var fp = normalizeFingerprint(fingerprint);
  if (reality) {
    if (_nonEmpty(publicKey) == null) {
      throw FormatException('REALITY link has no public key (pbk)', link);
    }
    fp ??= 'chrome';
  }
  return {
    'enabled': true,
    'server_name': ?serverName,
    if (disableSni) 'disable_sni': true,
    if (insecure && !reality) 'insecure': true,
    if (alpn.isNotEmpty) 'alpn': alpn,
    if (fp != null) 'utls': {'enabled': true, 'fingerprint': fp},
    if (reality)
      'reality': {
        'enabled': true,
        'public_key': publicKey!.trim(),
        if (_nonEmpty(shortId) != null) 'short_id': shortId!.trim(),
      },
  };
}

/// Builds the sing-box `transport` object of a V2Ray style link.
Map<String, dynamic>? buildTransport({
  required String network,
  required String link,
  String? host,
  String? path,
  String? serviceName,
  String? headerType,
  String? earlyData,
}) {
  final hostValue = _nonEmpty(host);
  var pathValue = _nonEmpty(path);
  switch (network.trim().toLowerCase()) {
    case '' || 'tcp' || 'raw' || 'none':
      if (headerType?.trim().toLowerCase() == 'http') {
        return {
          'type': 'http',
          if (hostValue != null) 'host': _splitList(hostValue),
          'path': pathValue ?? '/',
          'method': 'GET',
        };
      }
      return null;
    case 'ws' || 'websocket':
      var maxEarlyData = int.tryParse(earlyData ?? '');
      if (pathValue != null && pathValue.contains('?')) {
        final q = pathValue.indexOf('?');
        final params = parseQuery(pathValue.substring(q + 1));
        final ed = int.tryParse(params['ed'] ?? '');
        if (ed != null) {
          maxEarlyData ??= ed;
          final remaining = pathValue
              .substring(q + 1)
              .split('&')
              .where((p) => p.isNotEmpty && !p.toLowerCase().startsWith('ed='))
              .join('&');
          pathValue = _nonEmpty(
            pathValue.substring(0, q) +
                (remaining.isEmpty ? '' : '?$remaining'),
          );
        }
      }
      return {
        'type': 'ws',
        'path': ?pathValue,
        if (hostValue != null) 'headers': {'Host': hostValue},
        if (maxEarlyData != null && maxEarlyData > 0) ...{
          'max_early_data': maxEarlyData,
          'early_data_header_name': 'Sec-WebSocket-Protocol',
        },
      };
    case 'grpc' || 'gun':
      var name = _nonEmpty(serviceName) ?? pathValue;
      if (name != null && name.startsWith('/')) name = name.substring(1);
      return {
        'type': 'grpc',
        if (_nonEmpty(name) != null) 'service_name': name,
      };
    case 'http' || 'h2':
      return {
        'type': 'http',
        if (hostValue != null) 'host': _splitList(hostValue),
        'path': ?pathValue,
      };
    case 'httpupgrade':
      return {'type': 'httpupgrade', 'host': ?hostValue, 'path': ?pathValue};
    case 'quic':
      return {'type': 'quic'};
    case 'xhttp' || 'splithttp':
      throw FormatException(
        'XHTTP transport is not supported by sing-box',
        link,
      );
    case 'kcp' || 'mkcp':
      throw FormatException(
        'mKCP transport is not supported by sing-box',
        link,
      );
    default:
      throw FormatException('Unsupported transport "$network"', link);
  }
}

String? _flow(String? value, Map<String, dynamic>? transport, String link) {
  final flow = value?.trim().toLowerCase();
  if (flow == null || flow.isEmpty || flow == 'none') return null;
  if (flow == 'xtls-rprx-vision' || flow == 'xtls-rprx-vision-udp443') {
    // Vision only works on raw TCP (no V2Ray transport).
    return transport == null ? 'xtls-rprx-vision' : null;
  }
  throw FormatException('Unsupported VLESS flow "$value"', link);
}

String? _packetEncoding(String? value) {
  final encoding = value?.trim().toLowerCase();
  switch (encoding) {
    case 'xudp' || 'packetaddr':
      return encoding;
    case 'none':
      return '';
  }
  return null;
}

// --- VLESS / Trojan --------------------------------------------------------

_Parsed _vless(String link) {
  final p = splitLink(link);
  final uuid = percentDecode(p.userInfo ?? '').trim();
  if (uuid.isEmpty) throw FormatException('VLESS link has no UUID', link);
  final host = _requireHost(p.host, link);
  final port = _port(p.port, 443);
  final encryption = p.param(['encryption'])?.toLowerCase();
  if (encryption != null && encryption != 'none') {
    throw FormatException(
      'VLESS encryption "$encryption" is not supported by sing-box',
      link,
    );
  }
  final transport = _transportFromParams(p, link);
  final security = (p.param(['security']) ?? 'none').toLowerCase();
  final tls = _tlsFromParams(p, security, link);
  final flow = _flow(p.param(['flow']), transport, link);
  final encoding = _packetEncoding(p.param(['packetencoding']));
  return _Parsed(
    {
      'type': 'vless',
      'server': host,
      'server_port': port,
      'uuid': uuid,
      'flow': ?flow,
      'packet_encoding': ?encoding,
      'tls': ?tls,
      'transport': ?transport,
    },
    p.fragment,
    host,
    port,
  );
}

_Parsed _trojan(String link) {
  final p = splitLink(link);
  final password = percentDecode(p.userInfo ?? '');
  if (password.isEmpty) {
    throw FormatException('Trojan link has no password', link);
  }
  final host = _requireHost(p.host, link);
  final port = _port(p.port, 443);
  final transport = _transportFromParams(p, link);
  final security = (p.param(['security']) ?? 'tls').toLowerCase();
  final tls = _tlsFromParams(p, security, link);
  return _Parsed(
    {
      'type': 'trojan',
      'server': host,
      'server_port': port,
      'password': password,
      'tls': ?tls,
      'transport': ?transport,
    },
    p.fragment,
    host,
    port,
  );
}

Map<String, dynamic>? _transportFromParams(LinkParts p, String link) {
  return buildTransport(
    network: p.param(['type', 'network', 'net']) ?? 'tcp',
    link: link,
    host: p.param(['host']),
    path: p.param(['path']),
    serviceName: p.param(['servicename', 'service_name']),
    headerType: p.param(['headertype', 'header_type']),
    earlyData: p.param(['ed']),
  );
}

Map<String, dynamic>? _tlsFromParams(
  LinkParts p,
  String security,
  String link,
) {
  return buildTls(
    security: security,
    link: link,
    sni: p.param(['sni', 'peer', 'servername', 'server_name']),
    fallbackSni: p.param(['host']),
    alpn: _splitList(p.param(['alpn'])),
    fingerprint: p.param(['fp', 'fingerprint']),
    insecure: p.flag(['allowinsecure', 'insecure', 'skip-cert-verify']),
    publicKey: p.param(['pbk', 'publickey', 'public_key']),
    shortId: p.param(['sid', 'shortid', 'short_id']),
  );
}

// --- VMess -----------------------------------------------------------------

_Parsed _vmess(String link) {
  var body = link.substring(link.indexOf('://') + 3);
  String? fragment;
  final hash = body.indexOf('#');
  if (hash >= 0) {
    fragment = _nonEmpty(percentDecode(body.substring(hash + 1)));
    body = body.substring(0, hash);
  }
  final question = body.indexOf('?');
  final encoded = question >= 0 ? body.substring(0, question) : body;
  final decoded = tryDecodeBase64(percentDecode(encoded));
  if (decoded != null) {
    final text = decoded.trim();
    if (text.startsWith('{')) return _vmessJson(text, fragment, link);
    if (RegExp(r'^[^:@\s]+:[^@\s]+@\S+$').hasMatch(text)) {
      return _vmessShadowrocket(
        text,
        question >= 0 ? body.substring(question + 1) : '',
        fragment,
        link,
      );
    }
  }
  if (!body.contains('@')) {
    throw FormatException('Malformed VMess link', link);
  }
  // Xray standard format: vmess://uuid@host:port?type=ws&security=tls#name
  final p = splitLink(link);
  final uuid = percentDecode(p.userInfo ?? '').trim();
  if (uuid.isEmpty) throw FormatException('VMess link has no UUID', link);
  final host = _requireHost(p.host, link);
  final port = _port(p.port, 443);
  final transport = _transportFromParams(p, link);
  final tls = _tlsFromParams(
    p,
    (p.param(['security']) ?? 'none').toLowerCase(),
    link,
  );
  return _Parsed(
    {
      'type': 'vmess',
      'server': host,
      'server_port': port,
      'uuid': uuid,
      'security': _vmessSecurity(p.param(['encryption', 'scy'])),
      'alter_id': ?_positive(readInt(p.param(['alterid', 'aid']))),
      'packet_encoding': ?_nonEmpty(
        _packetEncoding(p.param(['packetencoding'])),
      ),
      'tls': ?tls,
      'transport': ?transport,
    },
    p.fragment,
    host,
    port,
  );
}

int? _positive(int? value) => value != null && value > 0 ? value : null;

String _vmessSecurity(String? value) {
  final security = value?.trim().toLowerCase();
  const known = {
    'auto',
    'none',
    'zero',
    'aes-128-cfb',
    'aes-128-gcm',
    'chacha20-poly1305',
  };
  return security != null && known.contains(security) ? security : 'auto';
}

_Parsed _vmessJson(String text, String? fragment, String link) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw FormatException('Malformed VMess JSON', link);
  }
  if (decoded is! Map) throw FormatException('Malformed VMess JSON', link);
  final map = decoded;
  final host = _requireHost(readString(map['add']) ?? '', link);
  final port = readInt(map['port']) ?? 443;
  if (port < 1 || port > 65535) {
    throw FormatException('Invalid VMess port ${map['port']}', link);
  }
  final uuid = readString(map['id']);
  if (uuid == null) throw FormatException('VMess link has no UUID', link);
  final net = (readString(map['net']) ?? 'tcp').toLowerCase();
  final transport = buildTransport(
    network: net,
    link: link,
    host: readString(map['host']),
    path: readString(map['path']),
    serviceName: net == 'grpc' ? readString(map['path']) : null,
    headerType: readString(map['type']),
  );
  final tlsValue = (readString(map['tls']) ?? '').toLowerCase();
  final tls = buildTls(
    security: tlsValue == 'tls' || tlsValue == '1' || tlsValue == 'true'
        ? 'tls'
        : 'none',
    link: link,
    sni: readString(map['sni']) ?? readString(map['peer']),
    fallbackSni: readString(map['host']),
    alpn: _splitList(readString(map['alpn'])),
    fingerprint: readString(map['fp']),
    insecure:
        readBool(map['allowInsecure']) ??
        readBool(map['insecure']) ??
        readBool(map['skip-cert-verify']) ??
        false,
  );
  final name = _nonEmpty(readString(map['ps'])) ?? fragment;
  return _Parsed(
    {
      'type': 'vmess',
      'server': host,
      'server_port': port,
      'uuid': uuid,
      'security': _vmessSecurity(readString(map['scy'])),
      'alter_id': ?_positive(readInt(map['aid'])),
      'tls': ?tls,
      'transport': ?transport,
    },
    name,
    host,
    port,
  );
}

/// Shadowrocket style: `vmess://base64(security:uuid@host:port)?remarks=…`.
_Parsed _vmessShadowrocket(
  String decoded,
  String query,
  String? fragment,
  String link,
) {
  final at = decoded.lastIndexOf('@');
  final userInfo = decoded.substring(0, at);
  final colon = userInfo.indexOf(':');
  final security = userInfo.substring(0, colon);
  final uuid = userInfo.substring(colon + 1);
  final hostPort = splitHostPort(decoded.substring(at + 1));
  final host = _requireHost(hostPort.host, link);
  final port = _port(hostPort.port, 443);
  final params = parseQuery(query);
  final obfs = (params['obfs'] ?? 'none').toLowerCase();
  var obfsHost = params['obfsparam'];
  if (obfsHost != null && obfsHost.trim().startsWith('{')) {
    try {
      final headers = jsonDecode(obfsHost);
      obfsHost = headers is Map ? readString(headers['Host']) : null;
    } on FormatException {
      obfsHost = null;
    }
  }
  final transport = buildTransport(
    network: switch (obfs) {
      'websocket' || 'ws' => 'ws',
      'h2' || 'http2' => 'http',
      'grpc' => 'grpc',
      'http' => 'tcp',
      _ => 'tcp',
    },
    link: link,
    host: obfsHost,
    path: params['path'],
    serviceName: params['path'],
    headerType: obfs == 'http' ? 'http' : null,
  );
  final tls = buildTls(
    security: readBool(params['tls']) ?? false ? 'tls' : 'none',
    link: link,
    sni: params['peer'] ?? params['sni'],
    fallbackSni: obfsHost,
    alpn: _splitList(params['alpn']),
    insecure: readBool(params['allowinsecure']) ?? false,
  );
  return _Parsed(
    {
      'type': 'vmess',
      'server': host,
      'server_port': port,
      'uuid': uuid,
      'security': _vmessSecurity(security),
      'alter_id': ?_positive(readInt(params['alterid'])),
      'tls': ?tls,
      'transport': ?transport,
    },
    _nonEmpty(params['remarks']) ?? fragment,
    host,
    port,
  );
}

// --- Shadowsocks -----------------------------------------------------------

_Parsed _shadowsocks(String link) {
  var body = link.substring(link.indexOf('://') + 3);
  String? fragment;
  final hash = body.indexOf('#');
  if (hash >= 0) {
    fragment = _nonEmpty(percentDecode(body.substring(hash + 1)));
    body = body.substring(0, hash);
  }
  final question = body.indexOf('?');
  final beforeQuery = question >= 0 ? body.substring(0, question) : body;
  final query = question >= 0 ? body.substring(question + 1) : '';
  String method;
  String password;
  HostPort hostPort;
  if (!beforeQuery.contains('@')) {
    // Legacy: ss://base64(method:password@host:port)#name
    var encoded = beforeQuery;
    if (encoded.endsWith('/')) {
      encoded = encoded.substring(0, encoded.length - 1);
    }
    final decoded = tryDecodeBase64(percentDecode(encoded));
    if (decoded == null || !decoded.contains('@')) {
      throw FormatException('Malformed Shadowsocks link', link);
    }
    final at = decoded.lastIndexOf('@');
    final credentials = decoded.substring(0, at);
    final colon = credentials.indexOf(':');
    if (colon <= 0) throw FormatException('Malformed Shadowsocks link', link);
    method = credentials.substring(0, colon);
    password = credentials.substring(colon + 1);
    hostPort = splitHostPort(decoded.substring(at + 1).trim());
  } else {
    final at = beforeQuery.lastIndexOf('@');
    final userInfo = beforeQuery.substring(0, at);
    var authority = beforeQuery.substring(at + 1);
    final slash = authority.indexOf('/');
    if (slash >= 0) authority = authority.substring(0, slash);
    hostPort = splitHostPort(authority);
    final plain = percentDecode(userInfo);
    String credentials;
    if (plain.contains(':')) {
      credentials = plain;
    } else {
      final decoded = tryDecodeBase64(plain);
      if (decoded == null || !decoded.contains(':')) {
        throw FormatException('Malformed Shadowsocks user info', link);
      }
      credentials = decoded;
    }
    final colon = credentials.indexOf(':');
    method = credentials.substring(0, colon);
    password = credentials.substring(colon + 1);
  }
  method = method.trim().toLowerCase();
  method = _shadowsocksMethodAliases[method] ?? method;
  if (!shadowsocksMethods.contains(method)) {
    throw FormatException(
      'Shadowsocks method "$method" is not supported by sing-box',
      link,
    );
  }
  if (password.isEmpty && method != 'none') {
    throw FormatException('Shadowsocks link has no password', link);
  }
  final host = _requireHost(hostPort.host, link);
  final port = hostPort.port;
  if (port == null) throw FormatException('Shadowsocks link has no port', link);
  final params = parseQuery(query);
  String? plugin;
  String? pluginOpts;
  final pluginValue = _nonEmpty(params['plugin']);
  if (pluginValue != null) {
    final semicolon = pluginValue.indexOf(';');
    plugin = (semicolon < 0 ? pluginValue : pluginValue.substring(0, semicolon))
        .trim()
        .toLowerCase();
    pluginOpts = semicolon < 0 ? null : pluginValue.substring(semicolon + 1);
    if (plugin == 'simple-obfs') plugin = 'obfs-local';
    if (plugin != 'obfs-local' && plugin != 'v2ray-plugin') {
      throw FormatException(
        'Shadowsocks plugin "$plugin" is not supported by sing-box',
        link,
      );
    }
  }
  final uot = readBool(params['uot']) ?? readBool(params['udp-over-tcp']);
  return _Parsed(
    {
      'type': 'shadowsocks',
      'server': host,
      'server_port': port,
      'method': method,
      'password': password,
      'plugin': ?plugin,
      'plugin_opts': ?_nonEmpty(pluginOpts),
      if (uot == true) 'udp_over_tcp': true,
    },
    fragment,
    host,
    port,
  );
}

// --- Hysteria 2 / Hysteria -------------------------------------------------

/// Converts `1000-2000,3000` (share link syntax) to sing-box `server_ports`
/// (`["1000:2000", "3000:3000"]`). Throws [FormatException] on bad input.
List<String> parsePortRanges(String value, String link) {
  final result = <String>[];
  for (final raw in value.split(RegExp('[,/]'))) {
    final item = raw.trim();
    if (item.isEmpty) continue;
    final parts = item.split(RegExp('[-:]'));
    final start = int.tryParse(parts.first.trim());
    final end = parts.length > 1 ? int.tryParse(parts[1].trim()) : start;
    if (parts.length > 2 ||
        start == null ||
        end == null ||
        start < 1 ||
        end > 65535 ||
        start > end) {
      throw FormatException('Invalid port range "$item"', link);
    }
    result.add('$start:$end');
  }
  return result;
}

bool _portCovered(int port, List<String> ranges) => ranges.any((range) {
  final parts = range.split(':');
  return port >= int.parse(parts[0]) && port <= int.parse(parts[1]);
});

int? _mbps(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^\s*(\d+)').firstMatch(value);
  final number = match == null ? null : int.tryParse(match.group(1)!);
  return number != null && number > 0 ? number : null;
}

String? _durationParam(String? value) {
  final v = _nonEmpty(value);
  if (v == null) return null;
  if (RegExp(r'^\d+$').hasMatch(v)) return '${v}s';
  return RegExp(r'^\d+(ms|s|m|h)$').hasMatch(v) ? v : null;
}

_Parsed _hysteria2(String link) {
  final p = splitLink(link, allowPortList: true);
  var password = percentDecode(p.userInfo ?? '');
  if (password.isEmpty) password = p.param(['auth', 'password']) ?? '';
  final host = _requireHost(p.host, link);
  List<String>? ports;
  int? port = p.port;
  if (p.port == null && p.hostPort.portText.isNotEmpty) {
    ports = parsePortRanges(p.hostPort.portText, link);
  }
  final mport = p.param(['mport', 'ports']);
  if (mport != null) {
    ports = [...?ports, ...parsePortRanges(mport, link)];
    if (port != null && !_portCovered(port, ports)) ports.add('$port:$port');
  }
  port ??= ports == null ? 443 : int.parse(ports.first.split(':').first);
  final obfsType = p.param(['obfs'])?.toLowerCase();
  Map<String, dynamic>? obfs;
  if (obfsType != null && obfsType != 'none' && obfsType != 'plain') {
    if (obfsType != 'salamander') {
      throw FormatException('Unsupported Hysteria 2 obfs "$obfsType"', link);
    }
    obfs = {
      'type': 'salamander',
      'password':
          p.param(['obfs-password', 'obfs_password', 'obfspassword']) ?? '',
    };
  }
  final tls = buildTls(
    security: 'tls',
    link: link,
    sni: p.param(['sni', 'peer']),
    alpn: _splitList(p.param(['alpn'])),
    insecure: p.flag(['insecure', 'allowinsecure', 'skip-cert-verify']),
  );
  return _Parsed(
    {
      'type': 'hysteria2',
      'server': host,
      if (ports == null) 'server_port': port,
      'server_ports': ?ports,
      'hop_interval': ?_durationParam(p.param(['hop_interval', 'hopinterval'])),
      'up_mbps': ?_mbps(p.param(['upmbps', 'up', 'up_mbps'])),
      'down_mbps': ?_mbps(p.param(['downmbps', 'down', 'down_mbps'])),
      'obfs': ?obfs,
      'password': password,
      'tls': ?tls,
    },
    p.fragment,
    host,
    port,
  );
}

_Parsed _hysteria(String link) {
  final p = splitLink(link, allowPortList: true);
  final host = _requireHost(p.host, link);
  List<String>? ports;
  var port = p.port;
  if (port == null && p.hostPort.portText.isNotEmpty) {
    ports = parsePortRanges(p.hostPort.portText, link);
  }
  final mport = p.param(['mport', 'ports']);
  if (mport != null) {
    ports = [...?ports, ...parsePortRanges(mport, link)];
    if (port != null && !_portCovered(port, ports)) ports.add('$port:$port');
  }
  port ??= ports == null ? 443 : int.parse(ports.first.split(':').first);
  final protocol = (p.param(['protocol']) ?? 'udp').toLowerCase();
  if (protocol != 'udp') {
    throw FormatException(
      'Hysteria protocol "$protocol" is not supported by sing-box',
      link,
    );
  }
  final obfs = p.param(['obfsparam', 'obfs-password', 'obfs_password']);
  final auth =
      p.param(['auth', 'auth_str']) ??
      _nonEmpty(percentDecode(p.userInfo ?? ''));
  final tls = buildTls(
    security: 'tls',
    link: link,
    sni: p.param(['peer', 'sni']),
    alpn: _splitList(p.param(['alpn'])),
    insecure: p.flag(['insecure', 'allowinsecure']),
  );
  return _Parsed(
    {
      'type': 'hysteria',
      'server': host,
      if (ports == null) 'server_port': port,
      'server_ports': ?ports,
      'up_mbps': _mbps(p.param(['upmbps', 'up', 'up_mbps'])) ?? 10,
      'down_mbps': _mbps(p.param(['downmbps', 'down', 'down_mbps'])) ?? 50,
      'obfs': ?obfs,
      'auth_str': ?auth,
      'tls': ?tls,
    },
    p.fragment,
    host,
    port,
  );
}

// --- TUIC ------------------------------------------------------------------

_Parsed _tuic(String link) {
  final p = splitLink(link);
  final userInfo = p.userInfo ?? '';
  final colon = userInfo.indexOf(':');
  final uuid = percentDecode(
    colon < 0 ? userInfo : userInfo.substring(0, colon),
  );
  var password = colon < 0 ? '' : percentDecode(userInfo.substring(colon + 1));
  if (password.isEmpty) password = p.param(['password']) ?? '';
  if (uuid.trim().isEmpty) throw FormatException('TUIC link has no UUID', link);
  if (password.isEmpty) {
    throw FormatException(
      'TUIC link has no password (TUIC v4 is not supported by sing-box)',
      link,
    );
  }
  final host = _requireHost(p.host, link);
  final port = _port(p.port, 443);
  final congestion = p.param([
    'congestion_control',
    'congestion-control',
    'congestion',
  ])?.toLowerCase();
  final relay = p.param(['udp_relay_mode', 'udp-relay-mode'])?.toLowerCase();
  final alpn = _splitList(p.param(['alpn']));
  final tls = buildTls(
    security: 'tls',
    link: link,
    sni: p.param(['sni', 'peer']),
    alpn: alpn.isEmpty ? const ['h3'] : alpn,
    insecure: p.flag(['allow_insecure', 'allowinsecure', 'insecure']),
    disableSni: p.flag(['disable_sni', 'disable-sni']),
  );
  return _Parsed(
    {
      'type': 'tuic',
      'server': host,
      'server_port': port,
      'uuid': uuid.trim(),
      'password': password,
      if (congestion == 'cubic' ||
          congestion == 'new_reno' ||
          congestion == 'bbr')
        'congestion_control': congestion,
      if (relay == 'native' || relay == 'quic') 'udp_relay_mode': relay,
      if (p.flag(['reduce_rtt', 'zero_rtt_handshake']))
        'zero_rtt_handshake': true,
      'tls': ?tls,
    },
    p.fragment,
    host,
    port,
  );
}

// --- SOCKS / HTTP ----------------------------------------------------------

(String?, String?) _credentials(String? userInfo) {
  if (userInfo == null || userInfo.isEmpty) return (null, null);
  var plain = percentDecode(userInfo);
  if (!plain.contains(':')) {
    final decoded = tryDecodeBase64(plain);
    if (decoded != null && decoded.contains(':')) plain = decoded;
  }
  final colon = plain.indexOf(':');
  if (colon < 0) return (_nonEmpty(plain), null);
  return (
    _nonEmpty(plain.substring(0, colon)),
    _nonEmpty(plain.substring(colon + 1)),
  );
}

_Parsed _socks(String link, String scheme) {
  var effective = link;
  final body = link.substring(link.indexOf('://') + 3);
  final beforeHash = body.split('#').first;
  if (!beforeHash.contains('@')) {
    // v2rayN legacy: socks://base64(user:pass@host:port)#name
    final decoded = tryDecodeBase64(percentDecode(beforeHash));
    if (decoded != null && decoded.contains('@')) {
      final hash = body.indexOf('#');
      effective = '$scheme://$decoded${hash >= 0 ? body.substring(hash) : ''}';
    }
  }
  final p = splitLink(effective);
  final host = _requireHost(p.host, link);
  final port = _port(p.port, 1080);
  final (username, password) = _credentials(p.userInfo);
  final version = switch (scheme) {
    'socks4' => '4',
    'socks4a' => '4a',
    _ => '5',
  };
  return _Parsed(
    {
      'type': 'socks',
      'server': host,
      'server_port': port,
      if (version != '5') 'version': version,
      'username': ?username,
      'password': ?password,
    },
    p.fragment,
    host,
    port,
  );
}

_Parsed _http(String link, String scheme) {
  final p = splitLink(link);
  if (p.path.isNotEmpty && p.path != '/') {
    throw FormatException(
      'Looks like a web address, not an HTTP proxy link',
      link,
    );
  }
  final host = _requireHost(p.host, link);
  final secure = scheme == 'https';
  final port = _port(p.port, secure ? 443 : 80);
  final (username, password) = _credentials(p.userInfo);
  final tls = secure
      ? buildTls(
          security: 'tls',
          link: link,
          sni: p.param(['sni', 'peer']),
          fallbackSni: host,
          insecure: p.flag(['insecure', 'allowinsecure', 'skip-cert-verify']),
        )
      : null;
  return _Parsed(
    {
      'type': 'http',
      'server': host,
      'server_port': port,
      'username': ?username,
      'password': ?password,
      'tls': ?tls,
    },
    p.fragment,
    host,
    port,
  );
}

// --- AnyTLS ----------------------------------------------------------------

_Parsed _anytls(String link) {
  final p = splitLink(link);
  final password = percentDecode(p.userInfo ?? '');
  if (password.isEmpty) {
    throw FormatException('AnyTLS link has no password', link);
  }
  final host = _requireHost(p.host, link);
  final port = _port(p.port, 443);
  final tls = buildTls(
    security: (p.param(['security']) ?? 'tls').toLowerCase() == 'reality'
        ? 'reality'
        : 'tls',
    link: link,
    sni: p.param(['sni', 'peer']),
    alpn: _splitList(p.param(['alpn'])),
    fingerprint: p.param(['fp']),
    insecure: p.flag(['insecure', 'allowinsecure']),
    publicKey: p.param(['pbk']),
    shortId: p.param(['sid']),
  );
  return _Parsed(
    {
      'type': 'anytls',
      'server': host,
      'server_port': port,
      'password': password,
      'tls': ?tls,
    },
    p.fragment,
    host,
    port,
  );
}

// --- WireGuard -------------------------------------------------------------

String? _normalizePrefix(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  return SingBoxValidators.normalizeCidr(v);
}

List<int>? _reserved(String? value) {
  final v = _nonEmpty(value);
  if (v == null) return null;
  if (v.contains(',') || RegExp(r'^\d+$').hasMatch(v)) {
    final bytes = [for (final s in v.split(',')) int.tryParse(s.trim())];
    if (bytes.length == 3 &&
        bytes.every((b) => b != null && b >= 0 && b < 256)) {
      return bytes.cast<int>();
    }
    return null;
  }
  try {
    final decoded = base64.decode(base64.normalize(v));
    return decoded.length == 3 ? decoded.toList() : null;
  } on FormatException {
    return null;
  }
}

_Parsed _wireguard(String link) {
  final p = splitLink(link);
  final privateKey =
      _nonEmpty(percentDecode(p.userInfo ?? '')) ??
      p.param(['privatekey', 'private_key', 'secretkey', 'secret_key', 'pk']);
  if (privateKey == null) {
    throw FormatException('WireGuard link has no private key', link);
  }
  final publicKey = p.param([
    'publickey',
    'public_key',
    'peer_pk',
    'peer_public_key',
    'peerpublickey',
    'pbk',
  ]);
  if (publicKey == null) {
    throw FormatException('WireGuard link has no peer public key', link);
  }
  final addresses = [
    for (final a in _splitList(
      p.param(['address', 'local_address', 'localaddress', 'ip', 'addresses']),
    ))
      if (_normalizePrefix(a) case final String prefix) prefix,
  ];
  if (addresses.isEmpty) {
    throw FormatException('WireGuard link has no local address', link);
  }
  final host = _requireHost(p.host, link);
  final port = _port(p.port, 51820);
  final allowed = [
    for (final a in _splitList(p.param(['allowedips', 'allowed_ips'])))
      if (_normalizePrefix(a) case final String prefix) prefix,
  ];
  final keepalive = readInt(
    p.param(['keepalive', 'persistent_keepalive', 'persistentkeepalive']),
  );
  final mtu = readInt(p.param(['mtu']));
  return _Parsed(
    {
      'type': 'wireguard',
      if (mtu != null && mtu > 0) 'mtu': mtu,
      'address': addresses,
      'private_key': privateKey,
      'peers': [
        {
          'address': host,
          'port': port,
          'public_key': publicKey,
          'pre_shared_key': ?p.param([
            'presharedkey',
            'pre_shared_key',
            'preshared_key',
            'psk',
          ]),
          'allowed_ips': allowed.isEmpty ? ['0.0.0.0/0', '::/0'] : allowed,
          if (keepalive != null && keepalive > 0)
            'persistent_keepalive_interval': keepalive,
          'reserved': ?_reserved(p.param(['reserved'])),
        },
      ],
    },
    p.fragment,
    host,
    port,
  );
}

/// Converts a legacy (removed in sing-box 1.13) WireGuard *outbound*
/// object to the endpoint format. Endpoint objects are returned unchanged.
Map<String, dynamic> convertLegacyWireGuard(Map<String, dynamic> outbound) {
  if (outbound['type'] != 'wireguard' || outbound['peers'] is List) {
    return outbound;
  }
  if (outbound['server'] == null && outbound['private_key'] == null) {
    return outbound;
  }
  final result = <String, dynamic>{'type': 'wireguard', 'tag': outbound['tag']};
  if (outbound['mtu'] != null) result['mtu'] = outbound['mtu'];
  result['address'] = readStringList(
    outbound['local_address'] ?? outbound['address'],
  );
  result['private_key'] = outbound['private_key'];
  final peer = <String, dynamic>{
    'address': outbound['server'],
    'port': outbound['server_port'] ?? 51820,
    'public_key': outbound['peer_public_key'],
    'pre_shared_key': ?outbound['pre_shared_key'],
    'allowed_ips': ['0.0.0.0/0', '::/0'],
    'reserved': ?outbound['reserved'],
  };
  result['peers'] = [peer];
  for (final key in const [
    'detour',
    'domain_resolver',
    'bind_interface',
    'workers',
  ]) {
    if (outbound[key] != null) result[key] = outbound[key];
  }
  if (result['tag'] == null) result.remove('tag');
  return result;
}
