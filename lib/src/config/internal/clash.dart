// Clash / mihomo YAML subscriptions. Internal; see
// SingBoxShareLink.parseSubscription.

import 'package:yaml/yaml.dart';

import '../outbound.dart';
import 'json_utils.dart';
import 'link_parser.dart';

/// Whether [text] looks like a Clash / mihomo configuration: a top-level
/// `proxies:` key.
bool isClashYaml(String text) =>
    RegExp(r'^proxies[ \t]*:', multiLine: true).hasMatch(text);

/// Converts the `proxies` of a Clash / mihomo YAML configuration to sing-box
/// outbounds (tags are the proxy names, not yet unique).
///
/// Proxies that sing-box cannot express are skipped and reported to
/// [onSkip] with the proxy name and the reason. `proxy-groups`, `rules`,
/// `dns` and `proxy-providers` are ignored. Returns an empty list when
/// [text] is not valid YAML or has no `proxies` list.
List<SingBoxOutbound> parseClashProxies(
  String text, {
  void Function(String name, String reason)? onSkip,
}) {
  final Object? document;
  try {
    document = loadYaml(text);
  } on YamlException {
    return [];
  }
  if (document is! Map) return [];
  final proxies = document['proxies'];
  if (proxies is! List) return [];
  final result = <SingBoxOutbound>[];
  for (final item in proxies) {
    if (item is! Map) continue;
    final proxy = _plain(item) as Map<String, dynamic>;
    final name =
        _string(proxy, 'name') ??
        '${_string(proxy, 'type') ?? 'proxy'}-${_string(proxy, 'server')}';
    try {
      final json = convertClashProxy(proxy)..['tag'] = name;
      result.add(SingBoxOutbound.fromJson(json, name: name));
    } on FormatException catch (e) {
      onSkip?.call(name, e.message);
    } on ArgumentError catch (e) {
      onSkip?.call(name, '${e.message}');
    }
  }
  return result;
}

/// Converts one Clash / mihomo proxy to a sing-box outbound (or WireGuard
/// endpoint) without a tag. Throws a [FormatException] when sing-box has no
/// equivalent.
Map<String, dynamic> convertClashProxy(Map<String, dynamic> proxy) {
  final type = _string(proxy, 'type')?.toLowerCase();
  final name = _string(proxy, 'name') ?? '$type';
  if (_string(proxy, 'dialer-proxy') != null) {
    throw FormatException('dialer-proxy chains are not supported', name);
  }
  final Map<String, dynamic> json;
  switch (type) {
    case 'ss':
      json = _shadowsocks(proxy, name);
    case 'vmess':
      json = _vmess(proxy, name);
    case 'vless':
      json = _vless(proxy, name);
    case 'trojan':
      json = _trojan(proxy, name);
    case 'hysteria':
      json = _hysteria(proxy, name);
    case 'hysteria2' || 'hy2':
      json = _hysteria2(proxy, name);
    case 'tuic':
      json = _tuic(proxy, name);
    case 'wireguard':
      json = _wireguard(proxy, name);
    case 'socks5':
      json = _socks(proxy, name);
    case 'http':
      json = _http(proxy, name);
    case 'anytls':
      json = _anytls(proxy, name);
    case 'ssh':
      json = _ssh(proxy, name);
    case null:
      throw FormatException('Proxy has no type', name);
    default:
      throw FormatException(
        'Proxy type "$type" is not supported by sing-box',
        name,
      );
  }
  if (_bool(proxy, 'tfo') == true) json['tcp_fast_open'] = true;
  return json;
}

// --- Protocols ---------------------------------------------------------------

Map<String, dynamic> _shadowsocks(Map<String, dynamic> p, String name) {
  final cipher = _string(p, 'cipher');
  if (cipher == null) throw FormatException('Missing cipher', name);
  final plugin = _string(p, 'plugin');
  final opts = _map(p['plugin-opts']);
  String? pluginName;
  String? pluginOpts;
  switch (plugin) {
    case null:
      break;
    case 'obfs':
      final mode = _string(opts, 'mode') ?? 'http';
      final host = _string(opts, 'host');
      pluginName = 'obfs-local';
      pluginOpts = [
        'obfs=$mode',
        if (host != null) 'obfs-host=$host',
      ].join(';');
    case 'v2ray-plugin':
      final mode = _string(opts, 'mode') ?? 'websocket';
      if (mode != 'websocket') {
        throw FormatException(
          'v2ray-plugin mode "$mode" is not supported',
          name,
        );
      }
      final host = _string(opts, 'host');
      final path = _string(opts, 'path');
      pluginName = 'v2ray-plugin';
      pluginOpts = [
        'mode=websocket',
        if (_bool(opts, 'tls') == true) 'tls',
        if (host != null) 'host=$host',
        if (path != null) 'path=$path',
      ].join(';');
    default:
      throw FormatException(
        'Shadowsocks plugin "$plugin" is not supported by sing-box',
        name,
      );
  }
  return {
    'type': 'shadowsocks',
    ..._address(p, name),
    'method': cipher,
    'password': _string(p, 'password') ?? '',
    if (pluginName != null) 'plugin': pluginName,
    if (pluginOpts != null && pluginOpts.isNotEmpty) 'plugin_opts': pluginOpts,
    if (_bool(p, 'udp-over-tcp') == true) 'udp_over_tcp': true,
    ..._multiplex(p),
  };
}

Map<String, dynamic> _vmess(Map<String, dynamic> p, String name) {
  final transport = _transport(p, name);
  final tls = _tls(p, name, enabled: _bool(p, 'tls') == true);
  final alterId = _int(p, 'alterId') ?? 0;
  return {
    'type': 'vmess',
    ..._address(p, name),
    'uuid': _required(p, 'uuid', name),
    'security': vmessSecurity(_string(p, 'cipher')),
    if (alterId > 0) 'alter_id': alterId,
    if (_bool(p, 'global-padding') == true) 'global_padding': true,
    if (_bool(p, 'authenticated-length') == true) 'authenticated_length': true,
    if (_packetEncoding(p) case final encoding?) 'packet_encoding': encoding,
    if (tls != null) 'tls': tls,
    if (transport != null) 'transport': transport,
    ..._multiplex(p),
  };
}

Map<String, dynamic> _vless(Map<String, dynamic> p, String name) {
  final encryption = _string(p, 'encryption');
  if (encryption != null && encryption != 'none') {
    throw FormatException(
      'VLESS encryption is not supported by sing-box',
      name,
    );
  }
  final transport = _transport(p, name);
  final reality = p.containsKey('reality-opts');
  final tls = _tls(p, name, enabled: reality || _bool(p, 'tls') == true);
  final flow = vlessFlow(_string(p, 'flow'), transport, name);
  return {
    'type': 'vless',
    ..._address(p, name),
    'uuid': _required(p, 'uuid', name),
    if (flow != null) 'flow': flow,
    if (_packetEncoding(p) case final encoding?) 'packet_encoding': encoding,
    if (tls != null) 'tls': tls,
    if (transport != null) 'transport': transport,
    ..._multiplex(p),
  };
}

Map<String, dynamic> _trojan(Map<String, dynamic> p, String name) {
  if (_bool(_map(p['ss-opts']), 'enabled') == true) {
    throw FormatException('Trojan-Go ss-opts are not supported', name);
  }
  final transport = _transport(p, name);
  return {
    'type': 'trojan',
    ..._address(p, name),
    'password': _required(p, 'password', name),
    'tls': _tls(p, name, enabled: true),
    if (transport != null) 'transport': transport,
    ..._multiplex(p),
  };
}

Map<String, dynamic> _hysteria(Map<String, dynamic> p, String name) {
  final protocol = (_string(p, 'protocol') ?? 'udp').toLowerCase();
  if (protocol != 'udp') {
    throw FormatException(
      'Hysteria protocol "$protocol" is not supported by sing-box',
      name,
    );
  }
  final auth = _string(p, 'auth-str') ?? _string(p, 'auth');
  final obfs = _string(p, 'obfs');
  return {
    'type': 'hysteria',
    ..._addressWithPorts(p, name),
    'up_mbps': parseMbps(_string(p, 'up')) ?? 10,
    'down_mbps': parseMbps(_string(p, 'down')) ?? 50,
    if (obfs != null) 'obfs': obfs,
    if (auth != null) 'auth_str': auth,
    if (_int(p, 'recv-window-conn') case final window? when window > 0)
      'recv_window_conn': window,
    if (_int(p, 'recv-window') case final window? when window > 0)
      'recv_window': window,
    if (_bool(p, 'disable_mtu_discovery') == true)
      'disable_mtu_discovery': true,
    'tls': _tls(p, name, enabled: true, utls: false),
  };
}

Map<String, dynamic> _hysteria2(Map<String, dynamic> p, String name) {
  final obfs = _string(p, 'obfs');
  if (obfs != null && obfs != 'salamander') {
    throw FormatException('Unsupported Hysteria 2 obfs "$obfs"', name);
  }
  return {
    'type': 'hysteria2',
    ..._addressWithPorts(p, name),
    if (durationParam(_string(p, 'hop-interval')) case final interval?)
      'hop_interval': interval,
    if (parseMbps(_string(p, 'up')) case final up?) 'up_mbps': up,
    if (parseMbps(_string(p, 'down')) case final down?) 'down_mbps': down,
    if (obfs != null)
      'obfs': {'type': obfs, 'password': _string(p, 'obfs-password') ?? ''},
    'password': _string(p, 'password') ?? _string(p, 'auth') ?? '',
    'tls': _tls(p, name, enabled: true, utls: false),
  };
}

Map<String, dynamic> _tuic(Map<String, dynamic> p, String name) {
  final uuid = _string(p, 'uuid');
  if (uuid == null) {
    throw FormatException('TUIC v4 (token) is not supported by sing-box', name);
  }
  final congestion = _string(p, 'congestion-controller');
  final relay = _string(p, 'udp-relay-mode');
  final heartbeat = _int(p, 'heartbeat-interval');
  return {
    'type': 'tuic',
    ..._address(p, name),
    'uuid': uuid,
    'password': _string(p, 'password') ?? '',
    if (congestion == 'cubic' ||
        congestion == 'new_reno' ||
        congestion == 'bbr')
      'congestion_control': congestion,
    if (relay == 'native' || relay == 'quic') 'udp_relay_mode': relay,
    if (_bool(p, 'udp-over-stream') == true) 'udp_over_stream': true,
    if (_bool(p, 'reduce-rtt') == true) 'zero_rtt_handshake': true,
    if (heartbeat != null && heartbeat > 0) 'heartbeat': '${heartbeat}ms',
    'tls': _tls(
      p,
      name,
      enabled: true,
      utls: false,
      disableSni: _bool(p, 'disable-sni') == true,
    ),
  };
}

Map<String, dynamic> _wireguard(Map<String, dynamic> p, String name) {
  if (p.containsKey('amnezia-wg-option')) {
    throw FormatException('AmneziaWG is not supported by sing-box', name);
  }
  final privateKey = _required(p, 'private-key', name);
  final addresses = [
    for (final key in const ['ip', 'ipv6'])
      if (_string(p, key) case final value?)
        if (normalizePrefix(value) case final prefix?) prefix,
  ];
  if (addresses.isEmpty) {
    throw FormatException('WireGuard proxy has no ip / ipv6', name);
  }
  final peerMaps =
      p['peers'] is List
          ? [for (final peer in p['peers'] as List) _map(peer)]
          : [p];
  final peers = [for (final peer in peerMaps) _wireguardPeer(peer, name)];
  final mtu = _int(p, 'mtu');
  return {
    'type': 'wireguard',
    if (mtu != null && mtu > 0) 'mtu': mtu,
    'address': addresses,
    'private_key': privateKey,
    'peers': peers,
  };
}

Map<String, dynamic> _wireguardPeer(Map<String, dynamic> peer, String name) {
  final reserved = peer['reserved'];
  final allowed = [
    for (final ip in _strings(peer['allowed-ips']))
      if (normalizePrefix(ip) case final prefix?) prefix,
  ];
  return {
    'address': _required(peer, 'server', name),
    'port': _port(peer, name),
    'public_key': _required(peer, 'public-key', name),
    if (_string(peer, 'pre-shared-key') case final psk?) 'pre_shared_key': psk,
    'allowed_ips': allowed.isEmpty ? ['0.0.0.0/0', '::/0'] : allowed,
    if (reserved is List && reserved.length == 3)
      'reserved': [for (final b in reserved) (b as num).toInt()]
    else if (parseReserved(reserved?.toString()) case final bytes?)
      'reserved': bytes,
  };
}

Map<String, dynamic> _socks(Map<String, dynamic> p, String name) {
  if (_bool(p, 'tls') == true) {
    throw FormatException('SOCKS over TLS is not supported by sing-box', name);
  }
  return {
    'type': 'socks',
    ..._address(p, name),
    'version': '5',
    if (_string(p, 'username') case final user?) 'username': user,
    if (_string(p, 'password') case final password?) 'password': password,
  };
}

Map<String, dynamic> _http(Map<String, dynamic> p, String name) {
  final tls = _tls(p, name, enabled: _bool(p, 'tls') == true);
  return {
    'type': 'http',
    ..._address(p, name),
    if (_string(p, 'username') case final user?) 'username': user,
    if (_string(p, 'password') case final password?) 'password': password,
    if (tls != null) 'tls': tls,
  };
}

Map<String, dynamic> _anytls(Map<String, dynamic> p, String name) {
  final check = _int(p, 'idle-session-check-interval');
  final timeout = _int(p, 'idle-session-timeout');
  final minIdle = _int(p, 'min-idle-session');
  return {
    'type': 'anytls',
    ..._address(p, name),
    'password': _required(p, 'password', name),
    if (check != null && check > 0) 'idle_session_check_interval': '${check}s',
    if (timeout != null && timeout > 0) 'idle_session_timeout': '${timeout}s',
    if (minIdle != null && minIdle > 0) 'min_idle_session': minIdle,
    'tls': _tls(p, name, enabled: true),
  };
}

Map<String, dynamic> _ssh(Map<String, dynamic> p, String name) {
  final hostKeys = _strings(p['host-key']);
  final algorithms = _strings(p['host-key-algorithms']);
  return {
    'type': 'ssh',
    ..._address(p, name),
    if (_string(p, 'username') case final user?) 'user': user,
    if (_string(p, 'password') case final password?) 'password': password,
    if (_string(p, 'private-key') case final key?) 'private_key': key,
    if (_string(p, 'private-key-passphrase') case final passphrase?)
      'private_key_passphrase': passphrase,
    if (hostKeys.isNotEmpty) 'host_key': hostKeys,
    if (algorithms.isNotEmpty) 'host_key_algorithms': algorithms,
  };
}

// --- Shared fields -----------------------------------------------------------

Map<String, dynamic> _address(Map<String, dynamic> p, String name) => {
  'server': requireHost(_string(p, 'server') ?? '', name),
  'server_port': _port(p, name),
};

/// `server_port`, or `server_ports` for port hopping (`ports: 1000-2000`).
Map<String, dynamic> _addressWithPorts(Map<String, dynamic> p, String name) {
  final server = requireHost(_string(p, 'server') ?? '', name);
  final ports = _string(p, 'ports');
  final port = _int(p, 'port');
  if (ports == null) return {'server': server, 'server_port': _port(p, name)};
  final ranges = parsePortRanges(ports, name);
  if (port != null && !ranges.any((r) => _inRange(port, r))) {
    ranges.add('$port:$port');
  }
  return {'server': server, 'server_ports': ranges};
}

bool _inRange(int port, String range) {
  final parts = range.split(':');
  return port >= int.parse(parts[0]) && port <= int.parse(parts[1]);
}

int _port(Map<String, dynamic> p, String name) {
  final port = _int(p, 'port');
  if (port == null || port < 1 || port > 65535) {
    throw FormatException('Invalid port', name);
  }
  return port;
}

Map<String, dynamic>? _tls(
  Map<String, dynamic> p,
  String name, {
  required bool enabled,
  bool utls = true,
  bool disableSni = false,
}) {
  final reality = _map(p['reality-opts']);
  final isReality = p.containsKey('reality-opts');
  if (!enabled && !isReality) return null;
  return buildTls(
    security: isReality ? 'reality' : 'tls',
    link: name,
    sni: _string(p, 'servername') ?? _string(p, 'sni'),
    alpn: _strings(p['alpn']),
    fingerprint: utls ? _string(p, 'client-fingerprint') : null,
    insecure: _bool(p, 'skip-cert-verify') == true,
    publicKey: _string(reality, 'public-key'),
    shortId: _string(reality, 'short-id'),
    disableSni: disableSni,
  );
}

/// The V2Ray transport of `network` and its `*-opts`.
Map<String, dynamic>? _transport(Map<String, dynamic> p, String name) {
  final network = (_string(p, 'network') ?? 'tcp').toLowerCase();
  switch (network) {
    case 'ws':
      final opts = _map(p['ws-opts']);
      final headers = _map(opts['headers']);
      final host = _string(headers, 'Host') ?? _string(headers, 'host');
      final path = _string(opts, 'path');
      if (_bool(opts, 'v2ray-http-upgrade') == true) {
        return buildTransport(
          network: 'httpupgrade',
          link: name,
          host: host,
          path: path,
        );
      }
      final transport =
          buildTransport(
            network: 'ws',
            link: name,
            host: host,
            path: path,
            earlyData: _int(opts, 'max-early-data')?.toString(),
          )!;
      final header = _string(opts, 'early-data-header-name');
      if (header != null && transport.containsKey('max_early_data')) {
        transport['early_data_header_name'] = header;
      }
      return transport;
    case 'grpc':
      return buildTransport(
        network: 'grpc',
        link: name,
        serviceName: _string(_map(p['grpc-opts']), 'grpc-service-name'),
      );
    case 'h2':
      final opts = _map(p['h2-opts']);
      final hosts = _strings(opts['host']);
      return buildTransport(
        network: 'h2',
        link: name,
        host: hosts.isEmpty ? null : hosts.join(','),
        path: _string(opts, 'path'),
      );
    case 'http':
      // HTTP/1.1 obfuscation (v2ray TCP with an HTTP header).
      final opts = _map(p['http-opts']);
      final hosts = _strings(_map(opts['headers'])['Host']);
      final paths = _strings(opts['path']);
      final transport =
          buildTransport(
            network: 'tcp',
            link: name,
            headerType: 'http',
            host: hosts.isEmpty ? null : hosts.join(','),
            path: paths.isEmpty ? null : paths.first,
          )!;
      final method = _string(opts, 'method');
      if (method != null) transport['method'] = method.toUpperCase();
      return transport;
    default:
      return buildTransport(network: network, link: name);
  }
}

String? _packetEncoding(Map<String, dynamic> p) {
  final encoding = packetEncoding(_string(p, 'packet-encoding'));
  if (encoding != null) return encoding.isEmpty ? null : encoding;
  if (_bool(p, 'xudp') == true) return 'xudp';
  if (_bool(p, 'packet-addr') == true) return 'packetaddr';
  return null;
}

Map<String, dynamic> _multiplex(Map<String, dynamic> p) {
  final smux = _map(p['smux']);
  if (_bool(smux, 'enabled') != true) return const {};
  final protocol = _string(smux, 'protocol');
  return {
    'multiplex': {
      'enabled': true,
      if (protocol == 'smux' || protocol == 'yamux' || protocol == 'h2mux')
        'protocol': protocol,
      if (_int(smux, 'max-connections') case final n? when n > 0)
        'max_connections': n,
      if (_int(smux, 'min-streams') case final n? when n > 0) 'min_streams': n,
      if (_int(smux, 'max-streams') case final n? when n > 0) 'max_streams': n,
      if (_bool(smux, 'padding') == true) 'padding': true,
    },
  };
}

// --- YAML values -------------------------------------------------------------

/// Converts YAML nodes into plain maps, lists and scalars.
Object? _plain(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries) '${e.key}': _plain(e.value),
    };
  }
  if (value is List) return [for (final item in value) _plain(item)];
  return value;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

String? _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null || value is Map || value is List) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

String _required(Map<String, dynamic> map, String key, String name) =>
    _string(map, key) ?? (throw FormatException('Missing $key', name));

int? _int(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is num) return value.toInt();
  return value is String ? int.tryParse(value.trim()) : null;
}

bool? _bool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) return value;
  return readBool(value);
}

List<String> _strings(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }
  if (value is String && value.trim().isNotEmpty) {
    return [
      for (final item in value.split(','))
        if (item.trim().isNotEmpty) item.trim(),
    ];
  }
  return const [];
}
