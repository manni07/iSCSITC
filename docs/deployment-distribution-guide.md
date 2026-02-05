# Deployment & Distribution Guide
## iSCSI Initiator for macOS

**Version:** 1.0
**Date:** 5. Februar 2026
**Purpose:** Complete guide for building, signing, notarizing, and distributing the iSCSI Initiator

---

## Table of Contents

1. [Overview](#1-overview)
2. [Code Signing](#2-code-signing)
3. [Notarization](#3-notarization)
4. [Installer Creation](#4-installer-creation)
5. [DMG Creation](#5-dmg-creation)
6. [Homebrew Distribution](#6-homebrew-distribution)
7. [GitHub Release Process](#7-github-release-process)
8. [User Installation Guide](#8-user-installation-guide)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Overview

### 1.1 Distribution Strategy

The iSCSI Initiator is distributed through multiple channels:

| Channel | Target Audience | Update Mechanism |
|---------|-----------------|------------------|
| **DMG** | General users | Manual download |
| **Homebrew Cask** | CLI users | `brew upgrade` |
| **GitHub Releases** | Developers, early adopters | Manual |
| **Direct Download** | Enterprise | Manual |

### 1.2 Release Artifacts

Each release includes:
- `iSCSI-Initiator-{version}.dmg` - Disk image with app
- `iSCSI-Initiator-{version}.pkg` - Installer package
- `checksums.txt` - SHA-256 checksums
- `RELEASE_NOTES.md` - Version-specific release notes

### 1.3 Supported Platforms

| macOS Version | Architecture | Status |
|---------------|--------------|--------|
| macOS 15 (Sequoia) | Apple Silicon, Intel | ✅ Fully Supported |
| macOS 14 (Sonoma) | Apple Silicon, Intel | ✅ Fully Supported |
| macOS 13 (Ventura) | Apple Silicon, Intel | ⚠️ Best Effort |
| macOS 12 (Monterey) | Apple Silicon, Intel | ❌ Not Supported |

---

## 2. Code Signing

### 2.1 Overview

All binaries must be signed with Developer ID certificates for distribution outside the Mac App Store.

**Required Certificates:**
- Developer ID Application (for app and extensions)
- Developer ID Installer (for PKG)

### 2.2 Signing Script

Create `Scripts/sign-all.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAM_ID)"
DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAM_ID)"
BUILD_DIR="${BUILD_DIR:-./build/Release}"
ENTITLEMENTS_DIR="./Entitlements"

echo "=== Code Signing iSCSI Initiator ==="
echo "Build directory: $BUILD_DIR"
echo

# Verify certificates exist
security find-identity -v -p codesigning | grep "$DEVELOPER_ID_APP" || {
    echo "❌ Developer ID Application certificate not found"
    exit 1
}

echo "✅ Certificates found"
echo

# Function to sign a binary
sign_binary() {
    local binary="$1"
    local entitlements="${2:-}"
    local extra_flags="${3:-}"

    echo "Signing: $(basename "$binary")"

    if [ -n "$entitlements" ]; then
        codesign --sign "$DEVELOPER_ID_APP" \
            --entitlements "$entitlements" \
            --options runtime \
            --timestamp \
            --force \
            $extra_flags \
            "$binary"
    else
        codesign --sign "$DEVELOPER_ID_APP" \
            --options runtime \
            --timestamp \
            --force \
            $extra_flags \
            "$binary"
    fi

    # Verify
    codesign --verify --verbose=4 "$binary"
    echo "  ✅ Signed successfully"
}

# Step 1: Sign DriverKit extension
echo "Step 1: Signing DriverKit extension..."
sign_binary \
    "$BUILD_DIR/iSCSI Initiator.app/Contents/SystemExtensions/iSCSIVirtualHBA.dext" \
    "$ENTITLEMENTS_DIR/iSCSIVirtualHBA.entitlements"
echo

# Step 2: Sign daemon
echo "Step 2: Signing daemon..."
sign_binary \
    "$BUILD_DIR/iSCSI Initiator.app/Contents/Library/LaunchServices/iscsid" \
    "$ENTITLEMENTS_DIR/iscsid.entitlements"
echo

# Step 3: Sign CLI tool
echo "Step 3: Signing CLI tool..."
sign_binary \
    "$BUILD_DIR/iscsiadm"
echo

# Step 4: Sign app bundle
echo "Step 4: Signing app bundle..."
sign_binary \
    "$BUILD_DIR/iSCSI Initiator.app" \
    "$ENTITLEMENTS_DIR/iSCSI_Initiator.entitlements" \
    "--deep"
echo

echo "✅ All binaries signed successfully"

# Verify all signatures
echo
echo "Verifying signatures..."
codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/iSCSI Initiator.app"
spctl --assess --type execute --verbose=4 "$BUILD_DIR/iSCSI Initiator.app"

echo
echo "✅ Signature verification complete"
```

### 2.3 Entitlements

#### 2.3.1 DriverKit Extension Entitlements

`Entitlements/iSCSIVirtualHBA.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.driverkit</key>
    <true/>
    <key>com.apple.developer.driverkit.transport.scsi</key>
    <true/>
    <key>com.apple.developer.driverkit.family.scsi-parallel</key>
    <true/>
    <key>com.apple.developer.driverkit.userclient-access</key>
    <true/>
</dict>
</plist>
```

#### 2.3.2 Daemon Entitlements

`Entitlements/iscsid.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.application-groups</key>
    <array>
        <string>com.opensource.iscsi</string>
    </array>
</dict>
</plist>
```

#### 2.3.3 App Entitlements

`Entitlements/iSCSI_Initiator.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.application-groups</key>
    <array>
        <string>com.opensource.iscsi</string>
    </array>
    <key>com.apple.developer.system-extension.install</key>
    <true/>
</dict>
</plist>
```

### 2.4 Automated Signing in Xcode

Add Run Script Phase to app target:

```bash
# Run Script Phase: Sign All Components

if [ "$CONFIGURATION" == "Release" ]; then
    echo "Running post-build signing..."
    "${PROJECT_DIR}/Scripts/sign-all.sh"
fi
```

---

## 3. Notarization

### 3.1 Overview

Notarization is required for software distributed outside the Mac App Store. Apple scans the app for malicious content.

**Process:**
1. Build and sign app
2. Create ZIP archive
3. Submit to Apple's notary service
4. Wait for scan results (usually 5-15 minutes)
5. Staple notarization ticket to app

### 3.2 Notarization Script

Create `Scripts/notarize.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
APP_PATH="${1:-./build/Release/iSCSI Initiator.app}"
APPLE_ID="${APPLE_ID:-your@email.com}"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"
APP_PASSWORD="@keychain:AC_PASSWORD"  # Stored in keychain

echo "=== Notarizing iSCSI Initiator ==="
echo "App path: $APP_PATH"
echo

# Verify app is signed
codesign --verify --deep --strict "$APP_PATH" || {
    echo "❌ App is not properly signed"
    exit 1
}
echo "✅ App signature verified"
echo

# Create ZIP for notarization
echo "Creating ZIP archive..."
ARCHIVE_PATH="$(dirname "$APP_PATH")/iSCSI-Initiator.zip"
ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH"
echo "✅ Archive created: $ARCHIVE_PATH"
echo

# Submit for notarization
echo "Submitting to Apple notary service..."
xcrun notarytool submit "$ARCHIVE_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait || {
    echo "❌ Notarization failed"
    exit 1
}
echo "✅ Notarization successful"
echo

# Staple ticket to app
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
echo "✅ Ticket stapled"
echo

# Verify stapling
xcrun stapler validate "$APP_PATH"
echo "✅ Stapler validation passed"

# Clean up
rm "$ARCHIVE_PATH"

echo
echo "✅ Notarization complete"
```

### 3.3 Keychain Setup for App Password

```bash
# Create app-specific password at appleid.apple.com
# Then store in keychain:

security add-generic-password \
    -a "your@email.com" \
    -w "xxxx-xxxx-xxxx-xxxx" \
    -s "AC_PASSWORD" \
    -T /usr/bin/security \
    -U

# Verify it's stored
security find-generic-password -s "AC_PASSWORD" -w
```

### 3.4 Automated Notarization in CI

Add to `.github/workflows/release.yml`:

```yaml
- name: Notarize app
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    TEAM_ID: ${{ secrets.TEAM_ID }}
    APP_PASSWORD: ${{ secrets.APP_PASSWORD }}
  run: |
    # Store password in keychain
    security create-keychain -p actions build.keychain
    security default-keychain -s build.keychain
    security unlock-keychain -p actions build.keychain
    security add-generic-password -a "$APPLE_ID" -w "$APP_PASSWORD" -s "AC_PASSWORD" build.keychain

    # Run notarization
    ./Scripts/notarize.sh "./build/Release/iSCSI Initiator.app"
```

---

## 4. Installer Creation

### 4.1 PKG Installer

Create a professional PKG installer with pre/post install scripts.

#### 4.1.1 Pre-install Script

Create `Installer/Scripts/preinstall`:

```bash
#!/bin/bash

echo "iSCSI Initiator Pre-install"

# Stop running daemon if exists
if launchctl list | grep -q "com.opensource.iscsi.daemon"; then
    echo "Stopping existing daemon..."
    launchctl unload /Library/LaunchDaemons/com.opensource.iscsi.daemon.plist 2>/dev/null || true
fi

# Unload existing system extension if present
if systemextensionsctl list | grep -q "com.opensource.iscsi.driver"; then
    echo "Note: Existing system extension will be replaced"
fi

exit 0
```

#### 4.1.2 Post-install Script

Create `Installer/Scripts/postinstall`:

```bash
#!/bin/bash

echo "iSCSI Initiator Post-install"

# Set permissions
chmod +x "/Applications/iSCSI Initiator.app/Contents/MacOS/iSCSI Initiator"
chmod +x "/Applications/iSCSI Initiator.app/Contents/Library/LaunchServices/iscsid"

# Install daemon plist
cp "/Applications/iSCSI Initiator.app/Contents/Resources/com.opensource.iscsi.daemon.plist" \
   "/Library/LaunchDaemons/com.opensource.iscsi.daemon.plist"

# Load daemon
launchctl load /Library/LaunchDaemons/com.opensource.iscsi.daemon.plist

# Create configuration directory
mkdir -p "/Library/Application Support/iSCSI Initiator"

echo "✅ Installation complete"
echo
echo "To complete setup:"
echo "1. Launch 'iSCSI Initiator' from Applications"
echo "2. Approve the system extension when prompted"
echo "3. Configure your iSCSI targets"

exit 0
```

Make scripts executable:
```bash
chmod +x Installer/Scripts/preinstall
chmod +x Installer/Scripts/postinstall
```

#### 4.1.3 Build PKG Script

Create `Scripts/build-pkg.sh`:

```bash
#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
BUILD_DIR="./build/Release"
PKG_ROOT="./build/pkg-root"
PKG_OUTPUT="./build/iSCSI-Initiator-${VERSION}.pkg"

echo "=== Building PKG Installer ==="
echo "Version: $VERSION"
echo

# Clean and create pkg root
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/usr/local/bin"

# Copy app
echo "Copying application..."
cp -R "$BUILD_DIR/iSCSI Initiator.app" "$PKG_ROOT/Applications/"

# Copy CLI tool
echo "Copying CLI tool..."
cp "$BUILD_DIR/iscsiadm" "$PKG_ROOT/usr/local/bin/"

# Build component package
echo "Building component package..."
pkgbuild --root "$PKG_ROOT" \
    --identifier "com.opensource.iscsi.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    --scripts "./Installer/Scripts" \
    --sign "Developer ID Installer: Your Name (TEAM_ID)" \
    "./build/iSCSI-Initiator-component.pkg"

# Create distribution package (with custom UI)
echo "Creating distribution package..."
productbuild --distribution "./Installer/Distribution.xml" \
    --resources "./Installer/Resources" \
    --package-path "./build" \
    --sign "Developer ID Installer: Your Name (TEAM_ID)" \
    "$PKG_OUTPUT"

echo "✅ PKG created: $PKG_OUTPUT"

# Verify
pkgutil --check-signature "$PKG_OUTPUT"
echo "✅ PKG signature verified"
```

#### 4.1.4 Distribution XML

Create `Installer/Distribution.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>iSCSI Initiator for macOS</title>
    <welcome file="Welcome.html"/>
    <readme file="ReadMe.html"/>
    <license file="License.html"/>
    <conclusion file="Conclusion.html"/>

    <options customize="never" require-scripts="true" rootVolumeOnly="true" />

    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>

    <choices-outline>
        <line choice="default">
            <line choice="com.opensource.iscsi.pkg"/>
        </line>
    </choices-outline>

    <choice id="default"/>
    <choice id="com.opensource.iscsi.pkg" visible="false">
        <pkg-ref id="com.opensource.iscsi.pkg"/>
    </choice>

    <pkg-ref id="com.opensource.iscsi.pkg" version="1.0.0" onConclusion="none">
        iSCSI-Initiator-component.pkg
    </pkg-ref>
</installer-gui-script>
```

---

## 5. DMG Creation

### 5.1 DMG Assembly Script

Create `Scripts/build-dmg.sh`:

```bash
#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_PATH="./build/Release/iSCSI Initiator.app"
DMG_PATH="./build/iSCSI-Initiator-${VERSION}.dmg"
DMG_TEMP="./build/dmg-temp"
VOLUME_NAME="iSCSI Initiator ${VERSION}"

echo "=== Creating DMG ==="
echo "Version: $VERSION"
echo

# Clean and create temp directory
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app
echo "Copying application..."
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create Applications symlink
echo "Creating Applications symlink..."
ln -s /Applications "$DMG_TEMP/Applications"

# Copy README
echo "Copying documentation..."
cp README.md "$DMG_TEMP/README.txt"
cp LICENSE "$DMG_TEMP/LICENSE.txt"

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Sign DMG
echo "Signing DMG..."
codesign --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --timestamp \
    "$DMG_PATH"

# Verify
codesign --verify --verbose=4 "$DMG_PATH"
echo "✅ DMG created and signed: $DMG_PATH"

# Clean up
rm -rf "$DMG_TEMP"

# Calculate checksum
echo
echo "Calculating SHA-256 checksum..."
shasum -a 256 "$DMG_PATH" | tee "./build/checksums.txt"

echo
echo "✅ DMG creation complete"
```

### 5.2 Custom DMG Background (Optional)

For a polished DMG with custom background:

```bash
#!/bin/bash
# Scripts/build-dmg-custom.sh

# ... (previous setup) ...

# Create temporary RW DMG
hdiutil create -size 200m -fs HFS+ -volname "$VOLUME_NAME" "./build/temp.dmg"

# Mount it
MOUNT_POINT=$(hdiutil attach "./build/temp.dmg" | grep "/Volumes" | cut -f3)

# Copy files
cp -R "$APP_PATH" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"

# Copy background image
mkdir "$MOUNT_POINT/.background"
cp "./Installer/Resources/dmg-background.png" "$MOUNT_POINT/.background/"

# Set window properties with AppleScript
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:dmg-background.png"
        set position of item "iSCSI Initiator.app" of container window to {150, 150}
        set position of item "Applications" of container window to {350, 150}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Unmount
hdiutil detach "$MOUNT_POINT"

# Convert to compressed, read-only
hdiutil convert "./build/temp.dmg" -format UDZO -o "$DMG_PATH"
rm "./build/temp.dmg"

# Sign
codesign --sign "Developer ID Application: Your Name (TEAM_ID)" "$DMG_PATH"
```

---

## 6. Homebrew Distribution

### 6.1 Create Homebrew Tap

```bash
# Create tap repository
mkdir homebrew-iscsi
cd homebrew-iscsi

# Initialize git
git init
git remote add origin https://github.com/yourusername/homebrew-iscsi.git
```

### 6.2 Cask Formula

Create `Casks/iscsi-initiator.rb`:

```ruby
cask "iscsi-initiator" do
  version "1.0.0"
  sha256 "abcd1234..."  # Update with actual SHA-256

  url "https://github.com/yourusername/iscsi-initiator-macos/releases/download/v#{version}/iSCSI-Initiator-#{version}.dmg"
  name "iSCSI Initiator for macOS"
  desc "Native iSCSI initiator for macOS with Apple Silicon support"
  homepage "https://github.com/yourusername/iscsi-initiator-macos"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "iSCSI Initiator.app"

  binary "#{appdir}/iSCSI Initiator.app/Contents/MacOS/iscsiadm"

  postflight do
    system_command "/bin/launchctl",
                   args: ["load", "/Library/LaunchDaemons/com.opensource.iscsi.daemon.plist"],
                   sudo: true
  end

  uninstall launchctl: "com.opensource.iscsi.daemon",
            quit:      "com.opensource.iscsi.app",
            delete:    [
              "/Library/LaunchDaemons/com.opensource.iscsi.daemon.plist",
              "/Library/Application Support/iSCSI Initiator",
            ]

  zap trash: [
    "~/Library/Preferences/com.opensource.iscsi.app.plist",
    "~/Library/Logs/iSCSI Initiator",
  ]
end
```

### 6.3 Update Formula Script

Create `Scripts/update-homebrew.sh`:

```bash
#!/bin/bash
set -euo pipefail

VERSION="$1"
DMG_PATH="./build/iSCSI-Initiator-${VERSION}.dmg"
TAP_PATH="../homebrew-iscsi"

echo "=== Updating Homebrew Formula ==="
echo "Version: $VERSION"
echo

# Calculate SHA-256
SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
echo "SHA-256: $SHA256"

# Update formula
cd "$TAP_PATH"

sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/iscsi-initiator.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256\"/" Casks/iscsi-initiator.rb

# Commit
git add Casks/iscsi-initiator.rb
git commit -m "Update iSCSI Initiator to v${VERSION}"
git tag "v${VERSION}"

echo "✅ Formula updated"
echo "Run 'git push && git push --tags' to publish"
```

### 6.4 User Installation

Users install with:
```bash
brew tap yourusername/iscsi
brew install --cask iscsi-initiator
```

---

## 7. GitHub Release Process

### 7.1 Release Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-and-release:
    runs-on: macos-14

    steps:
    - uses: actions/checkout@v4

    - name: Get version from tag
      id: get_version
      run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_OUTPUT

    - name: Setup certificates
      env:
        CERTIFICATE_P12: ${{ secrets.CERTIFICATE_P12 }}
        CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
      run: |
        echo "$CERTIFICATE_P12" | base64 --decode > certificate.p12
        security create-keychain -p actions build.keychain
        security default-keychain -s build.keychain
        security unlock-keychain -p actions build.keychain
        security import certificate.p12 -k build.keychain -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple: -s -k actions build.keychain

    - name: Build
      run: |
        xcodebuild clean build \
          -scheme "iSCSI Initiator" \
          -configuration Release \
          -derivedDataPath ./build

    - name: Sign
      run: ./Scripts/sign-all.sh

    - name: Notarize
      env:
        APPLE_ID: ${{ secrets.APPLE_ID }}
        TEAM_ID: ${{ secrets.TEAM_ID }}
        APP_PASSWORD: ${{ secrets.APP_PASSWORD }}
      run: ./Scripts/notarize.sh

    - name: Build PKG
      run: ./Scripts/build-pkg.sh ${{ steps.get_version.outputs.VERSION }}

    - name: Build DMG
      run: ./Scripts/build-dmg.sh ${{ steps.get_version.outputs.VERSION }}

    - name: Generate Release Notes
      run: |
        echo "# iSCSI Initiator v${{ steps.get_version.outputs.VERSION }}" > RELEASE_NOTES.md
        echo "" >> RELEASE_NOTES.md
        echo "## What's New" >> RELEASE_NOTES.md
        echo "" >> RELEASE_NOTES.md
        # Extract from CHANGELOG.md
        sed -n "/## \\[${{ steps.get_version.outputs.VERSION }}\\]/,/## \\[/p" CHANGELOG.md | head -n -1 >> RELEASE_NOTES.md

    - name: Create Release
      uses: softprops/action-gh-release@v1
      with:
        files: |
          build/iSCSI-Initiator-${{ steps.get_version.outputs.VERSION }}.dmg
          build/iSCSI-Initiator-${{ steps.get_version.outputs.VERSION }}.pkg
          build/checksums.txt
        body_path: RELEASE_NOTES.md
        draft: false
        prerelease: ${{ contains(github.ref, 'beta') || contains(github.ref, 'alpha') }}
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

    - name: Update Homebrew Tap
      env:
        TAP_REPO_TOKEN: ${{ secrets.TAP_REPO_TOKEN }}
      run: |
        git clone https://${TAP_REPO_TOKEN}@github.com/yourusername/homebrew-iscsi.git
        cd homebrew-iscsi
        ../Scripts/update-homebrew.sh ${{ steps.get_version.outputs.VERSION }}
        git push origin main
        git push origin --tags
```

### 7.2 Manual Release Checklist

1. **Pre-release**
   - [ ] All tests pass
   - [ ] CHANGELOG.md updated
   - [ ] Version bumped in Xcode project
   - [ ] Documentation updated
   - [ ] README.md updated

2. **Build**
   - [ ] Clean build (`xcodebuild clean`)
   - [ ] Release build (`xcodebuild -configuration Release`)
   - [ ] All targets build successfully

3. **Sign & Notarize**
   - [ ] Sign all binaries (`./Scripts/sign-all.sh`)
   - [ ] Notarize app (`./Scripts/notarize.sh`)
   - [ ] Verify notarization (`spctl --assess`)

4. **Package**
   - [ ] Build PKG (`./Scripts/build-pkg.sh`)
   - [ ] Build DMG (`./Scripts/build-dmg.sh`)
   - [ ] Generate checksums

5. **Test Installation**
   - [ ] Test PKG on clean VM
   - [ ] Test DMG on clean VM
   - [ ] Verify system extension loads
   - [ ] Test basic functionality

6. **Publish**
   - [ ] Create Git tag (`git tag v1.0.0`)
   - [ ] Push tag (`git push origin v1.0.0`)
   - [ ] GitHub Actions creates release
   - [ ] Update Homebrew tap
   - [ ] Announce release

---

## 8. User Installation Guide

### 8.1 DMG Installation

**For end users (recommended):**

1. **Download**
   - Visit https://github.com/yourusername/iscsi-initiator-macos/releases
   - Download `iSCSI-Initiator-{version}.dmg`

2. **Verify Download** (optional but recommended)
   ```bash
   shasum -a 256 ~/Downloads/iSCSI-Initiator-1.0.0.dmg
   # Compare with checksums.txt
   ```

3. **Install**
   - Double-click DMG to mount
   - Drag "iSCSI Initiator.app" to Applications folder
   - Eject DMG

4. **First Launch**
   - Open "iSCSI Initiator" from Applications
   - macOS will prompt: "System Extension Blocked"
   - Click "Open System Settings"
   - Click "Allow" next to "iSCSI Virtual HBA"
   - Restart app

5. **Verify Installation**
   - Daemon should be running:
     ```bash
     launchctl list | grep iscsi
     ```
   - CLI tool available:
     ```bash
     iscsiadm --version
     ```

### 8.2 Homebrew Installation

**For CLI users:**

```bash
# Add tap
brew tap yourusername/iscsi

# Install
brew install --cask iscsi-initiator

# Verify
iscsiadm --version
```

### 8.3 Uninstallation

#### GUI Method

1. Quit iSCSI Initiator app
2. Open Terminal and run:
   ```bash
   sudo launchctl unload /Library/LaunchDaemons/com.opensource.iscsi.daemon.plist
   sudo rm /Library/LaunchDaemons/com.opensource.iscsi.daemon.plist
   ```
3. Move app to Trash
4. Remove configuration:
   ```bash
   sudo rm -rf "/Library/Application Support/iSCSI Initiator"
   rm -rf ~/Library/Preferences/com.opensource.iscsi.app.plist
   ```

#### Homebrew Method

```bash
brew uninstall --cask iscsi-initiator
brew untap yourusername/iscsi
```

---

## 9. Troubleshooting

### 9.1 Code Signing Issues

#### Error: "No identity found"

**Solution:**
```bash
# List available identities
security find-identity -v -p codesigning

# If empty, import certificates
security import certificate.p12 -k ~/Library/Keychains/login.keychain
```

#### Error: "The executable does not have the hardened runtime enabled"

**Solution:**
Add `--options runtime` to codesign command:
```bash
codesign --sign "Developer ID Application" --options runtime --timestamp app.app
```

### 9.2 Notarization Issues

#### Error: "The binary is not signed with a valid Developer ID certificate"

**Solution:**
Ensure using "Developer ID Application" (not "Apple Development"):
```bash
codesign -dvv app.app 2>&1 | grep "Authority"
# Should show: Authority=Developer ID Application: ...
```

#### Error: "The signature does not include a secure timestamp"

**Solution:**
Add `--timestamp` flag:
```bash
codesign --sign "Developer ID Application" --timestamp app.app
```

#### Notarization stuck "In Progress"

**Solution:**
Check status manually:
```bash
xcrun notarytool log <submission-id> \
    --apple-id your@email.com \
    --team-id TEAM_ID \
    --password @keychain:AC_PASSWORD
```

### 9.3 Installation Issues

#### Error: "App is damaged and can't be opened"

**Cause:** Gatekeeper blocking unsigned/non-notarized app

**Solution:**
```bash
# For testing only (DO NOT distribute)
sudo xattr -rd com.apple.quarantine "/Applications/iSCSI Initiator.app"
```

**Proper fix:** Sign and notarize the app

#### System Extension Won't Load

**Solution:**
1. Enable developer mode:
   ```bash
   systemextensionsctl developer on
   ```

2. Check extension status:
   ```bash
   systemextensionsctl list
   ```

3. Check logs:
   ```bash
   log show --predicate 'subsystem == "com.apple.sysext"' --last 5m
   ```

### 9.4 PKG Issues

#### Error: "The package is signed but its signature is invalid"

**Solution:**
```bash
# Verify signing certificate
pkgutil --check-signature package.pkg

# Re-sign if needed
productsign --sign "Developer ID Installer" unsigned.pkg signed.pkg
```

---

## Conclusion

This guide provides a complete distribution workflow:

✅ **Code Signing** - All binaries properly signed
✅ **Notarization** - Approved by Apple
✅ **Installer** - Professional PKG with scripts
✅ **DMG** - User-friendly disk image
✅ **Homebrew** - CLI-friendly distribution
✅ **GitHub Releases** - Automated via CI/CD
✅ **Documentation** - Clear installation guide

**Next Steps:**
1. Set up Apple Developer account
2. Request DriverKit entitlements
3. Configure code signing in Xcode
4. Set up CI/CD secrets
5. Create first release

**Related Documents:**
- [Development Environment Setup](development-environment-setup.md)
- [Implementation Cookbook](implementation-cookbook.md)
- [Testing & Validation Guide](testing-validation-guide.md)