import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? error;
  try {
    await SingBox.instance.initialize(
      const SingBoxOptions(
        android: SingBoxAndroidOptions(
          notificationTitle: 'sing_box example',
          stopActionTitle: 'Disconnect',
        ),
        ios: SingBoxIosOptions(profileName: 'sing_box example'),
      ),
    );
  } on SingBoxException catch (e) {
    error = e;
  }
  runApp(
    error == null
        ? const ExampleApp()
        : MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Failed to initialize sing_box: $error'),
              ),
            ),
          ),
  );
}
