import '../utils/validators.dart';
import 'internal/uri_parts.dart';

/// Converts DNS server address strings into sing-box 1.12+ DNS server
/// objects (`dns.servers[]`).
///
/// | Address | Result |
/// |---------|--------|
/// | `1.1.1.1`, `1.1.1.1:5353`, `[2606:4700::1111]:53` | `{"type": "udp", "server": "1.1.1.1"}` |
/// | `udp://8.8.8.8` | `udp` |
/// | `tcp://8.8.8.8:53` | `tcp` |
/// | `tls://1.1.1.1`, `dot://…` | `tls` (port 853) |
/// | `quic://dns.adguard-dns.com`, `doq://…` | `quic` (port 853) |
/// | `https://1.1.1.1/dns-query`, `doh://…` | `https` (port 443, custom `path` kept) |
/// | `h3://dns.google/dns-query`, `http3://…` | `h3` (DNS over HTTP/3) |
/// | `dhcp://auto`, `dhcp://en0` | `dhcp` (optional `interface`) |
/// | `local`, `system` | `local` (system resolver) |
///
/// Default ports are omitted from the result.
///
/// ```dart
/// SingBoxDnsServer.parse('tls://1.1.1.1', tag: 'dns-remote', detour: 'proxy');
/// // {type: tls, tag: dns-remote, server: 1.1.1.1, detour: proxy}
/// ```
abstract final class SingBoxDnsServer {
  static const _defaultPorts = {
    'udp': 53,
    'tcp': 53,
    'tls': 853,
    'quic': 853,
    'https': 443,
    'h3': 443,
  };

  static const _schemeAliases = {
    'udp': 'udp',
    'tcp': 'tcp',
    'tls': 'tls',
    'dot': 'tls',
    'quic': 'quic',
    'doq': 'quic',
    'https': 'https',
    'doh': 'https',
    'h3': 'h3',
    'http3': 'h3',
  };

  /// DNS server types that connect to a remote `server`.
  static const remoteTypes = {'udp', 'tcp', 'tls', 'quic', 'https', 'h3'};

  /// Parses [address] into a DNS server object tagged [tag].
  ///
  /// [detour] (an outbound tag) is added to remote servers so their queries
  /// go through that outbound. [domainResolver] (a DNS server tag) is added
  /// when the server address is a host name and no [detour] is given; sing-box
  /// requires it in that case because DNS servers never resolve their own
  /// host names through the DNS rules.
  ///
  /// Throws a [FormatException] for empty, malformed or unsupported addresses
  /// (for example the removed legacy `rcode://` and `fakeip` formats, or
  /// plain `http://` DoH).
  static Map<String, dynamic> parse(
    String address, {
    required String tag,
    String? detour,
    String? domainResolver,
  }) {
    final input = address.trim();
    if (input.isEmpty) {
      throw const FormatException('DNS server address is empty');
    }
    final lower = input.toLowerCase();
    if (lower == 'local' || lower == 'system' || lower == 'local://') {
      return {'type': 'local', 'tag': tag};
    }
    final schemeEnd = input.indexOf('://');
    if (schemeEnd < 0) {
      final hostPort = splitHostPort(input);
      return _remote(
        type: 'udp',
        tag: tag,
        host: hostPort.host,
        port: hostPort.port,
        source: input,
        detour: detour,
        domainResolver: domainResolver,
      );
    }
    final scheme = lower.substring(0, schemeEnd);
    var rest = input.substring(schemeEnd + 3);
    if (scheme == 'dhcp') {
      final iface = rest.replaceAll('/', '').trim();
      return {
        'type': 'dhcp',
        'tag': tag,
        if (iface.isNotEmpty && iface.toLowerCase() != 'auto')
          'interface': iface,
      };
    }
    final type = _schemeAliases[scheme];
    if (type == null) {
      if (scheme == 'rcode' || scheme == 'fakeip') {
        throw FormatException(
          'Legacy DNS address "$input" is not supported by sing-box 1.14; '
          'use rule actions instead',
        );
      }
      if (scheme == 'http') {
        throw FormatException(
          'DNS over plain HTTP is not supported, use https://',
          input,
        );
      }
      throw FormatException('Unsupported DNS server scheme "$scheme"', input);
    }
    final hash = rest.indexOf('#');
    if (hash >= 0) rest = rest.substring(0, hash);
    var path = '';
    final slash = rest.indexOf('/');
    final question = rest.indexOf('?');
    var cut = -1;
    if (slash >= 0 && (question < 0 || slash < question)) {
      cut = slash;
    } else if (question >= 0) {
      cut = question;
    }
    if (cut >= 0) {
      path = rest.substring(cut);
      rest = rest.substring(0, cut);
    }
    final at = rest.lastIndexOf('@');
    if (at >= 0) rest = rest.substring(at + 1);
    final hostPort = splitHostPort(rest);
    if (path.startsWith('?')) path = '/dns-query$path';
    return _remote(
      type: type,
      tag: tag,
      host: hostPort.host,
      port: hostPort.port,
      source: input,
      detour: detour,
      domainResolver: domainResolver,
      path:
          (type == 'https' || type == 'h3') &&
              path != '/dns-query' &&
              path != '/'
          ? path
          : '',
    );
  }

  /// Like [parse] but returns `null` instead of throwing.
  static Map<String, dynamic>? tryParse(
    String address, {
    required String tag,
    String? detour,
    String? domainResolver,
  }) {
    try {
      return parse(
        address,
        tag: tag,
        detour: detour,
        domainResolver: domainResolver,
      );
    } on FormatException {
      return null;
    }
  }

  /// Whether [address] can be parsed by [parse].
  static bool isValid(String address) =>
      tryParse(address, tag: 'validation') != null;

  /// Whether the DNS server object [server] connects to a host name without
  /// a `detour` or `domain_resolver`, which sing-box rejects at startup.
  static bool needsDomainResolver(Map<dynamic, dynamic> server) {
    if (!remoteTypes.contains(server['type'])) return false;
    final host = server['server'];
    if (host is! String || SingBoxValidators.isIp(host)) return false;
    final detour = server['detour'];
    final resolver = server['domain_resolver'];
    return (detour == null || detour == '') &&
        (resolver == null || resolver == '');
  }

  static Map<String, dynamic> _remote({
    required String type,
    required String tag,
    required String host,
    required int? port,
    required String source,
    required String? detour,
    required String? domainResolver,
    String path = '',
  }) {
    if (host.isEmpty) {
      throw FormatException('DNS server address has no host', source);
    }
    final isIp = SingBoxValidators.isIp(host);
    if (!isIp && !SingBoxValidators.isDomain(host)) {
      throw FormatException('Invalid DNS server host "$host"', source);
    }
    if (port != null && (port < 1 || port > 65535)) {
      throw FormatException('Invalid DNS server port $port', source);
    }
    final hasDetour = detour != null && detour.isNotEmpty;
    return {
      'type': type,
      'tag': tag,
      'server': host,
      if (port != null && port != _defaultPorts[type]) 'server_port': port,
      if (path.isNotEmpty) 'path': path,
      if (hasDetour) 'detour': detour,
      if (!isIp && !hasDetour && domainResolver != null)
        'domain_resolver': domainResolver,
    };
  }
}
