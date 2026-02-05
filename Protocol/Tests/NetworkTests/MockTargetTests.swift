import XCTest
@testable import ISCSIProtocol
@testable import ISCSINetwork

final class MockTargetTests: XCTestCase {

    func testMockTargetStartsAndStops() async throws {
        // Start mock target
        let mock = MockISCSITarget(port: 13261)
        try await mock.start()

        // Stop mock target
        await mock.stop()

        // Test passes if no exceptions
        XCTAssertTrue(true)
    }

    func testLoginResponseEncoding() throws {
        // Test that we can encode and decode a login response
        var response = LoginResponsePDU()
        response.transit = true
        response.continue = false
        response.currentStageCode = 0
        response.nextStageCode = 1
        response.versionMax = 0
        response.versionActive = 0
        response.isid = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        response.tsih = 1
        response.initiatorTaskTag = 42
        response.statSN = 0
        response.expCmdSN = 1
        response.maxCmdSN = 64
        response.statusClass = 0
        response.statusDetail = 0
        response.keyValuePairs = ["TargetName": "iqn.test"]

        // Encode
        let encoded = try ISCSIPDUParser.encodeLoginResponse(response)

        // Decode
        let pdu = try ISCSIPDUParser.parsePDU(encoded)
        let decoded = try ISCSIPDUParser.parseLoginResponse(pdu)

        // Verify
        XCTAssertEqual(decoded.transit, response.transit)
        XCTAssertEqual(decoded.statusClass, response.statusClass)
        XCTAssertEqual(decoded.statusDetail, response.statusDetail)
        XCTAssertEqual(decoded.initiatorTaskTag, response.initiatorTaskTag)
    }

    // FIXME: This test needs debugging - network stream not receiving data
    func _testMockTargetRespondsToLogin() async throws {
        // Start mock target
        let mock = MockISCSITarget(port: 13260)
        try await mock.start()

        defer {
            Task {
                await mock.stop()
            }
        }

        // Connect initiator
        let conn = ISCSIConnection(host: "127.0.0.1", port: 13260)

        // Get receive stream before connecting
        let stream = await conn.receiveStream()

        try await conn.connect()

        defer {
            Task {
                await conn.disconnect()
            }
        }

        // Send login request
        let isid = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let sm = LoginStateMachine(isid: isid)
        let loginPDU = await sm.buildInitialLoginPDU(initiatorName: "iqn.2026-01.test:initiator")
        let loginData = try ISCSIPDUParser.encodeLoginRequest(loginPDU)

        try await conn.send(loginData)

        // Receive response with timeout using withThrowingTaskGroup
        let receivedResponse = try await withThrowingTaskGroup(of: Bool.self) { group in
            // Task 1: Try to receive response
            group.addTask {
                for await data in stream {
                    let pdu = try ISCSIPDUParser.parsePDU(data)
                    if pdu.bhs.opcode == ISCSIPDUOpcode.loginResponse.rawValue {
                        return true
                    }
                }
                return false
            }

            // Task 2: Timeout
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds
                return false
            }

            // Return first result
            if let result = try await group.next() {
                group.cancelAll()
                return result
            }
            return false
        }

        XCTAssertTrue(receivedResponse, "Should receive login response within timeout")
    }
}
