#!/bin/bash

# Script to optimize Libbox.xcframework by:
# 1. Replacing duplicate files with symbolic links
# 2. Removing duplicate Headers, Modules, and Resources directories

set -e

XCFRAMEWORK_PATH="ios/Frameworks/Libbox.xcframework"
FRAMEWORK_PATH="$XCFRAMEWORK_PATH/ios-arm64/Libbox.framework"
VERSIONS_A="$FRAMEWORK_PATH/Versions/A"
VERSIONS_CURRENT="$FRAMEWORK_PATH/Versions/Current"
ROOT_BINARY="$FRAMEWORK_PATH/Libbox"
CURRENT_BINARY="$VERSIONS_CURRENT/Libbox"

echo "Optimizing Libbox.xcframework..."

cd "$(dirname "$0")"

# Check if framework exists
if [ ! -d "$FRAMEWORK_PATH" ]; then
    echo "Error: Framework not found at $FRAMEWORK_PATH"
    exit 1
fi

# Get original size
ORIGINAL_SIZE=$(du -sh "$XCFRAMEWORK_PATH" | cut -f1)
BINARY_PATH="$VERSIONS_A/Libbox"
echo "Original framework size: $ORIGINAL_SIZE"

# Try to strip debug symbols from binary (optional optimization)
if [ -f "$BINARY_PATH" ]; then
    BINARY_SIZE_BEFORE=$(du -h "$BINARY_PATH" | cut -f1)
    echo "Binary size before strip: $BINARY_SIZE_BEFORE"
    
    # Try to strip debug symbols (may fail for universal binaries)
    if strip -S "$BINARY_PATH" 2>/dev/null; then
        BINARY_SIZE_AFTER=$(du -h "$BINARY_PATH" | cut -f1)
        echo "Binary size after strip: $BINARY_SIZE_AFTER"
    else
        echo "Note: strip failed (may be a universal binary or already stripped)"
    fi
fi

# Step 1: Ensure Versions/Current is a symlink to A
# If Current exists as a directory, remove it and create symlink
if [ -d "$VERSIONS_CURRENT" ] && [ ! -L "$VERSIONS_CURRENT" ]; then
    echo "Removing Versions/Current directory (duplicates exist in Versions/A)..."
    rm -rf "$VERSIONS_CURRENT"
    ln -s A "$VERSIONS_CURRENT"
elif [ ! -L "$VERSIONS_CURRENT" ]; then
    echo "Creating Versions/Current symlink..."
    ln -s A "$VERSIONS_CURRENT"
fi

# Step 2: Replace duplicate binary files with symlinks
# Note: Versions/Current is already a symlink to A, so we only need to replace root level files
if [ -f "$ROOT_BINARY" ] && [ ! -L "$ROOT_BINARY" ]; then
    echo "Replacing root Libbox with symlink..."
    rm -f "$ROOT_BINARY"
    ln -s Versions/Current/Libbox "$ROOT_BINARY"
fi

# Step 3: Replace duplicate Headers, Modules, and Resources with symlinks at root level only
# Note: Versions/Current is a symlink, so Current/Headers etc. are already resolved to A/Headers
for dir in Headers Modules Resources; do
    ROOT_DIR="$FRAMEWORK_PATH/$dir"
    
    if [ -d "$ROOT_DIR" ] && [ ! -L "$ROOT_DIR" ]; then
        echo "Replacing root $dir with symlink..."
        rm -rf "$ROOT_DIR"
        ln -s Versions/Current/$dir "$ROOT_DIR"
    fi
done

# Get new size
NEW_SIZE=$(du -sh "$XCFRAMEWORK_PATH" | cut -f1)
echo "New framework size: $NEW_SIZE"

# Verify structure
echo "Verifying structure..."
if [ -L "$VERSIONS_CURRENT" ] && [ -L "$ROOT_BINARY" ]; then
    echo "✓ Symlinks are correct"
    
    # Count actual files (not symlinks) in framework
    ACTUAL_FILES=$(find "$FRAMEWORK_PATH" -type f ! -type l 2>/dev/null | wc -l | tr -d ' ')
    echo "Actual files (excluding symlinks): $ACTUAL_FILES"
    
    # Verify that Versions/A contains the actual binary
    if [ -f "$VERSIONS_A/Libbox" ]; then
        BINARY_SIZE=$(du -h "$VERSIONS_A/Libbox" | cut -f1)
        echo "✓ Binary found in Versions/A: $BINARY_SIZE"
    else
        echo "✗ ERROR: Binary not found in Versions/A!"
        echo "  Framework may need to be restored from backup or rebuilt."
    fi
else
    echo "✗ Warning: Some symlinks are missing"
fi

echo "Optimization complete!"

