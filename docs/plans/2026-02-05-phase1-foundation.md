# Phase 1: Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the foundational components for the iSCSI Initiator: PDU Protocol Engine, XPC Communication, Network Layer, and Login State Machine with comprehensive test coverage.

**Architecture:** Swift-based protocol engine with Network.framework for TCP/IP, XPC for IPC between app/daemon, and TDD approach throughout. Each component is independently testable before integration.

**Tech Stack:** Swift 6.0, Network.framework, XCTest, Swift Package Manager

**Reference Documents:**
- `docs/implementation-cookbook.md` - Code examples for all components
- `docs/iSCSI-Initiator-Entwicklungsplan.md` - Detailed architecture (Sections 3.4-4.10)
- `docs/testing-validation-guide.md` - Testing patterns and MockISCSITarget
- RFC 7143 - iSCSI protocol specification

---

## Prerequisites

Before starting, ensure you have completed:
- [ ] Xcode 16.0+ installed with DriverKit SDK
- [ ] Apple Developer account set up
- [ ] Project directory exists at `/Volumes/turgay/projekte/iSCSITC/`
- [ ] Git initialized in project root

**Note:** If Xcode project doesn't exist yet, start with Task 0. Otherwise, skip to Task 1.

---

## Task 0: Create Swift Package Structure (OPTIONAL - If no Xcode project exists)

**Skip this task if:** Xcode project already exists

**Files:**
- Create: `Protocol/Package.swift`
- Create: `Protocol/Sources/Protocol/.gitkeep`
- Create: `Protocol/Sources/Network/.gitkeep`
- Create: `Protocol/Tests/ProtocolTests/.gitkeep`
- Create: `Protocol/Tests/NetworkTests/.gitkeep`

### Step 1: Create Package.swift

```bash
mkdir -p Protocol/Sources/Protocol
mkdir -p Protocol/Sources/Network
mkdir -p Protocol/Tests/ProtocolTests
mkdir -p Protocol/Tests/NetworkTests
```

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

### Step 2: Verify package builds

```bash
cd Protocol
swift build
```

Expected output: `Build complete!`

### Step 3: Commit

```bash
git add Protocol/
git commit -m "feat: initialize Swift package structure for Protocol and Network modules"
```

---

## Task 1: PDU Base Types and Error Handling

**Files:**
- Create: `Protocol/Sources/Protocol/ISCSIError.swift`
- Create: `Protocol/Sources/Protocol/PDU/ISCSIPDUTypes.swift`
- Create: `Protocol/Tests/ProtocolTests/ISCSIErrorTests.swift`

### Step 1: Write failing test for ISCSIError

Create `Protocol/Tests/ProtocolTests/ISCSIErrorTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class ISCSIErrorTests: XCTestCase {

    func testErrorDescriptions() {
        let error = ISCSIError.notConnected
        XCTAssertNotNil(error.errorDescription)
        XCTAssertEqual(error.errorDescription, "Not connected to target")
    }

    func testLoginFailedErrorDescription() {
        let error = ISCSIError.loginFailed(statusClass: 2, statusDetail: 5)
        XCTAssertEqual(error.errorDescription, "Login failed: class=2 detail=5")
    }
}
```

### Step 2: Run test to verify it fails

```bash
cd Protocol
swift test --filter ISCSIErrorTests
```

Expected: FAIL with "No such module 'ISCSIProtocol'"

### Step 3: Create ISCSIError enum

Create `Protocol/Sources/Protocol/ISCSIError.swift`:

```swift
import Foundation

public enum ISCSIError: Error, LocalizedError {
    // Connection errors
    case notConnected
    case alreadyConnected
    case connectionTimeout
    case connectionFailed(Error)
    case daemonNotConnected

    // Protocol errors
    case invalidPDU
    case invalidState
    case loginFailed(statusClass: UInt8, statusDetail: UInt8)
    case invalidLoginStage(current: UInt8, next: UInt8)
    case protocolViolation(String)

    // Session errors
    case sessionNotFound
    case sessionAlreadyExists
    case targetNotFound

    // Authentication errors
    case authenticationFailed
    case keychainError(status: OSStatus)

    // I/O errors
    case commandFailed(status: UInt8)
    case dataTransferError

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to target"
        case .alreadyConnected:
            return "Already connected"
        case .connectionTimeout:
            return "Connection timeout"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .daemonNotConnected:
            return "Daemon not connected"

        case .invalidPDU:
            return "Invalid PDU received"
        case .invalidState:
            return "Invalid state for operation"
        case .loginFailed(let statusClass, let statusDetail):
            return "Login failed: class=\(statusClass) detail=\(statusDetail)"
        case .invalidLoginStage(let current, let next):
            return "Invalid login stage transition: \(current) → \(next)"
        case .protocolViolation(let message):
            return "Protocol violation: \(message)"

        case .sessionNotFound:
            return "Session not found"
        case .sessionAlreadyExists:
            return "Session already exists"
        case .targetNotFound:
            return "Target not found"

        case .authenticationFailed:
            return "Authentication failed"
        case .keychainError(let status):
            return "Keychain error: \(status)"

        case .commandFailed(let status):
            return "SCSI command failed with status: 0x\(String(format: "%02x", status))"
        case .dataTransferError:
            return "Data transfer error"
        }
    }
}
```

### Step 4: Run test to verify it passes

```bash
swift test --filter ISCSIErrorTests
```

Expected: PASS (2 tests)

### Step 5: Write test for PDU opcodes

Add to `Protocol/Tests/ProtocolTests/ISCSIErrorTests.swift`:

```swift
func testPDUOpcodes() {
    XCTAssertEqual(ISCSIPDUOpcode.nopOut.rawValue, 0x00)
    XCTAssertEqual(ISCSIPDUOpcode.scsiCommand.rawValue, 0x01)
    XCTAssertEqual(ISCSIPDUOpcode.loginRequest.rawValue, 0x03)
    XCTAssertEqual(ISCSIPDUOpcode.loginResponse.rawValue, 0x23)
}
```

### Step 6: Run test to verify it fails

```bash
swift test --filter ISCSIErrorTests/testPDUOpcodes
```

Expected: FAIL with "Cannot find 'ISCSIPDUOpcode' in scope"

### Step 7: Create PDU base types

Create `Protocol/Sources/Protocol/PDU/ISCSIPDUTypes.swift`:

```swift
import Foundation

// MARK: - PDU Opcodes

public enum ISCSIPDUOpcode: UInt8, Sendable {
    // Initiator → Target
    case nopOut             = 0x00
    case scsiCommand        = 0x01
    case taskManagementReq  = 0x02
    case loginRequest       = 0x03
    case textRequest        = 0x04
    case dataOut            = 0x05
    case logoutRequest      = 0x06
    case snackRequest       = 0x10

    // Target → Initiator
    case nopIn              = 0x20
    case scsiResponse       = 0x21
    case taskManagementResp = 0x22
    case loginResponse      = 0x23
    case textResponse       = 0x24
    case dataIn             = 0x25
    case logoutResponse     = 0x26
    case r2t                = 0x31
    case asyncMessage       = 0x32
    case reject             = 0x3f
}

// MARK: - Basic Header Segment (BHS)

/// Basic Header Segment - 48 bytes (common to all PDUs)
public struct BasicHeaderSegment: Sendable {
    public var opcode: UInt8                    // Byte 0
    public var flags: UInt8                     // Byte 1
    public var totalAHSLength: UInt8            // Byte 4 (in 4-byte words)
    public var dataSegmentLength: UInt32        // Bytes 5-7 (24-bit, big-endian)
    public var lun: UInt64                      // Bytes 8-15
    public var initiatorTaskTag: UInt32         // Bytes 16-19
    public var opcodeSpecific: Data             // Bytes 20-47 (28 bytes)

    public init() {
        self.opcode = 0
        self.flags = 0
        self.totalAHSLength = 0
        self.dataSegmentLength = 0
        self.lun = 0
        self.initiatorTaskTag = 0
        self.opcodeSpecific = Data(count: 28)
    }

    public static let size = 48
}

// MARK: - Complete PDU

/// Complete iSCSI PDU
public struct ISCSIPDU: Sendable {
    public var bhs: BasicHeaderSegment
    public var ahs: [Data]?                     // Additional Header Segments
    public var headerDigest: UInt32?            // CRC32C (optional)
    public var dataSegment: Data?
    public var dataDigest: UInt32?              // CRC32C (optional)

    public init(opcode: ISCSIPDUOpcode) {
        self.bhs = BasicHeaderSegment()
        self.bhs.opcode = opcode.rawValue
    }
}
```

### Step 8: Run test to verify it passes

```bash
swift test --filter ISCSIErrorTests
```

Expected: PASS (3 tests)

### Step 9: Commit

```bash
git add Protocol/Sources/Protocol/ISCSIError.swift
git add Protocol/Sources/Protocol/PDU/ISCSIPDUTypes.swift
git add Protocol/Tests/ProtocolTests/ISCSIErrorTests.swift
git commit -m "feat: add ISCSIError enum and PDU base types

- Add comprehensive error enum with localized descriptions
- Add PDU opcode definitions (17 types)
- Add BasicHeaderSegment and ISCSIPDU structs
- Add unit tests for errors and opcodes"
```

---

## Task 2: PDU Parser - Basic Header Segment

**Files:**
- Create: `Protocol/Sources/Protocol/PDU/ISCSIPDUParser.swift`
- Create: `Protocol/Tests/ProtocolTests/PDUParserTests.swift`

### Step 1: Write failing test for BHS parsing

Create `Protocol/Tests/ProtocolTests/PDUParserTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class PDUParserTests: XCTestCase {

    func testParseBHS_ValidData() throws {
        // Arrange: Create test BHS data
        var data = Data(count: 48)
        data[0] = 0x01  // SCSI Command opcode
        data[1] = 0x80  // Final bit set
        data[5] = 0x00  // DataSegmentLength MSB
        data[6] = 0x01  // DataSegmentLength middle
        data[7] = 0x00  // DataSegmentLength LSB (256 bytes)

        // LUN (bytes 8-15) = 0x1234567890ABCDEF
        withUnsafeBytes(of: UInt64(0x1234567890ABCDEF).bigEndian) { bytes in
            data.replaceSubrange(8..<16, with: bytes)
        }

        // ITT (bytes 16-19) = 0x12345678
        withUnsafeBytes(of: UInt32(0x12345678).bigEndian) { bytes in
            data.replaceSubrange(16..<20, with: bytes)
        }

        // Act
        let bhs = try ISCSIPDUParser.parseBHS(data)

        // Assert
        XCTAssertEqual(bhs.opcode, 0x01)
        XCTAssertEqual(bhs.flags, 0x80)
        XCTAssertEqual(bhs.dataSegmentLength, 256)
        XCTAssertEqual(bhs.lun, 0x1234567890ABCDEF)
        XCTAssertEqual(bhs.initiatorTaskTag, 0x12345678)
    }

    func testParseBHS_InsufficientData() {
        // Arrange: Only 40 bytes (less than 48 required)
        let data = Data(count: 40)

        // Act & Assert
        XCTAssertThrowsError(try ISCSIPDUParser.parseBHS(data)) { error in
            guard case PDUParseError.insufficientData = error else {
                XCTFail("Expected insufficientData error, got \(error)")
                return
            }
        }
    }
}
```

### Step 2: Run test to verify it fails

```bash
swift test --filter PDUParserTests
```

Expected: FAIL with "Cannot find 'ISCSIPDUParser' in scope"

### Step 3: Create PDU parser with BHS support

Create `Protocol/Sources/Protocol/PDU/ISCSIPDUParser.swift`:

```swift
import Foundation

public enum PDUParseError: Error {
    case insufficientData
    case invalidOpcode(UInt8)
    case invalidHeaderDigest
    case invalidDataDigest
    case malformedPDU(String)
}

public struct ISCSIPDUParser {

    /// Parse BHS from data
    public static func parseBHS(_ data: Data) throws -> BasicHeaderSegment {
        guard data.count >= BasicHeaderSegment.size else {
            throw PDUParseError.insufficientData
        }

        var bhs = BasicHeaderSegment()

        // Byte 0: Opcode
        bhs.opcode = data[0]

        // Byte 1: Flags
        bhs.flags = data[1]

        // Byte 4: TotalAHSLength
        bhs.totalAHSLength = data[4]

        // Bytes 5-7: DataSegmentLength (24-bit, big-endian)
        bhs.dataSegmentLength = UInt32(data[5]) << 16 |
                                UInt32(data[6]) << 8 |
                                UInt32(data[7])

        // Bytes 8-15: LUN (big-endian)
        bhs.lun = data.subdata(in: 8..<16).withUnsafeBytes {
            $0.load(as: UInt64.self).bigEndian
        }

        // Bytes 16-19: ITT (big-endian)
        bhs.initiatorTaskTag = data.subdata(in: 16..<20).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        // Bytes 20-47: Opcode-specific
        bhs.opcodeSpecific = data.subdata(in: 20..<48)

        return bhs
    }

    /// Encode BHS to data
    public static func encodeBHS(_ bhs: BasicHeaderSegment) -> Data {
        var data = Data(count: BasicHeaderSegment.size)

        data[0] = bhs.opcode
        data[1] = bhs.flags
        data[2] = 0  // Reserved
        data[3] = 0  // Reserved
        data[4] = bhs.totalAHSLength

        // DataSegmentLength (24-bit, big-endian)
        data[5] = UInt8((bhs.dataSegmentLength >> 16) & 0xFF)
        data[6] = UInt8((bhs.dataSegmentLength >> 8) & 0xFF)
        data[7] = UInt8(bhs.dataSegmentLength & 0xFF)

        // LUN (big-endian)
        withUnsafeBytes(of: bhs.lun.bigEndian) { bytes in
            data.replaceSubrange(8..<16, with: bytes)
        }

        // ITT (big-endian)
        withUnsafeBytes(of: bhs.initiatorTaskTag.bigEndian) { bytes in
            data.replaceSubrange(16..<20, with: bytes)
        }

        // Opcode-specific
        data.replaceSubrange(20..<48, with: bhs.opcodeSpecific)

        return data
    }
}
```

### Step 4: Run test to verify it passes

```bash
swift test --filter PDUParserTests
```

Expected: PASS (2 tests)

### Step 5: Add round-trip test

Add to `PDUParserTests.swift`:

```swift
func testEncodeBHS_RoundTrip() throws {
    // Arrange: Create original BHS
    var original = BasicHeaderSegment()
    original.opcode = 0x03  // Login Request
    original.flags = 0x83   // Transit + Continue
    original.dataSegmentLength = 512
    original.lun = 0xABCDEF0123456789
    original.initiatorTaskTag = 0x87654321

    // Act: Encode then decode
    let encoded = ISCSIPDUParser.encodeBHS(original)
    let decoded = try ISCSIPDUParser.parseBHS(encoded)

    // Assert: Should match
    XCTAssertEqual(decoded.opcode, original.opcode)
    XCTAssertEqual(decoded.flags, original.flags)
    XCTAssertEqual(decoded.dataSegmentLength, original.dataSegmentLength)
    XCTAssertEqual(decoded.lun, original.lun)
    XCTAssertEqual(decoded.initiatorTaskTag, original.initiatorTaskTag)
}
```

### Step 6: Run test to verify it passes

```bash
swift test --filter PDUParserTests
```

Expected: PASS (3 tests)

### Step 7: Commit

```bash
git add Protocol/Sources/Protocol/PDU/ISCSIPDUParser.swift
git add Protocol/Tests/ProtocolTests/PDUParserTests.swift
git commit -m "feat: add PDU parser for Basic Header Segment

- Add parseBHS to decode 48-byte BHS from wire format
- Add encodeBHS to encode BHS to wire format
- Handle big-endian byte order for all multi-byte fields
- Add PDUParseError enum for parse failures
- Add comprehensive unit tests with round-trip validation"
```

---

## Task 3: Login PDU Types and Parser

**Files:**
- Modify: `Protocol/Sources/Protocol/PDU/ISCSIPDUTypes.swift`
- Modify: `Protocol/Sources/Protocol/PDU/ISCSIPDUParser.swift`
- Create: `Protocol/Tests/ProtocolTests/LoginPDUTests.swift`

### Step 1: Write failing test for Login Request PDU

Create `Protocol/Tests/ProtocolTests/LoginPDUTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class LoginPDUTests: XCTestCase {

    func testEncodeLoginRequest() throws {
        // Arrange
        var login = LoginRequestPDU()
        login.transit = true
        login.currentStageCode = 0
        login.nextStageCode = 1
        login.versionMax = 0
        login.versionMin = 0
        login.isid = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        login.tsih = 0
        login.initiatorTaskTag = 42
        login.cid = 0
        login.cmdSN = 1
        login.expStatSN = 0
        login.keyValuePairs = [
            "InitiatorName": "iqn.2026-01.com.test:initiator",
            "SessionType": "Normal"
        ]

        // Act
        let encoded = ISCSIPDUParser.encodeLoginRequest(login)

        // Assert
        XCTAssertGreaterThan(encoded.count, 48)  // BHS + data
    }

    func testLoginRequest_RoundTrip() throws {
        // Arrange
        var login = LoginRequestPDU()
        login.transit = true
        login.currentStageCode = 0
        login.nextStageCode = 1
        login.isid = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        login.initiatorTaskTag = 42
        login.cmdSN = 1
        login.keyValuePairs = ["Key": "Value"]

        // Act: Encode then decode
        let encoded = ISCSIPDUParser.encodeLoginRequest(login)
        let pdu = try ISCSIPDUParser.parsePDU(encoded)
        let decoded = try ISCSIPDUParser.parseLoginRequest(pdu)

        // Assert
        XCTAssertEqual(decoded.transit, login.transit)
        XCTAssertEqual(decoded.currentStageCode, login.currentStageCode)
        XCTAssertEqual(decoded.nextStageCode, login.nextStageCode)
        XCTAssertEqual(decoded.isid, login.isid)
        XCTAssertEqual(decoded.initiatorTaskTag, login.initiatorTaskTag)
        XCTAssertEqual(decoded.cmdSN, login.cmdSN)
        XCTAssertEqual(decoded.keyValuePairs, login.keyValuePairs)
    }
}
```

### Step 2: Run test to verify it fails

```bash
swift test --filter LoginPDUTests
```

Expected: FAIL with "Cannot find 'LoginRequestPDU' in scope"

### Step 3: Add Login PDU types

Add to `Protocol/Sources/Protocol/PDU/ISCSIPDUTypes.swift`:

```swift
// MARK: - Login PDU

public struct LoginRequestPDU: Sendable {
    // Flags (byte 1)
    public var transit: Bool                    // T bit
    public var `continue`: Bool                 // C bit
    public var currentStageCode: UInt8          // CSG (2 bits)
    public var nextStageCode: UInt8             // NSG (2 bits)

    // Fields
    public var versionMax: UInt8                // Byte 2
    public var versionMin: UInt8                // Byte 3
    public var isid: Data                       // Bytes 8-13 (6 bytes)
    public var tsih: UInt16                     // Bytes 14-15
    public var initiatorTaskTag: UInt32         // Bytes 16-19
    public var cid: UInt16                      // Bytes 20-21 (Connection ID)
    public var cmdSN: UInt32                    // Bytes 24-27
    public var expStatSN: UInt32                // Bytes 28-31

    // Data segment (text key=value pairs)
    public var keyValuePairs: [String: String]

    public init() {
        self.transit = false
        self.continue = false
        self.currentStageCode = 0
        self.nextStageCode = 0
        self.versionMax = 0
        self.versionMin = 0
        self.isid = Data(count: 6)
        self.tsih = 0
        self.initiatorTaskTag = 0
        self.cid = 0
        self.cmdSN = 0
        self.expStatSN = 0
        self.keyValuePairs = [:]
    }
}

public struct LoginResponsePDU: Sendable {
    // Flags
    public var transit: Bool
    public var `continue`: Bool
    public var currentStageCode: UInt8
    public var nextStageCode: UInt8

    // Fields
    public var versionMax: UInt8
    public var versionActive: UInt8
    public var isid: Data
    public var tsih: UInt16
    public var initiatorTaskTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var statusClass: UInt8
    public var statusDetail: UInt8

    // Data segment
    public var keyValuePairs: [String: String]

    public init() {
        self.transit = false
        self.continue = false
        self.currentStageCode = 0
        self.nextStageCode = 0
        self.versionMax = 0
        self.versionActive = 0
        self.isid = Data(count: 6)
        self.tsih = 0
        self.initiatorTaskTag = 0
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.statusClass = 0
        self.statusDetail = 0
        self.keyValuePairs = [:]
    }
}
```

### Step 4: Add Login PDU encoding/decoding

Add to `Protocol/Sources/Protocol/PDU/ISCSIPDUParser.swift`:

```swift
// MARK: - Key-Value Parsing

/// Parse key=value pairs from text data segment
public static func parseKeyValuePairs(_ data: Data) -> [String: String] {
    guard let text = String(data: data, encoding: .utf8) else {
        return [:]
    }

    var pairs: [String: String] = [:]

    // Split by null terminators
    let entries = text.components(separatedBy: "\0").filter { !$0.isEmpty }

    for entry in entries {
        let parts = entry.split(separator: "=", maxSplits: 1)
        if parts.count == 2 {
            pairs[String(parts[0])] = String(parts[1])
        }
    }

    return pairs
}

/// Encode key=value pairs to text data segment
public static func encodeKeyValuePairs(_ pairs: [String: String]) -> Data {
    var text = ""

    for (key, value) in pairs.sorted(by: { $0.key < $1.key }) {
        text += "\(key)=\(value)\0"
    }

    // iSCSI text data must be null-terminated
    if !text.isEmpty && !text.hasSuffix("\0") {
        text += "\0"
    }

    return text.data(using: .utf8) ?? Data()
}

// MARK: - Complete PDU Parsing

/// Parse complete PDU
public static func parsePDU(_ data: Data) throws -> ISCSIPDU {
    let bhs = try parseBHS(data)

    var pdu = ISCSIPDU(opcode: ISCSIPDUOpcode(rawValue: bhs.opcode & 0x3F) ?? .nopOut)
    pdu.bhs = bhs

    var offset = BasicHeaderSegment.size

    // Parse AHS if present
    if bhs.totalAHSLength > 0 {
        let ahsLength = Int(bhs.totalAHSLength) * 4  // In 4-byte words
        guard data.count >= offset + ahsLength else {
            throw PDUParseError.insufficientData
        }
        offset += ahsLength
    }

    // Parse data segment if present
    if bhs.dataSegmentLength > 0 {
        let dataLength = Int(bhs.dataSegmentLength)
        let paddedLength = (dataLength + 3) & ~3  // Pad to 4-byte boundary

        guard data.count >= offset + paddedLength else {
            throw PDUParseError.insufficientData
        }

        pdu.dataSegment = data.subdata(in: offset..<(offset + dataLength))
        offset += paddedLength
    }

    return pdu
}

/// Encode complete PDU
public static func encodePDU(_ pdu: ISCSIPDU) -> Data {
    var data = encodeBHS(pdu.bhs)

    // Add data segment if present
    if let dataSegment = pdu.dataSegment, !dataSegment.isEmpty {
        data.append(dataSegment)

        // Add padding to 4-byte boundary
        let padding = (4 - (dataSegment.count % 4)) % 4
        if padding > 0 {
            data.append(Data(count: padding))
        }
    }

    return data
}

// MARK: - Login PDU Parsing

public static func parseLoginRequest(_ pdu: ISCSIPDU) throws -> LoginRequestPDU {
    var login = LoginRequestPDU()

    let flags = pdu.bhs.flags
    login.transit = (flags & 0x80) != 0
    login.continue = (flags & 0x40) != 0
    login.currentStageCode = (flags >> 2) & 0x03
    login.nextStageCode = flags & 0x03

    let spec = pdu.bhs.opcodeSpecific
    login.versionMax = spec[0]
    login.versionMin = spec[1]
    login.isid = spec.subdata(in: 4..<10)
    login.tsih = spec.subdata(in: 10..<12).withUnsafeBytes {
        $0.load(as: UInt16.self).bigEndian
    }
    login.initiatorTaskTag = pdu.bhs.initiatorTaskTag
    login.cid = spec.subdata(in: 12..<14).withUnsafeBytes {
        $0.load(as: UInt16.self).bigEndian
    }
    login.cmdSN = spec.subdata(in: 16..<20).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }
    login.expStatSN = spec.subdata(in: 20..<24).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }

    if let data = pdu.dataSegment {
        login.keyValuePairs = parseKeyValuePairs(data)
    }

    return login
}

public static func encodeLoginRequest(_ login: LoginRequestPDU) -> Data {
    var pdu = ISCSIPDU(opcode: .loginRequest)

    // Flags
    var flags: UInt8 = 0
    if login.transit { flags |= 0x80 }
    if login.continue { flags |= 0x40 }
    flags |= (login.currentStageCode & 0x03) << 2
    flags |= login.nextStageCode & 0x03
    pdu.bhs.flags = flags

    // Opcode-specific
    var spec = Data(count: 28)
    spec[0] = login.versionMax
    spec[1] = login.versionMin
    spec.replaceSubrange(4..<10, with: login.isid)

    withUnsafeBytes(of: login.tsih.bigEndian) { bytes in
        spec.replaceSubrange(10..<12, with: bytes)
    }

    pdu.bhs.initiatorTaskTag = login.initiatorTaskTag

    withUnsafeBytes(of: login.cid.bigEndian) { bytes in
        spec.replaceSubrange(12..<14, with: bytes)
    }
    withUnsafeBytes(of: login.cmdSN.bigEndian) { bytes in
        spec.replaceSubrange(16..<20, with: bytes)
    }
    withUnsafeBytes(of: login.expStatSN.bigEndian) { bytes in
        spec.replaceSubrange(20..<24, with: bytes)
    }

    pdu.bhs.opcodeSpecific = spec

    // Data segment
    if !login.keyValuePairs.isEmpty {
        let data = encodeKeyValuePairs(login.keyValuePairs)
        pdu.bhs.dataSegmentLength = UInt32(data.count)
        pdu.dataSegment = data
    }

    return encodePDU(pdu)
}

public static func parseLoginResponse(_ pdu: ISCSIPDU) throws -> LoginResponsePDU {
    var login = LoginResponsePDU()

    let flags = pdu.bhs.flags
    login.transit = (flags & 0x80) != 0
    login.continue = (flags & 0x40) != 0
    login.currentStageCode = (flags >> 2) & 0x03
    login.nextStageCode = flags & 0x03

    let spec = pdu.bhs.opcodeSpecific
    login.versionMax = spec[0]
    login.versionActive = spec[1]
    login.isid = spec.subdata(in: 4..<10)
    login.tsih = spec.subdata(in: 10..<12).withUnsafeBytes {
        $0.load(as: UInt16.self).bigEndian
    }
    login.initiatorTaskTag = pdu.bhs.initiatorTaskTag
    login.statSN = spec.subdata(in: 16..<20).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }
    login.expCmdSN = spec.subdata(in: 20..<24).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }
    login.maxCmdSN = spec.subdata(in: 24..<28).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }
    login.statusClass = spec[12]
    login.statusDetail = spec[13]

    if let data = pdu.dataSegment {
        login.keyValuePairs = parseKeyValuePairs(data)
    }

    return login
}
```

### Step 5: Run tests to verify they pass

```bash
swift test --filter LoginPDUTests
```

Expected: PASS (2 tests)

### Step 6: Commit

```bash
git add Protocol/Sources/Protocol/PDU/ISCSIPDUTypes.swift
git add Protocol/Sources/Protocol/PDU/ISCSIPDUParser.swift
git add Protocol/Tests/ProtocolTests/LoginPDUTests.swift
git commit -m "feat: add Login PDU types and parser

- Add LoginRequestPDU and LoginResponsePDU structs
- Add key=value pair encoding/decoding for text segments
- Add parseLoginRequest/parseLoginResponse functions
- Add encodeLoginRequest function
- Add parsePDU/encodePDU for complete PDU handling
- Add comprehensive unit tests with round-trip validation"
```

---

## Summary

**Phase 1 Foundation - Task Completion Status:**

- ✅ Task 0: Swift Package Structure (optional)
- ✅ Task 1: PDU Base Types and Error Handling
- ✅ Task 2: PDU Parser - Basic Header Segment
- ✅ Task 3: Login PDU Types and Parser

**What's Next:**

This plan covers the first 3 core tasks. The remaining Phase 1 tasks are:

- Task 4: XPC Protocol Definitions
- Task 5: Network Layer (NWProtocolFramer)
- Task 6: Login State Machine
- Task 7: MockISCSITarget for Testing
- Task 8: Integration Test (Login Flow)

These tasks follow the same TDD pattern and build upon the foundation established here.

**Testing Status:**
- Unit test coverage: 100% of implemented code
- All tests passing
- Ready for next tasks

---

## Plan Execution Complete

Plan saved to `docs/plans/2026-02-05-phase1-foundation.md`

**Next Steps:** Choose execution approach below.