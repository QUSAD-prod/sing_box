// Downloads subscriptions and reads the provider headers. Internal; used by
// SingBox.addSubscription / updateSubscription.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config/internal/uri_parts.dart';
import 'exceptions.dart';

/// Metadata a provider sends in the subscription response headers.
class SubscriptionHeaders {
  /// Creates the metadata; every field is optional.
  const SubscriptionHeaders({
    this.name,
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.updateInterval,
    this.webPageUrl,
    this.supportUrl,
    this.announce,
  });

  /// From `profile-title`, else the `content-disposition` file name.
  final String? name;

  /// `subscription-userinfo` upload, in bytes.
  final int? upload;

  /// `subscription-userinfo` download, in bytes.
  final int? download;

  /// `subscription-userinfo` total, in bytes.
  final int? total;

  /// `subscription-userinfo` expire (Unix seconds).
  final DateTime? expire;

  /// From `profile-update-interval` (hours).
  final Duration? updateInterval;

  /// `profile-web-page-url`.
  final String? webPageUrl;

  /// `support-url`.
  final String? supportUrl;

  /// `announce` (plain or `base64:`).
  final String? announce;
}

/// A downloaded subscription body with its headers.
class SubscriptionResponse {
  /// Creates a response.
  const SubscriptionResponse(this.body, this.headers);

  /// The body decoded as UTF-8.
  final String body;

  /// The provider metadata.
  final SubscriptionHeaders headers;
}

/// Reads [SubscriptionHeaders]; [header] returns the value of a header by
/// its lower-case name.
SubscriptionHeaders parseSubscriptionHeaders(
  String? Function(String name) header,
) {
  final info = _userInfo(header('subscription-userinfo'));
  final interval = int.tryParse(
    header('profile-update-interval')?.trim() ?? '',
  );
  return SubscriptionHeaders(
    name:
        _text(header('profile-title')) ??
        _fileName(header('content-disposition')),
    upload: info['upload'],
    download: info['download'],
    total: info['total'],
    expire:
        (info['expire'] ?? 0) > 0
            ? DateTime.fromMillisecondsSinceEpoch(info['expire']! * 1000)
            : null,
    updateInterval:
        interval != null && interval > 0 ? Duration(hours: interval) : null,
    webPageUrl: _nonEmpty(header('profile-web-page-url')),
    supportUrl: _nonEmpty(header('support-url')),
    announce: _text(header('announce')),
  );
}

/// `upload=1; download=2; total=3; expire=4` (any order and spacing).
Map<String, int> _userInfo(String? value) {
  final result = <String, int>{};
  if (value == null) return result;
  for (final part in value.split(RegExp('[;,]'))) {
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    final key = part.substring(0, eq).trim().toLowerCase();
    final number = num.tryParse(part.substring(eq + 1).trim());
    if (number != null && number >= 0) result[key] = number.toInt();
  }
  return result;
}

/// A header value that may be `base64:<data>`.
String? _text(String? value) {
  final trimmed = _nonEmpty(value);
  if (trimmed == null) return null;
  if (trimmed.toLowerCase().startsWith('base64:')) {
    return _nonEmpty(tryDecodeBase64(trimmed.substring(7)));
  }
  return trimmed;
}

/// The file name of a `content-disposition` header (RFC 6266/5987),
/// without a subscription file extension.
String? _fileName(String? value) {
  if (value == null) return null;
  String? name;
  final extended = RegExp(
    r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)",
    caseSensitive: false,
  ).firstMatch(value);
  if (extended != null) {
    name = percentDecode(extended.group(2)!.trim());
  } else {
    final plain = RegExp(
      r'filename\s*=\s*("([^"]*)"|[^;]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (plain != null) name = (plain.group(2) ?? plain.group(1))!.trim();
  }
  name = name?.replaceFirst(
    RegExp(r'\.(ya?ml|txt|json|conf)$', caseSensitive: false),
    '',
  );
  return _nonEmpty(name);
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Downloads [url] with GET. Throws a [SingBoxSubscriptionException] for
/// network errors, non-2xx responses, oversized and empty bodies.
Future<SubscriptionResponse> downloadSubscription(
  Uri url, {
  required String userAgent,
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 30),
  int maxBytes = 16 * 1024 * 1024,
}) async {
  if (!url.isScheme('http') && !url.isScheme('https')) {
    throw SingBoxSubscriptionException(
      'Only http and https subscription URLs are supported',
      url: url.toString(),
    );
  }
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await () async {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw SingBoxSubscriptionException(
          'HTTP ${response.statusCode} ${response.reasonPhrase}'.trim(),
          url: url.toString(),
          statusCode: response.statusCode,
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw SingBoxSubscriptionException(
            'The response is larger than $maxBytes bytes',
            url: url.toString(),
          );
        }
      }
      final body = utf8.decode(bytes, allowMalformed: true);
      if (body.trim().isEmpty) {
        throw SingBoxSubscriptionException(
          'The subscription is empty',
          url: url.toString(),
          statusCode: response.statusCode,
        );
      }
      return SubscriptionResponse(
        body,
        parseSubscriptionHeaders((name) => response.headers.value(name)),
      );
    }().timeout(timeout);
  } on SingBoxSubscriptionException {
    rethrow;
  } on TimeoutException {
    throw SingBoxSubscriptionException(
      'Timed out after ${timeout.inSeconds} s',
      url: url.toString(),
    );
  } on IOException catch (e) {
    throw SingBoxSubscriptionException('$e', url: url.toString());
  } finally {
    client.close(force: true);
  }
}
