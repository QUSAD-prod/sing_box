#!/usr/bin/env bash
#
# Builds the sing-box `libbox` native library for Android (AAR) and Apple
# platforms (XCFramework) from the official SagerNet/sing-box sources, or with
# `--core lx` from the sing-box-lx fork (github.com/Leadaxe/sing-box-lx).
#
# Usage:
#   scripts/build_libbox.sh [android] [apple] [--core standard|lx] [--install]
#
# With no platform arguments both platforms are built. `--install` copies the
# results into the plugin (`android/libs/libbox.aar` and
# `ios/sing_box/Frameworks/Libbox.xcframework`; for lx `android/libs/libbox-lx.aar`
# and `ios/sing_box/Frameworks/lx/Libbox.xcframework`), which is what the example
# app and local development use. Release archives and SHA-256 checksums are
# written to `build/libbox/` (lx: `build/libbox-lx/`).
#
# Environment variables:
#   SING_BOX_CORE      core to build: standard (default) or lx; `--core` wins
#   SING_BOX_VERSION   tag to build without the `v` (default: value of the
#                      LIBBOX_VERSION file, for lx LIBBOX_LX_VERSION)
#   LIBBOX_TAGS        comma separated Go build tags (default: see below)
#   ANDROID_API        minimum Android API level (default: 24)
#   ANDROID_TARGETS    gomobile Android targets (default: android = all ABIs)
#   APPLE_TARGETS      gomobile Apple targets (default: ios,iossimulator)
#   GOMOBILE_VERSION   SagerNet gomobile version (default: v0.1.13)
#   JAVA_HOME          JDK used by gomobile for Android (JDK 17 or 21)
#   ANDROID_HOME       Android SDK location (default: ~/Library/Android/sdk)
#   ANDROID_NDK_HOME   Android NDK location (default: newest NDK in the SDK)
#   WORK_DIR           where sources are checked out (default: build/libbox/src)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${SING_BOX_CORE:-standard}"

BUILD_ANDROID=0
BUILD_APPLE=0
INSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    android) BUILD_ANDROID=1 ;;
    apple|ios) BUILD_APPLE=1 ;;
    --install) INSTALL=1 ;;
    --core) shift; CORE="${1:-}" ;;
    --core=*) CORE="${1#--core=}" ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
if [[ $BUILD_ANDROID -eq 0 && $BUILD_APPLE -eq 0 ]]; then
  BUILD_ANDROID=1
  BUILD_APPLE=1
fi

# Protocol support compiled into libbox. Mirrors the official mobile clients
# minus the components that add a lot of binary size for niche use cases
# (tailscale, naive/cronet, usbip, openvpn, openconnect).
DEFAULT_TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0"
case "$CORE" in
  standard)
    VERSION_FILE="$ROOT_DIR/LIBBOX_VERSION"
    REPO_URL="https://github.com/SagerNet/sing-box.git"
    OUT_DIR="$ROOT_DIR/build/libbox"
    INSTALL_AAR="$ROOT_DIR/android/libs/libbox.aar"
    INSTALL_XCFRAMEWORK="$ROOT_DIR/ios/sing_box/Frameworks/Libbox.xcframework"
    ;;
  lx)
    VERSION_FILE="$ROOT_DIR/LIBBOX_LX_VERSION"
    REPO_URL="https://github.com/Leadaxe/sing-box-lx.git"
    OUT_DIR="$ROOT_DIR/build/libbox-lx"
    INSTALL_AAR="$ROOT_DIR/android/libs/libbox-lx.aar"
    INSTALL_XCFRAMEWORK="$ROOT_DIR/ios/sing_box/Frameworks/lx/Libbox.xcframework"
    # The lx extras on top of the standard set (each behind its own tag in the
    # fork; MASQUE, REALITY post-quantum key share, VLESS encryption and DNS
    # groups need none). Unlike the fork's own AAR this keeps with_clash_api:
    # the generated configurations use experimental.clash_api.
    DEFAULT_TAGS="$DEFAULT_TAGS,with_xhttp,with_awg,with_lx_command,with_lx_chain,with_lx_idle_suspend,with_trusttunnel"
    ;;
  *) echo "Unknown core: $CORE (standard or lx)" >&2; exit 2 ;;
esac

SING_BOX_VERSION="${SING_BOX_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
SING_BOX_VERSION="${SING_BOX_VERSION#v}"
GOMOBILE_VERSION="${GOMOBILE_VERSION:-v0.1.13}"
ANDROID_API="${ANDROID_API:-24}"
ANDROID_TARGETS="${ANDROID_TARGETS:-android}"
APPLE_TARGETS="${APPLE_TARGETS:-ios,iossimulator}"
WORK_DIR="${WORK_DIR:-$OUT_DIR/src}"
SRC_DIR="$WORK_DIR/sing-box-$SING_BOX_VERSION"
LIBBOX_TAGS="${LIBBOX_TAGS:-$DEFAULT_TAGS}"
APPLE_EXTRA_TAGS="with_dhcp,grpcnotrace"

LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$SING_BOX_VERSION -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -s -w -buildid= -checklinkname=0"

log() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

command -v go >/dev/null || die "Go is not installed (https://go.dev/dl/)"
command -v git >/dev/null || die "git is not installed"

export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
GOBIN_DIR="$(go env GOPATH)/bin"
export PATH="$GOBIN_DIR:$PATH"

if [[ ! -x "$GOBIN_DIR/gomobile" || ! -x "$GOBIN_DIR/gobind" ]]; then
  log "Installing SagerNet gomobile $GOMOBILE_VERSION"
  go install "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE_VERSION"
  go install "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE_VERSION"
fi

mkdir -p "$OUT_DIR" "$WORK_DIR"
if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "Fetching $CORE sing-box v$SING_BOX_VERSION"
  git clone --quiet --depth 1 --branch "v$SING_BOX_VERSION" "$REPO_URL" "$SRC_DIR"
  if [[ "$CORE" == lx ]]; then
    # go.mod replaces these modules with the fork's submodules; the others
    # (clients/*) are the official apps and not needed.
    git -C "$SRC_DIR" submodule update --init --quiet \
      submodules/wireguard-go submodules/sing-tun submodules/gvisor submodules/utls
  fi
fi
(cd "$SRC_DIR" && go mod download)

build_android() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  [[ -d "$sdk" ]] || die "Android SDK not found (set ANDROID_HOME)"
  local ndk="${ANDROID_NDK_HOME:-}"
  if [[ -z "$ndk" ]]; then
    ndk="$(ls -d "$sdk"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
  fi
  [[ -f "$ndk/source.properties" ]] || die "Android NDK not found (set ANDROID_NDK_HOME)"
  if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home -v 21 2>/dev/null || true)"
  fi
  [[ -n "${JAVA_HOME:-}" ]] && export JAVA_HOME && export PATH="$JAVA_HOME/bin:$PATH"
  export ANDROID_HOME="$sdk" ANDROID_NDK_HOME="$ndk"

  log "Building $CORE libbox $SING_BOX_VERSION for Android ($ANDROID_TARGETS, API $ANDROID_API, NDK $(basename "$ndk"))"
  (
    cd "$SRC_DIR"
    gomobile bind -v \
      -o "$OUT_DIR/libbox.aar" \
      -target "$ANDROID_TARGETS" \
      -androidapi "$ANDROID_API" \
      -javapkg=io.nekohasekai \
      -libname=box \
      -trimpath -buildvcs=false \
      -ldflags "$LDFLAGS" \
      -tags "$LIBBOX_TAGS" \
      ./experimental/libbox
  )
  rm -f "$OUT_DIR/libbox-sources.jar"
  (cd "$OUT_DIR" && shasum -a 256 libbox.aar > libbox.aar.sha256)
  log "Android: $OUT_DIR/libbox.aar ($(du -h "$OUT_DIR/libbox.aar" | cut -f1))"

  if [[ $INSTALL -eq 1 ]]; then
    mkdir -p "$(dirname "$INSTALL_AAR")"
    cp "$OUT_DIR/libbox.aar" "$INSTALL_AAR"
    log "Installed ${INSTALL_AAR#"$ROOT_DIR"/}"
  fi
}

build_apple() {
  [[ "$(uname)" == "Darwin" ]] || die "Apple builds require macOS with Xcode"
  log "Building $CORE libbox $SING_BOX_VERSION for Apple ($APPLE_TARGETS)"
  rm -rf "$OUT_DIR/Libbox.xcframework"
  (
    cd "$SRC_DIR"
    gomobile bind -v \
      -o "$OUT_DIR/Libbox.xcframework" \
      -target "$APPLE_TARGETS" \
      -libname=box \
      -tags-not-macos=with_low_memory \
      -iosversion=15.0 \
      -trimpath -buildvcs=false \
      -ldflags "$LDFLAGS" \
      -tags "$LIBBOX_TAGS,$APPLE_EXTRA_TAGS" \
      ./experimental/libbox
  )
  # gomobile emits versioned (macOS style) frameworks; iOS needs shallow bundles.
  "$ROOT_DIR/scripts/flatten_xcframework.sh" "$OUT_DIR/Libbox.xcframework" 15.0
  (
    cd "$OUT_DIR"
    rm -f Libbox.xcframework.zip
    ditto -c -k --sequesterRsrc --keepParent Libbox.xcframework Libbox.xcframework.zip
    shasum -a 256 Libbox.xcframework.zip > Libbox.xcframework.zip.sha256
  )
  log "Apple: $OUT_DIR/Libbox.xcframework.zip ($(du -h "$OUT_DIR/Libbox.xcframework.zip" | cut -f1))"

  if [[ $INSTALL -eq 1 ]]; then
    mkdir -p "$(dirname "$INSTALL_XCFRAMEWORK")"
    rm -rf "$INSTALL_XCFRAMEWORK"
    cp -R "$OUT_DIR/Libbox.xcframework" "$INSTALL_XCFRAMEWORK"
    echo "$SING_BOX_VERSION" > "$INSTALL_XCFRAMEWORK/.libbox_version"
    log "Installed ${INSTALL_XCFRAMEWORK#"$ROOT_DIR"/}"
  fi
}

[[ $BUILD_ANDROID -eq 1 ]] && build_android
[[ $BUILD_APPLE -eq 1 ]] && build_apple

log "Done. Artifacts in $OUT_DIR"
