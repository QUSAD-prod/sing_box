# Third-party notices

`sing_box` is a Flutter wrapper around native code from the following projects.

## sing-box (libbox)

- Source: https://github.com/SagerNet/sing-box (version pinned in `LIBBOX_VERSION`)
- License: GNU General Public License v3.0 or later, with an additional
  attribution/naming clause — see https://github.com/SagerNet/sing-box/blob/main/LICENSE
- Usage: the `libbox` library (`experimental/libbox`) compiled with `gomobile` into
  `libbox.aar` (Android) and `Libbox.xcframework` (iOS). The binaries are not part of
  the Dart package; they are downloaded at build time from this repository's GitHub
  releases or built locally with `scripts/build_libbox.sh`.

Applications that ship libbox are distributing GPL-3.0 licensed code and must comply with
its terms (for example, making the corresponding source code available).

## sing-box-for-android / sing-box-for-apple

Parts of the native Android (Kotlin) and iOS (Swift) code are adapted from the official
sing-box clients (https://github.com/SagerNet/sing-box-for-android,
https://github.com/SagerNet/sing-box-for-apple), licensed under GPL-3.0.
