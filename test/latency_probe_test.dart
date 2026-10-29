import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/latency_probe.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  /// A server that answers every request with [response] (`null`: closes
  /// the connection; empty: never answers) and records the requests.
  Future<(ServerSocket, List<String>)> serve(String? response) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    server.listen((socket) {
      if (response == null) {
        socket.destroy();
        return;
      }
      final data = <int>[];
      socket.listen((chunk) {
        data.addAll(chunk);
        final text = String.fromCharCodes(data);
        if (text.contains('\r\n\r\n')) {
          requests.add(text);
          if (response.isNotEmpty) {
            socket.add(response.codeUnits);
            socket.destroy();
          }
        }
      }, onError: (_) {});
    });
    addTearDown(server.close);
    return (server, requests);
  }

  final url = Uri.parse('http://probe.test:8080/generate_204?x=1');

  test('measures the time to the response headers', () async {
    final (server, requests) = await serve(
      'HTTP/1.1 204 No Content\r\nServer: t\r\n\r\n',
    );
    final result = await measureHttp(
      '127.0.0.1',
      server.port,
      url,
      head: true,
      timeout: const Duration(seconds: 5),
    );
    expect(result.statusCode, 204);
    expect(result.milliseconds, greaterThanOrEqualTo(0));
    expect(
      requests.single,
      startsWith(
        'HEAD /generate_204?x=1 HTTP/1.1\r\nHost: probe.test:8080\r\n',
      ),
    );

    await measureHttp(
      '127.0.0.1',
      server.port,
      Uri.parse('http://probe.test'),
      head: false,
      timeout: const Duration(seconds: 5),
    );
    expect(requests.last, startsWith('GET / HTTP/1.1\r\nHost: probe.test\r\n'));
  });

  test('errors', () async {
    final (closing, _) = await serve(null);
    await expectLater(
      measureHttp(
        '127.0.0.1',
        closing.port,
        url,
        head: true,
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<SocketException>()),
    );

    final (garbage, _) = await serve('SSH-2.0-OpenSSH\r\n\r\n');
    await expectLater(
      measureHttp(
        '127.0.0.1',
        garbage.port,
        url,
        head: true,
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<FormatException>()),
    );

    final (silent, _) = await serve('');
    await expectLater(
      measureHttp(
        '127.0.0.1',
        silent.port,
        url,
        head: true,
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );

    final [free] = await freeLoopbackPorts(1);
    await expectLater(
      measureHttp(
        '127.0.0.1',
        free,
        url,
        head: true,
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<ProbeConnectException>()),
    );
  });

  test('freeLoopbackPorts returns distinct bindable ports', () async {
    final ports = await freeLoopbackPorts(5);
    expect(ports.toSet(), hasLength(5));
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      ports.first,
    );
    await server.close();
  });
}
