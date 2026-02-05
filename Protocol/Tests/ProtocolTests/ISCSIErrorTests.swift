import XCTest
@testable import ISCSIProtocol

final class ISCSIErrorTests: XCTestCase {

    // Test all connection errors
    func testConnectionErrors() {
        let notConnected = ISCSIError.notConnected
        XCTAssertEqual(notConnected.errorDescription, "Not connected to target")

        let alreadyConnected = ISCSIError.alreadyConnected
        XCTAssertEqual(alreadyConnected.errorDescription, "Already connected")

        let timeout = ISCSIError.connectionTimeout
        XCTAssertEqual(timeout.errorDescription, "Connection timeout")

        let failed = ISCSIError.connectionFailed(NSError(domain: "test", code: 1))
        XCTAssertNotNil(failed.errorDescription)
        XCTAssertTrue(failed.errorDescription!.contains("Connection failed"))

        let daemonNotConnected = ISCSIError.daemonNotConnected
        XCTAssertEqual(daemonNotConnected.errorDescription, "Daemon not connected")
    }

    // Test all protocol errors
    func testProtocolErrors() {
        let invalidPDU = ISCSIError.invalidPDU
        XCTAssertEqual(invalidPDU.errorDescription, "Invalid PDU received")

        let invalidState = ISCSIError.invalidState
        XCTAssertEqual(invalidState.errorDescription, "Invalid state for operation")

        let loginFailed = ISCSIError.loginFailed(statusClass: 2, statusDetail: 5)
        XCTAssertEqual(loginFailed.errorDescription, "Login failed: class=2 detail=5")

        let invalidStage = ISCSIError.invalidLoginStage(current: 0, next: 3)
        XCTAssertEqual(invalidStage.errorDescription, "Invalid login stage transition: 0 → 3")

        let violation = ISCSIError.protocolViolation("Invalid sequence")
        XCTAssertEqual(violation.errorDescription, "Protocol violation: Invalid sequence")
    }

    // Test session errors
    func testSessionErrors() {
        let notFound = ISCSIError.sessionNotFound
        XCTAssertEqual(notFound.errorDescription, "Session not found")

        let alreadyExists = ISCSIError.sessionAlreadyExists
        XCTAssertEqual(alreadyExists.errorDescription, "Session already exists")

        let targetNotFound = ISCSIError.targetNotFound
        XCTAssertEqual(targetNotFound.errorDescription, "Target not found")
    }

    // Test authentication errors
    func testAuthenticationErrors() {
        let authFailed = ISCSIError.authenticationFailed
        XCTAssertEqual(authFailed.errorDescription, "Authentication failed")

        let keychainErr = ISCSIError.keychainError(status: -25300)
        XCTAssertEqual(keychainErr.errorDescription, "Keychain error: -25300")
    }

    // Test I/O errors
    func testIOErrors() {
        let cmdFailed = ISCSIError.commandFailed(status: 0x02)
        XCTAssertEqual(cmdFailed.errorDescription, "SCSI command failed with status: 0x02")

        let transferErr = ISCSIError.dataTransferError
        XCTAssertEqual(transferErr.errorDescription, "Data transfer error")
    }

    // Test all initiator opcodes
    func testInitiatorOpcodes() {
        XCTAssertEqual(ISCSIPDUOpcode.nopOut.rawValue, 0x00)
        XCTAssertEqual(ISCSIPDUOpcode.scsiCommand.rawValue, 0x01)
        XCTAssertEqual(ISCSIPDUOpcode.taskManagementReq.rawValue, 0x02)
        XCTAssertEqual(ISCSIPDUOpcode.loginRequest.rawValue, 0x03)
        XCTAssertEqual(ISCSIPDUOpcode.textRequest.rawValue, 0x04)
        XCTAssertEqual(ISCSIPDUOpcode.dataOut.rawValue, 0x05)
        XCTAssertEqual(ISCSIPDUOpcode.logoutRequest.rawValue, 0x06)
        XCTAssertEqual(ISCSIPDUOpcode.snackRequest.rawValue, 0x10)
    }

    // Test all target opcodes
    func testTargetOpcodes() {
        XCTAssertEqual(ISCSIPDUOpcode.nopIn.rawValue, 0x20)
        XCTAssertEqual(ISCSIPDUOpcode.scsiResponse.rawValue, 0x21)
        XCTAssertEqual(ISCSIPDUOpcode.taskManagementResp.rawValue, 0x22)
        XCTAssertEqual(ISCSIPDUOpcode.loginResponse.rawValue, 0x23)
        XCTAssertEqual(ISCSIPDUOpcode.textResponse.rawValue, 0x24)
        XCTAssertEqual(ISCSIPDUOpcode.dataIn.rawValue, 0x25)
        XCTAssertEqual(ISCSIPDUOpcode.logoutResponse.rawValue, 0x26)
        XCTAssertEqual(ISCSIPDUOpcode.r2t.rawValue, 0x31)
        XCTAssertEqual(ISCSIPDUOpcode.asyncMessage.rawValue, 0x32)
        XCTAssertEqual(ISCSIPDUOpcode.reject.rawValue, 0x3f)
    }

    // Test BasicHeaderSegment
    func testBasicHeaderSegmentInitialization() {
        let bhs = BasicHeaderSegment()

        XCTAssertEqual(bhs.opcode, 0)
        XCTAssertEqual(bhs.flags, 0)
        XCTAssertEqual(bhs.totalAHSLength, 0)
        XCTAssertEqual(bhs.dataSegmentLength, 0)
        XCTAssertEqual(bhs.lun, 0)
        XCTAssertEqual(bhs.initiatorTaskTag, 0)
        XCTAssertEqual(bhs.opcodeSpecific.count, 28)
        XCTAssertEqual(BasicHeaderSegment.size, 48)
    }

    // Test ISCSIPDU
    func testISCSIPDUInitialization() {
        let pdu = ISCSIPDU(opcode: .loginRequest)

        XCTAssertEqual(pdu.bhs.opcode, 0x03)
        XCTAssertNil(pdu.ahs)
        XCTAssertNil(pdu.headerDigest)
        XCTAssertNil(pdu.dataSegment)
        XCTAssertNil(pdu.dataDigest)
    }
}
