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

    func testPDUOpcodes() {
        XCTAssertEqual(ISCSIPDUOpcode.nopOut.rawValue, 0x00)
        XCTAssertEqual(ISCSIPDUOpcode.scsiCommand.rawValue, 0x01)
        XCTAssertEqual(ISCSIPDUOpcode.loginRequest.rawValue, 0x03)
        XCTAssertEqual(ISCSIPDUOpcode.loginResponse.rawValue, 0x23)
    }
}
