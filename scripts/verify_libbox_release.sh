#!/usr/bin/env bash
#
# Checks that the libbox files the plugin downloads at build time are
# published and match the pinned SHA-256 checksums:
#   - libbox.aar              <- android/libbox.properties (baseUrl, fileName, sha256)
#   - Libbox.xcframework.zip  <- ios/sing_box/Package.swift (libboxBaseURL, libboxVersion, libboxChecksum)
# and the same pair of the sing-box-lx core (`lx.*` keys, `libboxLx*` lets,
# LIBBOX_LX_VERSION).
#
# Run it before publishing a plugin version: pub.dev users cannot build the
# plugin when these downloads fail.
#
# Usage:
#   scripts/verify_libbox_release.sh            # both cores
#   scripts/verify_libbox_release.sh standard   # one core (standard or lx)
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
Publish the libbox release first: scripts/release_libbox.sh [--core lx] --publish (doc/releasing.md, step 3)."
  local actual
  actual="$(sha256 "$TMP/$name")"
  [[ "$actual" == "$expected" ]] || die "$name sha256 mismatch
  expected: $expected
  actual:   $actual"
  log "$name OK ($(du -h "$TMP/$name" | cut -f1), sha256 $actual)"
}

# verify_core <name> <properties key prefix> <Swift let suffix> <version file>
verify_core() {
  local core="$1" prefix="$2" suffix="$3" version_file="$4"
  local aar_version aar_sha aar_file aar_base ios_version ios_sha ios_base version aar_url ios_url
  aar_version="$(prop "${prefix}version")"
  aar_sha="$(prop "${prefix}sha256")"
  aar_file="$(prop "${prefix}fileName")"
  aar_base="$(prop "${prefix}baseUrl")"
  ios_version="$(swift_let "libbox${suffix}Version")"
  ios_sha="$(swift_let "libbox${suffix}Checksum")"
  ios_base="$(swift_let libboxBaseURL)"
  version="$(tr -d '[:space:]' < "$ROOT_DIR/$version_file")"

  [[ -n "$aar_version" && -n "$aar_sha" && -n "$aar_base" ]] || die "$core: cannot read $PROPS"
  [[ -n "$ios_version" && -n "$ios_sha" && -n "$ios_base" ]] || die "$core: cannot read $PACKAGE"
  [[ "$aar_version" == "$version" && "$ios_version" == "$version" ]] ||
    die "$core: version mismatch: $version_file=$version, libbox.properties=$aar_version, Package.swift=$ios_version"

  if [[ -n "${SING_BOX_LIBBOX_BASE_URL:-}" ]]; then
    local base="${SING_BOX_LIBBOX_BASE_URL%/}"
    aar_url="$base/libbox-v$aar_version/${aar_file:-libbox.aar}"
    ios_url="$base/libbox-v$ios_version/Libbox.xcframework.zip"
  else
    aar_url="${aar_base//\{version\}/$aar_version}/${aar_file:-libbox.aar}"
    ios_url="${ios_base%/}/libbox-v$ios_version/Libbox.xcframework.zip"
  fi

  check "$core-libbox.aar" "$aar_url" "$aar_sha"
  check "$core-Libbox.xcframework.zip" "$ios_url" "$ios_sha"
  log "$core libbox $version release assets match the pinned checksums"
}

CORES=("${@:-standard lx}")
for core in ${CORES[*]}; do
  case "$core" in
    standard) verify_core standard "" "" LIBBOX_VERSION ;;
    lx) verify_core lx "lx\\." "Lx" LIBBOX_LX_VERSION ;;
    *) die "unknown core: $core (standard or lx)" ;;
  esac
done
