---
name: libbox-build-environment
description: "Toolchain, devices and network quirks on the user's Mac for building/testing the sing_box plugin"
metadata:
  node_type: memory
  type: reference
  originSessionId: 74d8003d-46eb-43d7-aed2-deade4eeec8f
  modified: 2026-10-28T07:42:58.472Z
---

- Flutter `~/dev/flutter` (not on PATH by default: `export PATH=$HOME/dev/flutter/bin:$HOME/.pub-cache/bin:$PATH`);
  pana is activated globally. Xcode 27.1, Go 1.26.
- `sum.golang.org` times out from this network; use `GOSUMDB=sum.golang.google.cn` (proxy.golang.org works). Use `GOTOOLCHAIN=local`.
- Default `java` is JDK 26 (breaks Gradle); use `JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home`.
- Android SDK `~/Library/Android/sdk` (NDK 28.2 + 30.0, adb at `platform-tools/adb`, not on PATH). AVD `Medium_Phone`
  (Android 17): `~/Library/Android/sdk/emulator/emulator -avd Medium_Phone -no-window -no-audio -no-boot-anim
  -no-snapshot-save -gpu swiftshader_indirect` (run in background).
- iOS simulator `iPhone 17 Pro` = `8A43E948-95F2-419A-9440-C359804654F6`. If Xcode reports a stale
  `SwiftExplicitPrecompiledModules/Libbox-*.pcm`, delete the whole `~/Library/Developer/Xcode/DerivedData/Runner-*` dir
  and `flutter clean` (deleting only the pcm folder breaks the build). A first `flutter test` on the simulator may hang
  on a white screen (VM service attach); rerun it.
- CocoaPods is Homebrew's. Global Flutter config has SPM enabled; CocoaPods test: temporarily add
  `config: enable-swift-package-manager: false` under `flutter:` in `example/pubspec.yaml`, build, then
  `git checkout example/pubspec.yaml example/ios/Podfile.lock example/ios/Runner.xcodeproj/project.pbxproj`.
- gomobile: `github.com/sagernet/gomobile@v0.1.13`; build via `scripts/build_libbox.sh` in the plugin repo. Built files
  (gitignored) in `build/libbox/`; local dev copies `android/libs/libbox.aar` + `ios/sing_box/Frameworks/Libbox.xcframework`
  are needed until the libbox GitHub release exists.
- sing-box CLI for `SING_BOX_BIN` (config tests, e2e server): clone v1.14.4 into the session scratchpad and build
  (command in `CONTRIBUTING.md`). The auto-mode classifier refused it until the user allowed it (2026-10-28).
- git-lfs was not installed (the user said on 2026-10-28 they would `brew install git-lfs`; check `git lfs version`).
  Without it the repo's LFS hooks fail: `pre-push` blocks pushes, `post-checkout` errors. Branch `1.0.0` no longer uses
  LFS (no `.gitattributes`). Use
  `git -c filter.lfs.process= -c filter.lfs.required=false` for merges touching `main`'s old LFS files.
- CocoaPods CLI fails with an encoding error unless `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` is set (fish shell).
- git-lfs 3.8.1 is installed now (2026-10-29), so the repo's LFS hooks no longer block pushes.
- `flutter create --offline` and `flutter pub add --offline ... --path <repo>` work for throwaway test apps in the
  scratchpad (Flutter 3.47 creates SPM-only iOS apps without a Podfile; it inserts the user's Xcode team id
  `DEVELOPMENT_TEAM` - never commit it into the public repo).
