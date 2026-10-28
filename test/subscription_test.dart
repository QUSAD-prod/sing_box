import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';
import 'package:sing_box/src/subscription_loader.dart';

import 'support/fake_platform.dart';

const _linkA = 'trojan://secret@198.51.100.4:443#Server%20A';
const _linkB = 'ss://YWVzLTEyOC1nY206dGVzdA@192.168.100.1:8888#Server%20B';
const _linkC = 'trojan://secret@198.51.100.5:443#Server%20C';

String _b64(String value) => base64.encode(utf8.encode(value));

/// A local subscription server: serves [body] with [headers] and records the
/// requests.
class _SubscriptionServer {
  late HttpServer _server;
  String body = '';
  int status = 200;
  Map<String, String> headers = {};
  final requests = <HttpHeaders>[];
  final _requested = StreamController<void>.broadcast();

  Stream<void> get onRequest => _requested.stream;

  String get url => 'http://127.0.0.1:${_server.port}/sub/token';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      requests.add(request.headers);
      request.response.statusCode = status;
      headers.forEach(request.response.headers.set);
      request.response.write(body);
      await request.response.close();
      _requested.add(null);
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeSingBoxPlatform platform;
  late _SubscriptionServer server;
  final singBox = SingBox.instance;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    await singBox.debugReset();
    platform = FakeSingBoxPlatform();
    SingBoxPlatform.instance = platform;
    server = _SubscriptionServer();
    await server.start();
    await singBox.initialize();
  });

  tearDown(() => server.stop());

  group('parseSubscriptionHeaders', () {
    SubscriptionHeaders parse(Map<String, String> headers) =>
        parseSubscriptionHeaders((name) => headers[name]);

    test('reads traffic, expiry, interval and provider links', () {
      final info = parse({
        'subscription-userinfo':
            'upload=455727941; download=6174315083;total=1073741824000; '
            'expire=1767225600',
        'profile-update-interval': '12',
        'profile-web-page-url': 'https://example.com',
        'support-url': 'https://t.me/support',
        'announce': 'base64:${_b64('Maintenance tonight')}',
      });
      expect(info.upload, 455727941);
      expect(info.download, 6174315083);
      expect(info.total, 1073741824000);
      expect(info.expire, DateTime.fromMillisecondsSinceEpoch(1767225600000));
      expect(info.updateInterval, const Duration(hours: 12));
      expect(info.webPageUrl, 'https://example.com');
      expect(info.supportUrl, 'https://t.me/support');
      expect(info.announce, 'Maintenance tonight');
    });

    test('takes the name from profile-title or content-disposition', () {
      expect(
        parse({'profile-title': 'base64:${_b64('Мой VPN')}'}).name,
        'Мой VPN',
      );
      expect(parse({'profile-title': ' Plain '}).name, 'Plain');
      expect(
        parse({
          'content-disposition':
              "attachment; filename*=UTF-8''%E2%9C%85%20Provider.yaml",
        }).name,
        '✅ Provider',
      );
      expect(
        parse({'content-disposition': 'attachment; filename="sub.txt"'}).name,
        'sub',
      );
      expect(parse({}).name, isNull);
    });

    test('ignores missing and malformed values', () {
      final info = parse({
        'subscription-userinfo': 'upload=; total=abc; expire=0',
        'profile-update-interval': 'soon',
      });
      expect(info.upload, isNull);
      expect(info.total, isNull);
      expect(info.expire, isNull);
      expect(info.updateInterval, isNull);
    });
  });

  group('SingBoxSubscription', () {
    test('round trips through maps', () {
      final subscription = SingBoxSubscription(
        id: 'sub-1',
        name: 'Provider',
        url: 'https://example.com/sub',
        userAgent: 'test',
        headers: const {'x-hwid': 'abc'},
        autoUpdate: false,
        updateInterval: const Duration(hours: 6),
        providerUpdateInterval: const Duration(hours: 12),
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(1000),
        lastError: 'HTTP 500',
        serverCount: 3,
        upload: 1,
        download: 2,
        total: 10,
        expire: DateTime.fromMillisecondsSinceEpoch(2000),
        webPageUrl: 'https://example.com',
        supportUrl: 'https://t.me/x',
        announce: 'hello',
      );
      final copy = SingBoxSubscription.fromMap(
        jsonDecode(jsonEncode(subscription.toMap())) as Map,
      );
      expect(copy, subscription);
      expect(copy.hashCode, subscription.hashCode);
      expect(subscription.copyWith(clearLastError: true).lastError, isNull);
      expect(
        subscription.copyWith(clearUpdateInterval: true).updateInterval,
        isNull,
      );
    });

    test('traffic, expiry and staleness', () {
      final now = DateTime(2026, 10, 28, 12);
      final subscription = SingBoxSubscription(
        id: 'a',
        name: 'a',
        url: 'https://a',
        upload: 3,
        download: 4,
        total: 10,
        providerUpdateInterval: const Duration(hours: 12),
        lastUpdated: now.subtract(const Duration(hours: 11)),
      );
      expect(subscription.used, 7);
      expect(subscription.remaining, 3);
      expect(subscription.isExpired, isFalse);
      expect(subscription.effectiveUpdateInterval, const Duration(hours: 12));
      expect(subscription.isStale(now), isFalse);
      expect(subscription.isStale(now.add(const Duration(hours: 1))), isTrue);
      expect(
        subscription
            .copyWith(updateInterval: const Duration(hours: 1))
            .isStale(now),
        isTrue,
      );
      const empty = SingBoxSubscription(id: 'b', name: 'b', url: 'https://b');
      expect(empty.used, isNull);
      expect(empty.remaining, isNull);
      expect(empty.isStale(now), isTrue);
      expect(
        empty.effectiveUpdateInterval,
        SingBoxSubscription.defaultUpdateInterval,
      );
      expect(
        SingBoxSubscription(
          id: 'c',
          name: 'c',
          url: 'https://c',
          expire: DateTime(2000),
        ).isExpired,
        isTrue,
      );
    });
  });

  group('SingBox subscriptions', () {
    test('addSubscription imports the servers and the metadata', () async {
      server
        ..body = _b64('$_linkA\n$_linkB')
        ..headers = {
          'subscription-userinfo': 'upload=1; download=2; total=100',
          'profile-title': 'base64:${_b64('Provider')}',
          'profile-update-interval': '6',
        };
      final subscription = await singBox.addSubscription(
        server.url,
        headers: {'x-hwid': 'device-1'},
      );
      expect(subscription.name, 'Provider');
      expect(subscription.serverCount, 2);
      expect(subscription.used, 3);
      expect(subscription.total, 100);
      expect(subscription.providerUpdateInterval, const Duration(hours: 6));
      expect(subscription.lastUpdated, isNotNull);
      expect(subscription.lastError, isNull);
      expect(await singBox.getSubscriptions(), [subscription]);

      final servers = await singBox.getServerConfigs();
      expect(servers.map((s) => s.name), ['Server A', 'Server B']);
      expect(servers.map((s) => s.subscriptionId).toSet(), {subscription.id});
      expect(servers.first.id, '${subscription.id}/Server A');

      final request = server.requests.single;
      expect(request.value(HttpHeaders.userAgentHeader), 'sing-box/1.14.4');
      expect(request.value('x-hwid'), 'device-1');
    });

    test('the name falls back to the URL host', () async {
      server.body = _linkA;
      singBox.subscriptionUserAgent = 'MyApp/1.0';
      final subscription = await singBox.addSubscription(server.url);
      expect(subscription.name, '127.0.0.1');
      expect(
        server.requests.single.value(HttpHeaders.userAgentHeader),
        'MyApp/1.0',
      );
      final named = await singBox.addSubscription(
        server.url,
        name: 'Mine',
        userAgent: 'Custom',
      );
      expect(named.name, 'Mine');
      expect(named.id, isNot(subscription.id));
      expect(server.requests.last.value(HttpHeaders.userAgentHeader), 'Custom');
    });

    test(
      'updateSubscription replaces the servers and keeps their state',
      () async {
        server.body = '$_linkA\n$_linkB';
        final subscription = await singBox.addSubscription(server.url);
        final servers = await singBox.getServerConfigs();
        final manual = SingBoxServerConfig.fromOutbound(
          SingBoxShareLink.parse(_linkC).json,
          id: 'manual',
        );
        await singBox.addServerConfig(manual);
        await singBox.updateServerConfig(servers[0].copyWith(enabled: false));
        await singBox.setActiveServerConfig(servers[1].id);

        final changes = singBox.watchSubscriptions().skip(1).first;
        server.body = '$_linkA\n$_linkC';
        final updated = await singBox.updateSubscription(subscription.id);
        expect(updated.serverCount, 2);
        expect((await changes).single.serverCount, 2);

        final after = await singBox.getServerConfigs();
        expect(after.map((s) => s.id), [
          '${subscription.id}/Server A',
          '${subscription.id}/Server C',
          'manual',
        ]);
        expect(after.first.enabled, isFalse);
        // The active server (Server B) disappeared.
        expect(await singBox.getActiveServerConfig(), isNull);
      },
    );

    test('failures are thrown and recorded', () async {
      server.body = _linkA;
      final subscription = await singBox.addSubscription(server.url);

      server.status = 404;
      await expectLater(
        singBox.updateSubscription(subscription.id),
        throwsA(
          isA<SingBoxSubscriptionException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
      final failed = (await singBox.getSubscription(subscription.id))!;
      expect(failed.lastError, contains('404'));
      expect(await singBox.getServerConfigs(), hasLength(1));

      server
        ..status = 200
        ..body = 'nothing useful here';
      await expectLater(
        singBox.addSubscription(server.url),
        throwsA(isA<SingBoxSubscriptionException>()),
      );
      expect(await singBox.getSubscriptions(), hasLength(1));

      await expectLater(
        singBox.addSubscription('not a url'),
        throwsA(isA<SingBoxSubscriptionException>()),
      );
      await expectLater(
        singBox.addSubscription('ftp://example.com/sub'),
        throwsA(isA<SingBoxSubscriptionException>()),
      );
      await expectLater(
        singBox.updateSubscription('missing'),
        throwsA(isA<SingBoxSubscriptionException>()),
      );

      server.body = _linkB;
      final recovered = await singBox.updateSubscription(subscription.id);
      expect(recovered.lastError, isNull);
    });

    test('updateSubscriptions(onlyStale) skips fresh subscriptions', () async {
      server.body = _linkA;
      final fresh = await singBox.addSubscription(server.url, name: 'fresh');
      final stale = await singBox.addSubscription(server.url, name: 'stale');
      await singBox.editSubscription(
        stale.copyWith(lastUpdated: DateTime(2000)),
      );
      final manualOnly = await singBox.addSubscription(
        server.url,
        name: 'manual',
        autoUpdate: false,
      );
      await singBox.editSubscription(
        manualOnly.copyWith(lastUpdated: DateTime(2000)),
      );

      final updated = await singBox.updateSubscriptions(onlyStale: true);
      expect(updated.map((s) => s.id), [stale.id]);
      expect((await singBox.updateSubscriptions()).map((s) => s.id), [
        fresh.id,
        stale.id,
        manualOnly.id,
      ]);
    });

    test('initialize updates stale subscriptions', () async {
      server.body = _linkA;
      final subscription = await singBox.addSubscription(server.url);
      await singBox.editSubscription(
        subscription.copyWith(lastUpdated: DateTime(2000)),
      );
      await singBox.debugReset();
      SingBoxPlatform.instance = platform;
      final requested = server.onRequest.first;
      await singBox.initialize();
      await requested.timeout(const Duration(seconds: 5));
      await pumpEventQueue();
      final updated = (await singBox.getSubscription(subscription.id))!;
      expect(updated.lastUpdated!.isAfter(DateTime(2001)), isTrue);
    });

    test('editSubscription and removeSubscription', () async {
      server.body = '$_linkA\n$_linkB';
      final first = await singBox.addSubscription(server.url, name: 'one');
      final second = await singBox.addSubscription(server.url, name: 'two');
      expect(
        await singBox.editSubscription(first.copyWith(name: 'One')),
        isTrue,
      );
      expect(
        await singBox.editSubscription(
          const SingBoxSubscription(id: 'x', name: 'x', url: 'https://x'),
        ),
        isFalse,
      );
      expect((await singBox.getSubscription(first.id))!.name, 'One');

      await singBox.setActiveServerConfig('${first.id}/Server A');
      expect(await singBox.removeSubscription(first.id), isTrue);
      expect(await singBox.removeSubscription(first.id), isFalse);
      expect(await singBox.getActiveServerConfig(), isNull);
      expect(
        (await singBox.getServerConfigs()).map((s) => s.subscriptionId).toSet(),
        {second.id},
      );

      expect(
        await singBox.removeSubscription(second.id, removeServers: false),
        isTrue,
      );
      final kept = await singBox.getServerConfigs();
      expect(kept, hasLength(2));
      expect(kept.every((s) => s.subscriptionId == null), isTrue);
      expect(await singBox.getSubscriptions(), isEmpty);
    });
  });
}
