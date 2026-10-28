// Entry point for the manual Android lifecycle checks in doc/android.md
// (app closed while connected, Quick Settings tile, start on boot,
// Always-on VPN). It needs no server: without HARNESS_LINK it connects
// through a `direct` outbound. Every state change is printed to logcat:
//
//   flutter run -t lib/e2e_harness.dart --dart-define=HARNESS_ACTION=connect
//   adb logcat -s flutter | grep SING_BOX_HARNESS
//
// Defines:
//   HARNESS_ACTION         `connect` (unless connected), `disconnect` or
//                          `watch` (default)
//   HARNESS_LINK           share link to connect with (default: direct)
//   HARNESS_START_ON_BOOT  `true`/`false`: sets SingBoxSettings.startOnBoot
//   HARNESS_TILE           `true`/`false`: sets SingBoxSettings.quickSettingsTile
import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

const action = String.fromEnvironment('HARNESS_ACTION', defaultValue: 'watch');
const link = String.fromEnvironment(
  'HARNESS_LINK',
  defaultValue: '{"type": "direct", "tag": "harness-direct"}',
);
const setStartOnBoot = bool.hasEnvironment('HARNESS_START_ON_BOOT');
const startOnBoot = bool.fromEnvironment('HARNESS_START_ON_BOOT');
const setQuickSettingsTile = bool.hasEnvironment('HARNESS_TILE');
const quickSettingsTile = bool.fromEnvironment('HARNESS_TILE');

void report(String message) => debugPrint('SING_BOX_HARNESS $message');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final singBox = SingBox.instance;
  final lines = ValueNotifier<List<String>>([]);
  void log(String message) {
    report(message);
    lines.value = [...lines.value, message];
  }

  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('sing_box harness')),
        body: ValueListenableBuilder(
          valueListenable: lines,
          builder: (context, value, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final line in value) Text(line)],
          ),
        ),
      ),
    ),
  );

  try {
    await singBox.initialize(
      const SingBoxOptions(
        android: SingBoxAndroidOptions(notificationTitle: 'sing_box harness'),
      ),
    );
    log('initialized status=${singBox.status.name}');
    singBox.watchConnectionState().listen(
      (state) =>
          log('state status=${state.status.name} error=${state.error ?? '-'}'),
    );
    if (setStartOnBoot || setQuickSettingsTile) {
      var settings = await singBox.getSettings();
      if (setStartOnBoot) {
        settings = settings.copyWith(startOnBoot: startOnBoot);
      }
      if (setQuickSettingsTile) {
        settings = settings.copyWith(quickSettingsTile: quickSettingsTile);
      }
      await singBox.saveSettings(settings);
      log(
        'settings startOnBoot=${settings.startOnBoot} '
        'tile=${settings.quickSettingsTile}',
      );
    }
    switch (action) {
      // Reopening the app while the VPN runs must find it connected.
      case 'connect' when singBox.status == SingBoxConnectionStatus.connected:
        log('already connected');
      case 'connect':
        await singBox.connect(link);
        log('connect done status=${singBox.status.name}');
      case 'disconnect':
        await singBox.disconnect();
        log('disconnect done');
    }
  } on SingBoxException catch (e) {
    log('error $e');
  }
}
