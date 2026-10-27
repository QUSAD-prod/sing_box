# Android agent notes (android/**, example/android/**)

Status: WRITING CODE (2026-10-27). Research done (libbox 1.14.4 API via javap, SFA bg/ sources, daemon/started_service.go).

## Environment
- JDK 21: `export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home`
- Flutter 3.47.6 at ~/dev/flutter; SDK ~/Library/Android/sdk; adb ~/Library/Android/sdk/platform-tools/adb
- sing-box CLI built: $SCRATCH/bin/sing-box (SCRATCH=/private/tmp/claude-501/-Users-qusadprod-projects-sing-box--claude-worktrees-singbox-flutter-plugin-review-22aa2f/74d8003d-46eb-43d7-aed2-deade4eeec8f/scratchpad)
- AAR extracted for javap: $SCRATCH/aar (classes.jar)

## Key API facts (libbox 1.14.4)
- No Libbox.setMemoryLimit anymore -> SetupOptions.oomKiller*; Android default (SFA) = oom killer off, no limit. `disableMemoryLimit` is accepted and ignored (deviation).
- PlatformInterface has 26 methods (shell/bridge/neighbor/tailscale hooks); no systemCertificates / packageNameByUid anymore.
- CommandClient.connect(): handler-bound client retries ~3.25s (10 attempts) then throws. Standalone clients close their connection after every call -> use a new standalone client per op.
- urlTestTime from libbox is unix SECONDS -> *1000 for contract. Connection createdAt/closedAt are ms.
- Logs on Android contain ANSI colours (DisableColors false on android) -> strip.
- ServiceStop/ServiceReload handler callbacks run inside gRPC handlers: must not block on grpc server close.
- androidx.core 1.19 needs compileSdk 37 -> use core-ktx 1.18.0. kotlinx-coroutines-android 1.11.0.

## Decisions
- libbox resolution at configuration time into <gradleUserHome>/caches/sing_box/libbox/<version>/ (download + sha256),
  extracted classes.jar -> implementation(files()), jni/ -> jniLibs srcDir (no task wiring needed).
- Service runs in main process; status in in-process singleton ServiceState (readable without Activity/engine).
- Quick Settings tile (lead request): TileService disabled in manifest, enabled via setServiceOptions({quickSettingsTile}).
- MY_PACKAGE_REPLACED restart only if startOnBoot && VPN was running (wasRunning flag); BOOT_COMPLETED if startOnBoot.

## Next steps
1. android/build.gradle.kts, settings.gradle.kts, libbox.properties, manifest, proguard.
2. Kotlin sources under android/src/main/kotlin/com/qusadprod/sing_box/.
3. example/android config, harness example/lib/_android_harness.dart, e2e on emulator.
