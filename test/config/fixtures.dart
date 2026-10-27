import 'dart:convert';

/// Valid keys and ids shared by the config tests (random, test only).
const uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';
const realityPublicKey = 'xHl1mD57kSgxtt6sG9F2wG_FO-qpT1t3EIXoT5eAKJY';
const wgPrivateKey = 'yNDPxgojl9MJfQ8G2/st48uBRsyUbR0D3hOg3eU0GGU=';
const wgPublicKey = 'YINmOE4p2J12qQKToG9cG5KGMMeuFgoYZb7VKzLTpz8=';
const wgPresharedKey = 'iAKdiUZ+IYXA3dZz8WLsVr0TiIixkaqz+p1oOlMmql0=';
const ss2022Key256 = 'k2b1063wk7LXNKAcyOw/0wQ/qXTAJVJaClJWxL2pLHw=';
const ss2022Key128 = 'Xf7ylnS7Wz1RLvUdNyWrRA==';

String b64(String value) => base64.encode(utf8.encode(value));

String b64Url(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

/// One valid share link of every supported scheme (and the most common
/// variants), used for round trips and `sing-box check`.
final validLinks = <String>[
  // VLESS
  'vless://$uuid@reality.example.com:443?encryption=none&flow=xtls-rprx-vision'
      '&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$realityPublicKey'
      '&sid=6ba85179e30d4fc2&type=tcp&headerType=none#Reality%20NL',
  'vless://$uuid@ws.example.com:443?encryption=none&security=tls'
      '&sni=cdn.example.com&type=ws&host=cdn.example.com'
      '&path=%2Fws%3Fed%3D2048#VLESS%20WS',
  'vless://$uuid@grpc.example.com:8443?security=tls&type=grpc'
      '&serviceName=grpc-svc&alpn=h2&fp=firefox#VLESS%20gRPC',
  'vless://$uuid@h2.example.com:443?security=tls&type=http'
      '&host=h2.example.com&path=%2Fh2#VLESS%20H2',
  'vless://$uuid@hu.example.com:80?type=httpupgrade&host=hu.example.com'
      '&path=%2Fupgrade#VLESS%20HTTPUpgrade',
  'vless://$uuid@[2001:db8::1]:443?security=tls&sni=v6.example.com'
      '&allowInsecure=1#VLESS%20IPv6',
  // VMess
  'vmess://${b64(jsonEncode({'v': '2', 'ps': 'VMess WS', 'add': 'vmess.example.com', 'port': '443', 'id': uuid, 'aid': '0', 'scy': 'auto', 'net': 'ws', 'type': 'none', 'host': 'vmess.example.com', 'path': '/vmess', 'tls': 'tls', 'sni': 'vmess.example.com', 'alpn': 'h2,http/1.1', 'fp': 'chrome'}))}',
  'vmess://${b64(jsonEncode({'v': '2', 'ps': 'VMess TCP', 'add': '203.0.113.7', 'port': 10086, 'id': uuid, 'aid': 0, 'scy': 'chacha20-poly1305', 'net': 'tcp', 'type': 'none', 'tls': ''}))}',
  'vmess://$uuid@vmess-grpc.example.com:443?type=grpc&serviceName=svc'
      '&security=tls&sni=vmess-grpc.example.com#VMess%20gRPC',
  // Trojan
  'trojan://p%40ss@trojan.example.com:443?sni=trojan.example.com'
      '&type=ws&path=%2Ftrojan#Trojan%20WS',
  'trojan://secret@198.51.100.4:443#Trojan%20TCP',
  // Shadowsocks
  'ss://${b64Url('aes-128-gcm:test')}@192.168.100.1:8888#SIP002',
  'ss://2022-blake3-aes-256-gcm:${Uri.encodeComponent(ss2022Key256)}'
      '@ss.example.com:8388#SS%202022',
  'ss://${b64('chacha20-ietf-poly1305:pass@ss-legacy.example.com:8389')}'
      '#Legacy',
  'ss://${b64Url('aes-256-gcm:pw')}@obfs.example.com:443/?plugin='
      '${Uri.encodeComponent('obfs-local;obfs=http;obfs-host=example.com')}'
      '#SS%20obfs',
  // Hysteria 2 / Hysteria
  'hysteria2://letmein@hy2.example.com:443/?insecure=1&obfs=salamander'
      '&obfs-password=gawrgura&sni=real.example.com#Hy2',
  'hy2://pass@hop.example.com:20000-30000/?sni=hop.example.com'
      '&hop_interval=30#Hy2%20hopping',
  'hysteria://hy.example.com:443?protocol=udp&auth=123456&peer=hy.example.com'
      '&insecure=1&upmbps=100&downmbps=200&alpn=hysteria'
      '&obfsParam=xplus#Hysteria',
  // TUIC
  'tuic://$uuid:tuic-pass@tuic.example.com:443?congestion_control=bbr'
      '&udp_relay_mode=native&alpn=h3&sni=tuic.example.com#TUIC',
  // SOCKS / HTTP
  'socks://${b64('user:pass')}@203.0.113.1:1080#SOCKS',
  'socks5://user:pa%3Ass@socks.example.com:1080#SOCKS5',
  'socks4://203.0.113.2:1081#SOCKS4',
  'http://user:pass@203.0.113.3:8080#HTTP',
  'https://proxy.example.com:443#HTTPS',
  // AnyTLS
  'anytls://anypass@anytls.example.com:443?sni=anytls.example.com#AnyTLS',
  // WireGuard
  'wireguard://${Uri.encodeComponent(wgPrivateKey)}@wg.example.com:51820'
      '?publickey=${Uri.encodeComponent(wgPublicKey)}'
      '&presharedkey=${Uri.encodeComponent(wgPresharedKey)}'
      '&address=10.0.0.2%2F32,fd00%3A%3A2%2F128&reserved=1,2,3&mtu=1280'
      '&keepalive=25#WireGuard',
];
