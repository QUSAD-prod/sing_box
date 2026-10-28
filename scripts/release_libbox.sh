#!/usr/bin/env bash
#
# Prepares (and optionally publishes) the libbox release assets that the
# plugin downloads at build time.
#
# Usage:
#   scripts/release_libbox.sh                    # update version/checksums in the repo
#   scripts/release_libbox.sh --publish          # ... and create the GitHub release
#   scripts/release_libbox.sh --publish --force  # ... replacing different assets
#
# Expects build/libbox/libbox.aar and build/libbox/Libbox.xcframework.zip
# (produced by scripts/build_libbox.sh). Updates:
#   - LIBBOX_VERSION
#   - android/libbox.properties   (version, sha256)
#   - ios/sing_box/Package.swift  (libboxVersion, libboxChecksum)
# The CocoaPods specs read the values from Package.swift.
#
# Publishing requires the GitHub CLI (`gh auth login`) with write access to
# the repository; the release tag is `libbox-v<version>`. Publish the very
# files whose checksums are committed: every released plugin version pins
# them, so an existing release is never overwritten with different files
# unless `--force` is given (which breaks the plugin versions pinning the old
# checksums - bump the libbox version instead).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build/libbox"
REPO="${REPO:-QUSAD-prod/sing_box}"
VERSION="${SING_BOX_VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/LIBBOX_VERSION")}"
VERSION="${VERSION#v}"
TAG="libbox-v$VERSION"
PUBLISH=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

die() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }
log() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }

AAR="$OUT_DIR/libbox.aar"
ZIP="$OUT_DIR/Libbox.xcframework.zip"
[[ -f "$AAR" ]] || die "$AAR not found, run scripts/build_libbox.sh first"
[[ -f "$ZIP" ]] || die "$ZIP not found, run scripts/build_libbox.sh first"

AAR_SHA="$(shasum -a 256 "$AAR" | cut -d' ' -f1)"
ZIP_SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
log "libbox $VERSION"
log "  libbox.aar              $AAR_SHA"
log "  Libbox.xcframework.zip  $ZIP_SHA"

echo "$VERSION" > "$ROOT_DIR/LIBBOX_VERSION"

PROPS="$ROOT_DIR/android/libbox.properties"
sed -i.bak -E "s/^version=.*/version=$VERSION/; s/^sha256=.*/sha256=$AAR_SHA/" "$PROPS"
rm -f "$PROPS.bak"

PACKAGE="$ROOT_DIR/ios/sing_box/Package.swift"
sed -i.bak -E \
  -e "s/(let libboxVersion = \")[^\"]*\"/\1$VERSION\"/" \
  -e "s/(let libboxChecksum = \")[^\"]*\"/\1$ZIP_SHA\"/" \
  "$PACKAGE"
rm -f "$PACKAGE.bak"
grep -q "let libboxVersion = \"$VERSION\"" "$PACKAGE" || die "could not update libboxVersion in $PACKAGE"
grep -q "let libboxChecksum = \"$ZIP_SHA\"" "$PACKAGE" || die "could not update libboxChecksum in $PACKAGE"
log "Updated LIBBOX_VERSION, android/libbox.properties and ios/sing_box/Package.swift"

if [[ $PUBLISH -eq 0 ]]; then
  log "Dry run done. Re-run with --publish to upload the assets to $REPO@$TAG."
  exit 0
fi

command -v gh >/dev/null || die "GitHub CLI (gh) is not installed"
NOTES="sing-box $VERSION native libraries for the sing_box Flutter plugin.

| File | SHA-256 |
| --- | --- |
| libbox.aar | \`$AAR_SHA\` |
| Libbox.xcframework.zip | \`$ZIP_SHA\` |

Built with scripts/build_libbox.sh from https://github.com/SagerNet/sing-box/tree/v$VERSION (GPL-3.0-or-later)."

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  PUBLISHED="$(mktemp -d)"
  trap 'rm -rf "$PUBLISHED"' EXIT
  gh release download "$TAG" --repo "$REPO" --dir "$PUBLISHED" \
    --pattern libbox.aar --pattern Libbox.xcframework.zip 2>/dev/null || true
  UPLOAD=()
  for asset in "$AAR" "$ZIP"; do
    name="$(basename "$asset")"
    new_sha="$(shasum -a 256 "$asset" | cut -d' ' -f1)"
    old_sha=missing
    [[ -f "$PUBLISHED/$name" ]] && old_sha="$(shasum -a 256 "$PUBLISHED/$name" | cut -d' ' -f1)"
    [[ "$old_sha" == "$new_sha" ]] && continue
    if [[ "$old_sha" != missing && $FORCE -eq 0 ]]; then
      die "release $TAG already has a different $name ($old_sha).
Published plugin versions pin that checksum; replacing the file breaks them.
Publish the matching file, bump the libbox version, or pass --force."
    fi
    UPLOAD+=("$asset")
  done
  if [[ ${#UPLOAD[@]} -eq 0 ]]; then
    log "Release $TAG already has these exact files, nothing to upload"
    exit 0
  fi
  log "Release $TAG exists, uploading: ${UPLOAD[*]##*/}"
  gh release upload "$TAG" "${UPLOAD[@]}" --repo "$REPO" --clobber
else
  log "Creating release $TAG"
  gh release create "$TAG" "$AAR" "$ZIP" --repo "$REPO" \
    --title "libbox $VERSION" --notes "$NOTES"
fi
log "Published https://github.com/$REPO/releases/tag/$TAG"
