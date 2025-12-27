#!/bin/bash

# Script to download and install Libbox.xcframework from GitHub Releases
# Usage: ./install_ios_framework.sh [version]
# If version is not specified, downloads the latest release

set -e

REPO="qusadprod/sing_box"
FRAMEWORK_NAME="Libbox.xcframework"
TARGET_DIR="ios/Frameworks"
ZIP_NAME="${FRAMEWORK_NAME}.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Installing Libbox.xcframework for sing_box plugin...${NC}"

# Check if we're in a Flutter project
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}Error: pubspec.yaml not found. Please run this script from your Flutter project root.${NC}"
    exit 1
fi

# Check if iOS directory exists
if [ ! -d "ios" ]; then
    echo -e "${RED}Error: ios/ directory not found. This script is for iOS projects only.${NC}"
    exit 1
fi

# Get version/branch (default: main)
BRANCH="${1:-main}"
echo -e "${GREEN}Installing framework from branch: ${BRANCH}${NC}"

# Create target directory
mkdir -p "$TARGET_DIR"

echo "Downloading ${FRAMEWORK_NAME} from repository..."
echo "Note: Framework is ~85 MB, this may take a while..."

# Use git sparse-checkout to download only the framework
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Initialize git repo
git init -q
git remote add origin "https://github.com/${REPO}.git"

# Configure sparse checkout to get only the framework
git config core.sparseCheckout true
mkdir -p .git/info
echo "ios/Frameworks/${FRAMEWORK_NAME}/*" > .git/info/sparse-checkout

# Install git-lfs if available (required for LFS files)
if command -v git-lfs &> /dev/null; then
    git lfs install --skip-smudge
fi

# Fetch and checkout only the framework directory
echo "Fetching framework (this may take a few minutes)..."
if ! git pull origin "$BRANCH" --depth=1 -q 2>/dev/null; then
    echo -e "${RED}Error: Failed to download framework from repository.${NC}"
    echo ""
    echo "The framework is stored using GitHub LFS. Please ensure:"
    echo "  1. Git LFS is installed: brew install git-lfs (macOS) or visit https://git-lfs.github.com/"
    echo "  2. The framework exists in the repository"
    echo "  3. You have internet connection"
    echo ""
    echo "Alternative: Clone the repository and copy manually:"
    echo "  git clone --depth=1 https://github.com/${REPO}.git temp_repo"
    echo "  cp -R temp_repo/ios/Frameworks/${FRAMEWORK_NAME} ios/Frameworks/"
    echo "  rm -rf temp_repo"
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check if framework was downloaded
if [ ! -d "ios/Frameworks/${FRAMEWORK_NAME}" ]; then
    echo -e "${RED}Error: Framework not found in repository.${NC}"
    echo "Please ensure the framework is committed to the repository."
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Remove old framework if exists
if [ -d "$OLDPWD/$TARGET_DIR/$FRAMEWORK_NAME" ]; then
    echo -e "${YELLOW}Removing old framework...${NC}"
    rm -rf "$OLDPWD/$TARGET_DIR/$FRAMEWORK_NAME"
fi

# Copy framework to target directory
echo "Installing framework to $TARGET_DIR..."
cp -R "ios/Frameworks/${FRAMEWORK_NAME}" "$OLDPWD/$TARGET_DIR/"

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"

echo -e "${GREEN}✓ Framework installed successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Run 'flutter pub get'"
echo "  2. Run 'cd ios && pod install'"
echo "  3. Build your project"

