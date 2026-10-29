/// Flutter plugin for [sing-box](https://sing-box.sagernet.org): a full
/// featured VPN client core for Android and iOS.
///
/// Start with [SingBox.instance]:
///
/// ```dart
/// import 'package:sing_box/sing_box.dart';
///
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await SingBox.instance.initialize();
///   runApp(const MyApp());
/// }
///
/// await SingBox.instance.connect('vless://...');
/// ```
///
/// Main building blocks:
///
/// * [SingBox] - tunnel control, statistics, logs, groups, tests, storage.
/// * [SingBoxConfigBuilder] / [SingBoxShareLink] - generate sing-box
///   configurations from share links, subscriptions and outbounds.
/// * [SingBoxRoutingRules] - bypass/block lists and DNS servers applied to
///   every configuration.
/// * [SingBoxServerConfig] / [SingBoxSettings] - persisted profiles and
///   behaviour.
/// * [SingBoxObserver] - diagnostics hooks (with a Talker adapter).
library;

export 'src/config/config.dart';
export 'src/exceptions.dart';
export 'src/models/clash_mode.dart';
export 'src/models/connection.dart';
export 'src/models/connection_stats.dart';
export 'src/models/connection_status.dart';
export 'src/models/core.dart';
export 'src/models/core_report.dart' hide loadCoreReports;
export 'src/models/log_entry.dart';
export 'src/models/network_quality.dart';
export 'src/models/outbound_group.dart';
export 'src/models/ping_result.dart';
export 'src/models/rule_set_status.dart';
export 'src/models/runtime_info.dart';
export 'src/models/server_config.dart';
export 'src/models/settings.dart';
export 'src/models/sing_box_notification.dart';
export 'src/models/speed_test_result.dart';
export 'src/models/stun_result.dart';
export 'src/models/subscription.dart';
export 'src/models/system_proxy_status.dart';
export 'src/observer/sing_box_observer.dart';
export 'src/observer/talker_observer.dart';
export 'src/options.dart';
export 'src/sing_box.dart';
export 'src/utils/validators.dart';
