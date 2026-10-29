/// The sing-box core linked into the app. It is chosen when the app is built
/// (`sing_box: core: lx` in the app's `pubspec.yaml`, see the README section
/// "sing-box-lx core") and reported by `SingBox.core` after `initialize()`.
enum SingBoxCore {
  /// The official sing-box core (SagerNet/sing-box).
  standard,

  /// The sing-box-lx fork (github.com/Leadaxe/sing-box-lx): the official
  /// core plus the [SingBoxCoreFeature]s.
  lx;

  /// The core whose libbox reports [version] (lx versions look like
  /// `1.14.4-lx.25`).
  static SingBoxCore fromVersion(String version) =>
      version.contains('-lx') ? lx : standard;

  /// Whether this core has [feature].
  bool supports(SingBoxCoreFeature feature) => this == lx;

  /// Message of the `SingBoxUnsupportedException` thrown when something
  /// needs the lx core.
  static const requiresLxMessage = 'requires the sing-box-lx core';
}

/// Capabilities that only the sing-box-lx core has ([SingBoxCore.lx]).
enum SingBoxCoreFeature {
  /// The Xray-compatible XHTTP ("splithttp") transport (`transport.type:
  /// xhttp`, VLESS links with `type=xhttp`).
  xhttp,

  /// AmneziaWG 2.0 / 3.x obfuscation of WireGuard endpoints (`jc`, `jmin`,
  /// `jmax`, `s1`-`s4`, `h1`-`h4`, `i1`-`i5`).
  amneziaWg,

  /// The `masque` outbound (CONNECT-IP, Cloudflare WARP).
  masque,

  /// The `trusttunnel` outbound (AdGuard TrustTunnel).
  trustTunnel,

  /// The post-quantum VLESS `encryption` layer (`mlkem768x25519plus`).
  vlessEncryption,

  /// REALITY with the hybrid post-quantum key share that current Xray
  /// servers require (`tls.reality.key_share`).
  realityKeyShare,

  /// The multi-hop `chain` outbound.
  chain,

  /// Round-robin load balancing and failover of `urltest` groups.
  loadBalancing,

  /// DNS server groups (`dns.servers[].type: group`).
  dnsServerGroup,

  /// Idle-suspend of WireGuard / AmneziaWG endpoints (`lx.wg.idle_suspend`).
  idleSuspend,

  /// The extra libbox command client queries (pools, rules, DNS queries).
  observability,
}
