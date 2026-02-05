# Development Environment Setup Guide
## iSCSI Initiator for macOS

**Version:** 1.0
**Date:** 5. Februar 2026
**Purpose:** Complete guide for setting up the development environment for the macOS iSCSI Initiator project

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Apple Developer Account Setup](#2-apple-developer-account-setup)
3. [Xcode Installation and Configuration](#3-xcode-installation-and-configuration)
4. [Project Creation](#4-project-creation)
5. [Required Tools Installation](#5-required-tools-installation)
6. [Repository Structure Setup](#6-repository-structure-setup)
7. [Verification](#7-verification)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Prerequisites

### 1.1 System Requirements

| Requirement | Specification | Notes |
|------------|---------------|-------|
| **macOS Version** | macOS 14.0 (Sonoma) or later | Required for modern DriverKit APIs |
| **Recommended** | macOS 15.0 (Sequoia) | Latest DriverKit and FSKit APIs |
| **Hardware** | Apple Silicon (M1/M2/M3/M4) | Primary target platform |
| **Intel Support** | x86_64 (Intel Mac) | Secondary target, fully supported |
| **RAM** | 16 GB minimum, 32 GB recommended | Xcode + DriverKit development |
| **Disk Space** | 50 GB free space minimum | Xcode, SDKs, build artifacts |

### 1.2 Required Accounts and Memberships

#### Apple Developer Program ($99/year)

**Why it's required:**
- DriverKit entitlements require Apple approval
- System Extension signing requires Developer ID certificates
- Notarization service access
- TestFlight distribution (optional)

**Sign up:** https://developer.apple.com/programs/

### 1.3 Knowledge Prerequisites

Developers should be familiar with:
- **Swift 6.0**: Modern concurrency (async/await, actors, Sendable)
- **C++20**: For DriverKit extension implementation
- **Xcode**: Build system, targets, schemes, entitlements
- **SCSI Protocol**: Basic understanding helpful but not required
- **iSCSI Protocol**: Will be learned through implementation
- **Network Programming**: TCP/IP, socket programming concepts

---

## 2. Apple Developer Account Setup

### 2.1 Account Registration

1. **Create Apple ID** (if you don't have one)
   - Go to https://appleid.apple.com
   - Follow registration process

2. **Enroll in Apple Developer Program**
   - Visit https://developer.apple.com/programs/enroll/
   - Choose Individual or Organization enrollment
   - Complete payment ($99/year)
   - Wait for enrollment confirmation (usually 24-48 hours)

3. **Note Your Team ID**
   - Log in to https://developer.apple.com/account
   - Navigate to "Membership"
   - Record your Team ID (10-character alphanumeric, e.g., `AB12CD34EF`)
   - You'll need this for code signing and entitlements

### 2.2 Certificates Setup

#### 2.2.1 Developer ID Application Certificate

**Purpose:** Sign macOS applications and system extensions

```bash
# Request certificate from Keychain Access
# 1. Open Keychain Access.app
# 2. Menu: Keychain Access > Certificate Assistant > Request a Certificate from a Certificate Authority
# 3. Enter your email address
# 4. Common Name: "Developer ID Application"
# 5. Choose "Saved to disk"
# 6. Save as: DeveloperIDApplication.certSigningRequest
```

Then in Apple Developer portal:
1. Navigate to Certificates, Identifiers & Profiles
2. Click Certificates → "+" button
3. Select "Developer ID Application"
4. Upload `DeveloperIDApplication.certSigningRequest`
5. Download and double-click to install in Keychain

#### 2.2.2 Developer ID Installer Certificate

**Purpose:** Sign installer packages (.pkg)

Follow same process as above, but select "Developer ID Installer" in step 3.

#### 2.2.3 Verify Certificates

```bash
# List all Developer ID certificates in keychain
security find-identity -p basic -v | grep "Developer ID"

# Expected output (example):
# 1) ABC123... "Developer ID Application: Your Name (TEAM_ID)"
# 2) DEF456... "Developer ID Installer: Your Name (TEAM_ID)"
```

### 2.3 DriverKit Entitlement Request

**Critical:** This is the most important step. Without DriverKit entitlements, your extension will not load.

#### 2.3.1 Entitlement Request Form

1. Go to https://developer.apple.com/contact/request/system-extension/
2. Fill out the request form:

**Required Information:**
- **Your Name**: [Your full name]
- **Apple ID**: [Your developer Apple ID email]
- **Team ID**: [Your 10-character Team ID]
- **Extension Type**: System Extension (DriverKit)
- **Extension Category**: SCSI Driver
- **Bundle Identifier**: `com.opensource.iscsi.driver` (or your chosen ID)

**Project Description (template):**
```
Project: Native macOS iSCSI Initiator
Purpose: Open-source iSCSI initiator for macOS using modern DriverKit APIs

Technical Details:
- IOUserSCSIParallelInterfaceController subclass for virtual SCSI HBA
- User-space iSCSI protocol implementation
- Network.framework for TCP/IP communication
- No kernel extensions (kext), fully user-space solution

Justification:
- No free iSCSI initiators available for Apple Silicon
- Legacy kext-based solutions no longer work on modern macOS
- Community need for open-source storage connectivity

Required Entitlements:
- com.apple.developer.driverkit
- com.apple.developer.driverkit.transport.scsi
- com.apple.developer.driverkit.family.scsi-parallel
- com.apple.developer.driverkit.userclient-access

Target Platforms: macOS 14+ (Sonoma), Apple Silicon primary, Intel secondary
License: MIT (open source)
Repository: [Your GitHub URL]
```

3. **Submit** and wait for response

#### 2.3.2 Expected Timeline

- **Typical response time**: 1-4 weeks
- **Follow-up**: If no response after 2 weeks, send a polite follow-up email
- **Approval notification**: You'll receive an email with entitlement approval
- **Provisioning profile**: Automatically available in Xcode after approval

#### 2.3.3 While Waiting for Approval

You can proceed with:
- Xcode project setup
- Swift protocol engine implementation
- Network layer development
- GUI and CLI tools
- Unit tests

You **cannot** do (until approval):
- Load DriverKit extension on your system
- Test SCSI HBA functionality
- End-to-end integration testing

### 2.4 App IDs and Bundle Identifiers

Create App IDs for all targets:

| Target | Bundle Identifier | Type |
|--------|-------------------|------|
| DriverKit Extension | `com.opensource.iscsi.driver` | System Extension |
| Daemon | `com.opensource.iscsi.daemon` | Command Line Tool |
| GUI App | `com.opensource.iscsi.app` | macOS App |
| CLI Tool | `com.opensource.iscsi.cli` | Command Line Tool |

**Note:** You can choose different reverse-domain identifiers. Consistency is important.

---

## 3. Xcode Installation and Configuration

### 3.1 Install Xcode

#### Option 1: Mac App Store (Recommended)

```bash
# Open App Store
open "macappstores://apps.apple.com/app/xcode/id497799835"

# Or search for "Xcode" in App Store
```

#### Option 2: Direct Download

1. Visit https://developer.apple.com/download/
2. Download Xcode 16.0 or later
3. Install to `/Applications/Xcode.app`

### 3.2 Install Command Line Tools

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Verify installation
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer

# Accept license
sudo xcodebuild -license accept
```

### 3.3 Configure Xcode

#### 3.3.1 First Launch

```bash
# Launch Xcode
open -a Xcode

# Wait for "Install Additional Required Components" prompt
# Click "Install" to install DriverKit SDK and other components
```

#### 3.3.2 Add Apple Developer Account

1. Xcode > Settings (⌘,)
2. Accounts tab
3. Click "+" → Add Apple ID
4. Enter your Apple Developer Apple ID credentials
5. Select your team
6. Click "Download Manual Profiles" to fetch entitlements

#### 3.3.3 Verify DriverKit SDK

```bash
# List available SDKs
xcodebuild -showsdks

# Expected output should include:
# driverkit22.0   -sdk driverkit22.0
# macosx15.0      -sdk macosx15.0
```

If `driverkit` SDK is missing:
1. Xcode > Settings > Locations > Command Line Tools
2. Select Xcode version
3. Close and restart Xcode

---

## 4. Project Creation

### 4.1 Create New Xcode Project

#### 4.1.1 Initial Project Setup

```bash
# Navigate to your projects directory
cd /path/to/your/projects/

# Create project directory
mkdir iscsi-initiator-macos
cd iscsi-initiator-macos

# Open Xcode and create new project
open -a Xcode
```

**In Xcode:**
1. File > New > Project
2. Choose **macOS** > **App**
3. Product Name: `iSCSI Initiator`
4. Team: Select your Apple Developer team
5. Organization Identifier: `com.opensource.iscsi` (or your choice)
6. Bundle Identifier: `com.opensource.iscsi.app` (auto-generated)
7. Interface: **SwiftUI**
8. Language: **Swift**
9. ✅ Include Tests
10. Click **Next**, choose directory, click **Create**

### 4.2 Configure Build Settings

#### 4.2.1 Project-Level Settings

1. Select project in Navigator
2. Select PROJECT "iSCSI Initiator" (not target)
3. Build Settings tab

**Key Settings:**

| Setting | Value | Notes |
|---------|-------|-------|
| Swift Language Version | Swift 6 | Modern concurrency |
| macOS Deployment Target | macOS 14.0 | Minimum supported version |
| Build Active Architecture Only | Debug: Yes, Release: No | Faster debug builds |
| Enable Hardened Runtime | Yes | Required for notarization |

### 4.3 Add DriverKit Extension Target

#### 4.3.1 Create DriverKit Target

1. File > New > Target
2. Select **DriverKit** > **DriverKit System Extension**
3. Product Name: `iSCSIVirtualHBA`
4. Organization Identifier: `com.opensource.iscsi`
5. Bundle Identifier: `com.opensource.iscsi.driver`
6. Language: **C++**
7. Click **Finish**

#### 4.3.2 Configure DriverKit Target Build Settings

Select `iSCSIVirtualHBA` target > Build Settings:

| Setting | Value | Notes |
|---------|-------|-------|
| C++ Language Dialect | C++20 | Modern C++ features |
| SDK | DriverKit | **Critical:** Must be DriverKit SDK |
| Supported Platforms | macOS | Only macOS supported |
| Skip Install | No | Extension must be copied to app |
| Always Embed Swift Standard Libraries | No | DriverKit doesn't use Swift |

#### 4.3.3 Configure DriverKit Info.plist

Edit `Driver/iSCSIVirtualHBA/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>DEXT</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>IOKitPersonalities</key>
    <dict>
        <key>iSCSIVirtualHBA</key>
        <dict>
            <key>CFBundleIdentifier</key>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            <key>IOClass</key>
            <string>IOService</string>
            <key>IOMatchCategory</key>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            <key>IOProviderClass</key>
            <string>IOResources</string>
            <key>IOResourceMatch</key>
            <string>IOKit</string>
            <key>IOUserClass</key>
            <string>iSCSIVirtualHBA</string>
        </dict>
    </dict>
    <key>OSBundleUsageDescription</key>
    <string>iSCSI Virtual SCSI Host Bus Adapter for network storage connectivity</string>
</dict>
</plist>
```

#### 4.3.4 Create DriverKit Entitlements File

Create `Driver/iSCSIVirtualHBA/iSCSIVirtualHBA.entitlements`:

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

**Add to target:**
1. Select `iSCSIVirtualHBA` target
2. Build Settings > Code Signing Entitlements
3. Set to: `Driver/iSCSIVirtualHBA/iSCSIVirtualHBA.entitlements`

### 4.4 Add LaunchDaemon Target (iscsid)

#### 4.4.1 Create Command Line Tool Target

1. File > New > Target
2. Select **macOS** > **Command Line Tool**
3. Product Name: `iscsid`
4. Language: **Swift**
5. Click **Finish**

#### 4.4.2 Configure Daemon Build Settings

Select `iscsid` target > Build Settings:

| Setting | Value |
|---------|-------|
| Product Name | `iscsid` |
| Swift Language Version | Swift 6 |
| macOS Deployment Target | macOS 14.0 |

#### 4.4.3 Create LaunchDaemon plist

Create `Daemon/com.opensource.iscsi.daemon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.opensource.iscsi.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/Application Support/iSCSI Initiator/iscsid</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>com.opensource.iscsi.daemon</key>
        <true/>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/iscsid.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/iscsid.log</string>
</dict>
</plist>
```

### 4.5 Add Swift Package Targets

#### 4.5.1 Create Package.swift

Create `Protocol/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ISCSIProtocol",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ISCSIProtocol",
            targets: ["ISCSIProtocol"]
        ),
        .library(
            name: "ISCSINetwork",
            targets: ["ISCSINetwork"]
        )
    ],
    targets: [
        .target(
            name: "ISCSIProtocol",
            dependencies: [],
            path: "Sources/Protocol"
        ),
        .target(
            name: "ISCSINetwork",
            dependencies: ["ISCSIProtocol"],
            path: "Sources/Network"
        ),
        .testTarget(
            name: "ISCSIProtocolTests",
            dependencies: ["ISCSIProtocol"],
            path: "Tests/ProtocolTests"
        ),
        .testTarget(
            name: "ISCSINetworkTests",
            dependencies: ["ISCSINetwork"],
            path: "Tests/NetworkTests"
        )
    ]
)
```

#### 4.5.2 Add Package to Xcode Project

1. File > Add Package Dependencies
2. Click "Add Local"
3. Select `Protocol` directory
4. Click "Add Package"

### 4.6 Add CLI Tool Target (iscsiadm)

1. File > New > Target
2. Select **macOS** > **Command Line Tool**
3. Product Name: `iscsiadm`
4. Language: **Swift**
5. Click **Finish**

**Add Swift Argument Parser:**

```swift
// Add to iscsiadm target dependencies
// Package.swift (if separate) or add via SPM:
// https://github.com/apple/swift-argument-parser
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
]
```

### 4.7 Configure Target Dependencies

#### 4.7.1 App Depends On

1. Select `iSCSI Initiator` (app) target
2. Build Phases > Dependencies
3. Add `+`:
   - `iSCSIVirtualHBA` (DriverKit extension)
   - `iscsid` (daemon)

4. Build Phases > Copy Files
   - Add new Copy Files Phase
   - Destination: **System Extensions**
   - Add `iSCSIVirtualHBA.dext`

5. Build Phases > Copy Files (second one)
   - Add new Copy Files Phase
   - Destination: **Helpers**
   - Add `iscsid`

#### 4.7.2 Daemon Depends On

1. Select `iscsid` target
2. General > Frameworks and Libraries
3. Add `+`:
   - `ISCSIProtocol` (from SPM)
   - `ISCSINetwork` (from SPM)

#### 4.7.3 CLI Depends On

1. Select `iscsiadm` target
2. General > Frameworks and Libraries
3. Add `+`:
   - `ISCSIProtocol` (from SPM)
   - `ArgumentParser` (from SPM)

### 4.8 Configure App Entitlements

Create `App/iSCSI Initiator/iSCSI_Initiator.entitlements`:

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

**Note:** `com.apple.security.app-sandbox` is `false` because system extension installation requires full disk access.

### 4.9 Code Signing Configuration

#### 4.9.1 Automatic Signing (Development)

For each target:
1. Select target
2. Signing & Capabilities tab
3. ✅ Automatically manage signing
4. Team: Select your Apple Developer team
5. Bundle Identifier: Verify correct

#### 4.9.2 Manual Signing (Release)

For release builds, you'll use manual signing with Developer ID certificates.

1. Select target
2. Signing & Capabilities tab
3. ❌ Automatically manage signing (uncheck)
4. Signing Certificate: **Developer ID Application**
5. Provisioning Profile: **None** (for Developer ID)

---

## 5. Required Tools Installation

### 5.1 Homebrew

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add to shell profile (if needed)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 5.2 Development Tools

```bash
# FIO - Flexible I/O tester for performance testing
brew install fio

# iperf3 - Network bandwidth testing
brew install iperf3

# Git LFS - For large binary files (optional)
brew install git-lfs
git lfs install

# SwiftFormat - Code formatting (optional but recommended)
brew install swiftformat

# SwiftLint - Linting tool (optional but recommended)
brew install swiftlint
```

### 5.3 Optional Development Tools

```bash
# Wireshark - Network protocol analyzer (useful for debugging iSCSI)
brew install --cask wireshark

# Hex Fiend - Hex editor (useful for inspecting PDUs)
brew install --cask hex-fiend

# Charles Proxy - HTTP/TCP proxy (for debugging)
brew install --cask charles

# Docker Desktop - For running test iSCSI targets
brew install --cask docker

# Visual Studio Code - Alternative editor
brew install --cask visual-studio-code
```

### 5.4 Docker Setup for Test Targets

```bash
# Install Docker Desktop (if not already done)
brew install --cask docker

# Start Docker Desktop
open -a Docker

# Pull Linux LIO iSCSI target image
docker pull targetcli/targetcli

# Verify Docker is running
docker ps
```

---

## 6. Repository Structure Setup

### 6.1 Create Directory Structure

```bash
# Navigate to project root
cd /path/to/iscsi-initiator-macos

# Create directory structure
mkdir -p Driver/iSCSIVirtualHBA
mkdir -p Daemon/iscsid
mkdir -p Protocol/Sources/{PDU,SCSI,Auth,Session,DataTransfer}
mkdir -p Protocol/Tests/{PDUTests,SCSITests,SessionTests}
mkdir -p Network/Sources
mkdir -p Network/Tests
mkdir -p App/"iSCSI Initiator"/{Views,ViewModels,Models,Resources}
mkdir -p CLI/iscsiadm/{Commands,Output}
mkdir -p Installer/{Scripts,Resources}
mkdir -p Docs
mkdir -p Scripts
mkdir -p Tests/{Integration,Performance}

# Create .gitkeep files for empty directories
find . -type d -empty -exec touch {}/.gitkeep \;
```

### 6.2 Create .gitignore

Create `.gitignore` in project root:

```gitignore
# Xcode
.DS_Store
build/
DerivedData/
*.xcodeproj/*
!*.xcodeproj/project.pbxproj
!*.xcodeproj/xcshareddata/
*.xcworkspace/*
!*.xcworkspace/contents.xcworkspacedata
!*.xcworkspace/xcshareddata/
xcuserdata/
*.moved-aside
*.swp
*~.nib

# Swift Package Manager
.build/
.swiftpm/
Package.resolved

# CocoaPods (if used)
Pods/
*.podspec

# Carthage (if used)
Carthage/

# Code signing
*.cer
*.p12
*.mobileprovision
*.provisionprofile

# Build artifacts
*.dSYM.zip
*.dSYM
*.ipa
*.app
*.dext
*.pkg
*.dmg

# Logs
*.log
logs/

# Test results
test-results/
test-logs/
*.profdata
*.profraw

# Temporary files
tmp/
temp/
.cache/

# IDE
.vscode/
.idea/

# Documentation build
docs/_build/

# Environment
.env
.env.local
secrets/
```

### 6.3 Initialize Git Repository

```bash
# Initialize git (if not already done)
git init

# Create initial commit
git add .
git commit -m "Initial project structure"

# Add remote (replace with your GitHub URL)
git remote add origin https://github.com/yourusername/iscsi-initiator-macos.git

# Push to remote (optional)
git push -u origin main
```

### 6.4 Create README.md

Create `README.md` in project root:

```markdown
# iSCSI Initiator for macOS

Native macOS iSCSI Initiator using DriverKit and Swift.

## Features

- Native Apple Silicon support
- DriverKit-based virtual SCSI HBA
- Modern Swift 6 implementation
- SwiftUI GUI application
- CLI tool (iscsiadm-compatible)
- CHAP authentication
- Auto-reconnect on network disruption

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Developer Program membership
- Xcode 16.0 or later

## Documentation

See `docs/` directory for comprehensive documentation:
- [Development Environment Setup](docs/development-environment-setup.md)
- [Implementation Cookbook](docs/implementation-cookbook.md)
- [Testing & Validation Guide](docs/testing-validation-guide.md)
- [Deployment & Distribution Guide](docs/deployment-distribution-guide.md)

## Status

🚧 **In Development** - Phase 1 Foundation

## License

MIT License - See LICENSE file for details

## Contributing

See CONTRIBUTING.md for guidelines.
```

---

## 7. Verification

### 7.1 Build Verification

#### 7.1.1 Build All Targets

```bash
# Clean build folder
rm -rf ~/Library/Developer/Xcode/DerivedData/iSCSI*

# Build from command line
cd /path/to/iscsi-initiator-macos
xcodebuild -scheme "iSCSI Initiator" -configuration Debug build

# Expected output:
# BUILD SUCCEEDED
```

**Common issues:**
- SDK not found: Restart Xcode
- Code signing error: Check team selection
- Entitlement error: Ensure entitlements file is linked in build settings

#### 7.1.2 Verify Build Products

```bash
# Find build products
find ~/Library/Developer/Xcode/DerivedData -name "iSCSI Initiator.app" 2>/dev/null

# Expected structure:
# iSCSI Initiator.app/
# ├── Contents/
# │   ├── MacOS/
# │   │   ├── iSCSI Initiator      (main app binary)
# │   │   └── iscsid                (daemon)
# │   ├── SystemExtensions/
# │   │   └── iSCSIVirtualHBA.dext  (DriverKit extension)
# │   └── Info.plist
```

### 7.2 DriverKit Extension Verification (After Entitlement Approval)

**Note:** This step will FAIL until Apple approves your DriverKit entitlements.

```bash
# Activate system extension (requires approval)
cd ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug
systemextensionsctl developer on  # Enable developer mode

# Attempt to load extension
open "iSCSI Initiator.app"

# Check system log for activation
log show --predicate 'subsystem == "com.apple.sysext"' --last 5m

# Expected (after approval):
# System extension activated: com.opensource.iscsi.driver
```

**Before approval, you'll see:**
```
System extension activation failed: extension does not have required entitlements
```

This is EXPECTED. Continue with other development tasks.

### 7.3 XPC Verification

Create test file `Daemon/iscsid/main.swift`:

```swift
import Foundation

@main
struct ISCSIDaemon {
    static func main() {
        print("iSCSI Daemon starting...")

        // Create XPC listener
        let listener = NSXPCListener(machServiceName: "com.opensource.iscsi.daemon")
        // listener.delegate = ISCSIDaemonDelegate()  // TODO: Implement
        print("XPC listener created for: com.opensource.iscsi.daemon")

        // Keep daemon running
        RunLoop.main.run()
    }
}
```

Build and test:

```bash
# Build daemon
xcodebuild -target iscsid -configuration Debug build

# Run daemon manually
~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/iscsid

# Expected output:
# iSCSI Daemon starting...
# XPC listener created for: com.opensource.iscsi.daemon
```

Press Ctrl+C to stop.

### 7.4 Network.framework Verification

Create test file `Network/Sources/NetworkTest.swift`:

```swift
import Foundation
import Network

func testNetworkFramework() {
    print("Testing Network.framework connectivity...")

    let connection = NWConnection(
        host: "1.1.1.1",
        port: 53,
        using: .udp
    )

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("✅ Network.framework is working!")
            connection.cancel()
        case .failed(let error):
            print("❌ Connection failed: \(error)")
        default:
            print("State: \(state)")
        }
    }

    connection.start(queue: .main)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
}

testNetworkFramework()
```

Run:
```bash
swift Network/Sources/NetworkTest.swift

# Expected output:
# Testing Network.framework connectivity...
# State: preparing
# State: ready
# ✅ Network.framework is working!
```

### 7.5 Swift Package Manager Verification

```bash
# Navigate to Protocol package
cd Protocol

# Build package
swift build

# Expected output:
# Building for debugging...
# Build complete!

# Run tests
swift test

# Expected (no tests yet):
# Test Suite 'All tests' started
# Test Suite 'All tests' passed
```

### 7.6 Final Checklist

- [ ] Xcode 16.0+ installed
- [ ] Command line tools installed
- [ ] Apple Developer account enrolled
- [ ] Team ID recorded
- [ ] Developer ID certificates installed
- [ ] DriverKit entitlements requested (waiting for approval is OK)
- [ ] All 7 targets build successfully
- [ ] XPC listener test passes
- [ ] Network.framework test passes
- [ ] Swift packages build and test successfully
- [ ] Git repository initialized
- [ ] Development tools installed (fio, iperf3, etc.)

---

## 8. Troubleshooting

### 8.1 Common Build Errors

#### Error: "No SDK with name 'driverkit'"

**Cause:** DriverKit SDK not installed

**Solution:**
```bash
# Close Xcode
killall Xcode

# Delete derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Restart Xcode
open -a Xcode

# Xcode will prompt to install additional components
# Click "Install"
```

#### Error: "Code signing error: provisioning profile doesn't include entitlement"

**Cause:** DriverKit entitlements not yet approved by Apple

**Solution:**
- This is EXPECTED before entitlement approval
- You can still build other targets (daemon, GUI, CLI)
- DriverKit target will fail to sign until approved
- Continue development on non-DriverKit components

**Workaround for development:**
1. Select `iSCSIVirtualHBA` target
2. Build Settings > Code Sign Identity
3. Set to "Sign to Run Locally" for Debug configuration
4. This allows building but NOT loading the extension

#### Error: "Swift Compiler Error: cannot find type 'IOUserSCSIParallelInterfaceController'"

**Cause:** Wrong SDK selected for DriverKit target

**Solution:**
1. Select `iSCSIVirtualHBA` target
2. Build Settings > Base SDK
3. Change to "DriverKit" (not macOS)
4. Clean build folder (⌘⇧K)
5. Rebuild (⌘B)

#### Error: "Library not loaded: @rpath/ISCSIProtocol.framework"

**Cause:** Swift package not properly linked

**Solution:**
1. Select target with error (e.g., `iscsid`)
2. General > Frameworks and Libraries
3. Ensure ISCSIProtocol shows "Do Not Embed"
4. Build Phases > Embed Frameworks
5. Remove ISCSIProtocol if present
6. Clean and rebuild

### 8.2 DriverKit Extension Issues

#### Extension Won't Load (After Entitlement Approval)

**Check system log:**
```bash
# Show last 5 minutes of system extension logs
log show --predicate 'subsystem == "com.apple.sysext"' --style compact --last 5m

# Common errors:
# - "Code signature invalid": Re-sign with correct certificate
# - "Entitlement not present": Check Entitlements.plist is linked
# - "Team identifier mismatch": Ensure all targets use same team
```

**Verify extension signature:**
```bash
# Check code signature
codesign -dvvv ~/Library/Developer/Xcode/DerivedData/.../iSCSIVirtualHBA.dext

# Should show:
# Authority=Apple Development: Your Name (TEAM_ID)
# Identifier=com.opensource.iscsi.driver
# Format=app bundle with DriverKit
# ...entitlements with driverkit...
```

**Enable developer mode for system extensions:**
```bash
# Allow unsigned/development-signed extensions
systemextensionsctl developer on

# Restart and try again
```

### 8.3 XPC Connection Issues

#### Error: "Connection invalid"

**Check Mach service name:**
```bash
# List all Mach services
launchctl list | grep iscsi

# Should show:
# com.opensource.iscsi.daemon
```

**Verify plist:**
1. Check `MachServices` key in LaunchDaemon plist
2. Ensure it matches XPC listener name in code
3. Service name must be exact match (case-sensitive)

#### Error: "Permission denied to access Mach service"

**Cause:** App sandbox restrictions

**Solution:**
1. App entitlements must disable sandbox OR
2. Add `com.apple.security.temporary-exception.mach-lookup.global-name` with service name

### 8.4 Network Issues

#### Error: "Network connection failed immediately"

**Check network permissions:**
```bash
# App must have network entitlements
# In App/iSCSI_Initiator.entitlements:
# <key>com.apple.security.network.client</key>
# <true/>
```

**Test basic connectivity:**
```bash
# Ping iSCSI target
ping -c 3 192.168.1.10

# Test port 3260 (iSCSI default)
nc -zv 192.168.1.10 3260
```

### 8.5 Performance Issues

#### Slow Build Times

```bash
# Clear derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Clear module cache
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# Disable indexing for faster builds (temporary)
defaults write com.apple.dt.Xcode IDEIndexDisable -bool YES

# Re-enable indexing later
defaults delete com.apple.dt.Xcode IDEIndexDisable
```

#### Xcode Hanging

```bash
# Kill all Xcode processes
killall Xcode
killall SourceKitService

# Reset Xcode preferences (use with caution)
defaults delete com.apple.dt.Xcode
```

### 8.6 Getting Help

#### Log Collection for Bug Reports

```bash
# Create log collection script
cat > collect-logs.sh << 'EOF'
#!/bin/bash
LOGDIR="iscsi-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"

# Build logs
cp ~/Library/Developer/Xcode/DerivedData/*/Logs/Build/*.xcactivitylog "$LOGDIR/" 2>/dev/null

# System logs (last hour)
log show --predicate 'subsystem == "com.apple.sysext" OR processImagePath CONTAINS "iscsi"' \
    --style compact --last 1h > "$LOGDIR/system.log"

# Daemon logs
cp /var/log/iscsid.log "$LOGDIR/" 2>/dev/null

# System info
system_profiler SPSoftwareDataType > "$LOGDIR/system-info.txt"
xcodebuild -version > "$LOGDIR/xcode-version.txt"

# Code signature
codesign -dvvv ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/iSCSIVirtualHBA.dext \
    > "$LOGDIR/codesign.txt" 2>&1

tar czf "$LOGDIR.tar.gz" "$LOGDIR"
echo "Logs collected: $LOGDIR.tar.gz"
EOF

chmod +x collect-logs.sh
./collect-logs.sh
```

#### Resources

- **Apple Developer Forums:** https://developer.apple.com/forums/
- **DriverKit Documentation:** https://developer.apple.com/documentation/driverkit
- **Project GitHub Issues:** [Your repository]/issues
- **Project Discussions:** [Your repository]/discussions

---

## Next Steps

After completing this setup guide:

1. **Review Architecture**
   - Read `docs/iSCSI-Initiator-Entwicklungsplan.md` for detailed architecture
   - Read `docs/session-transfer-protocol.md` for project overview

2. **Start Implementation**
   - Follow `docs/implementation-cookbook.md` for code examples
   - Begin with Phase 1: Foundation components

3. **Setup Testing**
   - Follow `docs/testing-validation-guide.md`
   - Setup MockISCSITarget for development

4. **Join Community**
   - GitHub Discussions for questions
   - Contributing guidelines in CONTRIBUTING.md

---

**Congratulations!** Your development environment is now ready for iSCSI Initiator development.

Next document: [Implementation Cookbook](implementation-cookbook.md)
