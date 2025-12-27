# Creating GitHub Release with Libbox.xcframework

This guide explains how to distribute the `Libbox.xcframework` (72 MB) which exceeds GitHub's 25 MB file size limit.

## Solution: GitHub LFS + Release Assets

Since GitHub limits individual files to 25 MB, we'll use **GitHub LFS (Large File Storage)** to store the framework in the repository, and users can download it directly from the repository or via the installation script.

## Prerequisites

1. The `Libbox.xcframework` must be built and located in `ios/Frameworks/Libbox.xcframework`
2. You need write access to the GitHub repository
3. **GitHub LFS must be enabled** for your repository (free tier includes 1 GB storage)

## Option 1: Using GitHub LFS (Recommended)

### Step 1: Set Up Git LFS

```bash
# Run the setup script
./setup_git_lfs.sh

# Or manually:
git lfs install
git lfs track "ios/Frameworks/Libbox.xcframework/**"
echo "ios/Frameworks/Libbox.xcframework/** filter=lfs diff=lfs merge=lfs -text" >> .gitattributes
```

### Step 2: Add Framework to Repository

```bash
# Add .gitattributes
git add .gitattributes

# Add framework (will be stored via LFS)
git add ios/Frameworks/Libbox.xcframework

# Commit
git commit -m "Add Libbox.xcframework via Git LFS"

# Push (this will upload to LFS)
git push origin main
```

### Step 3: Create GitHub Release (Without Framework)

Create a GitHub Release for versioning, but **don't upload the framework** (it's too large):

```bash
# Create release without framework
gh release create v0.0.1 \
  --title "sing_box v0.0.1" \
  --notes-file RELEASE_NOTES_v0.0.1.md
```

The framework will be downloaded directly from the repository by the installation script.

### Step 4: Test Installation

Test the installation script:

```bash
# In a test Flutter project
curl -L https://raw.githubusercontent.com/qusadprod/sing_box/main/install_ios_framework.sh | bash
```

## Option 2: Use External Hosting (Not Recommended)

You could host the framework on external storage (AWS S3, Google Cloud Storage, etc.), but this adds complexity and potential costs. GitHub LFS is the recommended solution.

## Important Notes

- **GitHub LFS Free Tier**: 1 GB storage, 1 GB bandwidth/month
- **Framework Size**: ~85 MB uncompressed, ~72 MB compressed
- **Installation**: Users will download directly from the repository, not from releases
- **Bandwidth**: Each download counts against LFS bandwidth quota

### 2. Create GitHub Release

#### Option A: Using GitHub Web Interface

1. Go to your repository on GitHub
2. Click on "Releases" → "Create a new release"
3. Fill in the release information:
   - **Tag version**: `v0.0.1` (or your version)
   - **Release title**: `sing_box v0.0.1`
   - **Description**: Copy from `RELEASE_NOTES_v0.0.1.md` or write your own
4. **Attach the framework**:
   - Click "Attach binaries"
   - Upload `ios/Frameworks/Libbox.xcframework.zip`
5. Click "Publish release"

#### Option B: Using GitHub CLI

```bash
# Install GitHub CLI if not installed
# brew install gh

# Authenticate
gh auth login

# Create release with framework
gh release create v0.0.1 \
  --title "sing_box v0.0.1" \
  --notes-file RELEASE_NOTES_v0.0.1.md \
  ios/Frameworks/Libbox.xcframework.zip
```

#### Option C: Using Git Tags and Manual Upload

```bash
# Create and push tag
git tag v0.0.1
git push origin v0.0.1

# Then go to GitHub web interface and create release from the tag
# Upload Libbox.xcframework.zip as an asset
```

### 3. Verify Release

After creating the release, verify:

1. The release is visible at: `https://github.com/qusadprod/sing_box/releases/tag/v0.0.1`
2. The `Libbox.xcframework.zip` file is listed under "Assets"
3. Users can download it using the installation script

### 4. Test Installation Script

Test that the installation script works:

```bash
# In a test Flutter project
curl -L https://raw.githubusercontent.com/qusadprod/sing_box/main/install_ios_framework.sh | bash
```

## Release Checklist

- [ ] Framework is built and optimized
- [ ] Framework is archived as `Libbox.xcframework.zip`
- [ ] Release notes are prepared
- [ ] Release is created on GitHub
- [ ] Framework zip is attached to release
- [ ] Installation script is tested
- [ ] README is updated with installation instructions

## Framework Size

The `Libbox.xcframework` is approximately 85 MB uncompressed and ~40-50 MB compressed. This is why it's distributed separately from the pub.dev package.

## Updating Framework

When updating the framework:

1. Rebuild the framework
2. Create a new archive
3. Create a new GitHub Release with the updated framework
4. Update the version in the installation script if needed

