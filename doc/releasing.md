# Releasing sing_box

A release has up to two parts:

1. **The native core** - the GitHub release `libbox-v<LIBBOX_VERSION>` with
   `libbox.aar` and `Libbox.xcframework.zip`, and the same for the
   sing-box-lx core (`libbox-v<LIBBOX_LX_VERSION>`). Every plugin version downloads
   these files at build time and checks their SHA-256, so they must exist
   *before* the plugin is published. Needed once per sing-box version.
2. **The plugin** - version `x.y.z` from `pubspec.yaml`, published to
   [pub.dev](https://pub.dev/packages/sing_box), either automatically by pushing
   the tag `vx.y.z` or manually with `flutter pub publish`.

This file is not part of the pub package. A Russian version is in
[releasing.ru.md](releasing.ru.md).

## 0. One-time setup

- **pub.dev account**: the Google account that uploads `sing_box`
  (`dart pub login` for manual publishing). Optionally move the package to a
  [verified publisher](https://dart.dev/tools/pub/verified-publishers).
- **Automated publishing** (for tag-based releases): on
  `https://pub.dev/packages/sing_box/admin` enable *Publishing from GitHub
  Actions* with repository `QUSAD-prod/sing_box`, tag pattern `v{{version}}`
  and *Require GitHub Actions environment* = `pub.dev`. In GitHub, *Settings ->
  Environments -> New environment* `pub.dev`, add yourself as a *required
  reviewer*: every publish then waits for your approval.
- **GitHub CLI** for the libbox release: `gh auth login`.
- **Name of the package**: the sing-box license asks derivative works not to
  use its name without consent. Before the first public release of a version
  that uses the name, ask the sing-box author (contact-sagernet@sekai.icu) and
  keep the answer.

## 1. Prepare the version

Follow [semantic versioning](https://semver.org): breaking API changes bump the
major version, new features the minor version, fixes the patch version.

1. Bump the version in **all** of:
   - `pubspec.yaml` (`version:`),
   - `ios/sing_box.podspec` and `ios/SingBoxTunnel.podspec` (`s.version`),
   - `android/build.gradle.kts` (`version =`),
   - the install snippet in `README.md` (`sing_box: ^x.y.z`).
2. Add a `## x.y.z` section at the top of `CHANGELOG.md` (Added / Changed /
   Fixed). The publish workflow refuses a tag without it.
3. If the sing-box version changes: update `LIBBOX_VERSION`, rebuild libbox
   (step 3) and mention the new core in the changelog and the README badge.

```bash
git grep -n -E "version: |s.version|^version = |sing_box: \^" -- pubspec.yaml ios/*.podspec android/build.gradle.kts README.md
```

## 2. Test

Run everything on the release commit. CONTRIBUTING.md explains each suite.

```bash
# Static checks and unit tests (configs validated with the real sing-box CLI)
dart format --output=none --set-exit-if-changed lib test example/lib example/integration_test
flutter analyze && (cd example && flutter analyze)
SING_BOX_BIN=/path/to/sing-box flutter test        # 0 skipped
flutter pub publish --dry-run                       # 0 warnings

# pub.dev score (160/160 expected once the release commit is on main)
dart pub global activate pana
dart pub global run pana --no-warning .
```

Android (emulator or device):

```bash
cd example
flutter build apk --debug && flutter build apk --release && flutter build appbundle
# end-to-end tests: local servers + VPN consent loop, see CONTRIBUTING.md
flutter test integration_test/vpn_e2e_test.dart -d emulator-5554 --dart-define=E2E_HOST=10.0.2.2
flutter test integration_test/permission_e2e_test.dart -d emulator-5554
```

Then the lifecycle scenarios with `lib/e2e_harness.dart`
([doc/android.md](android.md#checking-the-lifecycle-on-a-device)): Back /
swipe from Recents while connected, Quick Settings tile, boot start, app update
while connected, Always-on VPN with *Block connections without VPN* (no Stop
action).

iOS:

```bash
cd example
flutter build ios --simulator --debug
flutter test integration_test/smoke_test.dart -d <simulator id>
flutter build ios --release --no-codesign
# CocoaPods mode: flutter config --no-enable-swift-package-manager, build, switch back
```

On a real iPhone (paid team): connect, disconnect, a start that fails (wrong
server) shows the core error, switching servers while connected, On Demand /
kill switch settings, a reboot with On Demand enabled.

## 3. Publish the libbox release

Only when `libbox-v<LIBBOX_VERSION>` does not exist yet. The release must
contain **exactly** the files whose SHA-256 is committed.

```bash
# Build (or keep the existing build/libbox/ files the checksums were taken from)
scripts/build_libbox.sh android apple

# Write their checksums into android/libbox.properties and ios/sing_box/Package.swift
scripts/release_libbox.sh
git add LIBBOX_VERSION android/libbox.properties ios/sing_box/Package.swift
git commit -m "libbox <version>"

# Create the GitHub release libbox-v<version> with these two files
scripts/release_libbox.sh --publish

# The sing-box-lx core (LIBBOX_LX_VERSION, lx.* keys, libboxLx* lets), when
# libbox-v<lx version> does not exist yet
scripts/build_libbox.sh android apple --core lx
scripts/release_libbox.sh --core lx
git add LIBBOX_LX_VERSION android/libbox.properties ios/sing_box/Package.swift
git commit -m "libbox <lx version>"
scripts/release_libbox.sh --core lx --publish

# Download them back and compare with the pinned checksums (both cores; the
# publish workflow runs it too and stops when the lx release is missing)
scripts/verify_libbox_release.sh
```

Never replace the assets of an existing libbox release with different files:
published plugin versions pin the old checksums and would stop building
(`release_libbox.sh` refuses without `--force`). Build a new sing-box version
instead. The `libbox` workflow only builds the files for inspection; it never
publishes.

### Without GitHub releases

The files can be hosted anywhere over HTTPS with the layout
`<base>/libbox-v<version>/libbox.aar` and
`<base>/libbox-v<version>/Libbox.xcframework.zip`. Point the plugin to it
before publishing - `baseUrl` in `android/libbox.properties` (keep the
`/libbox-v{version}` suffix) and `libboxBaseURL` in `ios/sing_box/Package.swift`
- and run `scripts/verify_libbox_release.sh`. App developers can also override
the location per build: Android with `SING_BOX_LIBBOX_AAR` /
`SING_BOX_LIBBOX_BASE_URL`, iOS CocoaPods with
`SING_BOX_LIBBOX_XCFRAMEWORK_ZIP` / `SING_BOX_LIBBOX_BASE_URL`, iOS SwiftPM
with a local `Libbox.xcframework` in the plugin (see the platform guides).

## 4. Push the code

```bash
git push origin 1.0.0                 # the release branch
```

Open a pull request into `main`, wait for CI (analysis, tests with the
sing-box CLI, Android and iOS builds), then merge. If `main` has no other
changes, a fast-forward also works: `git push origin 1.0.0:main`.

The release must be on `main` before publishing: pub.dev checks that the
`repository` URL contains the same `pubspec.yaml`.

The native builds need the libbox release: until it is published, the CI job
*libbox release* fails with "libbox.aar is not downloadable" and the Android
and iOS builds are skipped.

## 5. Publish to pub.dev

Choose **one** of the two ways for a version.

### A. Through a GitHub tag or release (recommended)

```bash
git checkout main && git pull
git tag -a v1.0.0 -m "sing_box 1.0.0"
git push origin v1.0.0
```

or create a GitHub release with the new tag `v1.0.0` on `main` (*Releases ->
Draft a new release*, paste the CHANGELOG section as notes). The
`Publish to pub.dev` workflow then:

1. checks that the tag equals `v` + the pubspec version and that CHANGELOG has
   the section,
2. verifies the libbox release assets,
3. runs format, analysis, all tests (with the sing-box CLI) and a dry run,
4. waits for your approval of the `pub.dev` environment and publishes with
   GitHub's OIDC token (no secrets stored).

### B. Manually from your machine

```bash
git checkout main && git pull
flutter pub publish --dry-run
flutter pub publish                   # shows the file list, asks for confirmation
```

The first time `flutter pub publish` opens a browser to sign in. With automated
publishing enabled, do not push a `v1.0.0` tag afterwards (the workflow would
try to publish the same version and fail); create a tag with a different
pattern if you want one, for example `release-1.0.0`.

Published versions are immutable. A broken version can be *retracted* on the
admin page within 7 days; the fix is always a new version.

## 6. After publishing

- Check https://pub.dev/packages/sing_box: README, CHANGELOG, Example tab,
  platforms, and the score (pana runs a few minutes after publishing).
- Smoke-test the published package in a fresh app - this exercises the libbox
  download from the release:
  ```bash
  flutter create --platforms android,ios vpn_check && cd vpn_check
  flutter pub add sing_box:^1.0.0
  flutter build apk --debug
  ```
- Create the GitHub release `v1.0.0` with the CHANGELOG notes if you published
  manually or only pushed a tag.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Workflow: *Tag … does not match pubspec version* | Delete the tag (`git push origin :refs/tags/v1.0.0`), fix the version, tag again |
| Workflow: *libbox.aar is not downloadable* | Publish the libbox release (step 3) |
| Workflow: pub.dev rejects the OIDC token | Automated publishing settings: repository, tag pattern `v{{version}}`, environment name |
| *Version already exists* | Versions are immutable: bump the version |
| Users report a libbox sha256 mismatch | Release assets were replaced; restore the original files or publish a plugin version pinned to a new libbox release |
| pana: *Failed to verify repository URL* | `main` does not contain the published `pubspec.yaml` yet |
