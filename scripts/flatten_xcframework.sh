#!/usr/bin/env bash
# Converts the iOS slices of a gomobile `Libbox.xcframework` into shallow bundles.
#
# gomobile emits macOS style (versioned) frameworks for every platform:
#   Libbox.framework/Versions/A/{Libbox,Headers,Modules,Resources/Info.plist}
# iOS uses shallow bundles, and Xcode rejects the versioned layout when it
# processes the framework ("expected Info.plist at the root level since the
# platform uses shallow bundles"). This rewrites every iOS slice to
#   Libbox.framework/{Libbox,Headers,Modules,Info.plist}
# with a complete Info.plist, and fixes `BinaryPath` in the xcframework
# Info.plist. Running it on an already flattened xcframework is a no-op.
#
# Usage: scripts/flatten_xcframework.sh path/to/Libbox.xcframework [min iOS version]
set -euo pipefail

XCF="${1:?usage: $0 path/to/Libbox.xcframework [min iOS version]}"
MIN_IOS="${2:-15.0}"
PLIST_BUDDY=/usr/libexec/PlistBuddy

[[ -f "$XCF/Info.plist" ]] || { echo "not an xcframework: $XCF" >&2; exit 1; }

framework_plist() {
  local platform="$1"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Libbox</string>
	<key>CFBundleIdentifier</key>
	<string>io.nekohasekai.libbox</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Libbox</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$platform</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>MinimumOSVersion</key>
	<string>$MIN_IOS</string>
</dict>
</plist>
EOF
}

index=0
while identifier=$($PLIST_BUDDY -c "Print :AvailableLibraries:$index:LibraryIdentifier" "$XCF/Info.plist" 2>/dev/null); do
  case "$identifier" in
    ios-*)
      fw="$XCF/$identifier/Libbox.framework"
      if [[ -d "$fw/Versions" ]]; then
        src="$fw/Versions/A"
        flat="$fw.flat"
        rm -rf "$flat"
        mkdir -p "$flat"
        cp "$src/Libbox" "$flat/Libbox"
        cp -R "$src/Headers" "$flat/Headers"
        cp -R "$src/Modules" "$flat/Modules"
        rm -rf "$fw"
        mv "$flat" "$fw"
      fi
      platform=iPhoneOS
      [[ "$identifier" == *-simulator ]] && platform=iPhoneSimulator
      framework_plist "$platform" > "$fw/Info.plist"
      $PLIST_BUDDY -c "Set :AvailableLibraries:$index:BinaryPath Libbox.framework/Libbox" "$XCF/Info.plist" 2>/dev/null ||
        $PLIST_BUDDY -c "Add :AvailableLibraries:$index:BinaryPath string Libbox.framework/Libbox" "$XCF/Info.plist"
      echo "flattened $identifier"
      ;;
  esac
  index=$((index + 1))
done
