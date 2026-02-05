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
        let encoded = try ISCSIPDUParser.encodeLoginRequest(login)

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
        let encoded = try ISCSIPDUParser.encodeLoginRequest(login)
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
