import 'internal/json_utils.dart';

/// Log level of the generated sing-box configuration (`log.level`).
///
/// [disabled] turns logging off completely (`log.disabled: true`).
enum SingBoxConfigLogLevel {
  /// Most verbose level, includes every packet level event.
  trace('trace'),

  /// Debug messages.
  debug('debug'),

  /// Informational messages (default).
  info('info'),

  /// Warnings only.
  warn('warn'),

  /// Errors only.
  error('error'),

  /// Fatal errors only.
  fatal('fatal'),

  /// Panics only.
  panic('panic'),

  /// No logging at all.
  disabled('disabled');

  const SingBoxConfigLogLevel(this.value);

  /// The value used in the sing-box configuration.
  final String value;

  /// Returns the level whose [value] or [name] equals [value]
  /// (case-insensitive), or [fallback] when nothing matches.
  static SingBoxConfigLogLevel fromValue(
    String? value, {
    SingBoxConfigLogLevel fallback = SingBoxConfigLogLevel.info,
  }) {
    final normalized = value?.trim().toLowerCase();
    for (final level in values) {
      if (level.value == normalized || level.name.toLowerCase() == normalized) {
        return level;
      }
    }
    if (normalized == 'warning') return warn;
    return fallback;
  }
}

/// Network stack of the TUN inbound (`inbounds[].stack`).
enum SingBoxTunStack {
  /// The system network stack: fastest, uses the OS TCP/IP implementation.
  system('system'),

  /// The gVisor user space network stack: most compatible.
  gvisor('gvisor'),

  /// `system` for TCP and `gvisor` for UDP (default, recommended).
  mixed('mixed');

  const SingBoxTunStack(this.value);

  /// The value used in the sing-box configuration.
  final String value;

  /// Returns the stack whose [value] equals [value] (case-insensitive), or
  /// [fallback] when nothing matches.
  static SingBoxTunStack fromValue(
    String? value, {
    SingBoxTunStack fallback = SingBoxTunStack.mixed,
  }) {
    final normalized = value?.trim().toLowerCase();
    for (final stack in values) {
      if (stack.value == normalized) return stack;
    }
    return fallback;
  }
}

/// Domain resolution strategy (`dns.strategy`).
enum SingBoxDnsStrategy {
  /// Prefer IPv4 (A) answers, fall back to IPv6 (default).
  preferIpv4('prefer_ipv4'),

  /// Prefer IPv6 (AAAA) answers, fall back to IPv4.
  preferIpv6('prefer_ipv6'),

  /// Resolve IPv4 addresses only.
  ipv4Only('ipv4_only'),

  /// Resolve IPv6 addresses only.
  ipv6Only('ipv6_only');

  const SingBoxDnsStrategy(this.value);

  /// The value used in the sing-box configuration.
  final String value;

  /// Returns the strategy whose [value] or [name] equals [value]
  /// (case-insensitive), or [fallback] when nothing matches.
  static SingBoxDnsStrategy fromValue(
    String? value, {
    SingBoxDnsStrategy fallback = SingBoxDnsStrategy.preferIpv4,
  }) {
    final normalized = value?.trim().toLowerCase();
    for (final strategy in values) {
      if (strategy.value == normalized ||
          strategy.name.toLowerCase() == normalized) {
        return strategy;
      }
    }
    return fallback;
  }
}

/// Options of the TUN inbound created by `SingBoxConfigBuilder`.
///
/// The defaults match the official sing-box graphical clients and work on
/// Android and iOS without changes:
///
/// ```dart
/// const tun = SingBoxTunOptions(mtu: 1500, stack: SingBoxTunStack.gvisor);
/// ```
class SingBoxTunOptions {
  /// Creates TUN options.
  const SingBoxTunOptions({
    this.inet4Address = '172.19.0.1/30',
    this.inet6Address = 'fdfe:dcba:9876::1/126',
    this.enableIpv6 = true,
    this.mtu = 9000,
    this.stack = SingBoxTunStack.mixed,
    this.autoRoute = true,
    this.strictRoute = true,
    this.interfaceName,
    this.endpointIndependentNat = false,
  });

  /// IPv4 address (CIDR) of the TUN interface.
  final String inet4Address;

  /// IPv6 address (CIDR) of the TUN interface, used when [enableIpv6] is
  /// `true`.
  final String inet6Address;

  /// Whether the TUN interface gets an IPv6 address and IPv6 traffic is
  /// captured. Also controls the IPv6 FakeIP range.
  final bool enableIpv6;

  /// Maximum transmission unit of the TUN interface.
  final int mtu;

  /// Network stack used to process TUN traffic.
  final SingBoxTunStack stack;

  /// Whether the default route is set to the TUN interface.
  ///
  /// Required for `route_exclude_address` (bypassed subnets).
  final bool autoRoute;

  /// Whether to enforce strict routing (prevents leaks outside the tunnel).
  final bool strictRoute;

  /// Optional interface name (desktop platforms; ignored on mobile).
  final String? interfaceName;

  /// Whether to enable endpoint independent NAT (gVisor stack only).
  final bool endpointIndependentNat;

  /// The TUN addresses: [inet4Address] and, when [enableIpv6] is set,
  /// [inet6Address].
  List<String> get addresses => [inet4Address, if (enableIpv6) inet6Address];

  /// Converts the options to a JSON-safe map.
  Map<String, dynamic> toMap() => {
    'inet4Address': inet4Address,
    'inet6Address': inet6Address,
    'enableIpv6': enableIpv6,
    'mtu': mtu,
    'stack': stack.value,
    'autoRoute': autoRoute,
    'strictRoute': strictRoute,
    'interfaceName': interfaceName,
    'endpointIndependentNat': endpointIndependentNat,
  };

  /// Creates options from a map produced by [toMap].
  ///
  /// Unknown keys are ignored and missing or malformed values fall back to
  /// the defaults.
  factory SingBoxTunOptions.fromMap(Map<dynamic, dynamic> map) {
    const d = SingBoxTunOptions();
    return SingBoxTunOptions(
      inet4Address: readString(map['inet4Address']) ?? d.inet4Address,
      inet6Address: readString(map['inet6Address']) ?? d.inet6Address,
      enableIpv6: readBool(map['enableIpv6']) ?? d.enableIpv6,
      mtu: readInt(map['mtu']) ?? d.mtu,
      stack: SingBoxTunStack.fromValue(readString(map['stack'])),
      autoRoute: readBool(map['autoRoute']) ?? d.autoRoute,
      strictRoute: readBool(map['strictRoute']) ?? d.strictRoute,
      interfaceName: readString(map['interfaceName']),
      endpointIndependentNat:
          readBool(map['endpointIndependentNat']) ?? d.endpointIndependentNat,
    );
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// [interfaceName] cannot be reset to `null` through this method; create a
  /// new instance instead.
  SingBoxTunOptions copyWith({
    String? inet4Address,
    String? inet6Address,
    bool? enableIpv6,
    int? mtu,
    SingBoxTunStack? stack,
    bool? autoRoute,
    bool? strictRoute,
    String? interfaceName,
    bool? endpointIndependentNat,
  }) {
    return SingBoxTunOptions(
      inet4Address: inet4Address ?? this.inet4Address,
      inet6Address: inet6Address ?? this.inet6Address,
      enableIpv6: enableIpv6 ?? this.enableIpv6,
      mtu: mtu ?? this.mtu,
      stack: stack ?? this.stack,
      autoRoute: autoRoute ?? this.autoRoute,
      strictRoute: strictRoute ?? this.strictRoute,
      interfaceName: interfaceName ?? this.interfaceName,
      endpointIndependentNat:
          endpointIndependentNat ?? this.endpointIndependentNat,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxTunOptions &&
      other.inet4Address == inet4Address &&
      other.inet6Address == inet6Address &&
      other.enableIpv6 == enableIpv6 &&
      other.mtu == mtu &&
      other.stack == stack &&
      other.autoRoute == autoRoute &&
      other.strictRoute == strictRoute &&
      other.interfaceName == interfaceName &&
      other.endpointIndependentNat == endpointIndependentNat;

  @override
  int get hashCode => Object.hash(
    inet4Address,
    inet6Address,
    enableIpv6,
    mtu,
    stack,
    autoRoute,
    strictRoute,
    interfaceName,
    endpointIndependentNat,
  );

  @override
  String toString() => 'SingBoxTunOptions(${toMap()})';
}

/// DNS options of the configuration generated by `SingBoxConfigBuilder`.
///
/// Two resolvers are configured:
///
/// * [remote] answers every query by default and is reached **through the
///   proxy** (no DNS leaks). Overridden by `SingBoxRoutingRules.dnsServers`.
/// * [direct] resolves bypassed domains and the host names of the proxy
///   servers themselves (`route.default_domain_resolver`), without the proxy.
///
/// Addresses use the syntax of `SingBoxDnsServer.parse`, for example
/// `1.1.1.1`, `tls://1.1.1.1`, `https://dns.google/dns-query`,
/// `quic://dns.adguard-dns.com`, `h3://dns.google/dns-query`,
/// `tcp://8.8.8.8:53` or `local` (the system resolver).
///
/// ```dart
/// const dns = SingBoxDnsOptions(
///   remote: 'tls://8.8.8.8',
///   direct: 'https://223.5.5.5/dns-query',
///   fakeIp: true,
/// );
/// ```
class SingBoxDnsOptions {
  /// Creates DNS options.
  const SingBoxDnsOptions({
    this.remote = 'https://1.1.1.1/dns-query',
    this.direct = 'local',
    this.strategy = SingBoxDnsStrategy.preferIpv4,
    this.fakeIp = false,
    this.fakeIpInet4Range = '198.18.0.0/15',
    this.fakeIpInet6Range = 'fc00::/18',
    this.reverseMapping = false,
  });

  /// Address of the remote (proxied) DNS server.
  final String remote;

  /// Address of the direct DNS server used for bypassed domains and for
  /// resolving proxy server host names. `local` uses the system resolver of
  /// the underlying network.
  final String direct;

  /// Default domain strategy.
  final SingBoxDnsStrategy strategy;

  /// Whether A/AAAA queries of proxied domains are answered with fake IPs
  /// (FakeIP). Saves a DNS round trip and resolves names on the proxy side.
  final bool fakeIp;

  /// IPv4 range used for fake IPs.
  final String fakeIpInet4Range;

  /// IPv6 range used for fake IPs (only when IPv6 is enabled in the TUN).
  final String fakeIpInet6Range;

  /// Whether DNS answers are remembered so domain based route rules also
  /// match connections that could not be sniffed (`dns.reverse_mapping`).
  final bool reverseMapping;

  /// Converts the options to a JSON-safe map.
  Map<String, dynamic> toMap() => {
    'remote': remote,
    'direct': direct,
    'strategy': strategy.value,
    'fakeIp': fakeIp,
    'fakeIpInet4Range': fakeIpInet4Range,
    'fakeIpInet6Range': fakeIpInet6Range,
    'reverseMapping': reverseMapping,
  };

  /// Creates options from a map produced by [toMap].
  ///
  /// Unknown keys are ignored and missing or malformed values fall back to
  /// the defaults.
  factory SingBoxDnsOptions.fromMap(Map<dynamic, dynamic> map) {
    const d = SingBoxDnsOptions();
    return SingBoxDnsOptions(
      remote: readString(map['remote']) ?? d.remote,
      direct: readString(map['direct']) ?? d.direct,
      strategy: SingBoxDnsStrategy.fromValue(readString(map['strategy'])),
      fakeIp: readBool(map['fakeIp']) ?? d.fakeIp,
      fakeIpInet4Range:
          readString(map['fakeIpInet4Range']) ?? d.fakeIpInet4Range,
      fakeIpInet6Range:
          readString(map['fakeIpInet6Range']) ?? d.fakeIpInet6Range,
      reverseMapping: readBool(map['reverseMapping']) ?? d.reverseMapping,
    );
  }

  /// Returns a copy with the given fields replaced.
  SingBoxDnsOptions copyWith({
    String? remote,
    String? direct,
    SingBoxDnsStrategy? strategy,
    bool? fakeIp,
    String? fakeIpInet4Range,
    String? fakeIpInet6Range,
    bool? reverseMapping,
  }) {
    return SingBoxDnsOptions(
      remote: remote ?? this.remote,
      direct: direct ?? this.direct,
      strategy: strategy ?? this.strategy,
      fakeIp: fakeIp ?? this.fakeIp,
      fakeIpInet4Range: fakeIpInet4Range ?? this.fakeIpInet4Range,
      fakeIpInet6Range: fakeIpInet6Range ?? this.fakeIpInet6Range,
      reverseMapping: reverseMapping ?? this.reverseMapping,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxDnsOptions &&
      other.remote == remote &&
      other.direct == direct &&
      other.strategy == strategy &&
      other.fakeIp == fakeIp &&
      other.fakeIpInet4Range == fakeIpInet4Range &&
      other.fakeIpInet6Range == fakeIpInet6Range &&
      other.reverseMapping == reverseMapping;

  @override
  int get hashCode => Object.hash(
    remote,
    direct,
    strategy,
    fakeIp,
    fakeIpInet4Range,
    fakeIpInet6Range,
    reverseMapping,
  );

  @override
  String toString() => 'SingBoxDnsOptions(${toMap()})';
}

/// Global options of `SingBoxConfigBuilder`: logging, TUN, DNS, URL test,
/// Clash modes, cache file and rule-set downloads.
///
/// Routing preferences that users usually edit (bypass/block lists, DNS
/// servers, countries) live in `SingBoxRoutingRules` instead.
///
/// ```dart
/// const builder = SingBoxConfigBuilder(
///   SingBoxConfigOptions(
///     logLevel: SingBoxConfigLogLevel.warn,
///     dns: SingBoxDnsOptions(fakeIp: true),
///     urlTestInterval: Duration(minutes: 10),
///   ),
/// );
/// ```
class SingBoxConfigOptions {
  /// Creates builder options.
  const SingBoxConfigOptions({
    this.logLevel = SingBoxConfigLogLevel.info,
    this.logTimestamp = true,
    this.tun = const SingBoxTunOptions(),
    this.dns = const SingBoxDnsOptions(),
    this.sniff = true,
    this.urlTestUrl = 'https://www.gstatic.com/generate_204',
    this.urlTestInterval = const Duration(minutes: 3),
    this.urlTestTolerance = 50,
    this.interruptExistConnections = true,
    this.enableClashModes = true,
    this.cacheFile = true,
    this.ruleSetDownloadDetour = 'direct',
    this.ruleSetUpdateInterval = const Duration(days: 1),
    this.geoipRuleSetUrl = defaultGeoipRuleSetUrl,
    this.geositeRuleSetUrl = defaultGeositeRuleSetUrl,
  });

  /// Default download URL template of geoip rule-sets; `{tag}` is replaced
  /// by the rule-set tag, e.g. `geoip-ru`.
  static const defaultGeoipRuleSetUrl =
      'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/{tag}.srs';

  /// Default download URL template of geosite rule-sets; `{tag}` is replaced
  /// by the rule-set tag, e.g. `geosite-category-ads-all`.
  static const defaultGeositeRuleSetUrl =
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/{tag}.srs';

  /// Log level (`log.level`).
  final SingBoxConfigLogLevel logLevel;

  /// Whether log lines include a timestamp (`log.timestamp`).
  final bool logTimestamp;

  /// TUN inbound options.
  final SingBoxTunOptions tun;

  /// DNS options.
  final SingBoxDnsOptions dns;

  /// Whether protocols (TLS SNI, HTTP host, QUIC, DNS, …) are sniffed so that
  /// domain based rules work for connections made to IP addresses.
  final bool sniff;

  /// URL probed by the `auto` URL test group and by latency tests.
  final String urlTestUrl;

  /// Interval between automatic URL tests of the `auto` group.
  final Duration urlTestInterval;

  /// Latency difference in milliseconds below which the `auto` group keeps
  /// the current outbound.
  final int urlTestTolerance;

  /// Whether existing connections are closed when the selected outbound of
  /// the `proxy` or `auto` group changes.
  final bool interruptExistConnections;

  /// Whether Clash modes are available: `clash_mode` rules for `Direct`
  /// (everything direct) and `Global` (everything proxied) plus
  /// `experimental.clash_api`, so the app can switch between Rule, Global
  /// and Direct at runtime.
  final bool enableClashModes;

  /// Whether `experimental.cache_file` is enabled. It persists the selected
  /// outbound, the Clash mode, downloaded rule-sets and FakeIP mappings.
  final bool cacheFile;

  /// Outbound tag used to download remote rule-sets: `direct` (default) or
  /// `proxy`.
  ///
  /// Rule-sets are downloaded by an entry of `http_clients` (sing-box 1.14);
  /// `direct` means the HTTP client dials without a detour.
  final String ruleSetDownloadDetour;

  /// How often remote rule-sets are refreshed.
  final Duration ruleSetUpdateInterval;

  /// Download URL template of geoip rule-sets (`{tag}` placeholder). Point it
  /// to a mirror when `raw.githubusercontent.com` is not reachable.
  final String geoipRuleSetUrl;

  /// Download URL template of geosite rule-sets (`{tag}` placeholder).
  final String geositeRuleSetUrl;

  /// Converts the options to a JSON-safe map. Durations are stored in
  /// seconds.
  Map<String, dynamic> toMap() => {
    'logLevel': logLevel.value,
    'logTimestamp': logTimestamp,
    'tun': tun.toMap(),
    'dns': dns.toMap(),
    'sniff': sniff,
    'urlTestUrl': urlTestUrl,
    'urlTestInterval': urlTestInterval.inSeconds,
    'urlTestTolerance': urlTestTolerance,
    'interruptExistConnections': interruptExistConnections,
    'enableClashModes': enableClashModes,
    'cacheFile': cacheFile,
    'ruleSetDownloadDetour': ruleSetDownloadDetour,
    'ruleSetUpdateInterval': ruleSetUpdateInterval.inSeconds,
    'geoipRuleSetUrl': geoipRuleSetUrl,
    'geositeRuleSetUrl': geositeRuleSetUrl,
  };

  /// Creates options from a map produced by [toMap].
  ///
  /// Unknown keys are ignored and missing or malformed values fall back to
  /// the defaults.
  factory SingBoxConfigOptions.fromMap(Map<dynamic, dynamic> map) {
    const d = SingBoxConfigOptions();
    final tun = map['tun'];
    final dns = map['dns'];
    final interval = readInt(map['urlTestInterval']);
    final updateInterval = readInt(map['ruleSetUpdateInterval']);
    return SingBoxConfigOptions(
      logLevel: SingBoxConfigLogLevel.fromValue(readString(map['logLevel'])),
      logTimestamp: readBool(map['logTimestamp']) ?? d.logTimestamp,
      tun: tun is Map ? SingBoxTunOptions.fromMap(tun) : d.tun,
      dns: dns is Map ? SingBoxDnsOptions.fromMap(dns) : d.dns,
      sniff: readBool(map['sniff']) ?? d.sniff,
      urlTestUrl: readString(map['urlTestUrl']) ?? d.urlTestUrl,
      urlTestInterval: interval != null && interval > 0
          ? Duration(seconds: interval)
          : d.urlTestInterval,
      urlTestTolerance: readInt(map['urlTestTolerance']) ?? d.urlTestTolerance,
      interruptExistConnections:
          readBool(map['interruptExistConnections']) ??
          d.interruptExistConnections,
      enableClashModes: readBool(map['enableClashModes']) ?? d.enableClashModes,
      cacheFile: readBool(map['cacheFile']) ?? d.cacheFile,
      ruleSetDownloadDetour:
          readString(map['ruleSetDownloadDetour']) ?? d.ruleSetDownloadDetour,
      ruleSetUpdateInterval: updateInterval != null && updateInterval > 0
          ? Duration(seconds: updateInterval)
          : d.ruleSetUpdateInterval,
      geoipRuleSetUrl: readString(map['geoipRuleSetUrl']) ?? d.geoipRuleSetUrl,
      geositeRuleSetUrl:
          readString(map['geositeRuleSetUrl']) ?? d.geositeRuleSetUrl,
    );
  }

  /// Returns a copy with the given fields replaced.
  SingBoxConfigOptions copyWith({
    SingBoxConfigLogLevel? logLevel,
    bool? logTimestamp,
    SingBoxTunOptions? tun,
    SingBoxDnsOptions? dns,
    bool? sniff,
    String? urlTestUrl,
    Duration? urlTestInterval,
    int? urlTestTolerance,
    bool? interruptExistConnections,
    bool? enableClashModes,
    bool? cacheFile,
    String? ruleSetDownloadDetour,
    Duration? ruleSetUpdateInterval,
    String? geoipRuleSetUrl,
    String? geositeRuleSetUrl,
  }) {
    return SingBoxConfigOptions(
      logLevel: logLevel ?? this.logLevel,
      logTimestamp: logTimestamp ?? this.logTimestamp,
      tun: tun ?? this.tun,
      dns: dns ?? this.dns,
      sniff: sniff ?? this.sniff,
      urlTestUrl: urlTestUrl ?? this.urlTestUrl,
      urlTestInterval: urlTestInterval ?? this.urlTestInterval,
      urlTestTolerance: urlTestTolerance ?? this.urlTestTolerance,
      interruptExistConnections:
          interruptExistConnections ?? this.interruptExistConnections,
      enableClashModes: enableClashModes ?? this.enableClashModes,
      cacheFile: cacheFile ?? this.cacheFile,
      ruleSetDownloadDetour:
          ruleSetDownloadDetour ?? this.ruleSetDownloadDetour,
      ruleSetUpdateInterval:
          ruleSetUpdateInterval ?? this.ruleSetUpdateInterval,
      geoipRuleSetUrl: geoipRuleSetUrl ?? this.geoipRuleSetUrl,
      geositeRuleSetUrl: geositeRuleSetUrl ?? this.geositeRuleSetUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxConfigOptions &&
      other.logLevel == logLevel &&
      other.logTimestamp == logTimestamp &&
      other.tun == tun &&
      other.dns == dns &&
      other.sniff == sniff &&
      other.urlTestUrl == urlTestUrl &&
      other.urlTestInterval == urlTestInterval &&
      other.urlTestTolerance == urlTestTolerance &&
      other.interruptExistConnections == interruptExistConnections &&
      other.enableClashModes == enableClashModes &&
      other.cacheFile == cacheFile &&
      other.ruleSetDownloadDetour == ruleSetDownloadDetour &&
      other.ruleSetUpdateInterval == ruleSetUpdateInterval &&
      other.geoipRuleSetUrl == geoipRuleSetUrl &&
      other.geositeRuleSetUrl == geositeRuleSetUrl;

  @override
  int get hashCode => Object.hash(
    logLevel,
    logTimestamp,
    tun,
    dns,
    sniff,
    urlTestUrl,
    urlTestInterval,
    urlTestTolerance,
    interruptExistConnections,
    enableClashModes,
    cacheFile,
    ruleSetDownloadDetour,
    ruleSetUpdateInterval,
    geoipRuleSetUrl,
    geositeRuleSetUrl,
  );

  @override
  String toString() => 'SingBoxConfigOptions(${toMap()})';
}
