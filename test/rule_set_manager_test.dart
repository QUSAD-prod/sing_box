import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';
import 'package:sing_box/src/rule_set_manager.dart';

import 'support/fake_platform.dart';

/// A binary rule-set: the "SRS" magic, version 2 and some data.
final srs = [0x53, 0x52, 0x53, 0x02, 1, 2, 3];

/// A local rule-set server: `/<name>` answers with [files] or 404 and
/// counts the requests per path.
class _RuleSetServer {
  late HttpServer _server;
  final files = <String, List<int>>{};
  final requests = <String, int>{};

  String url(String name) => 'http://127.0.0.1:${_server.port}/$name';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final name = request.uri.path.substring(1);
      requests[name] = (requests[name] ?? 0) + 1;
      final body = files[name];
      request.response.statusCode = body == null ? 404 : 200;
      if (body != null) request.response.add(body);
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _RuleSetServer server;
  late Directory dir;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    server = _RuleSetServer();
    await server.start();
    dir = await Directory.systemTemp.createTemp('rule_sets');
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  RuleSetManager manager({Duration retryAfter = const Duration(minutes: 10)}) =>
      RuleSetManager(dir, retryAfter: retryAfter);

  group('RuleSetManager', () {
    test('downloads missing rule-sets and validates them', () async {
      server.files['a.srs'] = srs;
      server.files['src.json'] = utf8.encode(
        jsonEncode({
          'version': 3,
          'rules': [
            {
              'domain_suffix': ['example.com'],
            },
          ],
        }),
      );
      server.files['page.srs'] = utf8.encode('<html>blocked</html>');
      final rules = manager();
      final paths = await rules.prepare({
        'a': server.url('a.srs'),
        'src': server.url('src.json'),
        'page': server.url('page.srs'),
        'gone': server.url('gone.srs'),
      }, maxAge: const Duration(days: 1));
      expect(paths, {'a': '${dir.path}/a.srs', 'src': '${dir.path}/src.json'});
      expect(await File(paths['a']!).readAsBytes(), srs);

      final statuses = {for (final s in await rules.statuses()) s.tag: s};
      expect(statuses['a']!.size, srs.length);
      expect(statuses['a']!.lastError, isNull);
      expect(statuses['page']!.isAvailable, isFalse);
      expect(statuses['page']!.lastError, contains('not a binary'));
      expect(statuses['gone']!.lastError, contains('HTTP 404'));
      // No temporary files are left behind.
      expect(dir.listSync().map((e) => e.uri.pathSegments.last).toSet(), {
        'a.srs',
        'src.json',
        'index.json',
      });
    });

    test('failed downloads wait before the next attempt', () async {
      final rules = manager();
      final urls = {'gone': server.url('gone.srs')};
      await rules.prepare(urls, maxAge: const Duration(days: 1));
      await rules.prepare(urls, maxAge: const Duration(days: 1));
      expect(server.requests['gone.srs'], 1);
      // An explicit update retries at once and succeeds now.
      server.files['gone.srs'] = srs;
      final statuses = await rules.update(
        urls,
        maxAge: const Duration(days: 1),
      );
      expect(statuses.single.isAvailable, isTrue);
      expect(server.requests['gone.srs'], 2);

      final eager = manager(retryAfter: Duration.zero);
      final other = {'other': server.url('other.srs')};
      await eager.prepare(other, maxAge: const Duration(days: 1));
      await eager.prepare(other, maxAge: const Duration(days: 1));
      expect(server.requests['other.srs'], 2);
    });

    test('stale files are used and refreshed in the background', () async {
      server.files['a.srs'] = srs;
      final rules = manager();
      final urls = {'a': server.url('a.srs')};
      await rules.prepare(urls, maxAge: const Duration(days: 1));
      final refreshed = rules.changes.first;
      server.files['a.srs'] = [...srs, 4];
      final paths = await rules.prepare(urls, maxAge: Duration.zero);
      expect(paths, {'a': '${dir.path}/a.srs'});
      await refreshed;
      expect(server.requests['a.srs'], 2);
      expect(await File(paths['a']!).readAsBytes(), [...srs, 4]);
    });

    test('a failed refresh keeps the previous file', () async {
      server.files['a.srs'] = srs;
      final rules = manager();
      final urls = {'a': server.url('a.srs')};
      await rules.prepare(urls, maxAge: const Duration(days: 1));
      server.files.remove('a.srs');
      final statuses = await rules.update(
        urls,
        maxAge: const Duration(days: 1),
        force: true,
      );
      expect(statuses.single.isAvailable, isTrue);
      expect(statuses.single.lastError, contains('HTTP 404'));
      expect(await rules.prepare(urls, maxAge: const Duration(days: 1)), {
        'a': '${dir.path}/a.srs',
      });
    });

    test('a changed URL is downloaded again', () async {
      server.files['a.srs'] = srs;
      server.files['b.srs'] = [...srs, 9];
      final rules = manager();
      await rules.prepare({
        'a': server.url('a.srs'),
      }, maxAge: const Duration(days: 1));
      final paths = await rules.prepare({
        'a': server.url('b.srs'),
      }, maxAge: const Duration(days: 1));
      expect(await File(paths['a']!).readAsBytes(), [...srs, 9]);
    });

    test('the index survives a restart', () async {
      server.files['a.srs'] = srs;
      final urls = {'a': server.url('a.srs')};
      await manager().prepare(urls, maxAge: const Duration(days: 1));
      final restarted = manager();
      expect((await restarted.statuses()).single.tag, 'a');
      expect(await restarted.prepare(urls, maxAge: const Duration(days: 1)), {
        'a': '${dir.path}/a.srs',
      });
      expect(server.requests['a.srs'], 1);
    });
  });

  test('SingBoxRuleSetStatus round trips through maps', () {
    final status = SingBoxRuleSetStatus(
      tag: 'geoip-ru',
      url: 'https://example.com/geoip-ru.srs',
      path: '/data/geoip-ru.srs',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      size: 42,
      lastError: 'timed out',
      lastAttempt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    expect(SingBoxRuleSetStatus.tryFromMap(status.toMap()), status);
    expect(status.isAvailable, isTrue);
    expect(SingBoxRuleSetStatus.tryFromMap(const {'tag': 'x'}), isNull);
  });

  group('SingBox rule-sets', () {
    late FakeSingBoxPlatform platform;
    final singBox = SingBox.instance;

    SingBoxRoutingRules rulesWith(List<String> ruleSets) => SingBoxRoutingRules(
      bypassLan: false,
      customRules: [
        SingBoxRoutingRule(
          action: SingBoxRuleAction.direct,
          ruleSets: ruleSets,
        ),
      ],
    );

    Future<Map<String, dynamic>> build() async =>
        jsonDecode(
              await singBox.buildConfig('trojan://secret@198.51.100.4:443#A'),
            )
            as Map<String, dynamic>;

    setUp(() async {
      await singBox.debugReset();
      platform = FakeSingBoxPlatform()..workingDirectory = dir.path;
      SingBoxPlatform.instance = platform;
      await singBox.initialize();
    });

    tearDown(singBox.debugReset);

    test('configs read downloaded files and leave out missing ones', () async {
      server.files['a.srs'] = srs;
      await singBox.saveRoutingRules(
        rulesWith([server.url('a.srs'), server.url('gone.srs')]),
      );
      final config = await build();
      final route = config['route'] as Map;
      expect(route['rule_set'], [
        {
          'type': 'local',
          'tag': 'custom-a',
          'format': 'binary',
          'path': '${dir.path}/rule-sets/custom-a.srs',
        },
      ]);
      expect(
        (route['rules'] as List).where((r) => (r as Map)['rule_set'] != null),
        [
          {
            'rule_set': ['custom-a'],
            'action': 'route',
            'outbound': 'direct',
          },
        ],
      );
      expect(config.containsKey('http_clients'), isFalse);

      final statuses = await singBox.getRuleSets();
      expect(statuses.map((s) => s.tag).toSet(), {'custom-a', 'custom-gone'});
    });

    test('updateRuleSets reloads a tunnel that missed a rule-set', () async {
      await singBox.saveRoutingRules(rulesWith([server.url('late.srs')]));
      await singBox.connect('trojan://secret@198.51.100.4:443#A');
      expect(
        (jsonDecode(platform.started.last) as Map)['route'],
        isNot(contains('rule_set')),
      );
      server.files['late.srs'] = srs;
      final statuses = await singBox.updateRuleSets();
      expect(statuses.single.isAvailable, isTrue);
      final reloaded = jsonDecode(platform.reloaded.last!) as Map;
      expect(
        ((reloaded['route'] as Map)['rule_set'] as List).single['type'],
        'local',
      );
      // Nothing new: no further reload.
      await singBox.updateRuleSets();
      expect(platform.reloaded, hasLength(1));
    });

    test('manageRuleSets: false leaves the downloads to sing-box', () async {
      singBox.manageRuleSets = false;
      await singBox.saveRoutingRules(rulesWith([server.url('a.srs')]));
      final route = (await build())['route'] as Map;
      expect((route['rule_set'] as List).single['type'], 'remote');
      expect(await singBox.updateRuleSets(), isEmpty);
      expect(server.requests, isEmpty);
    });
  });
}
