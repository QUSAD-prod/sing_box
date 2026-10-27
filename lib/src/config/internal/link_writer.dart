// Internal share link writers. Not exported; see SingBoxShareLink.toLink.

import 'dart:convert';

import 'json_utils.dart';
import 'uri_parts.dart';

/// Outbound types [writeShareLink] can convert.
const writableTypes = {
  'vless',
  'vmess',
  'trojan',
  'shadowsocks',
  'hysteria2',
  'hysteria',
  'tuic',
  'socks',
  'http',
  'anytls',
  'wireguard',
};

/// Converts a sing-box outbound object to a share link.
String writeShareLink(Map<String, dynamic> outbound) {
  final type = readString(outbound['type']);
  switch (type) {
    case 'vless':
      return _vless(outbound);
    case 'vmess':
      return _vmess(outbound);
    case 'trojan':
      return _trojan(outbound);
    case 'shadowsocks':
      return _shadowsocks(outbound);
    case 'hysteria2':
      return _hysteria2(outbound);
    case 'hysteria':
      return _hysteria(outbound);
    case 'tuic':
      return _tuic(outbound);
    case 'socks':
      return _socks(outbound);
    case 'http':
      return _http(outbound);
    case 'anytls':
      return _anytls(outbound);
    case 'wireguard':
      return _wireguard(outbound);
  }
  throw UnsupportedError('Outbound type "$type" has no share link format');
}

String _server(Map<String, dynamic> o) {
  final server = readString(o['server']);
  if (server == null) {
    throw ArgumentError.value(o, 'outbound', 'Outbound has no "server"');
  }
  return server;
}

String _authority(Map<String, dynamic> o, int defaultPort) {
  final port = readInt(o['server_port']) ?? defaultPort;
  return '${formatHost(_server(o))}:$port';
}

String _fragment(Map<String, dynamic> o) {
  final tag = readString(o['tag']);
  return tag == null ? '' : '#${percentEncode(tag)}';
}

String _query(Map<String, String?> params) {
  final parts = [
    for (final e in params.entries)
      if (e.value != null && e.value!.isNotEmpty)
        '${e.key}=${percentEncode(e.value!)}',
  ];
  return parts.isEmpty ? '' : '?${parts.join('&')}';
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? asJsonMap(value) : null;

String? _join(Object? value) {
  final list = readStringList(value);
  return list.isEmpty ? null : list.join(',');
}

/// TLS related V2Ray style query parameters.
Map<String, String?> _tlsParams(Map<String, dynamic>? tls) {
  if (tls == null || readBool(tls['enabled']) != true) {
    return {'security': 'none'};
  }
  final reality = _map(tls['reality']);
  final isReality = reality != null && readBool(reality['enabled']) == true;
  final utls = _map(tls['utls']);
  return {
    'security': isReality ? 'reality' : 'tls',
    'sni': readString(tls['server_name']),
    'alpn': _join(tls['alpn']),
    'fp': utls != null && readBool(utls['enabled']) == true
        ? readString(utls['fingerprint']) ?? 'chrome'
        : null,
    'pbk': isReality ? readString(reality['public_key']) : null,
    'sid': isReality ? readString(reality['short_id']) : null,
    'allowInsecure': readBool(tls['insecure']) == true ? '1' : null,
  };
}

/// Transport related V2Ray style query parameters.
Map<String, String?> _transportParams(
  Map<String, dynamic>? transport, {
  required bool hasTls,
}) {
  if (transport == null) return {'type': 'tcp'};
  final type = readString(transport['type']);
  switch (type) {
    case 'ws':
      final headers = _map(transport['headers']);
      var path = readString(transport['path']) ?? '';
      final earlyData = readInt(transport['max_early_data']);
      if (earlyData != null && earlyData > 0) {
        path += '${path.contains('?') ? '&' : '?'}ed=$earlyData';
      }
      return {
        'type': 'ws',
        'host': headers == null
            ? null
            : readString(headers['Host'] ?? headers['host']),
        'path': path,
      };
    case 'grpc':
      return {
        'type': 'grpc',
        'serviceName': readString(transport['service_name']),
      };
    case 'http':
      if (!hasTls) {
        return {
          'type': 'tcp',
          'headerType': 'http',
          'host': _join(transport['host']),
          'path': readString(transport['path']),
        };
      }
      return {
        'type': 'http',
        'host': _join(transport['host']),
        'path': readString(transport['path']),
      };
    case 'httpupgrade':
      return {
        'type': 'httpupgrade',
        'host': readString(transport['host']),
        'path': readString(transport['path']),
      };
    case 'quic':
      return {'type': 'quic'};
  }
  throw UnsupportedError('Transport "$type" has no share link format');
}

String _vless(Map<String, dynamic> o) {
  final uuid = readString(o['uuid']) ?? '';
  final tls = _map(o['tls']);
  final hasTls = tls != null && readBool(tls['enabled']) == true;
  final encoding = o['packet_encoding'];
  final params = <String, String?>{
    'encryption': 'none',
    'flow': readString(o['flow']),
    ..._tlsParams(tls),
    ..._transportParams(_map(o['transport']), hasTls: hasTls),
    'packetEncoding': encoding is String
        ? (encoding.isEmpty ? 'none' : encoding)
        : null,
  };
  return 'vless://${percentEncode(uuid)}@${_authority(o, 443)}'
      '${_query(params)}${_fragment(o)}';
}

String _trojan(Map<String, dynamic> o) {
  final password = readString(o['password']) ?? '';
  final tls = _map(o['tls']);
  final hasTls = tls != null && readBool(tls['enabled']) == true;
  final params = <String, String?>{
    ..._tlsParams(tls),
    ..._transportParams(_map(o['transport']), hasTls: hasTls),
  };
  return 'trojan://${percentEncode(password)}@${_authority(o, 443)}'
      '${_query(params)}${_fragment(o)}';
}

String _vmess(Map<String, dynamic> o) {
  final tls = _map(o['tls']);
  final hasTls = tls != null && readBool(tls['enabled']) == true;
  final transport = _map(o['transport']);
  final t = _transportParams(transport, hasTls: hasTls);
  final utls = tls == null ? null : _map(tls['utls']);
  String net = t['type'] ?? 'tcp';
  if (net == 'http') net = 'h2';
  final json = <String, dynamic>{
    'v': '2',
    'ps': readString(o['tag']) ?? '',
    'add': _server(o),
    'port': '${readInt(o['server_port']) ?? 443}',
    'id': readString(o['uuid']) ?? '',
    'aid': '${readInt(o['alter_id']) ?? 0}',
    'scy': readString(o['security']) ?? 'auto',
    'net': net,
    'type': t['headerType'] ?? 'none',
    'host': t['host'] ?? '',
    'path': (net == 'grpc' ? t['serviceName'] : t['path']) ?? '',
    'tls': hasTls ? 'tls' : '',
    'sni': hasTls ? readString(tls['server_name']) ?? '' : '',
    'alpn': hasTls ? _join(tls['alpn']) ?? '' : '',
    'fp': utls != null && readBool(utls['enabled']) == true
        ? readString(utls['fingerprint']) ?? ''
        : '',
  };
  if (hasTls && readBool(tls['insecure']) == true) json['allowInsecure'] = true;
  return 'vmess://${encodeBase64(jsonEncode(json))}';
}

String _shadowsocks(Map<String, dynamic> o) {
  final method = readString(o['method']) ?? 'none';
  final password = o['password'] is String ? o['password'] as String : '';
  final userInfo = method.startsWith('2022-')
      ? '${percentEncode(method)}:${percentEncode(password)}'
      : encodeBase64UrlNoPadding('$method:$password');
  final plugin = readString(o['plugin']);
  final opts = readString(o['plugin_opts']);
  final query = plugin == null
      ? ''
      : '/?plugin=${percentEncode(opts == null ? plugin : '$plugin;$opts')}';
  final uot = readBool(o['udp_over_tcp']) == true || o['udp_over_tcp'] is Map;
  final uotQuery = uot ? '${query.isEmpty ? '/?' : '&'}uot=1' : '';
  return 'ss://$userInfo@${_authority(o, 8388)}$query$uotQuery${_fragment(o)}';
}

String _portsParam(Object? serverPorts) {
  final ranges = readStringList(serverPorts);
  return ranges
      .map((r) {
        final parts = r.split(':');
        return parts.length == 2 && parts[0] == parts[1]
            ? parts[0]
            : r.replaceAll(':', '-');
      })
      .join(',');
}

String _quicAuthority(Map<String, dynamic> o) {
  var port = readInt(o['server_port']);
  final ranges = readStringList(o['server_ports']);
  if (port == null && ranges.isNotEmpty) {
    port = int.tryParse(ranges.first.split(':').first);
  }
  return '${formatHost(_server(o))}:${port ?? 443}';
}

String _hysteria2(Map<String, dynamic> o) {
  final tls = _map(o['tls']) ?? const {};
  final obfs = _map(o['obfs']);
  final ports = _portsParam(o['server_ports']);
  final password = o['password'] is String ? o['password'] as String : '';
  final params = <String, String?>{
    'sni': readString(tls['server_name']),
    'insecure': readBool(tls['insecure']) == true ? '1' : null,
    'alpn': _join(tls['alpn']),
    'obfs': obfs == null ? null : readString(obfs['type']),
    'obfs-password': obfs == null ? null : readString(obfs['password']),
    'mport': ports.isEmpty ? null : ports,
    'upmbps': readInt(o['up_mbps'])?.toString(),
    'downmbps': readInt(o['down_mbps'])?.toString(),
    'hop_interval': readString(o['hop_interval']),
  };
  final auth = password.isEmpty ? '' : '${percentEncode(password)}@';
  return 'hysteria2://$auth${_quicAuthority(o)}/${_query(params)}'
      '${_fragment(o)}';
}

String _hysteria(Map<String, dynamic> o) {
  final tls = _map(o['tls']) ?? const {};
  final ports = _portsParam(o['server_ports']);
  final params = <String, String?>{
    'protocol': 'udp',
    'auth': readString(o['auth_str']),
    'peer': readString(tls['server_name']),
    'insecure': readBool(tls['insecure']) == true ? '1' : null,
    'alpn': _join(tls['alpn']),
    'upmbps': readInt(o['up_mbps'])?.toString(),
    'downmbps': readInt(o['down_mbps'])?.toString(),
    'obfs': readString(o['obfs']) == null ? null : 'xplus',
    'obfsParam': readString(o['obfs']),
    'mport': ports.isEmpty ? null : ports,
  };
  return 'hysteria://${_quicAuthority(o)}${_query(params)}${_fragment(o)}';
}

String _tuic(Map<String, dynamic> o) {
  final tls = _map(o['tls']) ?? const {};
  final uuid = readString(o['uuid']) ?? '';
  final password = o['password'] is String ? o['password'] as String : '';
  final params = <String, String?>{
    'congestion_control': readString(o['congestion_control']),
    'udp_relay_mode': readString(o['udp_relay_mode']),
    'alpn': _join(tls['alpn']),
    'sni': readString(tls['server_name']),
    'allow_insecure': readBool(tls['insecure']) == true ? '1' : null,
    'disable_sni': readBool(tls['disable_sni']) == true ? '1' : null,
    'zero_rtt_handshake': readBool(o['zero_rtt_handshake']) == true
        ? '1'
        : null,
  };
  return 'tuic://${percentEncode(uuid)}:${percentEncode(password)}@'
      '${_authority(o, 443)}${_query(params)}${_fragment(o)}';
}

String _userInfo(Map<String, dynamic> o) {
  final username = readString(o['username']);
  final password = o['password'] is String ? o['password'] as String : null;
  if (username == null && (password == null || password.isEmpty)) return '';
  return '${percentEncode(username ?? '')}'
      '${password == null ? '' : ':${percentEncode(password)}'}@';
}

String _socks(Map<String, dynamic> o) {
  final version = readString(o['version']) ?? '5';
  final scheme = switch (version) {
    '4' => 'socks4',
    '4a' => 'socks4a',
    _ => 'socks',
  };
  final username = readString(o['username']);
  final password = o['password'] is String ? o['password'] as String : '';
  final auth = username == null && password.isEmpty
      ? ''
      : '${encodeBase64UrlNoPadding('${username ?? ''}:$password')}@';
  return '$scheme://$auth${_authority(o, 1080)}${_fragment(o)}';
}

String _http(Map<String, dynamic> o) {
  final tls = _map(o['tls']);
  final secure = tls != null && readBool(tls['enabled']) == true;
  final params = <String, String?>{
    if (secure) ...{
      'sni': readString(tls['server_name']) == readString(o['server'])
          ? null
          : readString(tls['server_name']),
      'insecure': readBool(tls['insecure']) == true ? '1' : null,
    },
  };
  return '${secure ? 'https' : 'http'}://${_userInfo(o)}'
      '${_authority(o, secure ? 443 : 80)}${_query(params)}${_fragment(o)}';
}

String _anytls(Map<String, dynamic> o) {
  final tls = _map(o['tls']);
  final password = o['password'] is String ? o['password'] as String : '';
  final t = _tlsParams(tls);
  final params = <String, String?>{
    if (t['security'] == 'reality') 'security': 'reality',
    'sni': t['sni'],
    'insecure': t['allowInsecure'],
    'alpn': t['alpn'],
    'fp': t['fp'],
    'pbk': t['pbk'],
    'sid': t['sid'],
  };
  return 'anytls://${percentEncode(password)}@${_authority(o, 443)}/'
      '${_query(params)}${_fragment(o)}';
}

String _wireguard(Map<String, dynamic> o) {
  final peers = o['peers'];
  final peer = peers is List && peers.isNotEmpty && peers.first is Map
      ? asJsonMap(peers.first)!
      : <String, dynamic>{
          'address': o['server'],
          'port': o['server_port'],
          'public_key': o['peer_public_key'],
          'pre_shared_key': o['pre_shared_key'],
          'reserved': o['reserved'],
        };
  final host = readString(peer['address']);
  if (host == null) {
    throw ArgumentError.value(o, 'outbound', 'WireGuard peer has no address');
  }
  final reserved = peer['reserved'];
  final allowed = readStringList(peer['allowed_ips']);
  final isDefaultAllowed =
      allowed.isEmpty ||
      (allowed.length == 2 &&
          allowed.contains('0.0.0.0/0') &&
          allowed.contains('::/0'));
  final params = <String, String?>{
    'publickey': readString(peer['public_key']),
    'presharedkey': readString(peer['pre_shared_key']),
    'address': _join(o['address'] ?? o['local_address']),
    'mtu': readInt(o['mtu'])?.toString(),
    'reserved': reserved is List ? reserved.join(',') : null,
    'allowedips': isDefaultAllowed ? null : allowed.join(','),
    'keepalive': readInt(peer['persistent_keepalive_interval'])?.toString(),
  };
  final privateKey = readString(o['private_key']) ?? '';
  return 'wireguard://${percentEncode(privateKey)}@'
      '${formatHost(host)}:${readInt(peer['port']) ?? 51820}'
      '${_query(params)}${_fragment(o)}';
}
