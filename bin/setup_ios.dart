// Adds the Packet Tunnel Network Extension target that the sing_box plugin
// needs to a Flutter iOS project. Run it in the app's root directory:
//
//   dart run sing_box:setup_ios [--project ios/Runner.xcodeproj]
//       [--target PacketTunnel] [--bundle-id ID] [--app-group ID] [--team ID]
//
// Idempotent. With Swift Package Manager (Flutter 3.44+, or enabled) the
// extension links the plugin's `SingBoxTunnel` library through Flutter's
// generated Swift package: no CocoaPods, no Ruby. With CocoaPods it adds
// `pod 'SingBoxTunnel'` for the extension to the Podfile.
import 'dart:io';

import 'package:sing_box/src/tool/setup_ios.dart';

void main(List<String> arguments) {
  final values = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '-h' || argument == '--help') {
      stdout.writeln(_usage);
      return;
    }
    final option = argument.startsWith('--') ? argument.substring(2) : null;
    if (option == null ||
        !_options.contains(option) ||
        i + 1 >= arguments.length) {
      stderr.writeln('sing_box: unexpected argument $argument\n\n$_usage');
      exitCode = 64;
      return;
    }
    values[option] = arguments[++i];
  }
  final project =
      values['project'] ??
      [
        'ios/Runner.xcodeproj',
        'Runner.xcodeproj',
      ].firstWhere((path) => Directory(path).existsSync(), orElse: () => '');
  if (project.isEmpty || !Directory(project).existsSync()) {
    stderr.writeln('sing_box: Runner.xcodeproj not found, pass --project');
    exitCode = 66;
    return;
  }
  final options = SetupIosOptions(
    project: project,
    target: values['target'] ?? 'PacketTunnel',
    bundleId: values['bundle-id'],
    appGroup: values['app-group'],
    team: values['team'],
  );
  try {
    final linking = setupIos(options, (line) => stdout.writeln(line));
    stdout.writeln(switch (linking) {
      TunnelLinking.swiftPackageManager =>
        'The extension links SingBoxTunnel through Swift Package Manager.',
      TunnelLinking.cocoaPods =>
        'The extension links SingBoxTunnel through CocoaPods '
            '(`flutter build ios` runs `pod install`).',
      TunnelLinking.none =>
        'sing_box: the extension is not linked yet: run `flutter build ios` '
            'once (Flutter adds its Swift package to the project) and run '
            'this command again.',
    });
    stdout.writeln('''
Next steps:
  1. Enable the Network Extension and App Group capabilities for the app and
     the extension in your Apple Developer account.
  2. If you changed the defaults, initialize the plugin with the same ids:
     SingBoxIosOptions(appGroup: ..., tunnelBundleIdentifier: ...)''');
  } on Object catch (e) {
    stderr.writeln('sing_box: $e');
    exitCode = 1;
  }
}

const _options = {'project', 'target', 'bundle-id', 'app-group', 'team'};

const _usage = '''
Usage: dart run sing_box:setup_ios [options]

  --project PATH     Xcode project (default: ios/Runner.xcodeproj)
  --target NAME      extension target name (default: PacketTunnel)
  --bundle-id ID     extension bundle id (default: <app bundle id>.<target>)
  --app-group ID     App Group of app and extension (default: group.<app bundle id>)
  --team ID          DEVELOPMENT_TEAM (default: the Runner's team)''';
