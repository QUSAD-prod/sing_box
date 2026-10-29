import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/config/config.dart';

import 'fixtures.dart';
import 'support/sing_box_check.dart';

const builder = SingBoxConfigBuilder();

final vless = SingBoxShareLink.parse(validLinks[0]).json;
final trojan = SingBoxShareLink.parse(validLinks[10]).json;
final wireguard = SingBoxShareLink.parse(validLinks[25]).json;

List<Map<String, dynamic>> outboundsOf(Map<String, dynamic> config) =>
    (config['outbounds'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> outbound(Map<String, dynamic> config, String tag) =>
    outboundsOf(config).firstWhere((o) => o['tag'] == tag);

Map<String, dynamic> tun(Map<String, dynamic> config) =>
    (config['inbounds'] as List).cast<Map<String, dynamic>>().firstWhere(
      (i) => i['type'] == 'tun',
    );

List<Map<String, dynamic>> routeRules(Map<String, dynamic> config) =>
    ((config['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> dnsServers(Map<String, dynamic> config) =>
    ((config['dns'] as Map)['servers'] as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> dnsRules(Map<String, dynamic> config) =>
    ((config['dns'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

List<String> ruleSetTags(Map<String, dynamic> config) => [
  for (final r in ((config['route'] as Map)['rule_set'] as List? ?? const []))
    (r as Map)['tag'] as String,
];

/// A hand written user configuration with fields the builder does not
/// model.
Map<String, dynamic> userConfig() => {
  'log': {'level': 'warn'},
  'ntp': {'enabled': false, 'server': 'time.apple.com'},
  'dns': {
    'servers': [
      {'type': 'https', 'tag': 'cloudflare', 'server': '1.1.1.1'},
    ],
    'final': 'cloudflare',
  },
  'inbounds': [
    {
      'type': 'tun',
      'tag': 'tun',
      'address': ['172.18.0.1/30'],
      'auto_route': true,
      'exclude_package': ['com.user.keep'],
      'route_exclude_address': ['100.64.0.0/10'],
      'udp_timeout': '5m',
    },
  ],
  'outbounds': [
    {...vless, 'tag': 'my-proxy', 'connect_timeout': '5s'},
    {'type': 'direct', 'tag': 'bypass'},
  ],
  'route': {
    'rules': [
      {'action': 'sniff'},
      {'protocol': 'dns', 'action': 'hijack-dns'},
      {
        'domain_suffix': ['user.example'],
        'outbound': 'bypass',
      },
    ],
    'final': 'my-proxy',
  },
  'experimental': {
    'cache_file': {'enabled': true, 'path': 'cache.db'},
  },
};

const fullRules = SingBoxRoutingRules(
  bypassApps: ['com.bank.app', 'not a package'],
  bypassDomains: ['Example.RU', '.gov.ru', 'https://x.com/path', 'bad domain'],
  bypassSubnets: ['10.0.0.0/8', '192.168.1.1', 'nope'],
  blockedApps: ['com.ads.app'],
  blockedDomains: ['ads.example.com'],
  dnsServers: ['tls://dns.google', '9.9.9.9'],
  bypassCountries: ['RU', 'cn', 'uk', 'xx', 'de'],
  blockAds: true,
);

void main() {
  group('build', () {
    test('a single outbound needs no urltest group', () async {
      final config = builder.build([vless]);
      expect(outboundsOf(config).map((o) => o['tag']), [
        'proxy',
        'Reality NL',
        'direct',
      ]);
      expect(outbound(config, 'proxy'), {
        'type': 'selector',
        'tag': 'proxy',
        'outbounds': ['Reality NL'],
        'default': 'Reality NL',
        'interrupt_exist_connections': true,
      });
      expect((config['route'] as Map)['final'], 'proxy');
      expect(config.containsKey('endpoints'), isFalse);
      expect(config.containsKey('http_clients'), isFalse);
      expect((config['route'] as Map).containsKey('rule_set'), isFalse);
      await expectSingBoxAccepts(config);
    });

    test('several outbounds get an urltest group', () async {
      final config = builder.build([vless, trojan, wireguard]);
      expect(outbound(config, 'proxy')['outbounds'], [
        'auto',
        'Reality NL',
        'Trojan TCP',
        'WireGuard',
      ]);
      expect(outbound(config, 'proxy')['default'], 'auto');
      expect(outbound(config, 'auto'), {
        'type': 'urltest',
        'tag': 'auto',
        'outbounds': ['Reality NL', 'Trojan TCP', 'WireGuard'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': '3m',
        'tolerance': 50,
        'interrupt_exist_connections': true,
      });
      expect((config['endpoints'] as List).single['tag'], 'WireGuard');
      expect(outboundsOf(config).any((o) => o['type'] == 'wireguard'), isFalse);
      await expectSingBoxAccepts(config);
    });

    test('selectedTag picks the default selector member', () {
      expect(
        outbound(
          builder.build([vless, trojan], selectedTag: 'Trojan TCP'),
          'proxy',
        )['default'],
        'Trojan TCP',
      );
      expect(
        outbound(
          builder.build([vless, trojan], selectedTag: 'missing'),
          'proxy',
        )['default'],
        'auto',
      );
    });

    test('missing, clashing and reserved tags are made unique', () async {
      final noTag = Map<String, dynamic>.of(trojan)..remove('tag');
      final config = builder.build([
        {...vless, 'tag': 'proxy'},
        {...vless, 'tag': 'direct'},
        noTag,
        noTag,
      ]);
      expect(outbound(config, 'proxy')['outbounds'], [
        'auto',
        'proxy-2',
        'direct-2',
        'trojan',
        'trojan-2',
      ]);
      await expectSingBoxAccepts(config);
    });

    test('the input outbounds are not modified', () {
      final input = {...vless, 'tag': 'proxy'};
      final before = jsonEncode(input);
      builder.build([input]);
      expect(jsonEncode(input), before);
    });

    test('rejects empty input and outbounds without a type', () {
      expect(() => builder.build([]), throwsArgumentError);
      expect(
        () => builder.build([
          {'tag': 'x'},
        ]),
        throwsArgumentError,
      );
    });

    test('default sections', () {
      final config = builder.build([vless]);
      expect(config['log'], {'level': 'info', 'timestamp': true});
      expect(tun(config), {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        'stack': 'mixed',
      });
      expect(config['dns'], {
        'servers': [
          {
            'type': 'https',
            'tag': 'dns-remote',
            'server': '1.1.1.1',
            'detour': 'proxy',
          },
          {'type': 'local', 'tag': 'dns-direct'},
        ],
        'rules': [
          {'clash_mode': 'Direct', 'action': 'route', 'server': 'dns-direct'},
          {'clash_mode': 'Global', 'action': 'route', 'server': 'dns-remote'},
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      });
      expect(routeRules(config), [
        {'action': 'sniff'},
        {
          'type': 'logical',
          'mode': 'or',
          'rules': [
            {'protocol': 'dns'},
            {'port': 53},
          ],
          'action': 'hijack-dns',
        },
        {'clash_mode': 'Direct', 'action': 'route', 'outbound': 'direct'},
        {'clash_mode': 'Global', 'action': 'route', 'outbound': 'proxy'},
        {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
      ]);
      expect((config['route'] as Map)['auto_detect_interface'], true);
      expect((config['route'] as Map)['default_domain_resolver'], 'dns-direct');
      expect(config['experimental'], {
        'cache_file': {'enabled': true},
        'clash_api': {'default_mode': 'Rule'},
      });
    });
  });

  group('routing rules', () {
    test('bypassApps excludes valid packages from the tunnel', () {
      final config = builder.build(
        [vless],
        rules: const SingBoxRoutingRules(bypassApps: ['com.a', 'bad', 'com.a']),
      );
      expect(tun(config)['exclude_package'], ['com.a']);
      expect(tun(config).containsKey('include_package'), isFalse);
    });

    test('proxyApps wins over bypassApps', () {
      final config = builder.build(
        [vless],
        rules: const SingBoxRoutingRules(
          proxyApps: ['org.telegram.messenger'],
          bypassApps: ['com.a'],
        ),
      );
      expect(tun(config)['include_package'], ['org.telegram.messenger']);
      expect(tun(config).containsKey('exclude_package'), isFalse);
    });

    test('bypassDomains are normalized and resolved directly', () {
      final config = builder.build([vless], rules: fullRules);
      const domains = ['example.ru', 'gov.ru', 'x.com'];
      expect(
        routeRules(config),
        contains(
          equals({
            'domain_suffix': domains,
            'action': 'route',
            'outbound': 'direct',
          }),
        ),
      );
      expect(
        dnsRules(config),
        contains(
          equals({
            'domain_suffix': domains,
            'action': 'route',
            'server': 'dns-direct',
          }),
        ),
      );
    });

    test('bypassSubnets skip the tunnel and route directly', () {
      final config = builder.build([vless], rules: fullRules);
      const subnets = ['10.0.0.0/8', '192.168.1.1/32'];
      expect(tun(config)['route_exclude_address'], subnets);
      expect(
        routeRules(config),
        contains(
          equals({'ip_cidr': subnets, 'action': 'route', 'outbound': 'direct'}),
        ),
      );
      final noAutoRoute = SingBoxConfigBuilder(
        const SingBoxConfigOptions(tun: SingBoxTunOptions(autoRoute: false)),
      ).build([vless], rules: fullRules);
      expect(tun(noAutoRoute).containsKey('route_exclude_address'), isFalse);
    });

    test('blocked apps and domains are rejected and not resolved', () {
      final config = builder.build([vless], rules: fullRules);
      expect(routeRules(config)[2], {
        'package_name': ['com.ads.app'],
        'action': 'reject',
      });
      expect(routeRules(config)[3], {
        'domain_suffix': ['ads.example.com'],
        'action': 'reject',
      });
      expect(dnsRules(config).first, {
        'domain_suffix': ['ads.example.com'],
        'action': 'predefined',
        'rcode': 'NXDOMAIN',
      });
    });

    test('blockAds uses the ads rule-set for DNS and routing', () {
      final config = builder.build([
        vless,
      ], rules: const SingBoxRoutingRules(blockAds: true));
      expect(ruleSetTags(config), ['geosite-category-ads-all']);
      expect(
        routeRules(config),
        contains(
          equals({
            'rule_set': ['geosite-category-ads-all'],
            'action': 'reject',
          }),
        ),
      );
      expect(dnsRules(config).first, {
        'rule_set': ['geosite-category-ads-all'],
        'action': 'predefined',
        'rcode': 'NXDOMAIN',
      });
      expect(config['http_clients'], [
        {'tag': 'rule-set-download'},
      ]);
      expect((config['route'] as Map)['rule_set'], [
        {
          'type': 'remote',
          'tag': 'geosite-category-ads-all',
          'format': 'binary',
          'url':
              'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs',
          'http_client': 'rule-set-download',
          'update_interval': '1d',
        },
      ]);
    });

    test('bypassCountries reference existing rule-sets only', () {
      final config = builder.build([vless], rules: fullRules);
      const countrySets = [
        'geosite-category-ru',
        'geosite-ru-available-only-inside',
        'geoip-ru',
        'geosite-cn',
        'geoip-cn',
        'geoip-gb',
        'geoip-de',
      ];
      expect(ruleSetTags(config), ['geosite-category-ads-all', ...countrySets]);
      expect(routeRules(config).last, {
        'rule_set': countrySets,
        'action': 'route',
        'outbound': 'direct',
      });
      // geoip rule-sets must not be used by DNS rules.
      expect(
        dnsRules(config),
        contains(
          equals({
            'rule_set': [
              'geosite-category-ru',
              'geosite-ru-available-only-inside',
              'geosite-cn',
            ],
            'action': 'route',
            'server': 'dns-direct',
          }),
        ),
      );
    });

    test('dnsServers replace the remote resolver', () {
      final config = builder.build([vless], rules: fullRules);
      expect(dnsServers(config).take(2), [
        {
          'type': 'tls',
          'tag': 'dns-remote',
          'server': 'dns.google',
          'detour': 'proxy',
        },
        {
          'type': 'udp',
          'tag': 'dns-remote-2',
          'server': '9.9.9.9',
          'detour': 'proxy',
        },
      ]);
      expect((config['dns'] as Map)['final'], 'dns-remote');
      final local = builder.build([
        vless,
      ], rules: const SingBoxRoutingRules(dnsServers: ['local', 'bad://x']));
      expect(dnsServers(local).first, {'type': 'local', 'tag': 'dns-remote'});
      final invalid = builder.build([
        vless,
      ], rules: const SingBoxRoutingRules(dnsServers: ['bad://x']));
      expect(dnsServers(invalid).first['server'], '1.1.1.1');
    });

    test('bypassLan can be disabled', () {
      final config = builder.build([
        vless,
      ], rules: const SingBoxRoutingRules(bypassLan: false));
      expect(
        routeRules(config).where((r) => r['ip_is_private'] == true),
        isEmpty,
      );
    });

    test('every rule combination is accepted by sing-box', () async {
      final variants = <SingBoxRoutingRules>[
        const SingBoxRoutingRules(),
        fullRules,
        const SingBoxRoutingRules(
          proxyApps: ['org.telegram.messenger'],
          bypassLan: false,
        ),
        const SingBoxRoutingRules(
          blockAds: true,
          dnsServers: ['https://dns.adguard-dns.com/dns-query'],
        ),
        const SingBoxRoutingRules(
          bypassCountries: ['ir'],
          dnsServers: [
            'h3://dns.google',
            'quic://94.140.14.14',
            'tcp://8.8.8.8:53',
          ],
        ),
      ];
      for (final rules in variants) {
        await expectSingBoxAccepts(
          builder.build([vless, trojan, wireguard], rules: rules),
          reason: '$rules',
        );
      }
    }, skip: singBoxBinary == null ? 'SING_BOX_BIN is not set' : null);
  });

  group('routing mode and proxy lists', () {
    const listed = SingBoxRoutingRules(
      mode: SingBoxRoutingMode.proxyListed,
      proxyDomains: ['Example.ORG', 'bad domain'],
      proxySubnets: ['203.0.113.0/24', '198.51.100.7', 'nope'],
      blockedInCountries: ['RU', 'xx'],
      bypassCountries: ['ru'],
    );

    test('proxyAll keeps the proxy as the final outbound', () {
      final config = builder.build([vless]);
      expect((config['route'] as Map)['final'], 'proxy');
      expect((config['dns'] as Map)['final'], 'dns-remote');
    });

    test('proxyListed connects and resolves unlisted traffic directly', () {
      final config = builder.build([vless], rules: listed);
      expect((config['route'] as Map)['final'], 'direct');
      expect((config['dns'] as Map)['final'], 'dns-direct');
    });

    test('proxy lists come before the LAN and bypass rules', () {
      final rules = routeRules(builder.build([vless], rules: listed));
      final proxyRules = [
        {
          'domain_suffix': ['example.org'],
          'action': 'route',
          'outbound': 'proxy',
        },
        {
          'ip_cidr': ['203.0.113.0/24', '198.51.100.7/32'],
          'action': 'route',
          'outbound': 'proxy',
        },
        {
          'rule_set': ['geosite-ru-blocked', 'geoip-ru-blocked'],
          'action': 'route',
          'outbound': 'proxy',
        },
      ];
      final first = rules.indexOf(
        rules.firstWhere((r) => r['domain_suffix'] != null),
      );
      expect(rules.sublist(first, first + 3), proxyRules);
      final lan = rules.indexWhere((r) => r['ip_is_private'] == true);
      final bypass = rules.indexWhere(
        (r) => (r['rule_set'] as List?)?.contains('geoip-ru') ?? false,
      );
      expect(first, lessThan(lan));
      expect(lan, lessThan(bypass));
      // Global and Direct still override everything but the blocked lists.
      final global = rules.indexWhere((r) => r['clash_mode'] == 'Global');
      expect(global, lessThan(first));
    });

    test('blocked lists are downloaded from runetfreedom', () {
      final config = builder.build([vless], rules: listed);
      final sets = {
        for (final s in ((config['route'] as Map)['rule_set'] as List))
          (s as Map)['tag']: s['url'],
      };
      const base =
          'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box';
      expect(
        sets['geosite-ru-blocked'],
        '$base/rule-set-geosite/geosite-ru-blocked.srs',
      );
      expect(
        sets['geoip-ru-blocked'],
        '$base/rule-set-geoip/geoip-ru-blocked.srs',
      );
      expect(
        sets['geoip-ru'],
        'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs',
      );
    });

    test('proxied names are resolved remotely before the bypass lists', () {
      final rules = dnsRules(builder.build([vless], rules: listed));
      final domains = rules.indexOf(
        rules.firstWhere((r) => r['domain_suffix'] != null),
      );
      expect(rules.sublist(domains, domains + 3), [
        {
          'domain_suffix': ['example.org'],
          'action': 'route',
          'server': 'dns-remote',
        },
        // geoip rule-sets must not be used by DNS rules.
        {
          'rule_set': ['geosite-ru-blocked'],
          'action': 'route',
          'server': 'dns-remote',
        },
        {
          'rule_set': [
            'geosite-category-ru',
            'geosite-ru-available-only-inside',
          ],
          'action': 'route',
          'server': 'dns-direct',
        },
      ]);
    });

    test('FakeIP is limited to the proxy lists in proxyListed mode', () {
      const fakeIp = SingBoxConfigBuilder(
        SingBoxConfigOptions(dns: SingBoxDnsOptions(fakeIp: true)),
      );
      final listedRules = dnsRules(fakeIp.build([vless], rules: listed));
      expect(listedRules.where((r) => r['server'] == 'dns-fakeip'), [
        {
          'domain_suffix': ['example.org'],
          'query_type': ['A', 'AAAA'],
          'action': 'route',
          'server': 'dns-fakeip',
        },
        {
          'rule_set': ['geosite-ru-blocked'],
          'query_type': ['A', 'AAAA'],
          'action': 'route',
          'server': 'dns-fakeip',
        },
      ]);
      final all = dnsRules(
        fakeIp.build([
          vless,
        ], rules: listed.copyWith(mode: SingBoxRoutingMode.proxyAll)),
      );
      expect(all.last, {
        'query_type': ['A', 'AAAA'],
        'action': 'route',
        'server': 'dns-fakeip',
      });
    });

    test('countries without a blocked list are skipped', () {
      final config = builder.build([
        vless,
      ], rules: const SingBoxRoutingRules(blockedInCountries: ['de']));
      expect(ruleSetTags(config), isEmpty);
      expect(
        routeRules(config).where((r) => r['outbound'] == 'proxy'),
        hasLength(1), // the Clash Global rule
      );
    });

    test(
      'apply: proxy lists use the main outbound, final goes direct',
      () async {
        const rules = SingBoxRoutingRules(
          mode: SingBoxRoutingMode.proxyListed,
          proxyDomains: ['example.org'],
          blockedInCountries: ['ru'],
          dnsServers: ['tls://dns.google'],
        );
        final result = builder.apply(userConfig(), rules: rules);
        final route = result['route'] as Map;
        expect(route['final'], 'bypass');
        expect(routeRules(result).sublist(2, 4), [
          {
            'domain_suffix': ['example.org'],
            'action': 'route',
            'outbound': 'my-proxy',
          },
          {
            'rule_set': ['geosite-ru-blocked', 'geoip-ru-blocked'],
            'action': 'route',
            'outbound': 'my-proxy',
          },
        ]);
        // Custom DNS servers keep going through the proxy.
        expect(dnsServers(result).last, containsPair('detour', 'my-proxy'));
        await expectSingBoxAccepts(result);
      },
    );

    test('apply: no proxy lists without a proxy outbound', () {
      final config = {
        'outbounds': [
          {'type': 'direct', 'tag': 'direct'},
        ],
        'route': {'final': 'direct'},
      };
      final result = builder.apply(config, rules: listed);
      expect(
        routeRules(result).where((r) => r['outbound'] != 'direct'),
        isEmpty,
      );
      expect(ruleSetTags(result), isNot(contains('geosite-ru-blocked')));
    });

    test('every mode is accepted by sing-box', () async {
      const fakeIp = SingBoxConfigBuilder(
        SingBoxConfigOptions(dns: SingBoxDnsOptions(fakeIp: true)),
      );
      final variants = [
        listed,
        listed.copyWith(mode: SingBoxRoutingMode.proxyAll),
        const SingBoxRoutingRules(
          mode: SingBoxRoutingMode.proxyListed,
          blockedInCountries: ['cn'],
          blockAds: true,
          ipVersion: SingBoxIpVersion.ipv4,
        ),
        const SingBoxRoutingRules(mode: SingBoxRoutingMode.proxyListed),
      ];
      for (final rules in variants) {
        for (final b in [builder, fakeIp]) {
          await expectSingBoxAccepts(
            b.build([vless, trojan], rules: rules),
            reason: '$rules',
          );
        }
      }
    }, skip: singBoxBinary == null ? 'SING_BOX_BIN is not set' : null);
  });

  group('options', () {
    test('logging, sniffing, clash modes and cache can be disabled', () async {
      final config = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          logLevel: SingBoxConfigLogLevel.disabled,
          sniff: false,
          enableClashModes: false,
          cacheFile: false,
          interruptExistConnections: false,
        ),
      ).build([vless, trojan]);
      expect(config['log'], {'disabled': true});
      expect(routeRules(config).first['action'], 'hijack-dns');
      expect(
        routeRules(config).where((r) => r.containsKey('clash_mode')),
        isEmpty,
      );
      expect(dnsRules(config), isEmpty);
      expect(config['experimental'], {'clash_api': <String, dynamic>{}});
      expect(outbound(config, 'proxy')['interrupt_exist_connections'], false);
      await expectSingBoxAccepts(config);
    });

    test('IPv6 can be disabled', () async {
      final config = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          tun: SingBoxTunOptions(enableIpv6: false),
          dns: SingBoxDnsOptions(fakeIp: true),
        ),
      ).build([vless]);
      expect(tun(config)['address'], ['172.19.0.1/30']);
      expect((config['dns'] as Map)['strategy'], 'ipv4_only');
      expect(dnsServers(config).last, {
        'type': 'fakeip',
        'tag': 'dns-fakeip',
        'inet4_range': '198.18.0.0/15',
      });
      expect(dnsRules(config).last, {
        'query_type': ['A'],
        'action': 'route',
        'server': 'dns-fakeip',
      });
      await expectSingBoxAccepts(config);
    });

    test('IP version: IPv4 only rejects proxied IPv6 connections', () async {
      final config = const SingBoxConfigBuilder(
        SingBoxConfigOptions(dns: SingBoxDnsOptions(fakeIp: true)),
      ).build([
        vless,
      ], rules: const SingBoxRoutingRules(ipVersion: SingBoxIpVersion.ipv4));
      // The TUN keeps IPv6 so IPv6 traffic cannot leave outside the VPN.
      expect(tun(config)['address'], [
        '172.19.0.1/30',
        'fdfe:dcba:9876::1/126',
      ]);
      expect((config['dns'] as Map)['strategy'], 'ipv4_only');
      expect(dnsServers(config).last.containsKey('inet6_range'), isFalse);
      expect(dnsRules(config).last['query_type'], ['A']);
      expect(routeRules(config).last, {'ip_version': 6, 'action': 'reject'});
      await expectSingBoxAccepts(config);
    });

    test('IP version: IPv6 only and dual', () async {
      final v6 = const SingBoxConfigBuilder(
        SingBoxConfigOptions(dns: SingBoxDnsOptions(fakeIp: true)),
      ).build([
        vless,
      ], rules: const SingBoxRoutingRules(ipVersion: SingBoxIpVersion.ipv6));
      expect((v6['dns'] as Map)['strategy'], 'ipv6_only');
      expect(dnsServers(v6).last['inet6_range'], 'fc00::/18');
      expect(dnsRules(v6).last['query_type'], ['A', 'AAAA']);
      expect(routeRules(v6).any((r) => r.containsKey('ip_version')), isFalse);
      await expectSingBoxAccepts(v6);

      final dual = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          dns: SingBoxDnsOptions(strategy: SingBoxDnsStrategy.preferIpv6),
        ),
      ).build([vless]);
      expect((dual['dns'] as Map)['strategy'], 'prefer_ipv6');
      expect(routeRules(dual).any((r) => r.containsKey('ip_version')), isFalse);
      await expectSingBoxAccepts(dual);
    });

    test('FakeIP, reverse mapping and custom resolvers', () async {
      final config = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          dns: SingBoxDnsOptions(
            fakeIp: true,
            reverseMapping: true,
            remote: 'quic://dns.adguard-dns.com',
            direct: 'https://dns.alidns.com/dns-query',
            strategy: SingBoxDnsStrategy.preferIpv6,
          ),
        ),
      ).build([vless]);
      expect(dnsServers(config), [
        {
          'type': 'quic',
          'tag': 'dns-remote',
          'server': 'dns.adguard-dns.com',
          'detour': 'proxy',
        },
        {
          'type': 'https',
          'tag': 'dns-direct',
          'server': 'dns.alidns.com',
          'domain_resolver': 'dns-local',
        },
        {'type': 'local', 'tag': 'dns-local'},
        {
          'type': 'fakeip',
          'tag': 'dns-fakeip',
          'inet4_range': '198.18.0.0/15',
          'inet6_range': 'fc00::/18',
        },
      ]);
      expect((config['dns'] as Map)['strategy'], 'prefer_ipv6');
      expect((config['dns'] as Map)['reverse_mapping'], true);
      expect((config['experimental'] as Map)['cache_file'], {
        'enabled': true,
        'store_fakeip': true,
      });
      await expectSingBoxAccepts(config);
    });

    test('an invalid direct resolver falls back to the system one', () {
      final config = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          dns: SingBoxDnsOptions(direct: 'bad://x', remote: 'bad://y'),
        ),
      ).build([vless]);
      expect(dnsServers(config), [
        {
          'type': 'https',
          'tag': 'dns-remote',
          'server': '1.1.1.1',
          'detour': 'proxy',
        },
        {'type': 'local', 'tag': 'dns-direct'},
      ]);
    });

    test('TUN stack, NAT, interface and MTU', () async {
      final config = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          tun: SingBoxTunOptions(
            stack: SingBoxTunStack.gvisor,
            endpointIndependentNat: true,
            interfaceName: 'tun7',
            mtu: 1500,
            strictRoute: false,
          ),
        ),
      ).build([vless]);
      expect(tun(config), containsPair('stack', 'gvisor'));
      expect(tun(config), containsPair('endpoint_independent_nat', true));
      expect(tun(config), containsPair('interface_name', 'tun7'));
      expect(tun(config), containsPair('mtu', 1500));
      expect(tun(config), containsPair('strict_route', false));
      final system = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          tun: SingBoxTunOptions(
            stack: SingBoxTunStack.system,
            endpointIndependentNat: true,
          ),
        ),
      ).build([vless]);
      expect(tun(system).containsKey('endpoint_independent_nat'), isFalse);
      await expectSingBoxAccepts(config);
      await expectSingBoxAccepts(system);
    });

    test('URL test and rule-set options', () async {
      final config = const SingBoxConfigBuilder(
        SingBoxConfigOptions(
          urlTestUrl: 'https://cp.cloudflare.com',
          urlTestInterval: Duration(minutes: 10, seconds: 30),
          urlTestTolerance: 150,
          ruleSetDownloadDetour: 'proxy',
          ruleSetUpdateInterval: Duration(hours: 12),
          geoipRuleSetUrl: 'https://mirror.example.com/geoip/{tag}.srs',
          geositeRuleSetUrl: 'https://mirror.example.com/geosite/{tag}.srs',
        ),
      ).build([
        vless,
        trojan,
      ], rules: const SingBoxRoutingRules(bypassCountries: ['ru']));
      expect(
        outbound(config, 'auto'),
        containsPair('url', 'https://cp.cloudflare.com'),
      );
      expect(outbound(config, 'auto'), containsPair('interval', '630s'));
      expect(outbound(config, 'auto'), containsPair('tolerance', 150));
      expect(config['http_clients'], [
        {'tag': 'rule-set-download', 'detour': 'proxy'},
      ]);
      final sets =
          ((config['route'] as Map)['rule_set'] as List)
              .cast<Map<String, dynamic>>();
      expect(sets.map((s) => s['url']), [
        'https://mirror.example.com/geosite/geosite-category-ru.srs',
        // Not a SagerNet list: its fixed URL is kept.
        'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-ru-available-only-inside.srs',
        'https://mirror.example.com/geoip/geoip-ru.srs',
      ]);
      expect(sets.map((s) => s['update_interval']).toSet(), {'12h'});
      await expectSingBoxAccepts(config);
    });
  });

  group('apply', () {
    test('does not modify the input and keeps unknown fields', () async {
      final input = userConfig();
      final before = jsonEncode(input);
      final result = builder.apply(input, rules: fullRules);
      expect(jsonEncode(input), before);
      expect(result['ntp'], input['ntp']);
      expect(result['log'], {'level': 'warn'});
      expect(outbound(result, 'my-proxy')['connect_timeout'], '5s');
      expect(tun(result)['udp_timeout'], '5m');
      expect((result['experimental'] as Map)['cache_file'], {
        'enabled': true,
        'path': 'cache.db',
      });
      expect((result['route'] as Map)['final'], 'my-proxy');
      await expectSingBoxAccepts(result);
    });

    test('default rules only add LAN bypass and interface detection', () async {
      final result = builder.apply(userConfig());
      final expected = userConfig();
      (expected['route'] as Map)['rules'] = [
        {'action': 'sniff'},
        {'protocol': 'dns', 'action': 'hijack-dns'},
        {'ip_is_private': true, 'action': 'route', 'outbound': 'bypass'},
        {
          'domain_suffix': ['user.example'],
          'outbound': 'bypass',
        },
      ];
      (expected['route'] as Map)['auto_detect_interface'] = true;
      expect(result, expected);
      await expectSingBoxAccepts(result);
    });

    test('rules are inserted after the leading sniff and hijack-dns rules', () {
      final rules = routeRules(builder.apply(userConfig(), rules: fullRules));
      expect(rules[0], {'action': 'sniff'});
      expect(rules[1], {'protocol': 'dns', 'action': 'hijack-dns'});
      expect(rules[2], {
        'package_name': ['com.ads.app'],
        'action': 'reject',
      });
      expect(rules.last, {
        'domain_suffix': ['user.example'],
        'outbound': 'bypass',
      });
      expect(rules.where((r) => r.containsKey('clash_mode')), isEmpty);
      expect(
        rules,
        contains(
          equals({
            'ip_cidr': ['10.0.0.0/8', '192.168.1.1/32'],
            'action': 'route',
            'outbound': 'bypass',
          }),
        ),
      );
    });

    test('per-app lists and subnets are merged into TUN inbounds', () {
      final excluded = tun(builder.apply(userConfig(), rules: fullRules));
      expect(excluded['exclude_package'], ['com.user.keep', 'com.bank.app']);
      expect(excluded['route_exclude_address'], [
        '100.64.0.0/10',
        '10.0.0.0/8',
        '192.168.1.1/32',
      ]);
      final included = tun(
        builder.apply(
          userConfig(),
          rules: const SingBoxRoutingRules(
            proxyApps: ['org.telegram.messenger'],
          ),
        ),
      );
      expect(included['include_package'], ['org.telegram.messenger']);
      expect(included.containsKey('exclude_package'), isFalse);
    });

    test('adds a TUN inbound and a direct outbound when missing', () async {
      final result = builder.apply({
        'outbounds': [
          {...trojan, 'tag': 'direct'},
        ],
      }, rules: const SingBoxRoutingRules(bypassSubnets: ['10.0.0.0/8']));
      expect(tun(result), {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        'stack': 'mixed',
        'route_exclude_address': ['10.0.0.0/8'],
      });
      expect(outboundsOf(result).last, {'type': 'direct', 'tag': 'direct-2'});
      expect(routeRules(result).first, {
        'ip_is_private': true,
        'action': 'route',
        'outbound': 'direct-2',
      });
      expect((result['route'] as Map)['auto_detect_interface'], true);
      await expectSingBoxAccepts(result);
    });

    test('an explicit auto_detect_interface is kept', () {
      final input = userConfig();
      (input['route'] as Map)['auto_detect_interface'] = false;
      expect(
        (builder.apply(input)['route'] as Map)['auto_detect_interface'],
        false,
      );
    });

    test('rule-sets are added once with an HTTP client', () async {
      const rules = SingBoxRoutingRules(
        bypassCountries: ['ru'],
        blockAds: true,
      );
      final once = builder.apply(userConfig(), rules: rules);
      expect(ruleSetTags(once), [
        'geosite-category-ads-all',
        'geosite-category-ru',
        'geosite-ru-available-only-inside',
        'geoip-ru',
      ]);
      expect(once['http_clients'], [
        {'tag': 'rule-set-download'},
      ]);
      final twice = builder.apply(once, rules: rules);
      expect(ruleSetTags(twice), ruleSetTags(once));
      expect(twice['http_clients'], once['http_clients']);
      await expectSingBoxAccepts(once);
    });

    test('blocked domains are answered with NXDOMAIN', () {
      final result = builder.apply(
        userConfig(),
        rules: const SingBoxRoutingRules(blockedDomains: ['ads.example.com']),
      );
      expect(dnsRules(result), [
        {
          'domain_suffix': ['ads.example.com'],
          'action': 'predefined',
          'rcode': 'NXDOMAIN',
        },
      ]);
    });

    test('custom DNS servers go through the main outbound', () async {
      final result = builder.apply(
        userConfig(),
        rules: const SingBoxRoutingRules(
          dnsServers: ['tls://dns.google', 'bad://x', '8.8.8.8'],
        ),
      );
      expect(dnsServers(result), [
        {'type': 'https', 'tag': 'cloudflare', 'server': '1.1.1.1'},
        {
          'type': 'tls',
          'tag': 'dns-custom',
          'server': 'dns.google',
          'detour': 'my-proxy',
        },
        {
          'type': 'udp',
          'tag': 'dns-custom-2',
          'server': '8.8.8.8',
          'detour': 'my-proxy',
        },
      ]);
      expect((result['dns'] as Map)['final'], 'dns-custom');
      // The proxy server name is still resolved by the original server.
      expect((result['route'] as Map)['default_domain_resolver'], 'cloudflare');
      await expectSingBoxAccepts(result);
    });

    test(
      'custom DNS servers keep the system resolver for outbound names',
      () async {
        final input = userConfig()..remove('dns');
        final result = builder.apply(
          input,
          rules: const SingBoxRoutingRules(dnsServers: ['8.8.8.8']),
        );
        expect(dnsServers(result), [
          {
            'type': 'udp',
            'tag': 'dns-custom',
            'server': '8.8.8.8',
            'detour': 'my-proxy',
          },
          {'type': 'local', 'tag': 'dns-local'},
        ]);
        expect(
          (result['route'] as Map)['default_domain_resolver'],
          'dns-local',
        );
        await expectSingBoxAccepts(result);
      },
    );

    test('an explicit default_domain_resolver is kept', () async {
      final input = userConfig();
      (input['route'] as Map)['default_domain_resolver'] = 'cloudflare';
      (input['dns'] as Map)['servers'] = [
        ...((input['dns'] as Map)['servers'] as List),
        {'type': 'local', 'tag': 'system'},
      ];
      final result = builder.apply(
        input,
        rules: const SingBoxRoutingRules(dnsServers: ['8.8.8.8']),
      );
      expect((result['route'] as Map)['default_domain_resolver'], 'cloudflare');
      expect(dnsServers(result).map((s) => s['tag']), [
        'cloudflare',
        'system',
        'dns-custom',
      ]);
      await expectSingBoxAccepts(result);
    });

    test(
      'custom DNS servers never detour to an empty direct outbound',
      () async {
        final input = userConfig();
        (input['route'] as Map)['final'] = 'bypass';
        final result = builder.apply(
          input,
          rules: const SingBoxRoutingRules(
            dnsServers: ['tls://dns.google', '8.8.8.8'],
          ),
        );
        expect(dnsServers(result).skip(1), [
          {
            'type': 'tls',
            'tag': 'dns-custom',
            'server': 'dns.google',
            'domain_resolver': 'dns-local',
          },
          {'type': 'local', 'tag': 'dns-local'},
          {'type': 'udp', 'tag': 'dns-custom-2', 'server': '8.8.8.8'},
        ]);
        await expectSingBoxAccepts(result);
      },
    );

    test('without route.final the first proxy outbound is used', () {
      final input = userConfig();
      (input['route'] as Map).remove('final');
      final result = builder.apply(
        input,
        rules: const SingBoxRoutingRules(dnsServers: ['1.0.0.1']),
      );
      expect(dnsServers(result).last['detour'], 'my-proxy');
    });
  });

  group('apply IP version', () {
    test('dual leaves DNS and routing of the user config alone', () {
      final result = builder.apply(userConfig());
      expect((result['dns'] as Map?)?['strategy'], isNull);
      expect(
        routeRules(result).any((r) => r.containsKey('ip_version')),
        isFalse,
      );
    });

    test('IPv4 only sets the strategy and rejects IPv6 last', () async {
      final result = builder.apply(
        userConfig(),
        rules: const SingBoxRoutingRules(ipVersion: SingBoxIpVersion.ipv4),
      );
      expect((result['dns'] as Map)['strategy'], 'ipv4_only');
      expect(routeRules(result).last, {'ip_version': 6, 'action': 'reject'});
      // The user's own rules stay in front of it.
      expect(routeRules(result)[routeRules(result).length - 2], {
        'domain_suffix': ['user.example'],
        'outbound': 'bypass',
      });
      await expectSingBoxAccepts(result);
    });

    test('IPv6 only sets the strategy', () async {
      final result = builder.apply(
        userConfig(),
        rules: const SingBoxRoutingRules(ipVersion: SingBoxIpVersion.ipv6),
      );
      expect((result['dns'] as Map)['strategy'], 'ipv6_only');
      await expectSingBoxAccepts(result);
    });
  });

  group('buildFromJson', () {
    test('patches complete configurations', () {
      final json = builder.buildFromJson(
        jsonEncode(userConfig()),
        rules: fullRules,
      );
      expect(jsonDecode(json), builder.apply(userConfig(), rules: fullRules));
    });

    test('wraps one outbound or a list of outbounds', () {
      final single =
          jsonDecode(builder.buildFromJson(jsonEncode(vless)))
              as Map<String, dynamic>;
      expect(outbound(single, 'proxy')['outbounds'], ['Reality NL']);
      final list =
          jsonDecode(
                builder.buildFromJson(jsonEncode([vless, trojan, 'garbage'])),
              )
              as Map<String, dynamic>;
      expect(outbound(list, 'proxy')['outbounds'], [
        'auto',
        'Reality NL',
        'Trojan TCP',
      ]);
    });

    test('rejects invalid input', () {
      expect(() => builder.buildFromJson('{'), throwsFormatException);
      expect(() => builder.buildFromJson('"text"'), throwsFormatException);
      expect(
        () => builder.buildFromJson('{"tag": "no type"}'),
        throwsArgumentError,
      );
    });

    test('isFullConfig', () {
      expect(SingBoxConfigBuilder.isFullConfig({'route': {}}), isTrue);
      expect(SingBoxConfigBuilder.isFullConfig({'endpoints': []}), isTrue);
      expect(SingBoxConfigBuilder.isFullConfig(vless), isFalse);
    });
  });
}
