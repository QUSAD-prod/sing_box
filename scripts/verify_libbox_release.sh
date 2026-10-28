#!/usr/bin/env bash
#
# Checks that the libbox files the plugin downloads at build time are
# published and match the pinned SHA-256 checksums:
#   - libbox.aar              <- android/libbox.properties (baseUrl, fileName, sha256)
#   - Libbox.xcframework.zip  <- ios/sing_box/Package.swift (libboxBaseURL, libboxVersion, libboxChecksum)
#
# Run it before publishing a plugin version: pub.dev users cannot build the
# plugin when these downloads fail.
#
# Usage:
#   scripts/verify_libbox_release.sh
#
# Environment variables:
#   SING_BOX_LIBBOX_BASE_URL  check a mirror instead of the pinned base URLs
#                             (same layout: <base>/libbox-v<version>/<file>)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROPS="$ROOT_DIR/android/libbox.properties"
PACKAGE="$ROOT_DIR/ios/sing_box/Package.swift"

die() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }

prop() { sed -n -E "s/^$1=(.*)$/\1/p" "$PROPS" | tr -d '[:space:]'; }
swift_let() { sed -n -E "s/^let $1 = \"([^\"]*)\".*/\1/p" "$PACKAGE"; }

AAR_VERSION="$(prop version)"
AAR_SHA="$(prop sha256)"
AAR_FILE="$(prop fileName)"
AAR_BASE="$(prop baseUrl)"
IOS_VERSION="$(swift_let libboxVersion)"
IOS_SHA="$(swift_let libboxChecksum)"
IOS_BASE="$(swift_let libboxBaseURL)"
LIBBOX_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/LIBBOX_VERSION")"

[[ -n "$AAR_VERSION" && -n "$AAR_SHA" && -n "$AAR_BASE" ]] || die "cannot read $PROPS"
[[ -n "$IOS_VERSION" && -n "$IOS_SHA" && -n "$IOS_BASE" ]] || die "cannot read $PACKAGE"
[[ "$AAR_VERSION" == "$LIBBOX_VERSION" && "$IOS_VERSION" == "$LIBBOX_VERSION" ]] ||
  die "version mismatch: LIBBOX_VERSION=$LIBBOX_VERSION, libbox.properties=$AAR_VERSION, Package.swift=$IOS_VERSION"

if [[ -n "${SING_BOX_LIBBOX_BASE_URL:-}" ]]; then
  base="${SING_BOX_LIBBOX_BASE_URL%/}"
  AAR_URL="$base/libbox-v$AAR_VERSION/${AAR_FILE:-libbox.aar}"
  IOS_URL="$base/libbox-v$IOS_VERSION/Libbox.xcframework.zip"
else
  AAR_URL="${AAR_BASE//\{version\}/$AAR_VERSION}/${AAR_FILE:-libbox.aar}"
  IOS_URL="${IOS_BASE%/}/libbox-v$IOS_VERSION/Libbox.xcframework.zip"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

check() {
  local name="$1" url="$2" expected="$3"
  log "$name: $url"
  curl -fsSL --retry 3 --connect-timeout 30 -o "$TMP/$name" "$url" ||
    die "$name is not downloadable from $url
Publish the libbox release first: scripts/release_libbox.sh --publish (doc/releasing.md, step 3)."
  local actual
  actual="$(sha256 "$TMP/$name")"
  [[ "$actual" == "$expected" ]] || die "$name sha256 mismatch
  expected: $expected
  actual:   $actual"
  log "$name OK ($(du -h "$TMP/$name" | cut -f1), sha256 $actual)"
}

check libbox.aar "$AAR_URL" "$AAR_SHA"
check Libbox.xcframework.zip "$IOS_URL" "$IOS_SHA"
log "libbox $LIBBOX_VERSION release assets match the pinned checksums"
