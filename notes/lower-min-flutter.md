---
name: lower-min-flutter
description: "sing_box 1.1.0 lowers the minimum to Flutter 3.29 / Dart 3.7; DONE, CI-verified, pushed (commit 576f207 still titled WIP - fix by squash merge)"
metadata:
  node_type: memory
  type: project
  originSessionId: 7f1b09fa-8e64-4857-9853-99d9ed357c4c
  modified: 2026-10-28T16:19:27.861Z
---

DONE. Commit 576f207 (titled WIP, base of `release-1.1.0`) is pushed; CI runs 40731787920 and 40914059314 green
(Minimum Flutter 3.29.3 android / ios-spm / ios-cocoapods). Facts below stay valid; the "How to apply" steps are done.
Done: Dart null-aware elements rewritten (only Dart 3.8 feature used), 3.7 format, 248 unit tests + analyze pass on
3.47; Android build.gradle.kts applies `org.jetbrains.kotlin.android` only when no `kotlin` extension (no built-in
Kotlin), jvmTarget via `tasks.withType<KotlinJvmCompile>`, buildscript AGP 8.7.0 / KGP 1.8.22, compileSdk 35,
core-ktx 1.13.1, coroutines 1.7.3; iOS Package.swift adds FlutterFramework only if
`Context.packageDirectory/../FlutterFramework/Package.swift` exists; CHANGELOG/README/doc (released as part of 1.1.0).

Facts: SwiftPM is on by default on stable only since Flutter 3.44 (FlutterFramework package since 3.41/3.44);
Flutter 3.29 app template = AGP 8.7.0, Kotlin 1.8.22, Gradle 8.10.2, minSdk 21; 3.32 = AGP 8.7.3, Kotlin 2.1.0;
minSdk 24 default since 3.35.

**Why:** the user stopped all downloads on 2026-10-28 (slow network); verification waits until they are home.

**How to apply:** at home run: Flutter 3.47 example `flutter build apk --debug` and iOS simulator builds (SwiftPM +
CocoaPods); Flutter 3.29.3 SDK (~1.5 GB zip) → `flutter create` app + `flutter pub add sing_box --path`, minSdk 24,
build apk (Kotlin 1.8.22) and iOS (CocoaPods and SwiftPM); `SING_BOX_BIN` config tests; then add a CI job for the
minimum Flutter and drop "WIP" from the commit. If Kotlin 1.8 fails, fall back to Flutter 3.32 / Dart 3.8.
Ask before downloading anything big. This is task R0 of [[roadmap]]; see [[sing-box-plugin-rewrite]].
