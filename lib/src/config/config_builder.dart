import 'dart:convert';

import '../utils/validators.dart';
import 'config_options.dart';
import 'dns_server.dart';
import 'internal/json_utils.dart';
import 'outbound.dart';
import 'routing_rule.dart';
import 'routing_rules.dart';
import 'rule_sets.dart';

/// Builds complete sing-box 1.14 configurations for the VPN.
///
/// [build] wraps one or more outbounds (for example parsed from share links
/// with `SingBoxShareLink`) into a full configuration:
///
/// * `log` according to [SingBoxConfigOptions.logLevel];
/// * `dns` with a remote resolver reached **through the proxy** (no leaks), a
///   direct resolver for bypassed domains and for the host names of the proxy
///   servers themselves (`route.default_domain_resolver`), optional FakeIP;
/// * a `tun` inbound ([SingBoxTunOptions]) with per-app routing;
/// * outbounds: a `selector` [proxyTag] (when several outbounds are given it
///   contains the `urltest` group [autoTag] that picks the fastest one), the
///   outbounds themselves and a `direct` outbound [directTag];
/// * `route` with sniffing, DNS hijacking, the blocking, proxy and bypass
///   rules of [SingBoxRoutingRules], remote rule-sets and `final: proxy`
///   (`final: direct` in [SingBoxRoutingMode.proxyListed]);
/// * `experimental` with the cache file and the Clash API (modes `Rule`,
///   `Global`, `Direct`; traffic statistics).
///
/// [apply] patches an existing user configuration with the same routing
/// rules without touching anything else.
///
/// ```dart
/// final outbound = SingBoxShareLink.parse('vless://…');
/// final config = const SingBoxConfigBuilder().build(
///   [outbound.json],
///   rules: const SingBoxRoutingRules(bypassCountries: ['ru'], blockAds: true),
/// );
/// ```
class SingBoxConfigBuilder {
  /// Creates a builder using [options].
  const SingBoxConfigBuilder([this.options = const SingBoxConfigOptions()]);

  /// Options shaping the generated configuration.
  final SingBoxConfigOptions options;

  /// Tag of the main `selector` outbound (switch servers with
  /// `SingBox.selectOutbound(proxyTag, …)`).
  static const proxyTag = 'proxy';

  /// Tag of the `urltest` group that selects the fastest outbound.
  static const autoTag = 'auto';

  /// Tag of the `direct` outbound.
  static const directTag = 'direct';

  /// Tag of the generated TUN inbound.
  static const tunTag = 'tun-in';

  /// Tag of the remote (proxied) DNS server.
  static const dnsRemoteTag = 'dns-remote';

  /// Tag of the direct DNS server.
  static const dnsDirectTag = 'dns-direct';

  /// Tag of the system resolver used to bootstrap a host name based direct
  /// DNS server.
  static const dnsLocalTag = 'dns-local';

  /// Tag of the FakeIP DNS server.
  static const dnsFakeIpTag = 'dns-fakeip';

  /// Tag of the HTTP client that downloads remote rule-sets.
  static const ruleSetHttpClientTag = 'rule-set-download';

  static const _reservedTags = {proxyTag, autoTag, directTag};

  /// Builds a complete configuration from [outbounds].
  ///
  /// Each outbound is a sing-box outbound (or WireGuard endpoint) object;
  /// missing or clashing tags are replaced with unique ones. [selectedTag]
  /// becomes the default member of the [proxyTag] selector (by default the
  /// [autoTag] group when there are several outbounds).
  ///
  /// Throws an [ArgumentError] when [outbounds] is empty or an entry has no
  /// `type`.
  Map<String, dynamic> build(
    List<Map<String, dynamic>> outbounds, {
    SingBoxRoutingRules rules = const SingBoxRoutingRules(),
    String? selectedTag,
  }) {
    if (outbounds.isEmpty) {
      throw ArgumentError.value(outbounds, 'outbounds', 'No outbounds given');
    }
    final taken = <String>{..._reservedTags};
    final proxies = <Map<String, dynamic>>[];
    final endpoints = <Map<String, dynamic>>[];
    for (final raw in outbounds) {
      final outbound = SingBoxOutbound.fromJson(raw);
      final tag = uniqueTag(outbound.tag, taken);
      final json = deepCopyMap(outbound.json)..['tag'] = tag;
      (outbound.isEndpoint ? endpoints : proxies).add(json);
    }
    final memberTags = [
      ...proxies.map((o) => o['tag'] as String),
      ...endpoints.map((o) => o['tag'] as String),
    ];
    final useAuto = memberTags.length > 1;
    final selectorMembers = [if (useAuto) autoTag, ...memberTags];
    final defaultMember =
        selectedTag != null && selectorMembers.contains(selectedTag)
            ? selectedTag
            : selectorMembers.first;

    final custom = _CustomRules(rules, sniff: options.sniff);
    final routeRules = [
      ..._leadingRouteRules(),
      ..._routingRules(
        rules,
        custom,
        directTag,
        proxy: proxyTag,
        sniff: options.sniff,
        includeClashModes: true,
      ),
      ..._ipVersionRules(rules),
    ];
    // DNS rules only use rule-sets that the route rules use as well.
    final ruleSetTags = _referencedRuleSets(routeRules);
    final config = <String, dynamic>{
      'log': _log(),
      'dns': _dns(rules, custom),
      'inbounds': [_tunInbound(rules)],
      'outbounds': [
        {
          'type': 'selector',
          'tag': proxyTag,
          'outbounds': selectorMembers,
          'default': defaultMember,
          'interrupt_exist_connections': options.interruptExistConnections,
        },
        if (useAuto)
          {
            'type': 'urltest',
            'tag': autoTag,
            'outbounds': memberTags,
            'url': options.urlTestUrl,
            'interval': formatDuration(options.urlTestInterval),
            'tolerance': options.urlTestTolerance,
            'interrupt_exist_connections': options.interruptExistConnections,
          },
        ...proxies,
        {'type': 'direct', 'tag': directTag},
      ],
      if (endpoints.isNotEmpty) 'endpoints': endpoints,
      'route': {
        'rules': routeRules,
        if (ruleSetTags.isNotEmpty)
          'rule_set': [
            for (final tag in ruleSetTags) _ruleSet(tag, custom.urls),
          ],
        'final': _isListed(rules) ? directTag : proxyTag,
        'auto_detect_interface': true,
        'default_domain_resolver': dnsDirectTag,
      },
      if (ruleSetTags.isNotEmpty) 'http_clients': [_ruleSetHttpClient()],
      'experimental': _experimental(),
    };
    return config;
  }

  /// Converts [configOrOutbound] into a final configuration JSON string.
  ///
  /// * A complete configuration (an object with `outbounds`, `inbounds`,
  ///   `endpoints` or `route`) is patched with [apply].
  /// * A single outbound object or a JSON array of outbounds is wrapped with
  ///   [build].
  ///
  /// Throws a [FormatException] for invalid JSON.
  String buildFromJson(
    String configOrOutbound, {
    SingBoxRoutingRules rules = const SingBoxRoutingRules(),
  }) {
    final decoded = jsonDecode(configOrOutbound);
    if (decoded is List) {
      final list = decoded.whereType<Map<dynamic, dynamic>>().map(deepCopyMap);
      return jsonEncode(build(list.toList(), rules: rules));
    }
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object or array');
    }
    final map = deepCopyMap(decoded);
    if (isFullConfig(map)) return jsonEncode(apply(map, rules: rules));
    return jsonEncode(build([map], rules: rules));
  }

  /// Whether [json] is a complete configuration rather than one outbound.
  static bool isFullConfig(Map<dynamic, dynamic> json) =>
      json.containsKey('outbounds') ||
      json.containsKey('inbounds') ||
      json.containsKey('endpoints') ||
      json.containsKey('route');

  /// Applies [rules] to an existing complete [config] and returns a patched
  /// deep copy; [config] itself is never modified and unknown fields are
  /// preserved.
  ///
  /// * Blocking, proxy and bypass route rules are inserted after the leading
  ///   `sniff`/`hijack-dns` rules, before the user's own rules. The proxy
  ///   lists use the config's main outbound (`route.final`, else the first
  ///   proxy outbound) and are skipped when that is a `direct` or `block`
  ///   outbound.
  /// * [SingBoxRoutingMode.proxyListed] sets `route.final` to the `direct`
  ///   outbound; the DNS section is not changed for it.
  /// * Every `tun` inbound gets the per-app lists and the bypassed subnets
  ///   (`route_exclude_address`); a default TUN inbound is added when the
  ///   config has none (the tunnel cannot work without it).
  /// * A `direct` outbound is reused or added.
  /// * `route.auto_detect_interface` is enabled unless set explicitly.
  /// * Custom [SingBoxRoutingRules.dnsServers] become the final DNS servers,
  ///   reached through the config's main outbound (`route.final`, else the
  ///   first proxy outbound), or directly when that is a `direct` or `block`
  ///   outbound. Without `route.default_domain_resolver` the server names of
  ///   the outbounds keep being resolved as before: by the only original DNS
  ///   server, or by the system resolver when there was none.
  /// * Blocked domains are answered with NXDOMAIN by DNS.
  /// * [SingBoxRoutingRules.ipVersion] other than `dual` sets `dns.strategy`
  ///   and, for IPv4 only, appends a route rule rejecting IPv6 connections
  ///   after the user's own rules.
  Map<String, dynamic> apply(
    Map<String, dynamic> config, {
    SingBoxRoutingRules rules = const SingBoxRoutingRules(),
  }) {
    final result = deepCopyMap(config);

    final outbounds = _list(result, 'outbounds');
    final endpointList = result['endpoints'];
    var directOutbound = outbounds.firstWhere(
      (o) => o['type'] == 'direct' && o['detour'] == null,
      orElse: () => const {},
    );
    if (directOutbound.isEmpty) {
      final taken = {
        ...outbounds.map((o) => o['tag']).whereType<String>(),
        if (endpointList is List)
          ...endpointList
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => e['tag'])
              .whereType<String>(),
      };
      directOutbound = {'type': 'direct', 'tag': uniqueTag(directTag, taken)};
      outbounds.add(directOutbound);
    }
    final direct = directOutbound['tag'] as String? ?? directTag;

    // TUN inbounds.
    final inbounds = _list(result, 'inbounds');
    final tuns = inbounds.where((i) => i['type'] == 'tun').toList();
    if (tuns.isEmpty) {
      final tun = _tunInbound(const SingBoxRoutingRules(bypassLan: false));
      inbounds.insert(0, tun);
      tuns.add(tun);
    }
    final packages = _packages(rules);
    final subnets = _subnets(rules);
    for (final tun in tuns) {
      if (packages.include.isNotEmpty) {
        tun['include_package'] = dedupe([
          ...readStringList(tun['include_package']),
          ...packages.include,
        ]);
        tun.remove('exclude_package');
      } else if (packages.exclude.isNotEmpty) {
        tun['exclude_package'] = dedupe([
          ...readStringList(tun['exclude_package']),
          ...packages.exclude,
        ]);
      }
      if (subnets.isNotEmpty && tun['auto_route'] != false) {
        tun['route_exclude_address'] = dedupe([
          ...readStringList(tun['route_exclude_address']),
          ...subnets,
        ]);
      }
    }

    // Route.
    final proxy = _proxyDetourTag(result);
    final route = _map(result, 'route');
    final routeRules = _list(route, 'rules');
    var insertAt = 0;
    while (insertAt < routeRules.length &&
        _isLeadingRule(routeRules[insertAt])) {
      insertAt++;
    }
    // Protocol rules only work when the config sniffs.
    final sniff = routeRules.any((r) => r['action'] == 'sniff');
    final custom = _CustomRules(rules, sniff: sniff);
    final inserted = _routingRules(
      rules,
      custom,
      direct,
      proxy: proxy,
      sniff: sniff,
      includeClashModes: false,
    );
    routeRules.insertAll(insertAt, inserted);
    routeRules.addAll(_ipVersionRules(rules));
    route.putIfAbsent('auto_detect_interface', () => true);
    if (_isListed(rules)) route['final'] = direct;
    final ruleSetTags = _referencedRuleSets(inserted);
    if (ruleSetTags.isNotEmpty) {
      final ruleSets = _list(route, 'rule_set');
      final existing = ruleSets.map((r) => r['tag']).toSet();
      for (final tag in ruleSetTags) {
        if (!existing.contains(tag)) ruleSets.add(_ruleSet(tag, custom.urls));
      }
      final clients = _list(result, 'http_clients');
      if (!clients.any((c) => c['tag'] == ruleSetHttpClientTag)) {
        clients.add(_ruleSetHttpClient());
      }
    }

    // DNS.
    if (rules.ipVersion != SingBoxIpVersion.dual) {
      _map(result, 'dns')['strategy'] = _dnsStrategy(rules);
    }
    final blockedDomains = _domains(rules.blockedDomains);
    final dnsServers = rules.dnsServers.where((s) => s.trim().isNotEmpty);
    if (blockedDomains.isNotEmpty || dnsServers.isNotEmpty) {
      final dns = _map(result, 'dns');
      final servers = _list(dns, 'servers');
      final dnsRules = _list(dns, 'rules');
      if (blockedDomains.isNotEmpty) {
        dnsRules.insert(0, {
          'domain_suffix': blockedDomains,
          'action': 'predefined',
          'rcode': 'NXDOMAIN',
        });
      }
      if (dnsServers.isNotEmpty) {
        // Taken before proxyListed pointed `route.final` at `direct`.
        final detour = proxy;
        final taken = servers.map((s) => s['tag']).whereType<String>().toSet();
        // Without `route.default_domain_resolver` sing-box resolves outbound
        // server names with the only DNS server (none: the system resolver)
        // and rejects configs with several servers. Keep that resolver.
        final original = [...servers.map((s) => s['tag']).whereType<String>()];
        final keepResolver = original.length == 1 ? original.single : null;
        final route = _map(result, 'route');
        final needsResolver =
            route['default_domain_resolver'] == null && original.length <= 1;
        String? localTag;
        String? first;
        for (final address in dnsServers) {
          final server = SingBoxDnsServer.tryParse(
            address,
            tag: '',
            detour: detour,
          );
          if (server == null) continue;
          final tag = server['tag'] = uniqueTag('dns-custom', taken);
          servers.add(server);
          // Without a proxy detour a host name based server is bootstrapped
          // by the system resolver.
          if (SingBoxDnsServer.needsDomainResolver(server)) {
            localTag ??= _localDnsServerTag(servers, taken);
            server['domain_resolver'] = localTag;
          }
          first ??= tag;
        }
        if (first != null) {
          dns['final'] = first;
          if (needsResolver) {
            route['default_domain_resolver'] =
                keepResolver ??
                (localTag ??= _localDnsServerTag(servers, taken));
          }
        }
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _log() {
    if (options.logLevel == SingBoxConfigLogLevel.disabled) {
      return {'disabled': true};
    }
    return {'level': options.logLevel.value, 'timestamp': options.logTimestamp};
  }

  Map<String, dynamic> _tunInbound(SingBoxRoutingRules rules) {
    final tun = options.tun;
    final packages = _packages(rules);
    final subnets = _subnets(rules);
    return {
      'type': 'tun',
      'tag': tunTag,
      if (tun.interfaceName != null) 'interface_name': tun.interfaceName,
      'address': tun.addresses,
      'mtu': tun.mtu,
      'auto_route': tun.autoRoute,
      'strict_route': tun.strictRoute,
      'stack': tun.stack.value,
      if (tun.endpointIndependentNat && tun.stack != SingBoxTunStack.system)
        'endpoint_independent_nat': true,
      if (tun.autoRoute && subnets.isNotEmpty) 'route_exclude_address': subnets,
      if (packages.include.isNotEmpty) 'include_package': packages.include,
      if (packages.include.isEmpty && packages.exclude.isNotEmpty)
        'exclude_package': packages.exclude,
    };
  }

  Map<String, dynamic> _dns(SingBoxRoutingRules rules, _CustomRules custom) {
    final dnsOptions = options.dns;
    final servers = <Map<String, dynamic>>[];
    final taken = <String>{};

    // Remote resolvers, reached through the proxy.
    final remoteAddresses = [
      ...rules.dnsServers.where((s) => s.trim().isNotEmpty),
    ];
    if (remoteAddresses.isEmpty) remoteAddresses.add(dnsOptions.remote);
    String? remoteTag;
    for (final address in remoteAddresses) {
      final server = SingBoxDnsServer.tryParse(
        address,
        tag: '',
        detour: proxyTag,
      );
      if (server == null) continue;
      final tag = server['tag'] = uniqueTag(dnsRemoteTag, taken);
      if (server['type'] == 'local') server.remove('detour');
      servers.add(server);
      remoteTag ??= tag;
    }
    if (remoteTag == null) {
      servers.add(
        SingBoxDnsServer.parse(
          const SingBoxDnsOptions().remote,
          tag: dnsRemoteTag,
          detour: proxyTag,
        ),
      );
      remoteTag = dnsRemoteTag;
    }

    // Direct resolver for bypassed domains and proxy server host names.
    var direct = SingBoxDnsServer.tryParse(
      dnsOptions.direct,
      tag: dnsDirectTag,
      domainResolver: dnsLocalTag,
    );
    direct ??= {'type': 'local', 'tag': dnsDirectTag};
    servers.add(direct);
    if (direct['domain_resolver'] == dnsLocalTag) {
      servers.add({'type': 'local', 'tag': dnsLocalTag});
    }

    final ipv6 =
        options.tun.enableIpv6 && rules.ipVersion != SingBoxIpVersion.ipv4;
    if (dnsOptions.fakeIp) {
      servers.add({
        'type': 'fakeip',
        'tag': dnsFakeIpTag,
        'inet4_range': dnsOptions.fakeIpInet4Range,
        if (ipv6) 'inet6_range': dnsOptions.fakeIpInet6Range,
      });
    }

    final blocked = _domains(rules.blockedDomains);
    final bypass = _domains(rules.bypassDomains);
    final directGeosites =
        _countryRuleSets(rules).where(SingBoxRuleSets.isGeosite).toList();
    final listed = _isListed(rules);
    // Proxied names are resolved remotely (or get fake IPs), even when a
    // bypass list below also contains them.
    final proxyDomains = _domains(rules.proxyDomains);
    final proxyGeosites =
        _blockedRuleSets(rules).where(SingBoxRuleSets.isGeosite).toList();
    final proxyMatchers = <Map<String, dynamic>>[
      if (proxyDomains.isNotEmpty) {'domain_suffix': proxyDomains},
      if (proxyGeosites.isNotEmpty) {'rule_set': proxyGeosites},
    ];
    final remote = remoteTag;
    List<Map<String, dynamic>> proxied(Map<String, dynamic> matcher) => [
      if (dnsOptions.fakeIp)
        {
          ...matcher,
          'query_type': ['A', if (ipv6) 'AAAA'],
          'action': 'route',
          'server': dnsFakeIpTag,
        },
      {...matcher, 'action': 'route', 'server': remote},
    ];
    final dnsRules = <Map<String, dynamic>>[
      if (blocked.isNotEmpty)
        {'domain_suffix': blocked, 'action': 'predefined', 'rcode': 'NXDOMAIN'},
      if (rules.blockAds)
        {
          'rule_set': [SingBoxRuleSets.adsTag],
          'action': 'predefined',
          'rcode': 'NXDOMAIN',
        },
      if (options.enableClashModes) ...[
        {'clash_mode': 'Direct', 'action': 'route', 'server': dnsDirectTag},
        {'clash_mode': 'Global', 'action': 'route', 'server': remoteTag},
      ],
      for (final entry in custom.entries)
        if (entry.dnsMatch case final match?)
          ...switch (entry.action) {
            SingBoxRuleAction.block => [
              {...match, 'action': 'predefined', 'rcode': 'NXDOMAIN'},
            ],
            SingBoxRuleAction.direct => [
              {...match, 'action': 'route', 'server': dnsDirectTag},
            ],
            SingBoxRuleAction.proxy => proxied(match),
          },
      for (final matcher in proxyMatchers) ...proxied(matcher),
      if (bypass.isNotEmpty)
        {'domain_suffix': bypass, 'action': 'route', 'server': dnsDirectTag},
      if (directGeosites.isNotEmpty)
        {'rule_set': directGeosites, 'action': 'route', 'server': dnsDirectTag},
      // In proxyListed mode unlisted names are connected directly and keep
      // their real addresses.
      if (dnsOptions.fakeIp && !listed)
        {
          'query_type': ['A', if (ipv6) 'AAAA'],
          'action': 'route',
          'server': dnsFakeIpTag,
        },
    ];

    return {
      'servers': servers,
      'rules': dnsRules,
      'final': listed ? dnsDirectTag : remoteTag,
      'strategy': _dnsStrategy(rules),
      if (dnsOptions.reverseMapping) 'reverse_mapping': true,
    };
  }

  List<Map<String, dynamic>> _leadingRouteRules() => [
    if (options.sniff) {'action': 'sniff'},
    {
      'type': 'logical',
      'mode': 'or',
      'rules': [
        {'protocol': 'dns'},
        {'port': 53},
      ],
      'action': 'hijack-dns',
    },
  ];

  /// `dns.strategy` for [SingBoxRoutingRules.ipVersion]; `dual` uses
  /// [SingBoxDnsOptions.strategy] unless the TUN has no IPv6 address.
  String _dnsStrategy(SingBoxRoutingRules rules) => switch (rules.ipVersion) {
    SingBoxIpVersion.ipv4 => SingBoxDnsStrategy.ipv4Only.value,
    SingBoxIpVersion.ipv6 => SingBoxDnsStrategy.ipv6Only.value,
    SingBoxIpVersion.dual =>
      options.tun.enableIpv6
          ? options.dns.strategy.value
          : SingBoxDnsStrategy.ipv4Only.value,
  };

  /// IPv4 only: IPv6 connections not matched by an earlier (direct) rule are
  /// rejected instead of being proxied, so apps fall back to IPv4 at once.
  /// It is the last rule, so LAN and bypass rules keep working over IPv6.
  List<Map<String, dynamic>> _ipVersionRules(SingBoxRoutingRules rules) => [
    if (rules.ipVersion == SingBoxIpVersion.ipv4)
      {'ip_version': 6, 'action': 'reject'},
  ];

  static bool _isLeadingRule(Map<String, dynamic> rule) {
    final action = rule['action'];
    return action == 'sniff' || action == 'hijack-dns';
  }

  /// Route rules of [rules]; the proxy lists and the custom proxy rules are
  /// left out when [proxy] is `null` (a config without a proxy outbound),
  /// BitTorrent detection when the config does not [sniff].
  List<Map<String, dynamic>> _routingRules(
    SingBoxRoutingRules rules,
    _CustomRules custom,
    String direct, {
    required String? proxy,
    required bool sniff,
    required bool includeClashModes,
  }) {
    final blockedApps = _validPackages(rules.blockedApps);
    final blockedDomains = _domains(rules.blockedDomains);
    final proxyDomains = _domains(rules.proxyDomains);
    final proxySubnets = _cidrs(rules.proxySubnets);
    final proxySets = _blockedRuleSets(rules);
    final bypassDomains = _domains(rules.bypassDomains);
    final subnets = _subnets(rules);
    final countrySets = _countryRuleSets(rules);
    return [
      if (blockedApps.isNotEmpty)
        {'package_name': blockedApps, 'action': 'reject'},
      if (blockedDomains.isNotEmpty)
        {'domain_suffix': blockedDomains, 'action': 'reject'},
      if (rules.blockAds)
        {
          'rule_set': [SingBoxRuleSets.adsTag],
          'action': 'reject',
        },
      if (rules.blockQuic)
        sniff
            ? {'protocol': 'quic', 'action': 'reject'}
            : {'network': 'udp', 'port': 443, 'action': 'reject'},
      if (rules.bittorrentDirect && sniff)
        {'protocol': 'bittorrent', 'action': 'route', 'outbound': direct},
      if (includeClashModes && options.enableClashModes) ...[
        {'clash_mode': 'Direct', 'action': 'route', 'outbound': direct},
        {'clash_mode': 'Global', 'action': 'route', 'outbound': proxyTag},
      ],
      for (final entry in custom.entries)
        if (_routeAction(entry.action, direct, proxy) case final action?)
          {...entry.match, ...action},
      if (proxy != null) ...[
        if (proxyDomains.isNotEmpty)
          {'domain_suffix': proxyDomains, 'action': 'route', 'outbound': proxy},
        if (proxySubnets.isNotEmpty)
          {'ip_cidr': proxySubnets, 'action': 'route', 'outbound': proxy},
        if (proxySets.isNotEmpty)
          {'rule_set': proxySets, 'action': 'route', 'outbound': proxy},
      ],
      if (rules.bypassLan)
        {'ip_is_private': true, 'action': 'route', 'outbound': direct},
      if (bypassDomains.isNotEmpty)
        {'domain_suffix': bypassDomains, 'action': 'route', 'outbound': direct},
      if (subnets.isNotEmpty)
        {'ip_cidr': subnets, 'action': 'route', 'outbound': direct},
      if (countrySets.isNotEmpty)
        {'rule_set': countrySets, 'action': 'route', 'outbound': direct},
    ];
  }

  Map<String, dynamic> _experimental() => {
    if (options.cacheFile)
      'cache_file': {
        'enabled': true,
        if (options.dns.fakeIp) 'store_fakeip': true,
      },
    // The Clash API (without a listening controller) enables traffic
    // statistics and runtime mode switching.
    'clash_api': {if (options.enableClashModes) 'default_mode': 'Rule'},
  };

  /// Remote rule-set [tag]: a catalog entry of [SingBoxRuleSets], or one
  /// given by URL in a custom rule ([customUrls]).
  Map<String, dynamic> _ruleSet(String tag, Map<String, String> customUrls) {
    final url = customUrls[tag];
    if (url == null) {
      return SingBoxRuleSets.remote(
        tag,
        httpClient: ruleSetHttpClientTag,
        updateInterval: options.ruleSetUpdateInterval,
        geoipUrl: options.geoipRuleSetUrl,
        geositeUrl: options.geositeRuleSetUrl,
      );
    }
    final path = Uri.parse(url).path.toLowerCase();
    return {
      'type': 'remote',
      'tag': tag,
      'format': path.endsWith('.json') ? 'source' : 'binary',
      'url': url,
      'http_client': ruleSetHttpClientTag,
      'update_interval': formatDuration(options.ruleSetUpdateInterval),
    };
  }

  Map<String, dynamic> _ruleSetHttpClient() => {
    'tag': ruleSetHttpClientTag,
    if (options.ruleSetDownloadDetour.isNotEmpty &&
        options.ruleSetDownloadDetour != directTag)
      'detour': options.ruleSetDownloadDetour,
  };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Route rule action of a custom rule, or `null` for a proxy rule in a
  /// config without a proxy outbound.
  static Map<String, dynamic>? _routeAction(
    SingBoxRuleAction action,
    String direct,
    String? proxy,
  ) => switch (action) {
    SingBoxRuleAction.proxy =>
      proxy == null ? null : {'action': 'route', 'outbound': proxy},
    SingBoxRuleAction.direct => {'action': 'route', 'outbound': direct},
    SingBoxRuleAction.block => {'action': 'reject'},
  };

  /// Tags of the rule-sets used by [rules], in order of appearance.
  static List<String> _referencedRuleSets(List<Map<String, dynamic>> rules) =>
      dedupe([for (final rule in rules) ...readStringList(rule['rule_set'])]);

  static bool _isListed(SingBoxRoutingRules rules) =>
      rules.mode == SingBoxRoutingMode.proxyListed;

  static List<String> _countryRuleSets(SingBoxRoutingRules rules) => dedupe([
    for (final code in rules.bypassCountries)
      ...SingBoxRuleSets.countryRuleSets(code),
  ]);

  static List<String> _blockedRuleSets(SingBoxRoutingRules rules) => dedupe([
    for (final code in rules.blockedInCountries)
      ...SingBoxRuleSets.blockedRuleSets(code),
  ]);

  static List<String> _domains(List<String> values) =>
      dedupe(values.map(SingBoxValidators.normalizeDomain).whereType<String>());

  static List<String> _cidrs(List<String> values) =>
      dedupe(values.map(SingBoxValidators.normalizeCidr).whereType<String>());

  static List<String> _subnets(SingBoxRoutingRules rules) =>
      _cidrs(rules.bypassSubnets);

  static List<String> _validPackages(List<String> values) => dedupe(
    values.map((e) => e.trim()).where(SingBoxValidators.isPackageName),
  );

  static ({List<String> include, List<String> exclude}) _packages(
    SingBoxRoutingRules rules,
  ) {
    final include = _validPackages(rules.proxyApps);
    return (
      include: include,
      exclude: include.isEmpty ? _validPackages(rules.bypassApps) : const [],
    );
  }

  /// The main outbound of [config] when it can carry DNS traffic: a detour
  /// to an empty `direct` outbound fails at the first query and `block`
  /// drops everything, so both yield `null`.
  static String? _proxyDetourTag(Map<String, dynamic> config) {
    final tag = _mainOutboundTag(config);
    if (tag == null) return null;
    final outbounds = config['outbounds'];
    if (outbounds is List) {
      for (final o in outbounds.whereType<Map<dynamic, dynamic>>()) {
        if (o['tag'] != tag) continue;
        final type = o['type'];
        if (type == 'block' || (type == 'direct' && o['detour'] == null)) {
          return null;
        }
      }
    }
    return tag;
  }

  /// Tag of a `local` DNS server in [servers], adding one when missing.
  static String _localDnsServerTag(
    List<Map<String, dynamic>> servers,
    Set<String> taken,
  ) {
    for (final server in servers) {
      final tag = server['tag'];
      if (server['type'] == 'local' && tag is String) return tag;
    }
    final tag = uniqueTag(dnsLocalTag, taken);
    servers.add({'type': 'local', 'tag': tag});
    return tag;
  }

  static String? _mainOutboundTag(Map<String, dynamic> config) {
    final route = config['route'];
    if (route is Map && route['final'] is String) {
      return route['final'] as String;
    }
    final outbounds = config['outbounds'];
    if (outbounds is List) {
      for (final o in outbounds.whereType<Map<dynamic, dynamic>>()) {
        final type = o['type'];
        if (type is String && SingBoxOutbound.isProxyType(type)) {
          return o['tag'] as String?;
        }
      }
      for (final o in outbounds.whereType<Map<dynamic, dynamic>>()) {
        if (o['type'] == 'selector' || o['type'] == 'urltest') {
          return o['tag'] as String?;
        }
      }
    }
    return null;
  }

  static Map<String, dynamic> _map(Map<String, dynamic> parent, String key) {
    final value = parent[key];
    if (value is Map<String, dynamic>) return value;
    final map = value is Map ? deepCopyMap(value) : <String, dynamic>{};
    parent[key] = map;
    return map;
  }

  static List<Map<String, dynamic>> _list(
    Map<String, dynamic> parent,
    String key,
  ) {
    final value = parent[key];
    final list = <Map<String, dynamic>>[
      if (value is List)
        for (final item in value)
          if (item is Map) deepCopyMap(item),
    ];
    parent[key] = list;
    return list;
  }
}

/// The enabled [SingBoxRoutingRules.customRules] converted to sing-box rule
/// conditions. Invalid entries are dropped; a rule is skipped when one of its
/// conditions has no valid entry left (it would match too much otherwise),
/// or when it matches protocols but the config does not sniff.
class _CustomRules {
  _CustomRules(SingBoxRoutingRules rules, {required this.sniff}) {
    for (final rule in rules.customRules) {
      if (rule.enabled) _add(rule);
    }
  }

  /// Whether the config sniffs protocols.
  final bool sniff;

  /// The converted rules in order: route conditions ([match]) and, for rules
  /// that only depend on the domain name, DNS conditions ([dnsMatch]).
  final entries =
      <
        ({
          SingBoxRuleAction action,
          Map<String, dynamic> match,
          Map<String, dynamic>? dnsMatch,
        })
      >[];

  /// Download URLs of the rule-sets given as URLs, by generated tag.
  final urls = <String, String>{};

  static final _catalogTag = RegExp(r'^(geosite|geoip)-[a-z0-9!@._-]+$');

  void _add(SingBoxRoutingRule rule) {
    var incomplete = false;
    List<T> valid<T>(List<String> input, Iterable<T> output) {
      final list = output.toList();
      if (input.isNotEmpty && list.isEmpty) incomplete = true;
      return list;
    }

    final domains = valid(
      rule.domains,
      SingBoxConfigBuilder._domains(rule.domains),
    );
    final suffixes = valid(
      rule.domainSuffixes,
      SingBoxConfigBuilder._domains(rule.domainSuffixes),
    );
    final keywords = valid(
      rule.domainKeywords,
      dedupe(
        rule.domainKeywords
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty && !e.contains(RegExp(r'\s'))),
      ),
    );
    final regexes = valid(
      rule.domainRegexes,
      dedupe(rule.domainRegexes.map((e) => e.trim()).where(_isRegex)),
    );
    final cidrs = valid(
      rule.ipCidrs,
      SingBoxConfigBuilder._cidrs(rule.ipCidrs),
    );
    final ports = <int>[];
    final ranges = <String>[];
    for (final value in rule.ports) {
      _addPort(value.trim(), ports, ranges);
    }
    if (rule.ports.isNotEmpty && ports.isEmpty && ranges.isEmpty) {
      incomplete = true;
    }
    final packages = valid(
      rule.packages,
      SingBoxConfigBuilder._validPackages(rule.packages),
    );
    final ruleSets = valid(
      rule.ruleSets,
      dedupe(rule.ruleSets.map(_ruleSetTag).whereType<String>()),
    );
    final protocols = valid(
      rule.protocols,
      dedupe(
        rule.protocols
            .map((e) => e.trim().toLowerCase())
            .where(SingBoxRoutingRule.knownProtocols.contains),
      ),
    );
    if (incomplete || (protocols.isNotEmpty && !sniff)) return;

    final match = <String, dynamic>{
      if (domains.isNotEmpty) 'domain': domains,
      if (suffixes.isNotEmpty) 'domain_suffix': suffixes,
      if (keywords.isNotEmpty) 'domain_keyword': keywords,
      if (regexes.isNotEmpty) 'domain_regex': regexes,
      if (cidrs.isNotEmpty) 'ip_cidr': cidrs,
      if (ports.isNotEmpty) 'port': ports,
      if (ranges.isNotEmpty) 'port_range': ranges,
      if (packages.isNotEmpty) 'package_name': packages,
      if (ruleSets.isNotEmpty) 'rule_set': ruleSets,
      if (rule.network != null) 'network': rule.network!.name,
      if (protocols.isNotEmpty) 'protocol': protocols,
    };
    if (match.isEmpty) return;

    // A DNS query has no port, transport or protocol: such rules only get a
    // route rule. Destination conditions are alternatives, so the domain
    // ones alone are enough for DNS (IP rule-sets cannot be used there).
    final geosites = ruleSets.where(SingBoxRuleSets.isGeosite).toList();
    final domainMatch = <String, dynamic>{
      if (domains.isNotEmpty) 'domain': domains,
      if (suffixes.isNotEmpty) 'domain_suffix': suffixes,
      if (keywords.isNotEmpty) 'domain_keyword': keywords,
      if (regexes.isNotEmpty) 'domain_regex': regexes,
      if (geosites.isNotEmpty) 'rule_set': geosites,
    };
    final dnsOnlyByName =
        ports.isEmpty &&
        ranges.isEmpty &&
        rule.network == null &&
        protocols.isEmpty;
    entries.add((
      action: rule.action,
      match: match,
      dnsMatch:
          dnsOnlyByName && domainMatch.isNotEmpty
              ? {
                ...domainMatch,
                if (packages.isNotEmpty) 'package_name': packages,
              }
              : null,
    ));
  }

  static bool _isRegex(String value) {
    if (value.isEmpty) return false;
    try {
      RegExp(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  static void _addPort(String value, List<int> ports, List<String> ranges) {
    bool isPort(int? port) => port != null && port >= 1 && port <= 65535;
    final single = int.tryParse(value);
    if (single != null) {
      if (isPort(single) && !ports.contains(single)) ports.add(single);
      return;
    }
    final parts = value.split(RegExp('[-:]'));
    if (parts.length != 2) return;
    final from = int.tryParse(parts[0].trim());
    final to = int.tryParse(parts[1].trim());
    if (isPort(from) && isPort(to) && from! <= to!) {
      final range = '$from:$to';
      if (!ranges.contains(range)) ranges.add(range);
    }
  }

  /// Tag of a rule-set entry: a catalog tag as is, or a generated
  /// `custom-<file name>` tag for an `http(s)://` URL (remembered in [urls]).
  String? _ruleSetTag(String entry) {
    final value = entry.trim();
    final uri = Uri.tryParse(value);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      for (final known in urls.entries) {
        if (known.value == value) return known.key;
      }
      final file = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      var name = file
          .replaceFirst(RegExp(r'\.(srs|json)$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
      if (name.isEmpty) name = 'rule-set';
      final tag = uniqueTag('custom-$name', urls.keys.toSet());
      urls[tag] = value;
      return tag;
    }
    final tag = value.toLowerCase();
    return _catalogTag.hasMatch(tag) ? tag : null;
  }
}
