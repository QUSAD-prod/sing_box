import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/config/config.dart';

import 'fixtures.dart';
import 'support/sing_box_check.dart';

Map<String, dynamic> parse(String link) => SingBoxShareLink.parse(link).json;

void main() {
  group('VLESS', () {
    test('REALITY + Vision', () {
      final outbound = SingBoxShareLink.parse(validLinks[0]);
      expect(outbound.type, 'vless');
      expect(outbound.tag, 'Reality NL');
      expect(outbound.name, 'Reality NL');
      expect(outbound.server, 'reality.example.com');
      expect(outbound.serverPort, 443);
      expect(outbound.link, validLinks[0]);
      expect(outbound.json, {
        'type': 'vless',
        'tag': 'Reality NL',
        'server': 'reality.example.com',
        'server_port': 443,
        'uuid': uuid,
        'flow': 'xtls-rprx-vision',
        'tls': {
          'enabled': true,
          'server_name': 'www.microsoft.com',
          'utls': {'enabled': true, 'fingerprint': 'chrome'},
          'reality': {
            'enabled': true,
            'public_key': realityPublicKey,
            'short_id': '6ba85179e30d4fc2',
          },
        },
      });
    });

    test('REALITY defaults the uTLS fingerprint and requires pbk', () {
      final json = parse(
        'vless://$uuid@r.example.com?security=reality&sni=a.com'
        '&pbk=$realityPublicKey',
      );
      expect(json['server_port'], 443);
      expect(json['tls']['utls'], {'enabled': true, 'fingerprint': 'chrome'});
      expect(
        () => parse('vless://$uuid@r.example.com?security=reality&sni=a.com'),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            'REALITY link has no public key (pbk)',
          ),
        ),
      );
    });

    test('WebSocket early data is moved out of the path', () {
      expect(parse(validLinks[1])['transport'], {
        'type': 'ws',
        'path': '/ws',
        'headers': {'Host': 'cdn.example.com'},
        'max_early_data': 2048,
        'early_data_header_name': 'Sec-WebSocket-Protocol',
      });
      final json = parse(
        'vless://$uuid@h.example.com?type=ws&path=%2Fp%3Fa%3D1%26ed%3D512',
      );
      expect(json['transport']['path'], '/p?a=1');
      expect(json['transport']['max_early_data'], 512);
    });

    test('gRPC, HTTP/2 and HTTPUpgrade transports', () {
      expect(parse(validLinks[2])['transport'], {
        'type': 'grpc',
        'service_name': 'grpc-svc',
      });
      expect(parse(validLinks[2])['tls'], {
        'enabled': true,
        'alpn': ['h2'],
        'utls': {'enabled': true, 'fingerprint': 'firefox'},
      });
      expect(parse(validLinks[3])['transport'], {
        'type': 'http',
        'host': ['h2.example.com'],
        'path': '/h2',
      });
      expect(parse(validLinks[4])['transport'], {
        'type': 'httpupgrade',
        'host': 'hu.example.com',
        'path': '/upgrade',
      });
      expect(parse(validLinks[4])['tls'], isNull);
    });

    test('TCP with an HTTP header becomes an HTTP transport', () {
      final json = parse(
        'vless://$uuid@h.example.com:80?type=tcp&headerType=http'
        '&host=a.com,b.com&path=%2Fx',
      );
      expect(json['transport'], {
        'type': 'http',
        'host': ['a.com', 'b.com'],
        'path': '/x',
        'method': 'GET',
      });
    });

    test('IPv6 hosts and insecure TLS', () {
      final outbound = SingBoxShareLink.parse(validLinks[5]);
      expect(outbound.server, '2001:db8::1');
      expect(outbound.json['tls'], {
        'enabled': true,
        'server_name': 'v6.example.com',
        'insecure': true,
      });
      expect(outbound.toString(), contains('[2001:db8::1]:443'));
    });

    test('Vision is dropped on V2Ray transports', () {
      final json = parse(
        'vless://$uuid@h.example.com?type=ws&flow=xtls-rprx-vision'
        '&security=tls',
      );
      expect(json.containsKey('flow'), isFalse);
    });

    test('packet encoding', () {
      expect(
        parse(
          'vless://$uuid@h.example.com?packetEncoding=xudp',
        )['packet_encoding'],
        'xudp',
      );
      expect(
        parse(
          'vless://$uuid@h.example.com?packetEncoding=none',
        )['packet_encoding'],
        '',
      );
    });

    test('tag defaults to type-host-port and can be overridden', () {
      expect(
        SingBoxShareLink.parse('vless://$uuid@h.example.com:8443').tag,
        'vless-h.example.com-8443',
      );
      final outbound = SingBoxShareLink.parse(validLinks[0], tag: 'custom');
      expect(outbound.tag, 'custom');
      expect(outbound.name, 'Reality NL');
      expect(outbound.displayName, 'Reality NL');
    });
  });

  group('VMess', () {
    test('v2rayN JSON', () {
      expect(parse(validLinks[6]), {
        'type': 'vmess',
        'tag': 'VMess WS',
        'server': 'vmess.example.com',
        'server_port': 443,
        'uuid': uuid,
        'security': 'auto',
        'tls': {
          'enabled': true,
          'server_name': 'vmess.example.com',
          'alpn': ['h2', 'http/1.1'],
          'utls': {'enabled': true, 'fingerprint': 'chrome'},
        },
        'transport': {
          'type': 'ws',
          'path': '/vmess',
          'headers': {'Host': 'vmess.example.com'},
        },
      });
      expect(parse(validLinks[7]), {
        'type': 'vmess',
        'tag': 'VMess TCP',
        'server': '203.0.113.7',
        'server_port': 10086,
        'uuid': uuid,
        'security': 'chacha20-poly1305',
      });
    });

    test('alter id, legacy and unknown ciphers', () {
      final json = parse(
        'vmess://${b64(jsonEncode({'add': 'a.com', 'port': '1', 'id': uuid, 'aid': '64', 'scy': 'aes-128-ctr'}))}',
      );
      expect(json['alter_id'], 64);
      expect(json['security'], 'aes-128-ctr');
      final unknown = parse(
        'vmess://${b64(jsonEncode({'add': 'a.com', 'port': '1', 'id': uuid, 'scy': 'aes-128-cfb'}))}',
      );
      expect(unknown['security'], 'auto');
    });

    test('gRPC service name comes from path in JSON links', () {
      final json = parse(
        'vmess://${b64(jsonEncode({'add': 'a.com', 'port': '443', 'id': uuid, 'net': 'grpc', 'path': 'svc', 'tls': 'tls'}))}',
      );
      expect(json['transport'], {'type': 'grpc', 'service_name': 'svc'});
    });

    test('Xray standard URI format', () {
      expect(parse(validLinks[8]), {
        'type': 'vmess',
        'tag': 'VMess gRPC',
        'server': 'vmess-grpc.example.com',
        'server_port': 443,
        'uuid': uuid,
        'security': 'auto',
        'tls': {'enabled': true, 'server_name': 'vmess-grpc.example.com'},
        'transport': {'type': 'grpc', 'service_name': 'svc'},
      });
    });

    test('Shadowrocket format', () {
      final outbound = SingBoxShareLink.parse(
        'vmess://${b64Url('auto:$uuid@sr.example.com:443')}?remarks=SR'
        '&obfs=websocket&path=%2Fws&obfsParam=cdn.example.com&tls=1',
      );
      expect(outbound.tag, 'SR');
      expect(outbound.json['transport'], {
        'type': 'ws',
        'path': '/ws',
        'headers': {'Host': 'cdn.example.com'},
      });
      expect(outbound.json['tls'], {
        'enabled': true,
        'server_name': 'cdn.example.com',
      });
    });
  });

  group('Trojan', () {
    test('defaults to TLS and decodes the password', () {
      expect(parse(validLinks[9]), {
        'type': 'trojan',
        'tag': 'Trojan WS',
        'server': 'trojan.example.com',
        'server_port': 443,
        'password': 'p@ss',
        'tls': {'enabled': true, 'server_name': 'trojan.example.com'},
        'transport': {'type': 'ws', 'path': '/trojan'},
      });
      expect(parse(validLinks[10])['tls'], {'enabled': true});
      expect(
        parse('trojan://pw@t.example.com?security=none').containsKey('tls'),
        isFalse,
      );
    });
  });

  group('Shadowsocks', () {
    test('SIP002 with base64url user info', () {
      expect(parse(validLinks[11]), {
        'type': 'shadowsocks',
        'tag': 'SIP002',
        'server': '192.168.100.1',
        'server_port': 8888,
        'method': 'aes-128-gcm',
        'password': 'test',
      });
    });

    test('SIP022 plain user info', () {
      final json = parse(validLinks[12]);
      expect(json['method'], '2022-blake3-aes-256-gcm');
      expect(json['password'], ss2022Key256);
    });

    test('legacy fully encoded link', () {
      final json = parse(validLinks[13]);
      expect(json['server'], 'ss-legacy.example.com');
      expect(json['server_port'], 8389);
      expect(json['method'], 'chacha20-ietf-poly1305');
      expect(json['password'], 'pass');
    });

    test('plugins, aliases and UDP over TCP', () {
      final json = parse(validLinks[14]);
      expect(json['plugin'], 'obfs-local');
      expect(json['plugin_opts'], 'obfs=http;obfs-host=example.com');
      final aliased = parse(
        'ss://${b64Url('chacha20-poly1305:pw')}@a.com:1/?plugin=simple-obfs'
        '%3Bobfs%3Dtls&uot=1',
      );
      expect(aliased['method'], 'chacha20-ietf-poly1305');
      expect(aliased['plugin'], 'obfs-local');
      expect(aliased['udp_over_tcp'], true);
    });
  });

  group('Hysteria', () {
    test('Hysteria 2 with salamander obfs', () {
      expect(parse(validLinks[15]), {
        'type': 'hysteria2',
        'tag': 'Hy2',
        'server': 'hy2.example.com',
        'server_port': 443,
        'obfs': {'type': 'salamander', 'password': 'gawrgura'},
        'password': 'letmein',
        'tls': {
          'enabled': true,
          'server_name': 'real.example.com',
          'insecure': true,
        },
      });
    });

    test('Hysteria 2 port hopping', () {
      final outbound = SingBoxShareLink.parse(validLinks[16]);
      expect(outbound.json['server_ports'], ['20000:30000']);
      expect(outbound.json.containsKey('server_port'), isFalse);
      expect(outbound.json['hop_interval'], '30s');
      expect(outbound.serverPort, 20000);
      final mport = parse(
        'hysteria2://pw@h.example.com:443?mport=1000-1100,2000&up=50%20mbps',
      );
      expect(mport['server_ports'], ['1000:1100', '2000:2000', '443:443']);
      expect(mport['up_mbps'], 50);
    });

    test('Hysteria v1', () {
      expect(parse(validLinks[17]), {
        'type': 'hysteria',
        'tag': 'Hysteria',
        'server': 'hy.example.com',
        'server_port': 443,
        'up_mbps': 100,
        'down_mbps': 200,
        'obfs': 'xplus',
        'auth_str': '123456',
        'tls': {
          'enabled': true,
          'server_name': 'hy.example.com',
          'insecure': true,
          'alpn': ['hysteria'],
        },
      });
    });
  });

  group('TUIC', () {
    test('v5 link', () {
      expect(parse(validLinks[18]), {
        'type': 'tuic',
        'tag': 'TUIC',
        'server': 'tuic.example.com',
        'server_port': 443,
        'uuid': uuid,
        'password': 'tuic-pass',
        'congestion_control': 'bbr',
        'udp_relay_mode': 'native',
        'tls': {
          'enabled': true,
          'server_name': 'tuic.example.com',
          'alpn': ['h3'],
        },
      });
    });

    test('defaults ALPN to h3 and ignores unknown options', () {
      final json = parse(
        'tuic://$uuid:pw@t.example.com:443?congestion_control=hybla'
        '&disable_sni=1&reduce_rtt=1',
      );
      expect(json.containsKey('congestion_control'), isFalse);
      expect(json['zero_rtt_handshake'], true);
      expect(json['tls'], {
        'enabled': true,
        'disable_sni': true,
        'alpn': ['h3'],
      });
    });
  });

  group('SOCKS and HTTP', () {
    test('SOCKS variants', () {
      expect(parse(validLinks[19]), {
        'type': 'socks',
        'tag': 'SOCKS',
        'server': '203.0.113.1',
        'server_port': 1080,
        'username': 'user',
        'password': 'pass',
      });
      expect(parse(validLinks[20])['password'], 'pa:ss');
      expect(parse(validLinks[21])['version'], '4');
      expect(parse('socks4a://h.example.com')['version'], '4a');
      expect(parse('socks://h.example.com')['server_port'], 1080);
      expect(parse('socks://${b64('u:p@legacy.example.com:1089')}#L'), {
        'type': 'socks',
        'tag': 'L',
        'server': 'legacy.example.com',
        'server_port': 1089,
        'username': 'u',
        'password': 'p',
      });
    });

    test('HTTP and HTTPS proxies', () {
      expect(parse(validLinks[22]), {
        'type': 'http',
        'tag': 'HTTP',
        'server': '203.0.113.3',
        'server_port': 8080,
        'username': 'user',
        'password': 'pass',
      });
      expect(parse(validLinks[23])['tls'], {
        'enabled': true,
        'server_name': 'proxy.example.com',
      });
      expect(parse('http://h.example.com')['server_port'], 80);
    });
  });

  test('AnyTLS', () {
    expect(parse(validLinks[24]), {
      'type': 'anytls',
      'tag': 'AnyTLS',
      'server': 'anytls.example.com',
      'server_port': 443,
      'password': 'anypass',
      'tls': {'enabled': true, 'server_name': 'anytls.example.com'},
    });
  });

  group('WireGuard', () {
    test('becomes an endpoint', () {
      final outbound = SingBoxShareLink.parse(validLinks[25]);
      expect(outbound.isEndpoint, isTrue);
      expect(outbound.server, 'wg.example.com');
      expect(outbound.serverPort, 51820);
      expect(outbound.json, {
        'type': 'wireguard',
        'tag': 'WireGuard',
        'mtu': 1280,
        'address': ['10.0.0.2/32', 'fd00::2/128'],
        'private_key': wgPrivateKey,
        'peers': [
          {
            'address': 'wg.example.com',
            'port': 51820,
            'public_key': wgPublicKey,
            'pre_shared_key': wgPresharedKey,
            'allowed_ips': ['0.0.0.0/0', '::/0'],
            'persistent_keepalive_interval': 25,
            'reserved': [1, 2, 3],
          },
        ],
      });
    });

    test('accepts base64 reserved bytes and host addresses', () {
      final json = parse(
        'wg://${Uri.encodeComponent(wgPrivateKey)}@1.2.3.4'
        '?publickey=${Uri.encodeComponent(wgPublicKey)}'
        '&address=172.16.0.2&reserved=AQID&allowedips=10.0.0.0/8',
      );
      final peer = (json['peers'] as List).single as Map;
      expect(json['address'], ['172.16.0.2/32']);
      expect(peer['port'], 51820);
      expect(peer['reserved'], [1, 2, 3]);
      expect(peer['allowed_ips'], ['10.0.0.0/8']);
    });
  });

  group('malformed and unsupported links', () {
    final cases = <String, String>{
      '': 'Share link is empty',
      '   ': 'Share link is empty',
      'example.com:443': 'missing "scheme://"',
      'foo://bar': 'Unsupported share link scheme "foo"',
      'ssr://abc': 'ShadowsocksR is not supported',
      'naive+https://u:p@h.com': 'Unsupported share link scheme',
      'vless://@h.example.com:443': 'VLESS link has no UUID',
      'vless://$uuid@:443': 'no server address',
      'vless://$uuid@bad host:443': 'Invalid server address',
      'vless://$uuid@h.example.com:70000': 'port',
      'vless://$uuid@h.example.com:443?encryption=mlkem768x25519plus':
          'VLESS encryption',
      'vless://$uuid@h.example.com?type=xhttp':
          'XHTTP transport is not supported',
      'vless://$uuid@h.example.com?type=splithttp': 'XHTTP',
      'vless://$uuid@h.example.com?type=kcp': 'mKCP transport',
      'vless://$uuid@h.example.com?type=foo': 'Unsupported transport "foo"',
      'vless://$uuid@h.example.com?security=foo': 'Unsupported security "foo"',
      'vless://$uuid@h.example.com?flow=xtls-rprx-direct':
          'Unsupported VLESS flow',
      'vmess://not-base64!': 'Malformed VMess link',
      'vmess://${b64('{"add": "a.com"')}': 'Malformed VMess JSON',
      'vmess://${b64(jsonEncode({'add': 'a.com', 'port': '1'}))}': 'no UUID',
      'vmess://${b64(jsonEncode({'add': 'a.com', 'port': '0', 'id': uuid}))}':
          'Invalid VMess port',
      'trojan://@h.example.com': 'Trojan link has no password',
      'ss://${b64Url('rc4:pw')}@h.example.com:1': 'Shadowsocks method "rc4"',
      'ss://${b64Url('aes-128-gcm:')}@h.example.com:1': 'no password',
      'ss://${b64Url('aes-128-gcm:pw')}@h.example.com': 'no port',
      'ss://garbage': 'Malformed Shadowsocks link',
      'ss://${b64Url('aes-128-gcm:pw')}@h.example.com:1/?plugin=kcptun':
          'plugin "kcptun"',
      'hysteria2://pw@h.example.com?obfs=foo': 'Unsupported Hysteria 2 obfs',
      'hysteria2://pw@h.example.com:5-3': 'Invalid port range',
      'hysteria://h.example.com?protocol=faketcp': 'protocol "faketcp"',
      'tuic://$uuid@h.example.com': 'TUIC v4 is not supported',
      'tuic://:pw@h.example.com': 'TUIC link has no UUID',
      'http://h.example.com/index.html': 'web address',
      'anytls://@h.example.com': 'AnyTLS link has no password',
      'wireguard://@h.example.com?publickey=x&address=10.0.0.2':
          'no private key',
      'wireguard://k@h.example.com?address=10.0.0.2': 'no peer public key',
      'wireguard://k@h.example.com?publickey=x': 'no local address',
    };
    for (final entry in cases.entries) {
      test(entry.key.isEmpty ? '(empty)' : entry.key, () {
        expect(
          () => SingBoxShareLink.parse(entry.key),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(entry.value),
            ),
          ),
        );
        expect(SingBoxShareLink.tryParse(entry.key), isNull);
      });
    }
  });

  test('isSupported checks the scheme only', () {
    expect(SingBoxShareLink.isSupported(' VLESS://x'), isTrue);
    expect(SingBoxShareLink.isSupported('hy2://x'), isTrue);
    expect(SingBoxShareLink.isSupported('ssr://x'), isFalse);
    expect(SingBoxShareLink.isSupported('{"type": "vless"}'), isFalse);
    for (final link in validLinks) {
      expect(SingBoxShareLink.isSupported(link), isTrue, reason: link);
    }
  });

  group('round trip', () {
    for (final link in validLinks) {
      test(link, () {
        final outbound = SingBoxShareLink.parse(link);
        final written = outbound.toLink();
        expect(SingBoxShareLink.parse(written).json, outbound.json);
      });
    }

    test('IPv6 servers are bracketed', () {
      final link = SingBoxShareLink.toLink({
        'type': 'trojan',
        'tag': 'v6',
        'server': '2001:db8::2',
        'server_port': 443,
        'password': 'pw',
      });
      expect(link, startsWith('trojan://pw@[2001:db8::2]:443'));
    });

    test('non-proxy outbounds have no link format', () {
      expect(
        () => SingBoxShareLink.toLink({'type': 'selector', 'tag': 'proxy'}),
        throwsUnsupportedError,
      );
      expect(
        () => SingBoxShareLink.toLink({'type': 'vless', 'uuid': uuid}),
        throwsArgumentError,
      );
    });
  });

  test('every parsed outbound is accepted by sing-box', () async {
    final outbounds = [
      for (final link in validLinks) SingBoxShareLink.parse(link).json,
    ];
    for (final outbound in outbounds) {
      await expectSingBoxAccepts(
        const SingBoxConfigBuilder().build([outbound]),
        reason: outbound['tag'] as String,
      );
    }
  }, skip: singBoxBinary == null ? 'SING_BOX_BIN is not set' : null);

  test('the check helper detects invalid configs', () async {
    final error = await runSingBoxCheck({
      'outbounds': [
        {'type': 'nonexistent'},
      ],
    });
    expect(error, contains('unknown outbound type'));
  }, skip: singBoxBinary == null ? 'SING_BOX_BIN is not set' : null);
}
