import XCTest
@testable import ISCSIProtocol
@testable import ISCSINetwork

final class LoginIntegrationTests: XCTestCase {

    func testCompleteLoginFlow() async throws {
        // Arrange: Start mock target
        let mock = MockISCSITarget(port: 13261)
        try await mock.start()

        defer {
            Task {
                await mock.stop()
            }
        }

        // Act: Connect and login
        let conn = ISCSIConnection(host: "127.0.0.1", port: 13261)
        try await conn.connect()

        defer {
            Task {
                await conn.disconnect()
            }
        }

        let isid = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let sm = LoginStateMachine(isid: isid)

        // Build and send login request
        let loginPDU = await sm.buildInitialLoginPDU(
            initiatorName: "iqn.2026-01.test:initiator"
        )
        let loginData = try ISCSIPDUParser.encodeLoginRequest(loginPDU)
        try await conn.send(loginData)

        // Receive and process response
        var loginSuccessful = false
        for await data in await conn.receiveStream() {
            let pdu = try ISCSIPDUParser.parsePDU(data)

            if pdu.bhs.opcode == ISCSIPDUOpcode.loginResponse.rawValue {
                let response = try ISCSIPDUParser.parseLoginResponse(pdu)

                try await sm.processLoginResponse(response)

                let state = await sm.currentState
                if case .operationalNegotiation = state {
                    loginSuccessful = true
                    break
                } else if case .fullFeaturePhase = state {
                    loginSuccessful = true
                    break
                }
            }

            // Timeout after 1 second
            try await Task.sleep(nanoseconds: 1_000_000_000)
            break
        }

        // Assert: Login should succeed
        XCTAssertTrue(loginSuccessful, "Login flow should complete successfully")

        let finalState = await sm.currentState
        XCTAssertNotEqual(finalState, .free)
        XCTAssertNotEqual(finalState, .failed(""))
    }

    func testLoginWithInvalidTarget() async throws {
        // Test connection failure to non-existent target
        let conn = ISCSIConnection(host: "127.0.0.1", port: 19999)

        do {
            try await conn.connect()
            XCTFail("Should have thrown connection timeout")
        } catch ISCSIError.connectionTimeout {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
