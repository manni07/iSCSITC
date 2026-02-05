import XCTest
@testable import ISCSIProtocol

final class SCSICommandPDUTests: XCTestCase {
    func testSCSICommandPDUCreation() {
        let cdb = Data([0x12, 0x00, 0x00, 0x00, 0x24, 0x00]) // INQUIRY command
        let pdu = SCSICommandPDU(
            lun: 0,
            initiatorTaskTag: 1,
            expectedDataTransferLength: 36,
            cmdSN: 1,
            expStatSN: 0,
            cdb: cdb,
            flags: SCSICommandPDU.Flags(read: true, write: false, final: true)
        )

        XCTAssertEqual(pdu.lun, 0)
        XCTAssertEqual(pdu.initiatorTaskTag, 1)
        XCTAssertEqual(pdu.expectedDataTransferLength, 36)
        XCTAssertEqual(pdu.cdb, cdb)
        XCTAssertTrue(pdu.flags.read)
        XCTAssertFalse(pdu.flags.write)
        XCTAssertTrue(pdu.flags.final)
    }

    func testSCSIResponsePDUParsing() {
        let response = SCSIResponsePDU(
            initiatorTaskTag: 1,
            statSN: 1,
            expCmdSN: 2,
            maxCmdSN: 4,
            status: 0x00, // GOOD
            response: 0x00,
            residualCount: 0,
            senseData: Data()
        )

        XCTAssertEqual(response.status, 0x00)
        XCTAssertEqual(response.initiatorTaskTag, 1)
        XCTAssertEqual(response.residualCount, 0)
    }

    func testDataInPDUCreation() {
        let dataIn = DataInPDU(
            lun: 0,
            initiatorTaskTag: 1,
            targetTransferTag: 0xFFFFFFFF,
            statSN: 1,
            expCmdSN: 2,
            maxCmdSN: 4,
            dataSequenceNumber: 0,
            bufferOffset: 0,
            residualCount: 0,
            flags: DataInPDU.Flags(final: true, acknowledge: false, overflow: false, underflow: false, statusPresent: true),
            status: 0x00,
            data: Data([0x00, 0x00, 0x00, 0x00, 0x1F])
        )

        XCTAssertEqual(dataIn.initiatorTaskTag, 1)
        XCTAssertTrue(dataIn.flags.final)
        XCTAssertTrue(dataIn.flags.statusPresent)
        XCTAssertEqual(dataIn.status, 0x00)
    }
}
