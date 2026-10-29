import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/config/config.dart';
import 'package:sing_box/src/config/internal/clash.dart';

import 'fixtures.dart';
import 'support/sing_box_check.dart';

/// A mihomo configuration with every supported proxy type and a few that
/// sing-box cannot express.
final clashYaml = '''
mixed-port: 7890
allow-lan: false
mode: rule
proxies:
  - name: "SS obfs"
    type: ss
    server: ss.example.com
    port: 8388
    cipher: aes-128-gcm
    password: secret
    udp: true
    plugin: obfs
    plugin-opts:
      mode: tls
      host: bing.com
  - name: SS 2022 v2ray-plugin
    type: ss
    server: 203.0.113.1
    port: 443
    cipher: 2022-blake3-aes-256-gcm
    password: "$ss2022Key256"
    plugin: v2ray-plugin
    plugin-opts: {mode: websocket, tls: true, host: cdn.example.com, path: /ws}
    smux: {enabled: true, protocol: h2mux, max-connections: 4, padding: true}
  - name: VMess WS
    type: vmess
    server: vmess.example.com
    port: 443
    uuid: $uuid
    alterId: 0
    cipher: auto
    tls: true
    servername: sni.example.com
    skip-cert-verify: true
    client-fingerprint: chrome
    network: ws
    ws-opts:
      path: /path?ed=2048
      headers: {Host: cdn.example.com}
  - name: VLESS Reality
    type: vless
    server: 198.51.100.7
    port: 443
    uuid: $uuid
    flow: xtls-rprx-vision
    network: tcp
    tls: true
    servername: www.microsoft.com
    client-fingerprint: firefox
    reality-opts:
      public-key: $realityPublicKey
      short-id: 6ba85179e30d4fc2
  - name: VLESS gRPC
    type: vless
    server: grpc.example.com
    port: 443
    uuid: $uuid
    tls: true
    network: grpc
    grpc-opts: {grpc-service-name: svc}
  - name: VMess HTTP upgrade
    type: vmess
    server: up.example.com
    port: 80
    uuid: $uuid
    cipher: none
    network: ws
    ws-opts: {path: /up, headers: {Host: up.example.com}, v2ray-http-upgrade: true}
  - name: VMess H2
    type: vmess
    server: h2.example.com
    port: 443
    uuid: $uuid
    tls: true
    network: h2
    h2-opts: {host: [a.example.com, b.example.com], path: /h2}
  - name: VMess HTTP obfs
    type: vmess
    server: obfs.example.com
    port: 80
    uuid: $uuid
    network: http
    http-opts:
      method: get
      path: [/a, /b]
      headers: {Host: [h.example.com]}
  - name: Trojan
    type: trojan
    server: trojan.example.com
    port: 443
    password: pass
    sni: trojan.example.com
    alpn: [h2, http/1.1]
    tfo: true
  - name: Hysteria
    type: hysteria
    server: hy.example.com
    port: 443
    auth-str: token
    obfs: secret
    up: "30 Mbps"
    down: 200
    sni: hy.example.com
  - name: Hysteria 2
    type: hysteria2
    server: hy2.example.com
    port: 443
    ports: 20000-30000
    hop-interval: 30
    password: pass
    obfs: salamander
    obfs-password: obfs
    sni: hy2.example.com
    skip-cert-verify: true
  - name: TUIC
    type: tuic
    server: tuic.example.com
    port: 443
    uuid: $uuid
    password: pass
    congestion-controller: bbr
    udp-relay-mode: quic
    reduce-rtt: true
    heartbeat-interval: 10000
    alpn: [h3]
    sni: tuic.example.com
  - name: WireGuard
    type: wireguard
    server: 162.159.192.1
    port: 2408
    ip: 172.16.0.2
    ipv6: 2606:4700:110:8a36::1
    private-key: "$wgPrivateKey"
    public-key: "$wgPublicKey"
    pre-shared-key: "$wgPresharedKey"
    reserved: [1, 2, 3]
    mtu: 1280
  - name: SOCKS
    type: socks5
    server: 192.0.2.10
    port: 1080
    username: user
    password: pass
  - name: HTTPS
    type: http
    server: proxy.example.com
    port: 443
    username: user
    password: pass
    tls: true
    sni: proxy.example.com
  - name: AnyTLS
    type: anytls
    server: anytls.example.com
    port: 443
    password: pass
    idle-session-check-interval: 30
    idle-session-timeout: 60
    min-idle-session: 2
    client-fingerprint: chrome
  - name: SSH
    type: ssh
    server: ssh.example.com
    port: 22
    username: root
    password: pass
  - name: SSR
    type: ssr
    server: ssr.example.com
    port: 443
    cipher: aes-256-cfb
    password: pass
    obfs: plain
    protocol: origin
  - name: XHTTP
    type: vless
    server: x.example.com
    port: 443
    uuid: $uuid
    network: xhttp
  - name: Chained
    type: trojan
    server: chain.example.com
    port: 443
    password: pass
    dialer-proxy: Trojan
  - name: ShadowTLS
    type: ss
    server: stls.example.com
    port: 443
    cipher: aes-128-gcm
    password: pass
    plugin: shadow-tls
    plugin-opts: {host: cloud.tencent.com, password: x, version: 3}
proxy-groups:
  - name: Proxy
    type: select
    proxies: [Trojan, TUIC]
rules:
  - MATCH,Proxy
''';

void main() {
  final skipped = <String, String>{};
  final outbounds = parseClashProxies(
    clashYaml,
    onSkip: (name, reason) => skipped[name] = reason,
  );
  Map<String, dynamic> byName(String name) =>
      outbounds.firstWhere((o) => o.tag == name).json;

  test('detects Clash YAML', () {
    expect(isClashYaml(clashYaml), isTrue);
    expect(isClashYaml('# comment\nproxies:\n  - {}'), isTrue);
    expect(isClashYaml('{"outbounds": []}'), isFalse);
    expect(isClashYaml('vless://x@y:1#proxies:'), isFalse);
  });

  test('converts every supported proxy and skips the others', () {
    expect(outbounds.map((o) => o.tag), [
      'SS obfs',
      'SS 2022 v2ray-plugin',
      'VMess WS',
      'VLESS Reality',
      'VLESS gRPC',
      'VMess HTTP upgrade',
      'VMess H2',
      'VMess HTTP obfs',
      'Trojan',
      'Hysteria',
      'Hysteria 2',
      'TUIC',
      'WireGuard',
      'SOCKS',
      'HTTPS',
      'AnyTLS',
      'SSH',
    ]);
    expect(skipped.keys, ['SSR', 'XHTTP', 'Chained', 'ShadowTLS']);
    expect(skipped['SSR'], contains('not supported'));
    expect(skipped['XHTTP'], contains('XHTTP'));
    expect(skipped['Chained'], contains('dialer-proxy'));
    expect(skipped['ShadowTLS'], contains('shadow-tls'));
  });

  test('Shadowsocks plugins and multiplex', () {
    expect(byName('SS obfs'), {
      'type': 'shadowsocks',
      'tag': 'SS obfs',
      'server': 'ss.example.com',
      'server_port': 8388,
      'method': 'aes-128-gcm',
      'password': 'secret',
      'plugin': 'obfs-local',
      'plugin_opts': 'obfs=tls;obfs-host=bing.com',
    });
    final v2ray = byName('SS 2022 v2ray-plugin');
    expect(v2ray['plugin'], 'v2ray-plugin');
    expect(
      v2ray['plugin_opts'],
      'mode=websocket;tls;host=cdn.example.com;path=/ws',
    );
    expect(v2ray['multiplex'], {
      'enabled': true,
      'protocol': 'h2mux',
      'max_connections': 4,
      'padding': true,
    });
  });

  test('VMess and VLESS with TLS, REALITY and transports', () {
    expect(byName('VMess WS'), {
      'type': 'vmess',
      'tag': 'VMess WS',
      'server': 'vmess.example.com',
      'server_port': 443,
      'uuid': uuid,
      'security': 'auto',
      'tls': {
        'enabled': true,
        'server_name': 'sni.example.com',
        'insecure': true,
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
      },
      'transport': {
        'type': 'ws',
        'path': '/path',
        'headers': {'Host': 'cdn.example.com'},
        'max_early_data': 2048,
        'early_data_header_name': 'Sec-WebSocket-Protocol',
      },
    });
    expect(byName('VLESS Reality'), {
      'type': 'vless',
      'tag': 'VLESS Reality',
      'server': '198.51.100.7',
      'server_port': 443,
      'uuid': uuid,
      'flow': 'xtls-rprx-vision',
      'tls': {
        'enabled': true,
        'server_name': 'www.microsoft.com',
        'utls': {'enabled': true, 'fingerprint': 'firefox'},
        'reality': {
          'enabled': true,
          'public_key': realityPublicKey,
          'short_id': '6ba85179e30d4fc2',
        },
      },
    });
    expect(byName('VLESS gRPC')['transport'], {
      'type': 'grpc',
      'service_name': 'svc',
    });
    expect(byName('VMess HTTP upgrade')['transport'], {
      'type': 'httpupgrade',
      'host': 'up.example.com',
      'path': '/up',
    });
    expect(byName('VMess HTTP upgrade')['security'], 'none');
    expect(byName('VMess H2')['transport'], {
      'type': 'http',
      'host': ['a.example.com', 'b.example.com'],
      'path': '/h2',
    });
    expect(byName('VMess HTTP obfs')['transport'], {
      'type': 'http',
      'host': ['h.example.com'],
      'path': '/a',
      'method': 'GET',
    });
  });

  test('Trojan, Hysteria, Hysteria 2 and TUIC', () {
    expect(byName('Trojan'), {
      'type': 'trojan',
      'tag': 'Trojan',
      'server': 'trojan.example.com',
      'server_port': 443,
      'password': 'pass',
      'tls': {
        'enabled': true,
        'server_name': 'trojan.example.com',
        'alpn': ['h2', 'http/1.1'],
      },
      'tcp_fast_open': true,
    });
    expect(byName('Hysteria'), {
      'type': 'hysteria',
      'tag': 'Hysteria',
      'server': 'hy.example.com',
      'server_port': 443,
      'up_mbps': 30,
      'down_mbps': 200,
      'obfs': 'secret',
      'auth_str': 'token',
      'tls': {'enabled': true, 'server_name': 'hy.example.com'},
    });
    expect(byName('Hysteria 2'), {
      'type': 'hysteria2',
      'tag': 'Hysteria 2',
      'server': 'hy2.example.com',
      'server_ports': ['20000:30000', '443:443'],
      'hop_interval': '30s',
      'obfs': {'type': 'salamander', 'password': 'obfs'},
      'password': 'pass',
      'tls': {
        'enabled': true,
        'server_name': 'hy2.example.com',
        'insecure': true,
      },
    });
    expect(byName('TUIC'), {
      'type': 'tuic',
      'tag': 'TUIC',
      'server': 'tuic.example.com',
      'server_port': 443,
      'uuid': uuid,
      'password': 'pass',
      'congestion_control': 'bbr',
      'udp_relay_mode': 'quic',
      'zero_rtt_handshake': true,
      'heartbeat': '10000ms',
      'tls': {
        'enabled': true,
        'server_name': 'tuic.example.com',
        'alpn': ['h3'],
      },
    });
  });

  test('WireGuard, SOCKS, HTTP, AnyTLS and SSH', () {
    expect(byName('WireGuard'), {
      'type': 'wireguard',
      'tag': 'WireGuard',
      'mtu': 1280,
      'address': ['172.16.0.2/32', '2606:4700:110:8a36::1/128'],
      'private_key': wgPrivateKey,
      'peers': [
        {
          'address': '162.159.192.1',
          'port': 2408,
          'public_key': wgPublicKey,
          'pre_shared_key': wgPresharedKey,
          'allowed_ips': ['0.0.0.0/0', '::/0'],
          'reserved': [1, 2, 3],
        },
      ],
    });
    expect(byName('SOCKS'), {
      'type': 'socks',
      'tag': 'SOCKS',
      'server': '192.0.2.10',
      'server_port': 1080,
      'version': '5',
      'username': 'user',
      'password': 'pass',
    });
    expect(byName('HTTPS')['tls'], {
      'enabled': true,
      'server_name': 'proxy.example.com',
    });
    expect(byName('AnyTLS'), {
      'type': 'anytls',
      'tag': 'AnyTLS',
      'server': 'anytls.example.com',
      'server_port': 443,
      'password': 'pass',
      'idle_session_check_interval': '30s',
      'idle_session_timeout': '60s',
      'min_idle_session': 2,
      'tls': {
        'enabled': true,
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
      },
    });
    expect(byName('SSH'), {
      'type': 'ssh',
      'tag': 'SSH',
      'server': 'ssh.example.com',
      'server_port': 22,
      'user': 'root',
      'password': 'pass',
    });
  });

  test('parseSubscription accepts Clash YAML', () {
    final parsed = SingBoxShareLink.parseSubscription(clashYaml);
    expect(parsed.map((o) => o.tag), outbounds.map((o) => o.tag));
    expect(SingBoxShareLink.parseSubscription('proxies: [oops'), isEmpty);
    expect(SingBoxShareLink.parseSubscription('proxies: 42'), isEmpty);
  });

  test('every converted proxy is accepted by sing-box', () async {
    final config = const SingBoxConfigBuilder().build([
      for (final o in outbounds) o.json,
    ]);
    await expectSingBoxAccepts(config);
  });
}
