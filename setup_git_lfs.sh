#!/bin/bash

# Script to set up GitHub LFS for Libbox.xcframework
# Run this once to configure Git LFS for the framework

set -e

echo "Setting up GitHub LFS for Libbox.xcframework..."

# Check if git-lfs is installed
if ! command -v git-lfs &> /dev/null; then
    echo "Error: git-lfs is not installed."
    echo "Install it with:"
    echo "  macOS: brew install git-lfs"
    echo "  Linux: sudo apt-get install git-lfs"
    echo "  Windows: Download from https://git-lfs.github.com/"
    exit 1
fi

# Initialize git-lfs
git lfs install

# Track the framework file
git lfs track "ios/Frameworks/Libbox.xcframework/**"

# Add .gitattributes if it doesn't exist or update it
if [ ! -f .gitattributes ]; then
    echo "Creating .gitattributes..."
    echo "ios/Frameworks/Libbox.xcframework/** filter=lfs diff=lfs merge=lfs -text" > .gitattributes
else
    if ! grep -q "ios/Frameworks/Libbox.xcframework" .gitattributes; then
        echo "Adding LFS tracking to .gitattributes..."
        echo "ios/Frameworks/Libbox.xcframework/** filter=lfs diff=lfs merge=lfs -text" >> .gitattributes
    fi
fi

echo "✓ GitHub LFS configured for Libbox.xcframework"
echo ""
echo "Next steps:"
echo "  1. Commit .gitattributes: git add .gitattributes && git commit -m 'Add LFS tracking for framework'"
echo "  2. Add framework to LFS: git add ios/Frameworks/Libbox.xcframework"
echo "  3. Commit: git commit -m 'Add Libbox.xcframework via LFS'"
echo "  4. Push: git push origin main"

