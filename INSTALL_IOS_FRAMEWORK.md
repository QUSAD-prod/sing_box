# Installing Libbox.xcframework for iOS

Due to package size limitations on pub.dev, the iOS framework (`Libbox.xcframework`) is distributed separately via GitHub Releases.

## Quick Installation

Run this command from your Flutter project root:

```bash
curl -L https://raw.githubusercontent.com/qusadprod/sing_box/main/install_ios_framework.sh | bash
```

This will automatically:
1. Download the latest `Libbox.xcframework.zip` from GitHub Releases
2. Extract it to `ios/Frameworks/`
3. Clean up temporary files

## Manual Installation

1. **Download the framework**:
   - Go to [GitHub Releases](https://github.com/qusadprod/sing_box/releases/latest)
   - Download `Libbox.xcframework.zip`

2. **Extract and install**:
   ```bash
   # Create Frameworks directory if it doesn't exist
   mkdir -p ios/Frameworks
   
   # Extract the archive
   unzip Libbox.xcframework.zip
   
   # Copy to your project
   cp -R Libbox.xcframework ios/Frameworks/
   
   # Clean up
   rm Libbox.xcframework.zip
   ```

3. **Install CocoaPods dependencies**:
   ```bash
   cd ios
   pod install
   cd ..
   ```

## Installing a Specific Version

To install a specific version instead of the latest:

```bash
./install_ios_framework.sh v0.0.1
```

## Verifying Installation

After installation, verify the framework is in place:

```bash
ls -la ios/Frameworks/Libbox.xcframework
```

You should see the framework directory with its contents.

## Troubleshooting

### Framework not found

If you get errors about the framework not being found:

1. Verify the framework is in the correct location:
   ```bash
   ls -la ios/Frameworks/Libbox.xcframework
   ```

2. Make sure the path in `ios/sing_box.podspec` is correct (it should point to `Frameworks/Libbox.xcframework`)

3. Run `pod install` again:
   ```bash
   cd ios
   pod install
   cd ..
   ```

### Download fails

If the download fails:

1. Check your internet connection
2. Verify the release exists on GitHub
3. Try downloading manually from the [releases page](https://github.com/qusadprod/sing_box/releases)

### Build errors

If you encounter build errors:

1. Clean the build:
   ```bash
   flutter clean
   flutter pub get
   cd ios
   pod install
   cd ..
   ```

2. Open Xcode and check the framework is linked:
   - Open `ios/Runner.xcworkspace` in Xcode
   - Check that `Libbox.xcframework` appears in the project navigator

