import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/config/config.dart';

import 'fixtures.dart';
import 'support/sing_box_check.dart';

List<String> tags(List<SingBoxOutbound> outbounds) =>
    outbounds.map((o) => o.tag).toList();

void main() {
  final plain = validLinks.join('\n');

  test('plain link lists skip comments, blanks and invalid lines', () {
    final outbounds = SingBoxShareLink.parseSubscription(
      '﻿# comment\r\n\r\n${validLinks[0]}\r\n// note\n; ini comment\n'
      'not a link\nvless://broken\n  ${validLinks[10]}  \n',
    );
    expect(tags(outbounds), ['Reality NL', 'Trojan TCP']);
    expect(outbounds.first.link, validLinks[0]);
  });

  test('base64 encoded subscriptions', () {
    expect(
      SingBoxShareLink.parseSubscription(b64(plain)),
      hasLength(validLinks.length),
    );
    expect(
      SingBoxShareLink.parseSubscription(b64Url(plain)),
      hasLength(validLinks.length),
    );
    // Some providers wrap the base64 text.
    final wrapped = b64(
      plain,
    ).replaceAllMapped(RegExp('.{76}'), (m) => '${m[0]}\n');
    expect(
      SingBoxShareLink.parseSubscription(wrapped),
      hasLength(validLinks.length),
    );
  });

  test('every line encoded separately', () {
    final content =
        '${b64(validLinks[0])}\n${b64('${validLinks[10]}\n${validLinks[11]}')}';
    expect(tags(SingBoxShareLink.parseSubscription(content)), [
      'Reality NL',
      'Trojan TCP',
      'SIP002',
    ]);
  });

  test('duplicate tags are numbered', () {
    final outbounds = SingBoxShareLink.parseSubscription(
      [validLinks[0], validLinks[0], validLinks[0]].join('\n'),
    );
    expect(tags(outbounds), ['Reality NL', 'Reality NL (2)', 'Reality NL (3)']);
    expect(outbounds[1].json['tag'], 'Reality NL (2)');
    expect(outbounds[1].name, 'Reality NL');
  });

  test('sing-box configurations keep only proxy outbounds and endpoints', () {
    final config = {
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'proxy',
          'outbounds': ['a'],
        },
        {
          'type': 'urltest',
          'tag': 'auto',
          'outbounds': ['a'],
        },
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
        {'type': 'dns', 'tag': 'dns-out'},
        {
          'type': 'trojan',
          'tag': 'a',
          'server': 't.example.com',
          'server_port': 443,
          'password': 'x',
        },
        {'tag': 'no type'},
        'not an object',
      ],
      'endpoints': [
        {
          'type': 'wireguard',
          'tag': 'wg',
          'address': ['10.0.0.2/32'],
          'private_key': wgPrivateKey,
          'peers': [],
        },
      ],
    };
    final outbounds = SingBoxShareLink.parseSubscription(jsonEncode(config));
    expect(tags(outbounds), ['wg', 'a']);
    expect(outbounds.last.name, 'a');
    expect(outbounds.first.isEndpoint, isTrue);
    // Base64 wrapped JSON works as well.
    expect(tags(SingBoxShareLink.parseSubscription(b64(jsonEncode(config)))), [
      'wg',
      'a',
    ]);
  });

  test('JSON arrays may mix outbound objects and links', () {
    final outbounds = SingBoxShareLink.parseSubscription(
      jsonEncode([
        {'type': 'socks', 'tag': 's', 'server': '1.2.3.4', 'server_port': 1080},
        validLinks[10],
        'garbage',
      ]),
    );
    expect(tags(outbounds), ['s', 'Trojan TCP']);
  });

  test('a single outbound object', () {
    final outbounds = SingBoxShareLink.parseSubscription(
      jsonEncode({'type': 'socks', 'server': '1.2.3.4', 'server_port': 1080}),
    );
    expect(tags(outbounds), ['socks']);
  });

  test('legacy WireGuard outbounds become endpoints', () async {
    final outbounds = SingBoxShareLink.parseSubscription(
      jsonEncode({
        'outbounds': [
          {
            'type': 'wireguard',
            'tag': 'legacy-wg',
            'server': 'wg.example.com',
            'server_port': 51821,
            'local_address': ['10.0.0.2/32'],
            'private_key': wgPrivateKey,
            'peer_public_key': wgPublicKey,
            'reserved': [1, 2, 3],
            'mtu': 1280,
            'detour': 'other',
          },
        ],
      }),
    );
    expect(outbounds.single.json, {
      'type': 'wireguard',
      'tag': 'legacy-wg',
      'mtu': 1280,
      'address': ['10.0.0.2/32'],
      'private_key': wgPrivateKey,
      'peers': [
        {
          'address': 'wg.example.com',
          'port': 51821,
          'public_key': wgPublicKey,
          'allowed_ips': ['0.0.0.0/0', '::/0'],
          'reserved': [1, 2, 3],
        },
      ],
      'detour': 'other',
    });
    final endpoint = Map<String, dynamic>.of(outbounds.single.json)
      ..remove('detour');
    await expectSingBoxAccepts(const SingBoxConfigBuilder().build([endpoint]));
  });

  test('SIP008 documents', () async {
    final outbounds = SingBoxShareLink.parseSubscription(
      jsonEncode({
        'version': 1,
        'servers': [
          {
            'id': '27b8a625-4f4b-4428-9f0f-8a2317db7c79',
            'remarks': 'Server 1',
            'server': 'ss1.example.com',
            'server_port': 8388,
            'password': 'pw',
            'method': 'chacha20-poly1305',
            'plugin': 'simple-obfs',
            'plugin_opts': 'obfs=http',
          },
          {
            'id': 'id-2',
            'server': 'ss2.example.com',
            'server_port': 8389,
            'password': 'pw',
            'method': 'aes-256-gcm',
          },
          {
            'server': 'bad.example.com',
            'server_port': 1,
            'password': 'pw',
            'method': 'rc4',
          },
          {
            'server': 'kcp.example.com',
            'server_port': 1,
            'password': 'pw',
            'method': 'aes-128-gcm',
            'plugin': 'kcptun',
          },
          {'server': 'incomplete.example.com'},
        ],
      }),
    );
    expect(tags(outbounds), ['Server 1', 'id-2']);
    expect(outbounds.first.json, {
      'type': 'shadowsocks',
      'tag': 'Server 1',
      'server': 'ss1.example.com',
      'server_port': 8388,
      'method': 'chacha20-ietf-poly1305',
      'password': 'pw',
      'plugin': 'obfs-local',
      'plugin_opts': 'obfs=http',
    });
    await expectSingBoxAccepts(
      const SingBoxConfigBuilder().build([for (final o in outbounds) o.json]),
    );
  });

  test('empty and unrelated content yields nothing', () {
    expect(SingBoxShareLink.parseSubscription(''), isEmpty);
    expect(SingBoxShareLink.parseSubscription('  \n '), isEmpty);
    expect(
      SingBoxShareLink.parseSubscription('<html>Not found</html>'),
      isEmpty,
    );
    expect(SingBoxShareLink.parseSubscription('{"error": "expired"}'), isEmpty);
    expect(SingBoxShareLink.parseSubscription('{broken json'), isEmpty);
  });

  test('a whole subscription builds into an accepted configuration', () async {
    final outbounds = SingBoxShareLink.parseSubscription(b64('$plain\n$plain'));
    expect(outbounds, hasLength(validLinks.length * 2));
    expect(tags(outbounds).toSet(), hasLength(outbounds.length));
    await expectSingBoxAccepts(
      const SingBoxConfigBuilder().build([for (final o in outbounds) o.json]),
    );
  });
}
