# Testing & Validation Guide
## iSCSI Initiator for macOS

**Version:** 1.0
**Date:** 5. Februar 2026
**Purpose:** Comprehensive testing and validation strategy for all project components

---

## Table of Contents

1. [Overview](#1-overview)
2. [Unit Testing](#2-unit-testing)
3. [Mock Infrastructure](#3-mock-infrastructure)
4. [Integration Testing](#4-integration-testing)
5. [System Integration Testing](#5-system-integration-testing)
6. [Interoperability Testing](#6-interoperability-testing)
7. [Performance Testing](#7-performance-testing)
8. [CI/CD Pipeline](#8-cicd-pipeline)
9. [Manual Test Procedures](#9-manual-test-procedures)

---

## 1. Overview

### 1.1 Testing Strategy

The testing strategy follows the test pyramid:

```
        ┌─────────────────┐
        │  Manual E2E     │  ← Smallest number of tests
        │  (5%)           │
        ├─────────────────┤
        │  Integration    │  ← Medium number of tests
        │  (25%)          │
        ├─────────────────┤
        │  Unit Tests     │  ← Largest number of tests
        │  (70%)          │
        └─────────────────┘
```

### 1.2 Test Levels

| Level | Scope | Tools | Automation |
|-------|-------|-------|------------|
| **Unit** | Individual classes/functions | XCTest | ✅ CI |
| **Integration** | Component interactions | XCTest + MockISCSITarget | ✅ CI |
| **System** | DriverKit + Daemon + GUI | Manual + Scripts | ⚠️ Partial |
| **Interoperability** | Real iSCSI targets | FIO, iperf3 | ⚠️ Partial |
| **Performance** | Throughput, latency | FIO, custom tools | ⚠️ Baseline |
| **Manual** | User workflows | Test checklists | ❌ Manual |

### 1.3 Quality Gates

Code cannot be merged until:
- ✅ All unit tests pass
- ✅ Code coverage ≥ 70%
- ✅ Integration tests pass with MockISCSITarget
- ✅ At least one real target test passes (Synology or TrueNAS)
- ✅ No compiler warnings
- ✅ SwiftLint/SwiftFormat checks pass

---

## 2. Unit Testing

### 2.1 Test Structure

All unit tests use XCTest framework and follow this structure:

```
Tests/
├── ProtocolTests/
│   ├── PDUParserTests.swift
│   ├── CHAPAuthenticatorTests.swift
│   └── SequenceNumberTests.swift
├── NetworkTests/
│   ├── FramerTests.swift
│   └── ConnectionTests.swift
└── SessionTests/
    ├── LoginStateMachineTests.swift
    └── SessionManagerTests.swift
```

### 2.2 PDU Parser Tests

Create `Protocol/Tests/PDUParserTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class PDUParserTests: XCTestCase {

    // MARK: - BHS Parsing

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
            XCTAssertTrue(error is PDUParseError)
        }
    }

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

    // MARK: - Login PDU Tests

    func testParseLoginRequest() throws {
        // Arrange: Build login request
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
            "SessionType": "Normal",
            "AuthMethod": "None"
        ]

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

    func testParseKeyValuePairs() {
        // Arrange
        let text = "Key1=Value1\0Key2=Value2\0Key3=Value3\0"
        let data = text.data(using: .utf8)!

        // Act
        let pairs = ISCSIPDUParser.parseKeyValuePairs(data)

        // Assert
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs["Key1"], "Value1")
        XCTAssertEqual(pairs["Key2"], "Value2")
        XCTAssertEqual(pairs["Key3"], "Value3")
    }

    func testEncodeKeyValuePairs() {
        // Arrange
        let pairs = [
            "InitiatorName": "iqn.2026-01.com.test:initiator",
            "TargetName": "iqn.2026-01.com.target:disk1",
            "SessionType": "Normal"
        ]

        // Act
        let data = ISCSIPDUParser.encodeKeyValuePairs(pairs)
        let decoded = ISCSIPDUParser.parseKeyValuePairs(data)

        // Assert
        XCTAssertEqual(decoded, pairs)
    }

    // MARK: - SCSI Command PDU Tests

    func testSCSICommandPDU() {
        // TODO: Implement SCSI command PDU tests
        // - Test READ(10) command encoding
        // - Test WRITE(10) command encoding
        // - Test INQUIRY command encoding
    }
}
```

### 2.3 CHAP Authenticator Tests

Create `Protocol/Tests/CHAPAuthenticatorTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class CHAPAuthenticatorTests: XCTestCase {

    func testCHAPResponseMD5() async {
        // Arrange
        let authenticator = CHAPAuthenticator()
        let identifier: UInt8 = 5
        let secret = "my_secret"
        let challenge = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

        // Act
        let response = await authenticator.computeResponse(
            identifier: identifier,
            secret: secret,
            challenge: challenge,
            algorithm: .md5
        )

        // Assert
        XCTAssertEqual(response.count, 16)  // MD5 = 16 bytes
        XCTAssertNotEqual(response, Data(count: 16))  // Should not be all zeros

        // Verify deterministic (same inputs = same output)
        let response2 = await authenticator.computeResponse(
            identifier: identifier,
            secret: secret,
            challenge: challenge,
            algorithm: .md5
        )
        XCTAssertEqual(response, response2)
    }

    func testCHAPResponseSHA256() async {
        // Arrange
        let authenticator = CHAPAuthenticator()
        let identifier: UInt8 = 7
        let secret = "another_secret"
        let challenge = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])

        // Act
        let response = await authenticator.computeResponse(
            identifier: identifier,
            secret: secret,
            challenge: challenge,
            algorithm: .sha256
        )

        // Assert
        XCTAssertEqual(response.count, 32)  // SHA-256 = 32 bytes
    }

    func testParseCHAPChallenge() async {
        // Arrange
        let authenticator = CHAPAuthenticator()
        let keyValuePairs = [
            "CHAP_A": "5",  // MD5
            "CHAP_I": "42",
            "CHAP_C": "0x0102030405060708"
        ]

        // Act
        let result = await authenticator.parseCHAPChallenge(keyValuePairs)

        // Assert
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.algorithm, .md5)
        XCTAssertEqual(result?.identifier, 42)
        XCTAssertEqual(result?.challenge, Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
    }

    func testBuildCHAPResponse() async {
        // Arrange
        let authenticator = CHAPAuthenticator()
        let identifier: UInt8 = 10
        let secret = "test_secret"
        let challenge = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let name = "test_initiator"

        // Act
        let result = await authenticator.buildCHAPResponse(
            identifier: identifier,
            secret: secret,
            challenge: challenge,
            name: name,
            algorithm: .md5
        )

        // Assert
        XCTAssertEqual(result["CHAP_N"], name)
        XCTAssertNotNil(result["CHAP_R"])
        XCTAssertTrue(result["CHAP_R"]!.hasPrefix("0x"))
    }
}
```

### 2.4 Sequence Number Tests

Create `Protocol/Tests/SequenceNumberTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class SequenceNumberTests: XCTestCase {

    func testSequenceNumberIncrement() async {
        // Arrange
        let manager = SequenceNumberManager()

        // Act
        let sn1 = await manager.nextCmdSN()
        let sn2 = await manager.nextCmdSN()
        let sn3 = await manager.nextCmdSN()

        // Assert
        XCTAssertEqual(sn1, 0)
        XCTAssertEqual(sn2, 1)
        XCTAssertEqual(sn3, 2)
    }

    func testSequenceNumberWrapAround() async {
        // Arrange
        let manager = SequenceNumberManager()

        // Set to near wrap point
        await manager.setCmdSN(UInt32.max - 1)

        // Act
        let sn1 = await manager.nextCmdSN()
        let sn2 = await manager.nextCmdSN()
        let sn3 = await manager.nextCmdSN()

        // Assert: Should wrap around to 0
        XCTAssertEqual(sn1, UInt32.max - 1)
        XCTAssertEqual(sn2, UInt32.max)
        XCTAssertEqual(sn3, 0)  // Wrapped
    }

    func testSequenceNumberWindow() async {
        // Arrange
        let manager = SequenceNumberManager()

        // Act: Update window
        await manager.updateWindow(expCmdSN: 5, maxCmdSN: 10)

        // Assert: Check if window is valid
        let canSend = await manager.canSendCommand()
        XCTAssertTrue(canSend)

        // Set CmdSN beyond window
        await manager.setCmdSN(11)
        let cannotSend = await manager.canSendCommand()
        XCTAssertFalse(cannotSend)
    }
}

// Mock SequenceNumberManager for testing
actor SequenceNumberManager {
    private var cmdSN: UInt32 = 0
    private var expCmdSN: UInt32 = 0
    private var maxCmdSN: UInt32 = 0

    func nextCmdSN() -> UInt32 {
        let current = cmdSN
        cmdSN = cmdSN &+ 1  // Wrapping addition
        return current
    }

    func setCmdSN(_ value: UInt32) {
        cmdSN = value
    }

    func updateWindow(expCmdSN: UInt32, maxCmdSN: UInt32) {
        self.expCmdSN = expCmdSN
        self.maxCmdSN = maxCmdSN
    }

    func canSendCommand() -> Bool {
        // RFC 1982 serial number arithmetic
        let diff = Int32(bitPattern: cmdSN &- expCmdSN)
        return diff >= 0 && cmdSN <= maxCmdSN
    }
}
```

---

## 3. Mock Infrastructure

### 3.1 MockISCSITarget

Create `Tests/Mocks/MockISCSITarget.swift`:

```swift
import Foundation
import Network
@testable import ISCSIProtocol

/// Mock iSCSI target for testing (runs locally)
actor MockISCSITarget {

    let port: UInt16
    let targetIQN: String
    let authMode: AuthMode

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    enum AuthMode {
        case none
        case chapUnidirectional(secret: String)
        case chapBidirectional(initiatorSecret: String, targetSecret: String)
    }

    init(
        port: UInt16 = 13260,
        targetIQN: String = "iqn.2026-01.com.test:mock-target",
        authMode: AuthMode = .none
    ) {
        self.port = port
        self.targetIQN = targetIQN
        self.authMode = authMode
    }

    func start() throws {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))

        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleNewConnection(connection)
            }
        }

        let queue = DispatchQueue(label: "com.opensource.iscsi.mock-target")
        listener.start(queue: queue)

        self.listener = listener
        print("MockISCSITarget listening on port \(port)")
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connections.append(connection)

        print("MockISCSITarget: New connection")

        // Start receiving
        receiveNextPDU(on: connection)
    }

    private func receiveNextPDU(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 48, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            Task {
                if let data = data, !data.isEmpty {
                    await self?.handlePDU(data, on: connection)
                }

                if let error = error {
                    print("MockISCSITarget: Receive error: \(error)")
                    return
                }

                // Continue receiving
                await self?.receiveNextPDU(on: connection)
            }
        }
    }

    private func handlePDU(_ data: Data, on connection: NWConnection) {
        do {
            let pdu = try ISCSIPDUParser.parsePDU(data)
            let opcode = ISCSIPDUOpcode(rawValue: pdu.bhs.opcode & 0x3F)

            switch opcode {
            case .loginRequest:
                let response = handleLoginRequest(pdu)
                let responseData = ISCSIPDUParser.encodePDU(response)
                sendPDU(responseData, on: connection)

            case .textRequest:
                let response = handleTextRequest(pdu)
                let responseData = ISCSIPDUParser.encodePDU(response)
                sendPDU(responseData, on: connection)

            case .logoutRequest:
                let response = handleLogoutRequest(pdu)
                let responseData = ISCSIPDUParser.encodePDU(response)
                sendPDU(responseData, on: connection)

            case .scsiCommand:
                let response = handleSCSICommand(pdu)
                let responseData = ISCSIPDUParser.encodePDU(response)
                sendPDU(responseData, on: connection)

            case .nopOut:
                let response = handleNOPOut(pdu)
                let responseData = ISCSIPDUParser.encodePDU(response)
                sendPDU(responseData, on: connection)

            default:
                print("MockISCSITarget: Unhandled opcode: \(opcode?.rawValue ?? 0)")
            }
        } catch {
            print("MockISCSITarget: Parse error: \(error)")
        }
    }

    private func sendPDU(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("MockISCSITarget: Send error: \(error)")
            }
        })
    }

    // MARK: - PDU Handlers

    private func handleLoginRequest(_ pdu: ISCSIPDU) -> ISCSIPDU {
        // Parse login request
        guard let request = try? ISCSIPDUParser.parseLoginRequest(pdu) else {
            return createLoginResponse(
                initiatorTaskTag: pdu.bhs.initiatorTaskTag,
                statusClass: 0x02,  // Initiator error
                statusDetail: 0x00
            )
        }

        // Build successful response
        var responsePDU = ISCSIPDU(opcode: .loginResponse)
        responsePDU.bhs.flags = request.transit ? 0x80 : 0x00
        responsePDU.bhs.flags |= (request.currentStageCode & 0x03) << 2
        responsePDU.bhs.flags |= request.nextStageCode & 0x03

        var spec = Data(count: 28)
        spec[0] = 0  // VersionMax
        spec[1] = 0  // VersionActive
        spec.replaceSubrange(4..<10, with: request.isid)

        // Assign TSIH (session ID)
        let tsih: UInt16 = request.tsih == 0 ? 1 : request.tsih
        withUnsafeBytes(of: tsih.bigEndian) { bytes in
            spec.replaceSubrange(10..<12, with: bytes)
        }

        responsePDU.bhs.initiatorTaskTag = request.initiatorTaskTag
        responsePDU.bhs.opcodeSpecific = spec

        // Add response key-value pairs
        var responseParams: [String: String] = [
            "TargetName": targetIQN,
            "TargetAlias": "Mock iSCSI Target",
            "TargetPortalGroupTag": "1"
        ]

        // Handle auth
        switch authMode {
        case .none:
            responseParams["AuthMethod"] = "None"
        case .chapUnidirectional:
            responseParams["AuthMethod"] = "CHAP"
            // TODO: Send CHAP challenge
        case .chapBidirectional:
            responseParams["AuthMethod"] = "CHAP"
            // TODO: Send CHAP challenge
        }

        if request.transit && request.nextStageCode == 3 {
            // Moving to full feature phase
            responseParams["MaxRecvDataSegmentLength"] = "65536"
            responseParams["HeaderDigest"] = "None"
            responseParams["DataDigest"] = "None"
        }

        let responseData = ISCSIPDUParser.encodeKeyValuePairs(responseParams)
        responsePDU.bhs.dataSegmentLength = UInt32(responseData.count)
        responsePDU.dataSegment = responseData

        return responsePDU
    }

    private func createLoginResponse(
        initiatorTaskTag: UInt32,
        statusClass: UInt8,
        statusDetail: UInt8
    ) -> ISCSIPDU {
        var pdu = ISCSIPDU(opcode: .loginResponse)
        pdu.bhs.initiatorTaskTag = initiatorTaskTag

        var spec = Data(count: 28)
        spec[12] = statusClass
        spec[13] = statusDetail
        pdu.bhs.opcodeSpecific = spec

        return pdu
    }

    private func handleTextRequest(_ pdu: ISCSIPDU) -> ISCSIPDU {
        // TODO: Handle SendTargets discovery
        var response = ISCSIPDU(opcode: .textResponse)
        response.bhs.initiatorTaskTag = pdu.bhs.initiatorTaskTag
        response.bhs.flags = 0x80  // Final

        let responseParams = [
            "TargetName": targetIQN,
            "TargetAddress": "127.0.0.1:\(port),1"
        ]

        let responseData = ISCSIPDUParser.encodeKeyValuePairs(responseParams)
        response.bhs.dataSegmentLength = UInt32(responseData.count)
        response.dataSegment = responseData

        return response
    }

    private func handleLogoutRequest(_ pdu: ISCSIPDU) -> ISCSIPDU {
        var response = ISCSIPDU(opcode: .logoutResponse)
        response.bhs.initiatorTaskTag = pdu.bhs.initiatorTaskTag

        var spec = Data(count: 28)
        spec[0] = 0  // Response: success
        response.bhs.opcodeSpecific = spec

        return response
    }

    private func handleSCSICommand(_ pdu: ISCSIPDU) -> ISCSIPDU {
        // Mock SCSI response (always success)
        var response = ISCSIPDU(opcode: .scsiResponse)
        response.bhs.initiatorTaskTag = pdu.bhs.initiatorTaskTag

        var spec = Data(count: 28)
        spec[0] = 0x00  // Response: command completed at target
        spec[1] = 0x00  // Status: GOOD
        response.bhs.opcodeSpecific = spec

        return response
    }

    private func handleNOPOut(_ pdu: ISCSIPDU) -> ISCSIPDU {
        // Echo back NOP-In
        var response = ISCSIPDU(opcode: .nopIn)
        response.bhs.initiatorTaskTag = pdu.bhs.initiatorTaskTag
        response.dataSegment = pdu.dataSegment
        if let data = pdu.dataSegment {
            response.bhs.dataSegmentLength = UInt32(data.count)
        }

        return response
    }
}
```

### 3.2 MockTransport

Create `Tests/Mocks/MockTransport.swift`:

```swift
import Foundation
@testable import ISCSIProtocol

/// Mock transport for unit testing (no network)
actor MockTransport: ISCSITransport {

    private(set) var sentData: [Data] = []
    private var responseQueue: [Data] = []

    func enqueueResponse(_ pdu: Data) {
        responseQueue.append(pdu)
    }

    func enqueueResponses(_ pdus: [Data]) {
        responseQueue.append(contentsOf: pdus)
    }

    func send(_ data: Data) async throws {
        sentData.append(data)
    }

    func receive() async throws -> Data {
        guard !responseQueue.isEmpty else {
            throw ISCSIError.connectionTimeout
        }
        return responseQueue.removeFirst()
    }

    func close() async {
        sentData.removeAll()
        responseQueue.removeAll()
    }

    // Test helpers
    func getSentPDUCount() -> Int {
        return sentData.count
    }

    func getLastSentPDU() -> Data? {
        return sentData.last
    }

    func clearSent() {
        sentData.removeAll()
    }
}
```

---

## 4. Integration Testing

### 4.1 Login Flow Test

Create `Tests/IntegrationTests/LoginFlowTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class LoginFlowTests: XCTestCase {

    var mockTarget: MockISCSITarget!

    override func setUp() async throws {
        mockTarget = MockISCSITarget()
        try mockTarget.start()
    }

    override func tearDown() async throws {
        await mockTarget.stop()
    }

    func testSuccessfulLogin() async throws {
        // Arrange
        let connection = ISCSIConnection(host: "127.0.0.1", port: 13260)
        try await connection.connect()

        let isid = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let loginSM = LoginStateMachine(isid: isid)

        // Act
        try await loginSM.startLogin(connection: connection)

        // Assert
        let state = await loginSM.currentState
        switch state {
        case .fullFeaturePhase:
            break  // Success
        default:
            XCTFail("Expected fullFeaturePhase, got \(state)")
        }

        connection.disconnect()
    }

    func testLoginWithInvalidTarget() async {
        // Arrange: Connect to non-existent target
        let connection = ISCSIConnection(host: "127.0.0.1", port: 9999)  // Wrong port

        // Act & Assert
        do {
            try await connection.connect()
            XCTFail("Should have thrown connection error")
        } catch {
            // Expected
        }
    }
}
```

### 4.2 Discovery Test

Create `Tests/IntegrationTests/DiscoveryTests.swift`:

```swift
import XCTest
@testable import ISCSIProtocol

final class DiscoveryTests: XCTestCase {

    var mockTarget: MockISCSITarget!

    override func setUp() async throws {
        mockTarget = MockISCSITarget(
            port: 13260,
            targetIQN: "iqn.2026-01.com.test:disk1"
        )
        try mockTarget.start()
    }

    override func tearDown() async throws {
        await mockTarget.stop()
    }

    func testSendTargetsDiscovery() async throws {
        // Arrange
        let manager = ISCSISessionManager()

        // Act
        let targets = try await manager.discoverTargets(portal: "127.0.0.1:13260")

        // Assert
        XCTAssertFalse(targets.isEmpty)
        XCTAssertTrue(targets.contains { $0.iqn.contains("iqn.2026-01.com.test:disk1") })
    }
}
```

---

## 5. System Integration Testing

### 5.1 DriverKit Extension Loading

Create script `Tests/SystemTests/test-dext-loading.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "Testing DriverKit Extension Loading..."

# Build project
xcodebuild -scheme "iSCSI Initiator" -configuration Debug build

# Find build products
BUILD_DIR=$(xcodebuild -showBuildSettings -scheme "iSCSI Initiator" | grep " BUILD_DIR" | sed 's/.*= //')
APP_PATH="$BUILD_DIR/iSCSI Initiator.app"

echo "App path: $APP_PATH"

# Check if dext exists
DEXT_PATH="$APP_PATH/Contents/SystemExtensions/iSCSIVirtualHBA.dext"
if [ ! -d "$DEXT_PATH" ]; then
    echo "❌ DriverKit extension not found at: $DEXT_PATH"
    exit 1
fi

echo "✅ DriverKit extension found"

# Check code signature
codesign -dvvv "$DEXT_PATH" 2>&1 | grep "Authority=Developer ID Application" && echo "✅ Signed correctly" || {
    echo "⚠️ Not signed with Developer ID (development signing OK for testing)"
}

# Enable developer mode for system extensions
echo "Enabling developer mode..."
systemextensionsctl developer on

# TODO: Attempt to load extension (requires user approval)
# open "$APP_PATH"

echo "✅ DriverKit extension ready for loading"
echo "To test loading, run the app and approve the system extension"
```

### 5.2 Block Device Appearance Test

```bash
#!/bin/bash
# Tests/SystemTests/test-block-device.sh

echo "Testing block device appearance..."

# Prerequisites: iSCSI session must be logged in

# Wait for block device
echo "Waiting for block device to appear..."
for i in {1..30}; do
    if diskutil list | grep -q "iSCSI"; then
        echo "✅ Block device appeared"
        diskutil list | grep "iSCSI"
        exit 0
    fi
    sleep 1
done

echo "❌ Block device did not appear within 30 seconds"
exit 1
```

---

## 6. Interoperability Testing

### 6.1 Test Matrix

Test against these targets:

| Target | Model | Auth | Priority |
|--------|-------|------|----------|
| Synology DSM | DS923+ | CHAP | High |
| QNAP QTS | TS-464 | CHAP | High |
| TrueNAS SCALE | 24.x | None/CHAP | High |
| Linux LIO | Ubuntu 22.04 | None/CHAP | Medium |
| Windows iSCSI | Server 2022 | None/CHAP | Medium |

### 6.2 Baseline Test Script

Create `Tests/InteropTests/baseline-test.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
TARGET_IP="${TARGET_IP:-192.168.1.10}"
TARGET_IQN="${TARGET_IQN:-iqn.2024-01.com.test:disk1}"
TARGET_PORT="${TARGET_PORT:-3260}"
TEST_VOLUME="/Volumes/ISCSI_TEST"
RUNTIME=300  # 5 minutes

echo "=== iSCSI Interoperability Baseline Test ==="
echo "Target: $TARGET_IQN @ $TARGET_IP:$TARGET_PORT"
echo

# Step 1: Discovery
echo "Step 1: Discovery..."
./iscsiadm discover -p "$TARGET_IP:$TARGET_PORT" || {
    echo "❌ Discovery failed"
    exit 1
}
echo "✅ Discovery successful"
echo

# Step 2: Login
echo "Step 2: Login..."
./iscsiadm login -t "$TARGET_IQN" -p "$TARGET_IP:$TARGET_PORT" || {
    echo "❌ Login failed"
    exit 1
}
echo "✅ Login successful"
echo

# Step 3: Wait for block device
echo "Step 3: Waiting for block device..."
sleep 5

if [ ! -d "$TEST_VOLUME" ]; then
    echo "❌ Volume not mounted at $TEST_VOLUME"
    exit 1
fi
echo "✅ Volume mounted"
echo

# Step 4: I/O Test with FIO
echo "Step 4: Running FIO I/O tests..."

# 4K random read
echo "  - 4K random read..."
fio --name=randread_4k \
    --filename="$TEST_VOLUME/fio-test.bin" \
    --rw=randread \
    --bs=4k \
    --iodepth=32 \
    --numjobs=4 \
    --size=1G \
    --time_based \
    --runtime=$RUNTIME \
    --direct=1 \
    --group_reporting \
    --output-format=json \
    --output=fio-randread-4k.json

# 1M sequential read
echo "  - 1M sequential read..."
fio --name=seqread_1m \
    --filename="$TEST_VOLUME/fio-test.bin" \
    --rw=read \
    --bs=1m \
    --iodepth=8 \
    --numjobs=1 \
    --size=2G \
    --time_based \
    --runtime=$RUNTIME \
    --direct=1 \
    --group_reporting \
    --output-format=json \
    --output=fio-seqread-1m.json

echo "✅ I/O tests completed"
echo

# Step 5: Session stability (keep alive for 60 minutes idle + 60 minutes I/O)
echo "Step 5: Session stability test (60 min idle + 60 min I/O)..."
echo "  Idle for 60 minutes..."
sleep 3600

echo "  I/O for 60 minutes..."
fio --name=stability \
    --filename="$TEST_VOLUME/fio-stability.bin" \
    --rw=randrw \
    --bs=64k \
    --iodepth=16 \
    --numjobs=2 \
    --size=10G \
    --time_based \
    --runtime=3600 \
    --direct=1 \
    --group_reporting

echo "✅ Stability test passed"
echo

# Step 6: Logout
echo "Step 6: Logout..."
./iscsiadm logout -t "$TARGET_IQN" -p "$TARGET_IP:$TARGET_PORT"
echo "✅ Logout successful"

echo
echo "=== All tests passed ==="
```

---

## 7. Performance Testing

### 7.1 Throughput Benchmarks

Create `Tests/PerformanceTests/throughput-test.sh`:

```bash
#!/bin/bash
set -euo pipefail

TARGET_VOLUME="/Volumes/ISCSI_TEST"
RESULTS_DIR="./performance-results"
mkdir -p "$RESULTS_DIR"

echo "=== iSCSI Performance Benchmarks ==="

# Sequential read
echo "Sequential read (1M block size)..."
fio --name=seq_read \
    --filename="$TARGET_VOLUME/perf-test.bin" \
    --rw=read \
    --bs=1m \
    --iodepth=8 \
    --numjobs=1 \
    --size=10G \
    --runtime=60 \
    --time_based \
    --direct=1 \
    --output="$RESULTS_DIR/seq_read.json" \
    --output-format=json

# Sequential write
echo "Sequential write (1M block size)..."
fio --name=seq_write \
    --filename="$TARGET_VOLUME/perf-test.bin" \
    --rw=write \
    --bs=1m \
    --iodepth=8 \
    --numjobs=1 \
    --size=10G \
    --runtime=60 \
    --time_based \
    --direct=1 \
    --output="$RESULTS_DIR/seq_write.json" \
    --output-format=json

# Random read (4K)
echo "Random read (4K block size)..."
fio --name=rand_read \
    --filename="$TARGET_VOLUME/perf-test.bin" \
    --rw=randread \
    --bs=4k \
    --iodepth=32 \
    --numjobs=4 \
    --size=5G \
    --runtime=60 \
    --time_based \
    --direct=1 \
    --output="$RESULTS_DIR/rand_read.json" \
    --output-format=json

# Random write (4K)
echo "Random write (4K block size)..."
fio --name=rand_write \
    --filename="$TARGET_VOLUME/perf-test.bin" \
    --rw=randwrite \
    --bs=4k \
    --iodepth=32 \
    --numjobs=4 \
    --size=5G \
    --runtime=60 \
    --time_based \
    --direct=1 \
    --output="$RESULTS_DIR/rand_write.json" \
    --output-format=json

echo
echo "✅ Performance tests completed"
echo "Results saved to: $RESULTS_DIR"
```

### 7.2 Latency Benchmarks

```bash
#!/bin/bash
# Tests/PerformanceTests/latency-test.sh

TARGET_VOLUME="/Volumes/ISCSI_TEST"

echo "=== iSCSI Latency Benchmarks ==="

# Low queue depth for latency measurement
fio --name=latency \
    --filename="$TARGET_VOLUME/latency-test.bin" \
    --rw=randread \
    --bs=4k \
    --iodepth=1 \
    --numjobs=1 \
    --size=1G \
    --runtime=60 \
    --time_based \
    --direct=1 \
    --output-format=normal \
    --lat_percentiles=1 \
    --percentile_list=50:90:95:99:99.9

echo "✅ Latency test completed"
```

---

## 8. CI/CD Pipeline

### 8.1 GitHub Actions Workflow

Create `.github/workflows/build-and-test.yml`:

```yaml
name: Build and Test

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: macos-14  # macOS Sonoma

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode version
      run: sudo xcode-select -s /Applications/Xcode_16.0.app

    - name: Build all targets
      run: |
        xcodebuild clean build \
          -scheme "iSCSI Initiator" \
          -configuration Debug \
          -destination 'platform=macOS' \
          CODE_SIGN_IDENTITY="" \
          CODE_SIGNING_REQUIRED=NO

    - name: Run unit tests
      run: |
        xcodebuild test \
          -scheme "iSCSI Initiator" \
          -configuration Debug \
          -destination 'platform=macOS' \
          -enableCodeCoverage YES \
          CODE_SIGN_IDENTITY="" \
          CODE_SIGNING_REQUIRED=NO

    - name: Generate code coverage report
      run: |
        xcrun llvm-cov export -format="lcov" \
          .build/debug/iSCSIProtocolPackageTests.xctest/Contents/MacOS/iSCSIProtocolPackageTests \
          -instr-profile .build/debug/codecov/default.profdata \
          > coverage.lcov

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        files: ./coverage.lcov
        fail_ci_if_error: false

    - name: SwiftLint
      run: |
        brew install swiftlint
        swiftlint --strict

  integration-test:
    runs-on: macos-14
    needs: build

    steps:
    - uses: actions/checkout@v4

    - name: Build project
      run: |
        xcodebuild build \
          -scheme "iSCSI Initiator" \
          -configuration Debug

    - name: Start MockISCSITarget
      run: |
        # TODO: Launch mock target in background
        # ./Tests/Mocks/run-mock-target.sh &

    - name: Run integration tests
      run: |
        # TODO: Run integration test suite
        # ./Tests/IntegrationTests/run-all.sh
        echo "Integration tests pending MockISCSITarget"
```

---

## 9. Manual Test Procedures

### 9.1 Pre-Release Checklist

Before releasing a new version:

- [ ] All unit tests pass locally
- [ ] All integration tests pass
- [ ] Tested against at least 3 real iSCSI targets
- [ ] GUI app launches successfully
- [ ] CLI tool works for all commands
- [ ] Daemon starts and responds to XPC
- [ ] DriverKit extension loads without errors
- [ ] Block devices appear in Disk Utility
- [ ] Volumes mount successfully
- [ ] Read/write operations work
- [ ] Sleep/wake cycle recovers correctly
- [ ] Logout cleans up all resources
- [ ] No memory leaks (Instruments check)
- [ ] Code coverage ≥ 70%
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Version numbers bumped

### 9.2 User Acceptance Test Scenarios

#### Scenario 1: First-Time User

1. Download and install DMG
2. Launch app
3. System prompts for extension approval
4. User approves extension
5. App shows empty session list
6. Click "Discover" button
7. Enter portal address
8. Targets discovered
9. Click "Login" on a target
10. Session appears in list as "Connected"
11. Volume appears in Finder
12. User can read/write files

#### Scenario 2: Auto-Connect

1. User has existing session
2. Enable "Auto-connect at login"
3. Reboot Mac
4. User logs in
5. Daemon automatically connects to target
6. Volume mounts without user intervention

#### Scenario 3: Network Interruption

1. User has active session
2. Disconnect network cable or disable Wi-Fi
3. App shows "Connection Lost" status
4. Reconnect network
5. Session automatically recovers
6. I/O resumes without data loss

---

## Conclusion

This testing strategy ensures:
- ✅ High code quality through unit tests
- ✅ Component integration through integration tests
- ✅ Real-world compatibility through interoperability tests
- ✅ Performance baselines through benchmarking
- ✅ Continuous quality through CI/CD
- ✅ User satisfaction through manual testing

**Next document:** [Deployment & Distribution Guide](deployment-distribution-guide.md)