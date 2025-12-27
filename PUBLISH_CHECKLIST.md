# Publishing Checklist

Before publishing to pub.dev, complete these steps:

## Pre-Publication Steps

### 1. Create GitHub Release with Framework

The iOS framework is distributed separately via GitHub Releases:

```bash
# 1. Create framework archive
cd ios/Frameworks
zip -r Libbox.xcframework.zip Libbox.xcframework
cd ../..

# 2. Create GitHub Release (see CREATE_RELEASE.md for details)
# Upload Libbox.xcframework.zip to the release
```

### 2. Verify Package Size

Check that the package (without framework) is within limits:

```bash
flutter pub publish --dry-run
```

Expected results:
- ✅ Compressed archive: ~25-30 MB (well within 100 MB limit)
- ✅ Uncompressed archive: ~25-30 MB (well within 100 MB limit)
- ✅ Package has 0 warnings

### 3. Update Documentation

- [ ] README.md includes iOS framework installation instructions
- [ ] INSTALL_IOS_FRAMEWORK.md is complete
- [ ] CREATE_RELEASE.md is available for maintainers

### 4. Test Installation

Test that users can install the framework:

```bash
# In a test Flutter project
curl -L https://raw.githubusercontent.com/qusadprod/sing_box/main/install_ios_framework.sh | bash
```

## Publication Steps

### 1. Publish to pub.dev

```bash
flutter pub publish
```

### 2. Verify Publication

- [ ] Package appears on pub.dev
- [ ] Version is correct
- [ ] Documentation is visible
- [ ] Installation instructions are clear

### 3. Update GitHub Release

- [ ] Link to pub.dev package in release notes
- [ ] Include installation instructions
- [ ] Verify framework download works

## Post-Publication

### 1. Test End-to-End

- [ ] Create a new Flutter project
- [ ] Add `sing_box: ^0.0.1` to pubspec.yaml
- [ ] Run `flutter pub get`
- [ ] Install iOS framework using the script
- [ ] Verify the project builds

### 2. Monitor Issues

- [ ] Watch for user issues on GitHub
- [ ] Monitor pub.dev package page for questions
- [ ] Be ready to provide support

## Package Contents (Published)

The published package includes:
- ✅ Android library (`libbox.aar` - 20 MB)
- ✅ iOS Swift/Kotlin source code
- ✅ Dart API implementation
- ❌ iOS framework (distributed via GitHub Releases)

## Package Size

After excluding the iOS framework:
- **Compressed**: ~25-30 MB
- **Uncompressed**: ~25-30 MB
- **Status**: ✅ Well within pub.dev limits

