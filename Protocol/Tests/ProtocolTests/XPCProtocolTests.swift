import XCTest
@testable import ISCSIProtocol

final class XPCProtocolTests: XCTestCase {

    func testISCSITarget_NSSecureCoding() throws {
        // Arrange
        let target = ISCSITarget(
            iqn: "iqn.2026-01.com.test:storage",
            portal: "192.168.1.10:3260",
            tpgt: 1
        )

        // Act: Encode
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: target,
            requiringSecureCoding: true
        )

        // Decode
        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ISCSITarget.self,
            from: data
        )

        // Assert
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.iqn, target.iqn)
        XCTAssertEqual(decoded?.portal, target.portal)
        XCTAssertEqual(decoded?.targetPortalGroupTag, target.targetPortalGroupTag)
    }

    func testISCSISessionInfo_NSSecureCoding() throws {
        let target = ISCSITarget(iqn: "iqn.test", portal: "10.0.0.1:3260")
        let session = ISCSISessionInfo(
            target: target,
            state: .loggedIn,
            sessionID: "session-123",
            connectedAt: Date()
        )

        let data = try NSKeyedArchiver.archivedData(
            withRootObject: session,
            requiringSecureCoding: true
        )

        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ISCSISessionInfo.self,
            from: data
        )

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.sessionID, session.sessionID)
        XCTAssertEqual(decoded?.state, session.state)
    }
}
