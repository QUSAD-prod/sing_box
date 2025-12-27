#!/bin/bash

# Script to fix XCFramework duplicates by ensuring Versions/Current is a symlink
# and removing any duplicate files inside it

set -e

FRAMEWORK_PATH="ios/Frameworks/Libbox.xcframework/ios-arm64/Libbox.framework"
VERSIONS_A="$FRAMEWORK_PATH/Versions/A"
VERSIONS_CURRENT="$FRAMEWORK_PATH/Versions/Current"

echo "Fixing XCFramework duplicates..."

cd "$(dirname "$0")"

# Check if framework exists
if [ ! -d "$FRAMEWORK_PATH" ]; then
    echo "Error: Framework not found at $FRAMEWORK_PATH"
    exit 1
fi

# Step 1: Remove Versions/Current if it exists (as directory or symlink)
if [ -e "$VERSIONS_CURRENT" ]; then
    echo "Removing existing Versions/Current..."
    rm -rf "$VERSIONS_CURRENT"
fi

# Step 2: Create Versions/Current as symlink to A
echo "Creating Versions/Current symlink..."
ln -s A "$VERSIONS_CURRENT"

# Step 3: Verify
if [ -L "$VERSIONS_CURRENT" ]; then
    echo "✓ Versions/Current is now a symlink to A"
    
    # Count actual files (should only be in Versions/A)
    ACTUAL_FILES=$(find "$FRAMEWORK_PATH/Versions" -type f ! -type l 2>/dev/null | wc -l | tr -d ' ')
    echo "Actual files in Versions: $ACTUAL_FILES"
    
    # Verify symlink target
    LINK_TARGET=$(readlink "$VERSIONS_CURRENT")
    if [ "$LINK_TARGET" = "A" ]; then
        echo "✓ Symlink target is correct: $LINK_TARGET"
    else
        echo "✗ Warning: Symlink target is $LINK_TARGET (expected A)"
    fi
else
    echo "✗ ERROR: Failed to create symlink!"
    exit 1
fi

echo "Fix complete!"

