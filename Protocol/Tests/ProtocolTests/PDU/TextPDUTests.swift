import XCTest
@testable import ISCSIProtocol

final class TextPDUTests: XCTestCase {
    func testTextRequestPDUCreation() {
        let pdu = TextRequestPDU(
            initiatorTaskTag: 1,
            targetTransferTag: 0xFFFFFFFF,
            cmdSN: 1,
            expStatSN: 0,
            keyValuePairs: ["SendTargets": "All"],
            flags: TextRequestPDU.Flags(final: true, `continue`: false)
        )

        XCTAssertEqual(pdu.initiatorTaskTag, 1)
        XCTAssertEqual(pdu.targetTransferTag, 0xFFFFFFFF)
        XCTAssertEqual(pdu.cmdSN, 1)
        XCTAssertEqual(pdu.expStatSN, 0)
        XCTAssertEqual(pdu.keyValuePairs["SendTargets"], "All")
        XCTAssertTrue(pdu.flags.final)
        XCTAssertFalse(pdu.flags.continue)
    }

    func testTextResponsePDUCreation() {
        let keyValuePairs = [
            "TargetName": "iqn.2025-02.com.test:storage.target01",
            "TargetAddress": "192.168.1.100:3260,1"
        ]

        let pdu = TextResponsePDU(
            initiatorTaskTag: 1,
            targetTransferTag: 0xFFFFFFFF,
            statSN: 1,
            expCmdSN: 2,
            maxCmdSN: 4,
            keyValuePairs: keyValuePairs,
            flags: TextResponsePDU.Flags(final: true, `continue`: false)
        )

        XCTAssertEqual(pdu.initiatorTaskTag, 1)
        XCTAssertEqual(pdu.statSN, 1)
        XCTAssertEqual(pdu.keyValuePairs["TargetName"], "iqn.2025-02.com.test:storage.target01")
        XCTAssertEqual(pdu.keyValuePairs["TargetAddress"], "192.168.1.100:3260,1")
        XCTAssertTrue(pdu.flags.final)
        XCTAssertFalse(pdu.flags.continue)
    }

    func testSendTargetsResponseParsing() {
        let keyValuePairs = [
            "TargetName": "iqn.2025-02.com.test:storage.target01",
            "TargetAddress": "192.168.1.100:3260,1"
        ]

        let targets = TextPDU.parseSendTargetsResponse(keyValuePairs)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].iqn, "iqn.2025-02.com.test:storage.target01")
        XCTAssertEqual(targets[0].portals.count, 1)
        XCTAssertEqual(targets[0].portals[0].address, "192.168.1.100")
        XCTAssertEqual(targets[0].portals[0].port, 3260)
        XCTAssertEqual(targets[0].portals[0].groupTag, 1)
    }

    func testPortalAddressParsing() {
        // Test various portal address formats
        let keyValuePairs1 = [
            "TargetName": "iqn.2025-02.com.test:storage.target01",
            "TargetAddress": "192.168.1.100:3260,1"
        ]
        let targets1 = TextPDU.parseSendTargetsResponse(keyValuePairs1)
        XCTAssertEqual(targets1.count, 1)
        XCTAssertEqual(targets1[0].portals[0].address, "192.168.1.100")
        XCTAssertEqual(targets1[0].portals[0].port, 3260)
        XCTAssertEqual(targets1[0].portals[0].groupTag, 1)

        // Test with different port
        let keyValuePairs2 = [
            "TargetName": "iqn.2025-02.com.test:storage.target02",
            "TargetAddress": "10.0.0.1:3261,2"
        ]
        let targets2 = TextPDU.parseSendTargetsResponse(keyValuePairs2)
        XCTAssertEqual(targets2[0].portals[0].address, "10.0.0.1")
        XCTAssertEqual(targets2[0].portals[0].port, 3261)
        XCTAssertEqual(targets2[0].portals[0].groupTag, 2)
    }
}
