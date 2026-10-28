import 'internal/link_parser.dart';
import 'internal/link_writer.dart';
import 'internal/subscription.dart';
import 'outbound.dart';

/// Parses proxy share links and subscriptions into sing-box outbounds, and
/// converts outbounds back to share links.
///
/// Supported link formats follow the de-facto standards used by v2rayN,
/// NekoBox, Hiddify and the Xray share link proposal:
///
/// | Scheme | Protocol | Notes |
/// |--------|----------|-------|
/// | `vless://` | VLESS | `security` none/tls/reality, `flow=xtls-rprx-vision`, transports tcp/ws/grpc/http(h2)/httpupgrade/quic |
/// | `vmess://` | VMess | v2rayN base64 JSON, Xray URL style and Shadowrocket style |
/// | `trojan://` | Trojan | TLS by default, same transports as VLESS |
/// | `ss://` | Shadowsocks | SIP002 (base64 or plain user info), legacy base64, `obfs-local`/`v2ray-plugin` plugins |
/// | `hysteria2://`, `hy2://` | Hysteria 2 | salamander obfs, port hopping (`mport`, `host:1000-2000`) |
/// | `hysteria://` | Hysteria (v1) | best effort, UDP protocol only |
/// | `tuic://` | TUIC v5 | `uuid:password` |
/// | `socks://`, `socks5://`, `socks4://`, `socks4a://` | SOCKS | plain or base64 user info |
/// | `http://`, `https://` | HTTP proxy | links with a path are rejected as web addresses |
/// | `anytls://` | AnyTLS | `password@host:port?sni=…` |
/// | `wireguard://`, `wg://` | WireGuard | sing-box **endpoint** ([SingBoxOutbound.isEndpoint]) |
///
/// Unsupported by sing-box and rejected with a [FormatException]: XHTTP
/// (`type=xhttp`), mKCP, VLESS encryption other than `none`, legacy XTLS
/// flows, ShadowsocksR, TUIC v4 and Shadowsocks plugins other than
/// `obfs-local`/`v2ray-plugin`.
///
/// ```dart
/// final outbound = SingBoxShareLink.parse(
///   'vless://uuid@example.com:443?security=reality&sni=www.microsoft.com'
///   '&fp=chrome&pbk=KEY&sid=ab&flow=xtls-rprx-vision#Netherlands',
/// );
/// final servers = SingBoxShareLink.parseSubscription(responseBody);
/// final link = SingBoxShareLink.toLink(outbound.json);
/// ```
abstract final class SingBoxShareLink {
  /// Link schemes accepted by [parse] (lower case, without `://`).
  static const schemes = supportedSchemes;

  /// Outbound types accepted by [toLink].
  static const linkTypes = writableTypes;

  /// Parses a single share [link] into an outbound.
  ///
  /// The outbound tag is [tag] if given, otherwise the link name
  /// (`#fragment`, VMess `ps`), otherwise `<type>-<server>-<port>`.
  ///
  /// Throws a [FormatException] with a descriptive message for malformed
  /// links, unknown schemes and features sing-box does not support.
  static SingBoxOutbound parse(String link, {String? tag}) =>
      parseShareLink(link, tag: tag);

  /// Like [parse] but returns `null` instead of throwing.
  static SingBoxOutbound? tryParse(String link, {String? tag}) {
    try {
      return parseShareLink(link, tag: tag);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Whether [link] uses a supported scheme.
  ///
  /// Only the scheme is checked; use [tryParse] to validate the whole link.
  static bool isSupported(String link) {
    final scheme = schemeOf(link);
    return scheme != null && supportedSchemes.contains(scheme);
  }

  /// Parses subscription [content] into outbounds with unique tags.
  ///
  /// Accepted formats:
  ///
  /// * share links, one per line (CRLF/LF, blank lines and `#`/`//`
  ///   comments are ignored);
  /// * the same list encoded as base64 (standard or URL-safe, with or
  ///   without padding, possibly wrapped across lines), also per line;
  /// * a sing-box configuration JSON: its proxy outbounds and endpoints are
  ///   taken (groups, `direct`, `block` and `dns` are skipped, legacy
  ///   WireGuard outbounds are converted to endpoints);
  /// * a JSON array of outbound objects (or of share link strings) and a
  ///   single outbound object;
  /// * a SIP008 Shadowsocks JSON document (`{"servers": [...]}`).
  ///
  /// Invalid lines and unsupported entries are skipped. Duplicate tags get
  /// a ` (2)`, ` (3)`, … suffix. Returns an empty list when nothing usable
  /// is found. Clash YAML subscriptions are not supported.
  static List<SingBoxOutbound> parseSubscription(String content) =>
      parseSubscriptionContent(content);

  /// Converts a sing-box outbound (or WireGuard endpoint) object to a share
  /// link, using the formats understood by [parse].
  ///
  /// Supported types are listed in [linkTypes]: `vless`, `vmess`
  /// (v2rayN JSON), `trojan`, `shadowsocks` (SIP002), `hysteria2`,
  /// `hysteria`, `tuic`, `socks`, `http`, `anytls` and `wireguard`. The tag
  /// becomes the link name. Options without a link representation (e.g.
  /// multiplex, dial fields) are dropped.
  ///
  /// Throws an [UnsupportedError] for other types or transports and an
  /// [ArgumentError] when the object has no server.
  static String toLink(Map<String, dynamic> outbound) =>
      writeShareLink(outbound);
}
