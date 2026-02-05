import XCTest
@testable import ISCSIProtocol

final class ISCSISessionManagerTests: XCTestCase {
    func testInitialState() async {
        let manager = ISCSISessionManager(initiatorName: "iqn.2025-02.com.test:initiator")
        let sessions = await manager.listSessions()
        XCTAssertTrue(sessions.isEmpty, "Should start with no sessions")
    }

    func testGenerateISID() async {
        let manager = ISCSISessionManager(initiatorName: "iqn.2025-02.com.test:initiator")
        let isid1 = await manager.generateISID()
        let isid2 = await manager.generateISID()

        XCTAssertEqual(isid1.count, 6, "ISID should be 6 bytes")
        XCTAssertEqual(isid2.count, 6, "ISID should be 6 bytes")
        XCTAssertNotEqual(isid1, isid2, "Each ISID should be unique")
    }

    func testSessionTracking() async throws {
        let manager = ISCSISessionManager(initiatorName: "iqn.2025-02.com.test:initiator")
        let testIQN = "iqn.2025-02.com.test:storage.target01"
        let testPortal = "192.168.1.100:3260"

        // Track new session
        let sessionID = await manager.trackSession(targetIQN: testIQN, portal: testPortal)

        // Verify session exists
        let sessions = await manager.listSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].targetIQN, testIQN)
        XCTAssertEqual(sessions[0].portal, testPortal)
        XCTAssertEqual(sessions[0].sessionID, sessionID)
    }

    func testRemoveSession() async {
        let manager = ISCSISessionManager(initiatorName: "iqn.2025-02.com.test:initiator")
        let testIQN = "iqn.2025-02.com.test:storage.target01"
        let testPortal = "192.168.1.100:3260"

        let sessionID = await manager.trackSession(targetIQN: testIQN, portal: testPortal)
        await manager.removeSession(sessionID: sessionID)

        let sessions = await manager.listSessions()
        XCTAssertTrue(sessions.isEmpty, "Session should be removed")
    }
}
