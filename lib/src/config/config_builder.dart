import 'dart:convert';

import '../utils/validators.dart';
import 'config_options.dart';
import 'dns_server.dart';
import 'internal/json_utils.dart';
import 'outbound.dart';
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
/// * `route` with sniffing, DNS hijacking, the blocking and bypass rules of
///   [SingBoxRoutingRules], remote rule-sets and `final: proxy`;
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
      taken.add(tag);
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

    final ruleSetTags = _ruleSetTags(rules);
    final config = <String, dynamic>{
      'log': _log(),
      'dns': _dns(rules),
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
        'rules': [
          ..._leadingRouteRules(),
          ..._routingRules(rules, directTag, includeClashModes: true),
        ],
        if (ruleSetTags.isNotEmpty)
          'rule_set': ruleSetTags.map(_ruleSet).toList(),
        'final': proxyTag,
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
  /// * Blocking and bypass route rules are inserted after the leading
  ///   `sniff`/`hijack-dns` rules, before the user's own rules.
  /// * Every `tun` inbound gets the per-app lists and the bypassed subnets
  ///   (`route_exclude_address`); a default TUN inbound is added when the
  ///   config has none (the tunnel cannot work without it).
  /// * A `direct` outbound is reused or added.
  /// * `route.auto_detect_interface` is enabled unless set explicitly.
  /// * Custom [SingBoxRoutingRules.dnsServers] become the final DNS servers,
  ///   reached through the config's main outbound.
  /// * Blocked domains are answered with NXDOMAIN by DNS.
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
    final route = _map(result, 'route');
    final routeRules = _list(route, 'rules');
    var insertAt = 0;
    while (insertAt < routeRules.length &&
        _isLeadingRule(routeRules[insertAt])) {
      insertAt++;
    }
    routeRules.insertAll(
      insertAt,
      _routingRules(rules, direct, includeClashModes: false),
    );
    route.putIfAbsent('auto_detect_interface', () => true);
    final ruleSetTags = _ruleSetTags(rules);
    if (ruleSetTags.isNotEmpty) {
      final ruleSets = _list(route, 'rule_set');
      final existing = ruleSets.map((r) => r['tag']).toSet();
      for (final tag in ruleSetTags) {
        if (!existing.contains(tag)) ruleSets.add(_ruleSet(tag));
      }
      final clients = _list(result, 'http_clients');
      if (!clients.any((c) => c['tag'] == ruleSetHttpClientTag)) {
        clients.add(_ruleSetHttpClient());
      }
    }

    // DNS.
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
        final detour = _mainOutboundTag(result);
        final taken = servers.map((s) => s['tag']).whereType<String>().toSet();
        String? first;
        for (final address in dnsServers) {
          final tag = uniqueTag('dns-custom', taken);
          final server = SingBoxDnsServer.tryParse(
            address,
            tag: tag,
            detour: detour,
          );
          if (server == null || SingBoxDnsServer.needsDomainResolver(server)) {
            continue;
          }
          taken.add(tag);
          servers.add(server);
          first ??= tag;
        }
        if (first != null) dns['final'] = first;
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

  Map<String, dynamic> _dns(SingBoxRoutingRules rules) {
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
      final tag = uniqueTag(dnsRemoteTag, taken);
      final server = SingBoxDnsServer.tryParse(
        address,
        tag: tag,
        detour: proxyTag,
      );
      if (server == null) continue;
      if (server['type'] == 'local') server.remove('detour');
      taken.add(tag);
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
      taken.add(remoteTag);
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

    final ipv6 = options.tun.enableIpv6;
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
    final directGeosites = _countryRuleSets(
      rules,
    ).where(SingBoxRuleSets.isGeosite).toList();
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
      if (bypass.isNotEmpty)
        {'domain_suffix': bypass, 'action': 'route', 'server': dnsDirectTag},
      if (directGeosites.isNotEmpty)
        {'rule_set': directGeosites, 'action': 'route', 'server': dnsDirectTag},
      if (dnsOptions.fakeIp)
        {
          'query_type': ['A', if (ipv6) 'AAAA'],
          'action': 'route',
          'server': dnsFakeIpTag,
        },
    ];

    return {
      'servers': servers,
      'rules': dnsRules,
      'final': remoteTag,
      'strategy': ipv6 ? dnsOptions.strategy.value : 'ipv4_only',
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

  static bool _isLeadingRule(Map<String, dynamic> rule) {
    final action = rule['action'];
    return action == 'sniff' || action == 'hijack-dns';
  }

  List<Map<String, dynamic>> _routingRules(
    SingBoxRoutingRules rules,
    String direct, {
    required bool includeClashModes,
  }) {
    final blockedApps = _validPackages(rules.blockedApps);
    final blockedDomains = _domains(rules.blockedDomains);
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
      if (includeClashModes && options.enableClashModes) ...[
        {'clash_mode': 'Direct', 'action': 'route', 'outbound': direct},
        {'clash_mode': 'Global', 'action': 'route', 'outbound': proxyTag},
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

  Map<String, dynamic> _ruleSet(String tag) => SingBoxRuleSets.remote(
    tag,
    httpClient: ruleSetHttpClientTag,
    updateInterval: options.ruleSetUpdateInterval,
    geoipUrl: options.geoipRuleSetUrl,
    geositeUrl: options.geositeRuleSetUrl,
  );

  Map<String, dynamic> _ruleSetHttpClient() => {
    'tag': ruleSetHttpClientTag,
    if (options.ruleSetDownloadDetour.isNotEmpty &&
        options.ruleSetDownloadDetour != directTag)
      'detour': options.ruleSetDownloadDetour,
  };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<String> _ruleSetTags(SingBoxRoutingRules rules) => dedupe([
    if (rules.blockAds) SingBoxRuleSets.adsTag,
    ..._countryRuleSets(rules),
  ]);

  static List<String> _countryRuleSets(SingBoxRoutingRules rules) => dedupe([
    for (final code in rules.bypassCountries)
      ...SingBoxRuleSets.countryRuleSets(code),
  ]);

  static List<String> _domains(List<String> values) =>
      dedupe(values.map(SingBoxValidators.normalizeDomain).whereType<String>());

  static List<String> _subnets(SingBoxRoutingRules rules) => dedupe(
    rules.bypassSubnets
        .map(SingBoxValidators.normalizeCidr)
        .whereType<String>(),
  );

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
