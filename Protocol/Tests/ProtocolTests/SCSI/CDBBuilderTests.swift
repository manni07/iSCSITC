import XCTest
@testable import ISCSIProtocol

final class CDBBuilderTests: XCTestCase {
    func testINQUIRYCommand() {
        let cdb = CDBBuilder.inquiry(allocationLength: 36)

        XCTAssertEqual(cdb.count, 6)
        XCTAssertEqual(cdb[0], 0x12) // INQUIRY opcode
        XCTAssertEqual(cdb[1], 0x00) // EVPD=0
        XCTAssertEqual(cdb[2], 0x00) // Page code
        XCTAssertEqual(cdb[3], 0x00) // Reserved
        XCTAssertEqual(cdb[4], 36) // Allocation length
        XCTAssertEqual(cdb[5], 0x00) // Control
    }

    func testREAD10Command() {
        let cdb = CDBBuilder.read10(lba: 0x12345678, transferLength: 16)

        XCTAssertEqual(cdb.count, 10)
        XCTAssertEqual(cdb[0], 0x28) // READ(10) opcode
        XCTAssertEqual(cdb[1], 0x00) // Flags
        // LBA bytes 2-5
        XCTAssertEqual(cdb[2], 0x12)
        XCTAssertEqual(cdb[3], 0x34)
        XCTAssertEqual(cdb[4], 0x56)
        XCTAssertEqual(cdb[5], 0x78)
        XCTAssertEqual(cdb[6], 0x00) // Group number
        // Transfer length bytes 7-8
        XCTAssertEqual(cdb[7], 0x00)
        XCTAssertEqual(cdb[8], 16)
        XCTAssertEqual(cdb[9], 0x00) // Control
    }

    func testWRITE10Command() {
        let cdb = CDBBuilder.write10(lba: 0x100, transferLength: 8)

        XCTAssertEqual(cdb.count, 10)
        XCTAssertEqual(cdb[0], 0x2A) // WRITE(10) opcode
        XCTAssertEqual(cdb[1], 0x00)
        // LBA
        XCTAssertEqual(cdb[2], 0x00)
        XCTAssertEqual(cdb[3], 0x00)
        XCTAssertEqual(cdb[4], 0x01)
        XCTAssertEqual(cdb[5], 0x00)
        XCTAssertEqual(cdb[6], 0x00)
        // Transfer length
        XCTAssertEqual(cdb[7], 0x00)
        XCTAssertEqual(cdb[8], 8)
        XCTAssertEqual(cdb[9], 0x00)
    }

    func testTEST_UNIT_READYCommand() {
        let cdb = CDBBuilder.testUnitReady()

        XCTAssertEqual(cdb.count, 6)
        XCTAssertEqual(cdb[0], 0x00) // TEST UNIT READY opcode
        XCTAssertEqual(cdb[1], 0x00)
        XCTAssertEqual(cdb[2], 0x00)
        XCTAssertEqual(cdb[3], 0x00)
        XCTAssertEqual(cdb[4], 0x00)
        XCTAssertEqual(cdb[5], 0x00)
    }

    func testREAD_CAPACITYCommand() {
        let cdb = CDBBuilder.readCapacity10()

        XCTAssertEqual(cdb.count, 10)
        XCTAssertEqual(cdb[0], 0x25) // READ CAPACITY(10) opcode
        for i in 1..<10 {
            XCTAssertEqual(cdb[i], 0x00)
        }
    }
}
