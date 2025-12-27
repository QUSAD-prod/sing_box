#!/bin/bash

# Script to optimize libbox.aar by removing x86, x86_64, and armeabi-v7a architectures
# This reduces the size significantly:
# - x86/x86_64 are only needed for emulators
# - armeabi-v7a is for old 32-bit Android devices (rarely used now)
# Only arm64-v8a is kept (modern 64-bit Android devices)

set -e

AAR_FILE="android/libs/libbox.aar"
OPTIMIZED_AAR="android/libs/libbox_optimized.aar"
TEMP_DIR=$(mktemp -d)

echo "Extracting AAR..."
cd "$(dirname "$0")"
unzip -q "$AAR_FILE" -d "$TEMP_DIR"

echo "Removing x86, x86_64, and armeabi-v7a architectures..."
echo "Keeping only arm64-v8a (modern 64-bit Android devices)"
rm -rf "$TEMP_DIR/jni/x86" "$TEMP_DIR/jni/x86_64" "$TEMP_DIR/jni/armeabi-v7a"

echo "Creating optimized AAR..."
cd "$TEMP_DIR"
zip -9 -r "$(pwd)/libbox_optimized.aar" . > /dev/null

ORIGINAL_SIZE=$(du -h "$AAR_FILE" | cut -f1)
OPTIMIZED_SIZE=$(du -h "$TEMP_DIR/libbox_optimized.aar" | cut -f1)

echo "Original size: $ORIGINAL_SIZE"
echo "Optimized size: $OPTIMIZED_SIZE"

# Backup original and replace with optimized
if [ -f "$OPTIMIZED_AAR" ]; then
    rm "$OPTIMIZED_AAR"
fi
mv "$TEMP_DIR/libbox_optimized.aar" "$OPTIMIZED_AAR"

# Cleanup
rm -rf "$TEMP_DIR"

echo "Done! Optimized AAR saved to: $OPTIMIZED_AAR"
echo "To use it, rename libbox_optimized.aar to libbox.aar"

