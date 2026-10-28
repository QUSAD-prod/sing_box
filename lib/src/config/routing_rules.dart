import 'internal/json_utils.dart';

/// Which IP versions the VPN uses ([SingBoxRoutingRules.ipVersion]).
///
/// | Value | DNS (`dns.strategy`) | Connections |
/// |-------|----------------------|-------------|
/// | [dual] | both, preferring `SingBoxDnsOptions.strategy` | IPv4 and IPv6 |
/// | [ipv4] | `ipv4_only` | IPv6 connections that would go through the proxy are rejected |
/// | [ipv6] | `ipv6_only` | IPv4 addresses still work, but names resolve to IPv6 only |
enum SingBoxIpVersion {
  /// IPv4 and IPv6 (the default). Which family is preferred when a name has
  /// both is set by `SingBoxDnsOptions.strategy` (IPv4 by default).
  dual,

  /// IPv4 only. Names resolve to IPv4 addresses and IPv6 connections that
  /// would otherwise go through the proxy are rejected, so apps fall back to
  /// IPv4 at once. Use it when a server or network has no working IPv6.
  ///
  /// The TUN interface keeps its IPv6 address, so IPv6 traffic is still
  /// captured and cannot leave outside the VPN.
  ipv4,

  /// IPv6 only. Names resolve to IPv6 addresses (sites without IPv6 cannot
  /// be opened by name); connections to IPv4 addresses still work. Requires
  /// `SingBoxTunOptions.enableIpv6` (the default).
  ipv6;

  /// Returns the value whose [name] equals [name] (case-insensitive), or
  /// [dual] when nothing matches.
  static SingBoxIpVersion fromName(String? name) {
    final normalized = name?.trim().toLowerCase();
    for (final value in values) {
      if (value.name == normalized) return value;
    }
    return dual;
  }
}

/// User routing preferences applied on top of any server configuration:
/// per-app split tunneling, bypassed and blocked domains/subnets, custom DNS
/// servers, country based bypass and ad blocking.
///
/// `SingBoxConfigBuilder` translates the rules into sing-box fields:
///
/// | Rule | sing-box |
/// |------|----------|
/// | [proxyApps] | TUN `include_package` (only these apps use the VPN) |
/// | [bypassApps] | TUN `exclude_package` (ignored when [proxyApps] is set) |
/// | [blockedApps] | route rule `package_name` → `reject` |
/// | [bypassDomains] | route rule `domain_suffix` → `direct`, DNS via the direct resolver |
/// | [blockedDomains] | route rule `domain_suffix` → `reject`, DNS answered `NXDOMAIN` |
/// | [bypassSubnets] | TUN `route_exclude_address` + route rule `ip_cidr` → `direct` |
/// | [bypassLan] | route rule `ip_is_private` → `direct` |
/// | [bypassCountries] | remote rule-sets `geoip-<cc>` (+ geosite where available) → `direct` |
/// | [blockAds] | rule-set `geosite-category-ads-all` → `reject` |
/// | [dnsServers] | replace the remote (proxied) DNS server |
/// | [ipVersion] | `dns.strategy` and, for IPv4 only, a route rule `ip_version: 6` → `reject` |
///
/// Invalid entries (malformed domains, CIDRs, package names, unknown country
/// codes) are skipped by the builder instead of producing a broken config.
///
/// ```dart
/// const rules = SingBoxRoutingRules(
///   bypassApps: ['com.android.vending'],
///   bypassDomains: ['example.com', 'intranet.local'],
///   blockedDomains: ['ads.example.net'],
///   bypassCountries: ['ru'],
///   dnsServers: ['tls://1.1.1.1'],
///   blockAds: true,
/// );
/// ```
class SingBoxRoutingRules {
  /// Creates routing rules. Every list defaults to empty, [bypassLan] to
  /// `true`, [blockAds] to `false` and [ipVersion] to
  /// [SingBoxIpVersion.dual].
  const SingBoxRoutingRules({
    this.bypassApps = const [],
    this.proxyApps = const [],
    this.bypassDomains = const [],
    this.bypassSubnets = const [],
    this.blockedApps = const [],
    this.blockedDomains = const [],
    this.dnsServers = const [],
    this.bypassLan = true,
    this.bypassCountries = const [],
    this.blockAds = false,
    this.ipVersion = SingBoxIpVersion.dual,
  });

  /// Android package names whose traffic does not enter the VPN
  /// (TUN `exclude_package`). Ignored when [proxyApps] is not empty.
  /// Has no effect on iOS.
  final List<String> bypassApps;

  /// Android package names that are the **only** apps using the VPN
  /// (TUN `include_package`). When not empty, [bypassApps] is ignored.
  /// Has no effect on iOS.
  final List<String> proxyApps;

  /// Domain suffixes connected directly and resolved with the direct DNS
  /// server. `example.com` also matches `www.example.com`.
  final List<String> bypassDomains;

  /// Subnets (CIDR, or plain IP addresses) connected directly and excluded
  /// from the TUN routes.
  final List<String> bypassSubnets;

  /// Android package names whose connections are rejected.
  final List<String> blockedApps;

  /// Domain suffixes whose DNS queries and connections are rejected.
  final List<String> blockedDomains;

  /// Custom remote DNS servers replacing the default remote resolver. The
  /// first entry answers queries; the others are added as additional
  /// servers. Supported formats: `1.1.1.1`, `1.1.1.1:53`, `udp://…`,
  /// `tcp://8.8.8.8:53`, `tls://1.1.1.1`, `https://dns.google/dns-query`,
  /// `quic://…`, `h3://…`, `dhcp://auto` and `local`.
  final List<String> dnsServers;

  /// Whether private and local network addresses (RFC 1918, link-local,
  /// loopback, …) and LAN host names are connected directly.
  final bool bypassLan;

  /// ISO 3166-1 alpha-2 country codes (e.g. `ru`, `cn`, `ir`) whose IP
  /// ranges and, where a curated list exists, domains are connected directly.
  /// See `SingBoxRuleSets.countryRuleSets`.
  final List<String> bypassCountries;

  /// Whether connections to known advertising domains are rejected
  /// (`geosite-category-ads-all`).
  final bool blockAds;

  /// Which IP versions are used: IPv4 and IPv6 (default), IPv4 only or IPv6
  /// only. See [SingBoxIpVersion].
  final SingBoxIpVersion ipVersion;

  /// Whether no rule differs from the defaults.
  bool get isDefault => this == const SingBoxRoutingRules();

  /// Converts the rules to a JSON-safe map whose keys are the field names.
  Map<String, dynamic> toMap() => {
    'bypassApps': List<String>.of(bypassApps),
    'proxyApps': List<String>.of(proxyApps),
    'bypassDomains': List<String>.of(bypassDomains),
    'bypassSubnets': List<String>.of(bypassSubnets),
    'blockedApps': List<String>.of(blockedApps),
    'blockedDomains': List<String>.of(blockedDomains),
    'dnsServers': List<String>.of(dnsServers),
    'bypassLan': bypassLan,
    'bypassCountries': List<String>.of(bypassCountries),
    'blockAds': blockAds,
    'ipVersion': ipVersion.name,
  };

  /// Creates rules from a map produced by [toMap].
  ///
  /// Unknown keys are ignored, non-string list items are dropped and missing
  /// or malformed values fall back to the defaults.
  factory SingBoxRoutingRules.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxRoutingRules(
      bypassApps: readStringList(map['bypassApps']),
      proxyApps: readStringList(map['proxyApps']),
      bypassDomains: readStringList(map['bypassDomains']),
      bypassSubnets: readStringList(map['bypassSubnets']),
      blockedApps: readStringList(map['blockedApps']),
      blockedDomains: readStringList(map['blockedDomains']),
      dnsServers: readStringList(map['dnsServers']),
      bypassLan: readBool(map['bypassLan']) ?? true,
      bypassCountries: readStringList(map['bypassCountries']),
      blockAds: readBool(map['blockAds']) ?? false,
      ipVersion: SingBoxIpVersion.fromName(readString(map['ipVersion'])),
    );
  }

  /// Returns a copy with the given fields replaced.
  SingBoxRoutingRules copyWith({
    List<String>? bypassApps,
    List<String>? proxyApps,
    List<String>? bypassDomains,
    List<String>? bypassSubnets,
    List<String>? blockedApps,
    List<String>? blockedDomains,
    List<String>? dnsServers,
    bool? bypassLan,
    List<String>? bypassCountries,
    bool? blockAds,
    SingBoxIpVersion? ipVersion,
  }) {
    return SingBoxRoutingRules(
      bypassApps: bypassApps ?? this.bypassApps,
      proxyApps: proxyApps ?? this.proxyApps,
      bypassDomains: bypassDomains ?? this.bypassDomains,
      bypassSubnets: bypassSubnets ?? this.bypassSubnets,
      blockedApps: blockedApps ?? this.blockedApps,
      blockedDomains: blockedDomains ?? this.blockedDomains,
      dnsServers: dnsServers ?? this.dnsServers,
      bypassLan: bypassLan ?? this.bypassLan,
      bypassCountries: bypassCountries ?? this.bypassCountries,
      blockAds: blockAds ?? this.blockAds,
      ipVersion: ipVersion ?? this.ipVersion,
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxRoutingRules &&
      _listEquals(other.bypassApps, bypassApps) &&
      _listEquals(other.proxyApps, proxyApps) &&
      _listEquals(other.bypassDomains, bypassDomains) &&
      _listEquals(other.bypassSubnets, bypassSubnets) &&
      _listEquals(other.blockedApps, blockedApps) &&
      _listEquals(other.blockedDomains, blockedDomains) &&
      _listEquals(other.dnsServers, dnsServers) &&
      other.bypassLan == bypassLan &&
      _listEquals(other.bypassCountries, bypassCountries) &&
      other.blockAds == blockAds &&
      other.ipVersion == ipVersion;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(bypassApps),
    Object.hashAll(proxyApps),
    Object.hashAll(bypassDomains),
    Object.hashAll(bypassSubnets),
    Object.hashAll(blockedApps),
    Object.hashAll(blockedDomains),
    Object.hashAll(dnsServers),
    bypassLan,
    Object.hashAll(bypassCountries),
    blockAds,
    ipVersion,
  );

  @override
  String toString() => 'SingBoxRoutingRules(${toMap()})';
}
