// Run with the VPN consent revoked:
//   adb shell appops set com.qusadprod.sing_box_example ACTIVATE_VPN ignore
//   flutter test integration_test/permission_e2e_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sing_box/sing_box.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connect without the VPN permission fails cleanly', (
    tester,
  ) async {
    final singBox = SingBox.instance;
    await singBox.initialize();
    expect(await singBox.hasVpnPermission(), isFalse);
    await expectLater(
      singBox.connect(
        'ss://YWVzLTEyOC1nY206cHc@10.0.2.2:8388#x',
        requestPermission: false,
      ),
      throwsA(isA<SingBoxPermissionException>()),
    );
    expect(singBox.status, SingBoxConnectionStatus.disconnected);
  });
}
