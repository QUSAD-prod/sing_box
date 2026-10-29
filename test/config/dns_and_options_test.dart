import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/config/config.dart';

void main() {
  group('SingBoxDnsServer.parse', () {
    final cases = <String, Map<String, dynamic>>{
      'local': {'type': 'local', 'tag': 't'},
      'System': {'type': 'local', 'tag': 't'},
      '8.8.8.8': {'type': 'udp', 'tag': 't', 'server': '8.8.8.8'},
      '8.8.8.8:5353': {
        'type': 'udp',
        'tag': 't',
        'server': '8.8.8.8',
        'server_port': 5353,
      },
      '[2001:4860:4860::8888]:53': {
        'type': 'udp',
        'tag': 't',
        'server': '2001:4860:4860::8888',
      },
      'udp://1.1.1.1': {'type': 'udp', 'tag': 't', 'server': '1.1.1.1'},
      'tcp://1.1.1.1:53': {'type': 'tcp', 'tag': 't', 'server': '1.1.1.1'},
      'tls://1.1.1.1': {'type': 'tls', 'tag': 't', 'server': '1.1.1.1'},
      'dot://dns.google:8853': {
        'type': 'tls',
        'tag': 't',
        'server': 'dns.google',
        'server_port': 8853,
      },
      'quic://dns.adguard-dns.com': {
        'type': 'quic',
        'tag': 't',
        'server': 'dns.adguard-dns.com',
      },
      'https://1.1.1.1/dns-query': {
        'type': 'https',
        'tag': 't',
        'server': '1.1.1.1',
      },
      'doh://dns.google/resolve#x': {
        'type': 'https',
        'tag': 't',
        'server': 'dns.google',
        'path': '/resolve',
      },
      'https://dns.nextdns.io/abc123': {
        'type': 'https',
        'tag': 't',
        'server': 'dns.nextdns.io',
        'path': '/abc123',
      },
      'https://user@dns.example.com?ct=json': {
        'type': 'https',
        'tag': 't',
        'server': 'dns.example.com',
        'path': '/dns-query?ct=json',
      },
      'h3://dns.google': {'type': 'h3', 'tag': 't', 'server': 'dns.google'},
      'dhcp://auto': {'type': 'dhcp', 'tag': 't'},
      'dhcp://en0': {'type': 'dhcp', 'tag': 't', 'interface': 'en0'},
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(SingBoxDnsServer.parse(entry.key, tag: 't'), entry.value);
        expect(SingBoxDnsServer.isValid(entry.key), isTrue);
      });
    }

    test('detour and domain resolver', () {
      expect(
        SingBoxDnsServer.parse(
          'tls://dns.google',
          tag: 't',
          detour: 'proxy',
          domainResolver: 'local',
        ),
        {'type': 'tls', 'tag': 't', 'server': 'dns.google', 'detour': 'proxy'},
      );
      expect(
        SingBoxDnsServer.parse(
          'tls://dns.google',
          tag: 't',
          domainResolver: 'local',
        ),
        {
          'type': 'tls',
          'tag': 't',
          'server': 'dns.google',
          'domain_resolver': 'local',
        },
      );
      expect(
        SingBoxDnsServer.parse(
          'tls://8.8.8.8',
          tag: 't',
          domainResolver: 'local',
        ),
        {'type': 'tls', 'tag': 't', 'server': '8.8.8.8'},
      );
    });

    test('needsDomainResolver', () {
      expect(
        SingBoxDnsServer.needsDomainResolver(
          SingBoxDnsServer.parse('tls://dns.google', tag: 't'),
        ),
        isTrue,
      );
      expect(
        SingBoxDnsServer.needsDomainResolver(
          SingBoxDnsServer.parse('tls://dns.google', tag: 't', detour: 'proxy'),
        ),
        isFalse,
      );
      expect(
        SingBoxDnsServer.needsDomainResolver(
          SingBoxDnsServer.parse('tls://8.8.8.8', tag: 't'),
        ),
        isFalse,
      );
      expect(
        SingBoxDnsServer.needsDomainResolver(
          SingBoxDnsServer.parse('local', tag: 't'),
        ),
        isFalse,
      );
    });

    final invalid = <String, String>{
      '': 'empty',
      'rcode://refused': 'Legacy DNS address',
      'fakeip://x': 'Legacy DNS address',
      'http://1.1.1.1/dns-query': 'plain HTTP',
      'sdns://AgcAAAAAAAAA': 'Unsupported DNS server scheme "sdns"',
      'tls://': 'no host',
      'tls://bad host': 'Invalid DNS server host',
      '1.1.1.1:0': 'Invalid port',
    };
    for (final entry in invalid.entries) {
      test('rejects "${entry.key}"', () {
        expect(
          () => SingBoxDnsServer.parse(entry.key, tag: 't'),
          throwsA(
            isFormatException.having(
              (e) => e.message,
              'message',
              contains(entry.value),
            ),
          ),
        );
        expect(SingBoxDnsServer.tryParse(entry.key, tag: 't'), isNull);
        expect(SingBoxDnsServer.isValid(entry.key), isFalse);
      });
    }
  });

  group('SingBoxRuleSets', () {
    test('country codes are normalized', () {
      expect(SingBoxRuleSets.normalizeCountryCode(' RU '), 'ru');
      expect(SingBoxRuleSets.normalizeCountryCode('geoip-de'), 'de');
      expect(SingBoxRuleSets.normalizeCountryCode('uk'), 'gb');
      expect(SingBoxRuleSets.normalizeCountryCode('xx'), isNull);
      expect(SingBoxRuleSets.isSupportedCountry('IR'), isTrue);
      expect(SingBoxRuleSets.isSupportedCountry('zz'), isFalse);
    });

    test('only curated countries get geosite lists', () {
      expect(SingBoxRuleSets.countryRuleSets('ru'), [
        'geosite-category-ru',
        'geosite-ru-available-only-inside',
        'geoip-ru',
      ]);
      expect(SingBoxRuleSets.countryRuleSets('cn'), ['geosite-cn', 'geoip-cn']);
      expect(SingBoxRuleSets.countryRuleSets('ir'), [
        'geosite-category-ir',
        'geoip-ir',
      ]);
      expect(SingBoxRuleSets.countryRuleSets('de'), ['geoip-de']);
      expect(SingBoxRuleSets.countryRuleSets('nowhere'), isEmpty);
    });

    test('blocked resource lists per country', () {
      expect(SingBoxRuleSets.blockedRuleSets(' RU '), [
        'geosite-ru-blocked',
        'geoip-ru-blocked',
      ]);
      expect(SingBoxRuleSets.blockedRuleSets('cn'), [
        'geosite-geolocation-!cn',
      ]);
      expect(SingBoxRuleSets.blockedRuleSets('de'), isEmpty);
      expect(SingBoxRuleSets.isSupportedBlockedCountry('ru'), isTrue);
      expect(SingBoxRuleSets.isSupportedBlockedCountry('ir'), isFalse);
      // Third-party lists keep their URL whatever the SagerNet templates.
      expect(
        SingBoxRuleSets.url(
          'geoip-ru-blocked',
          geoipUrl: 'https://m.example/{tag}.srs',
        ),
        'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru-blocked.srs',
      );
      for (final tags in SingBoxRuleSets.blockedCountryTags.values) {
        for (final tag in tags) {
          expect(SingBoxRuleSets.url(tag), endsWith('/$tag.srs'));
        }
      }
    });

    test('GitHub rule-sets have jsDelivr mirrors', () {
      expect(SingBoxRuleSets.mirrors(SingBoxRuleSets.url('geoip-ru')), [
        'https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-ru.srs',
        'https://testingcf.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-ru.srs',
      ]);
      expect(
        SingBoxRuleSets.mirrors(SingBoxRuleSets.url('geoip-ru-blocked')).first,
        'https://cdn.jsdelivr.net/gh/runetfreedom/russia-v2ray-rules-dat@release/sing-box/rule-set-geoip/geoip-ru-blocked.srs',
      );
      expect(
        SingBoxRuleSets.mirrors('https://example.com/a/b/c/d.srs'),
        isEmpty,
      );
      expect(
        SingBoxRuleSets.mirrors('https://raw.githubusercontent.com/a/b'),
        isEmpty,
      );
    });

    test('remote rule-set objects', () {
      expect(
        SingBoxRuleSets.remote(
          'geoip-ru',
          httpClient: 'c',
          updateInterval: const Duration(hours: 6),
        ),
        {
          'type': 'remote',
          'tag': 'geoip-ru',
          'format': 'binary',
          'url':
              'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs',
          'http_client': 'c',
          'update_interval': '6h',
        },
      );
      expect(
        SingBoxRuleSets.remote('geosite-cn').containsKey('http_client'),
        isFalse,
      );
      expect(
        SingBoxRuleSets.url(
          'geosite-cn',
          geositeUrl: 'https://m.example/{tag}.srs',
        ),
        'https://m.example/geosite-cn.srs',
      );
    });
  });

  group('options', () {
    test('enums parse wire values with fallbacks', () {
      expect(
        SingBoxConfigLogLevel.fromValue('WARNING'),
        SingBoxConfigLogLevel.warn,
      );
      expect(
        SingBoxConfigLogLevel.fromValue('panic'),
        SingBoxConfigLogLevel.panic,
      );
      expect(SingBoxConfigLogLevel.fromValue(null), SingBoxConfigLogLevel.info);
      expect(SingBoxTunStack.fromValue('GVISOR'), SingBoxTunStack.gvisor);
      expect(SingBoxTunStack.fromValue('lwip'), SingBoxTunStack.mixed);
      expect(
        SingBoxDnsStrategy.fromValue('ipv6_only'),
        SingBoxDnsStrategy.ipv6Only,
      );
      expect(
        SingBoxDnsStrategy.fromValue('preferIpv6'),
        SingBoxDnsStrategy.preferIpv6,
      );
      expect(SingBoxDnsStrategy.fromValue('?'), SingBoxDnsStrategy.preferIpv4);
    });

    test('SingBoxConfigOptions round trips through maps', () {
      const options = SingBoxConfigOptions(
        logLevel: SingBoxConfigLogLevel.debug,
        logTimestamp: false,
        tun: SingBoxTunOptions(
          inet4Address: '10.10.0.1/30',
          enableIpv6: false,
          mtu: 1400,
          stack: SingBoxTunStack.system,
          strictRoute: false,
          interfaceName: 'utun9',
          endpointIndependentNat: true,
        ),
        dns: SingBoxDnsOptions(
          remote: 'tls://dns.google',
          direct: '77.88.8.8',
          strategy: SingBoxDnsStrategy.ipv4Only,
          fakeIp: true,
          reverseMapping: true,
        ),
        sniff: false,
        urlTestUrl: 'https://cp.cloudflare.com',
        urlTestInterval: Duration(minutes: 5),
        urlTestTolerance: 10,
        interruptExistConnections: false,
        enableClashModes: false,
        cacheFile: false,
        ruleSetDownloadDetour: 'proxy',
        ruleSetUpdateInterval: Duration(hours: 3),
        geoipRuleSetUrl: 'https://m.example/ip/{tag}.srs',
        geositeRuleSetUrl: 'https://m.example/site/{tag}.srs',
        probeAddress: '',
        localProxy: SingBoxLocalProxy(
          listen: '0.0.0.0',
          port: 7890,
          systemProxy: true,
          bypassDomains: ['example.com'],
          matchDomains: ['example.org'],
        ),
      );
      expect(SingBoxConfigOptions.fromMap(options.toMap()), options);
      expect(
        SingBoxConfigOptions.fromMap(
          jsonDecode(jsonEncode(options.toMap())) as Map,
        ),
        options,
      );
      expect(
        SingBoxLocalProxy.fromMap(const {'port': 70000, 'listen': ''}),
        const SingBoxLocalProxy(),
      );
      expect(
        SingBoxConfigOptions.fromMap(options.toMap()).hashCode,
        options.hashCode,
      );
      expect(
        SingBoxConfigOptions.fromMap(const {}),
        const SingBoxConfigOptions(),
      );
      expect(
        SingBoxConfigOptions.fromMap(const {
          'urlTestInterval': 0,
          'ruleSetUpdateInterval': -1,
        }),
        const SingBoxConfigOptions(),
      );
      expect(
        options.copyWith(sniff: true, tun: const SingBoxTunOptions()),
        isNot(options),
      );
      expect(options.copyWith(), options);
    });

    test('SingBoxRoutingRules round trips through maps', () {
      const rules = SingBoxRoutingRules(
        mode: SingBoxRoutingMode.proxyListed,
        bypassApps: ['a.b'],
        proxyApps: ['c.d'],
        proxyDomains: ['y.com'],
        proxySubnets: ['192.0.2.0/24'],
        bypassDomains: ['x.com'],
        bypassSubnets: ['10.0.0.0/8'],
        blockedApps: ['e.f'],
        blockedDomains: ['ads.com'],
        dnsServers: ['1.1.1.1'],
        bypassLan: false,
        bypassCountries: ['ru'],
        blockedInCountries: ['ru'],
        blockAds: true,
        blockQuic: true,
        bittorrentDirect: true,
        customRules: [
          SingBoxRoutingRule(
            action: SingBoxRuleAction.block,
            domains: ['z.com'],
          ),
        ],
        ipVersion: SingBoxIpVersion.ipv4,
      );
      expect(SingBoxRoutingRules.fromMap(rules.toMap()), rules);
      expect(
        SingBoxRoutingRules.fromMap(
          jsonDecode(jsonEncode(rules.toMap())) as Map,
        ),
        rules,
      );
      expect(rules.toMap()['ipVersion'], 'ipv4');
      expect(rules.toMap()['mode'], 'proxyListed');
      expect(rules.copyWith(ipVersion: SingBoxIpVersion.dual), isNot(rules));
      expect(rules.copyWith(mode: SingBoxRoutingMode.proxyAll), isNot(rules));
      expect(rules.copyWith(proxyDomains: const []), isNot(rules));
      expect(rules.copyWith(blockedInCountries: const []), isNot(rules));
      expect(rules.copyWith(blockQuic: false), isNot(rules));
      expect(rules.copyWith(bittorrentDirect: false), isNot(rules));
      expect(rules.copyWith(customRules: const []), isNot(rules));
      // Custom rules without a valid action are dropped.
      expect(
        SingBoxRoutingRules.fromMap({
          'customRules': [
            {
              'action': 'teleport',
              'domains': ['x.com'],
            },
            'not a map',
            {
              'action': 'direct',
              'domains': ['x.com'],
            },
          ],
        }).customRules,
        const [
          SingBoxRoutingRule(
            action: SingBoxRuleAction.direct,
            domains: ['x.com'],
          ),
        ],
      );
      // 1.0 maps without the new keys keep their meaning.
      expect(
        SingBoxRoutingRules.fromMap(const {
          'bypassCountries': ['ru'],
        }),
        const SingBoxRoutingRules(bypassCountries: ['ru']),
      );
      expect(
        SingBoxRoutingRules.fromMap(rules.toMap()).hashCode,
        rules.hashCode,
      );
      expect(SingBoxRoutingRules.fromMap(const {}).isDefault, isTrue);
      expect(rules.isDefault, isFalse);
      expect(rules.copyWith(blockAds: false), isNot(rules));
      // toMap returns copies that cannot alter the rules.
      (rules.toMap()['bypassApps'] as List).add('mutated');
      expect(rules.bypassApps, ['a.b']);
    });
  });

  test('SingBoxRoutingRule round trips through maps', () {
    const rule = SingBoxRoutingRule(
      action: SingBoxRuleAction.proxy,
      name: 'Streaming',
      enabled: false,
      domains: ['a.com'],
      domainSuffixes: ['b.com'],
      domainKeywords: ['c'],
      domainRegexes: [r'^d\.com$'],
      ipCidrs: ['192.0.2.0/24'],
      ports: ['443', '1000-2000'],
      packages: ['e.f'],
      ruleSets: ['geosite-youtube'],
      network: SingBoxRuleNetwork.udp,
      protocols: ['quic'],
    );
    expect(SingBoxRoutingRule.tryFromMap(rule.toMap()), rule);
    expect(
      SingBoxRoutingRule.tryFromMap(rule.toMap())!.hashCode,
      rule.hashCode,
    );
    expect(rule.toMap()['action'], 'proxy');
    expect(rule.toMap()['network'], 'udp');
    // Defaults are not written.
    expect(const SingBoxRoutingRule(action: SingBoxRuleAction.direct).toMap(), {
      'action': 'direct',
    });
    expect(
      SingBoxRoutingRule.tryFromMap(const {
        'domains': ['x'],
      }),
      isNull,
    );
    expect(
      SingBoxRoutingRule.tryFromMap(const {
        'action': 'BLOCK',
        'ports': [25, '465', true],
        'network': 'sctp',
      }),
      const SingBoxRoutingRule(
        action: SingBoxRuleAction.block,
        ports: ['25', '465'],
      ),
    );
    expect(rule.copyWith(clearNetwork: true).network, isNull);
    expect(rule.copyWith(enabled: true), isNot(rule));
    expect(rule.copyWith(), rule);
  });

  test('SingBoxRoutingMode.fromName', () {
    expect(
      SingBoxRoutingMode.fromName('proxylisted'),
      SingBoxRoutingMode.proxyListed,
    );
    expect(
      SingBoxRoutingMode.fromName('proxyAll'),
      SingBoxRoutingMode.proxyAll,
    );
    expect(SingBoxRoutingMode.fromName(null), SingBoxRoutingMode.proxyAll);
    expect(SingBoxRoutingMode.fromName('direct'), SingBoxRoutingMode.proxyAll);
  });

  test('SingBoxIpVersion.fromName', () {
    expect(SingBoxIpVersion.fromName('IPv4'), SingBoxIpVersion.ipv4);
    expect(SingBoxIpVersion.fromName('ipv6'), SingBoxIpVersion.ipv6);
    expect(SingBoxIpVersion.fromName('dual'), SingBoxIpVersion.dual);
    expect(SingBoxIpVersion.fromName(null), SingBoxIpVersion.dual);
    expect(SingBoxIpVersion.fromName('both'), SingBoxIpVersion.dual);
  });

  group('SingBoxOutbound', () {
    test('reads server information from outbounds and endpoints', () {
      final hop = SingBoxOutbound.fromJson({
        'type': 'hysteria2',
        'server': 'h.example.com',
        'server_ports': ['2000-3000'],
      });
      expect(hop.tag, 'hysteria2');
      expect(hop.serverPort, 2000);
      final wg = SingBoxOutbound.fromJson({
        'type': 'wireguard',
        'tag': 'wg',
        'peers': [
          {'address': '1.2.3.4', 'port': 51820},
        ],
      });
      expect(wg.server, '1.2.3.4');
      expect(wg.serverPort, 51820);
      expect(wg.isEndpoint, isTrue);
      expect(() => SingBoxOutbound.fromJson({'tag': 'x'}), throwsArgumentError);
    });

    test('is immutable and compares by content', () {
      final source = {'type': 'socks', 'tag': 's', 'server': '1.2.3.4'};
      final a = SingBoxOutbound.fromJson(source);
      source['server'] = '5.6.7.8';
      expect(a.server, '1.2.3.4');
      expect(a.json['server'], '1.2.3.4');
      final b = SingBoxOutbound.fromJson({
        'type': 'socks',
        'tag': 's',
        'server': '1.2.3.4',
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final renamed = a.withTag('t');
      expect(renamed.tag, 't');
      expect(renamed.json['tag'], 't');
      expect(a.tag, 's');
      expect(renamed, isNot(a));
    });

    test('proxy type classification', () {
      expect(SingBoxOutbound.isProxyType('vless'), isTrue);
      for (final type in SingBoxOutbound.nonProxyTypes) {
        expect(SingBoxOutbound.isProxyType(type), isFalse, reason: type);
      }
    });
  });
}
