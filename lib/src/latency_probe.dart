// Measures HTTP latency through a probe route of the running tunnel or a
// probe core. Internal; used by the SingBox ping methods.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The probe route or core could not be reached at all, e.g. because the app
/// itself is not routed through the tunnel.
class ProbeConnectException implements Exception {
  /// Creates the exception.
  const ProbeConnectException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ProbeConnectException: $message';
}

/// Connects to [address]:[port], which forwards to the host of [url] through
/// a proxy, sends a `HEAD` (or, with `head: false`, `GET`) request for [url]
/// (TLS with the URL's host name for `https`) and returns the time until the
/// response headers arrived together with the status code.
///
/// Throws a [ProbeConnectException] when the TCP connection fails, a
/// [TimeoutException] after [timeout] and other exceptions for TLS and HTTP
/// errors.
Future<({int milliseconds, int statusCode})> measureHttp(
  String address,
  int port,
  Uri url, {
  required bool head,
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  Duration left() {
    final remaining = timeout - stopwatch.elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Socket socket;
  try {
    socket = await Socket.connect(address, port, timeout: timeout);
  } on SocketException catch (e) {
    throw ProbeConnectException(e.osError?.message ?? e.message);
  } on OSError catch (e) {
    // Seen on iOS: a reset during connect surfaces as a bare OSError.
    throw ProbeConnectException(e.message);
  }
  // Write errors (a reset connection) surface through the reads below; the
  // done future must not report them as unhandled errors.
  socket.done.ignore();
  try {
    if (url.scheme == 'https') {
      socket = await SecureSocket.secure(
        socket,
        host: url.host,
      ).timeout(left());
      socket.done.ignore();
    }
    final path = url.path.isEmpty ? '/' : url.path;
    final target = url.hasQuery ? '$path?${url.query}' : path;
    final host = url.hasPort ? '${url.host}:${url.port}' : url.host;
    socket.add(
      ascii.encode(
        '${head ? 'HEAD' : 'GET'} $target HTTP/1.1\r\n'
        'Host: $host\r\n'
        'User-Agent: sing_box\r\n'
        'Accept: */*\r\n'
        'Connection: close\r\n\r\n',
      ),
    );
    final statusCode = await _readStatus(socket).timeout(left());
    return (
      milliseconds: stopwatch.elapsedMilliseconds,
      statusCode: statusCode,
    );
  } finally {
    socket.destroy();
  }
}

/// Reads the response headers and returns the status code.
Future<int> _readStatus(Stream<List<int>> socket) async {
  final bytes = <int>[];
  await for (final chunk in socket) {
    bytes.addAll(chunk);
    final end = _indexOf(bytes, const [13, 10, 13, 10]);
    if (end >= 0) {
      final statusLine = latin1.decode(bytes.sublist(0, end)).split('\r\n')[0];
      final match = RegExp(r'^HTTP/\d(?:\.\d)? (\d{3})').firstMatch(statusLine);
      if (match == null) {
        throw FormatException('Not an HTTP response: $statusLine');
      }
      return int.parse(match.group(1)!);
    }
    if (bytes.length > 64 * 1024) {
      throw const FormatException('The response headers are too long');
    }
  }
  throw const SocketException('The connection was closed before a response');
}

int _indexOf(List<int> bytes, List<int> pattern) {
  outer:
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Reserves [count] free TCP ports on the loopback interface (they are free
/// again when this returns, so a probe core can bind them right away).
Future<List<int>> freeLoopbackPorts(int count) async {
  final sockets = <ServerSocket>[];
  try {
    for (var i = 0; i < count; i++) {
      sockets.add(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    }
    return [for (final socket in sockets) socket.port];
  } finally {
    for (final socket in sockets) {
      await socket.close();
    }
  }
}
