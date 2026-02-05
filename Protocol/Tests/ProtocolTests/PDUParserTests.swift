import XCTest
@testable import ISCSIProtocol

final class PDUParserTests: XCTestCase {

    func testParseBHS_ValidData() throws {
        // Arrange: Create test BHS data
        var data = Data(count: 48)
        data[0] = 0x01  // SCSI Command opcode
        data[1] = 0x80  // Final bit set
        data[5] = 0x00  // DataSegmentLength MSB
        data[6] = 0x01  // DataSegmentLength middle
        data[7] = 0x00  // DataSegmentLength LSB (256 bytes)

        // LUN (bytes 8-15) = 0x1234567890ABCDEF
        withUnsafeBytes(of: UInt64(0x1234567890ABCDEF).bigEndian) { bytes in
            data.replaceSubrange(8..<16, with: bytes)
        }

        // ITT (bytes 16-19) = 0x12345678
        withUnsafeBytes(of: UInt32(0x12345678).bigEndian) { bytes in
            data.replaceSubrange(16..<20, with: bytes)
        }

        // Act
        let bhs = try ISCSIPDUParser.parseBHS(data)

        // Assert
        XCTAssertEqual(bhs.opcode, 0x01)
        XCTAssertEqual(bhs.flags, 0x80)
        XCTAssertEqual(bhs.dataSegmentLength, 256)
        XCTAssertEqual(bhs.lun, 0x1234567890ABCDEF)
        XCTAssertEqual(bhs.initiatorTaskTag, 0x12345678)
    }

    func testParseBHS_InsufficientData() {
        // Arrange: Only 40 bytes (less than 48 required)
        let data = Data(count: 40)

        // Act & Assert
        XCTAssertThrowsError(try ISCSIPDUParser.parseBHS(data)) { error in
            guard case PDUParseError.insufficientData = error else {
                XCTFail("Expected insufficientData error, got \(error)")
                return
            }
        }
    }

    func testEncodeBHS_RoundTrip() throws {
        // Arrange: Create original BHS
        var original = BasicHeaderSegment()
        original.opcode = 0x03  // Login Request
        original.flags = 0x83   // Transit + Continue
        original.dataSegmentLength = 512
        original.lun = 0xABCDEF0123456789
        original.initiatorTaskTag = 0x87654321

        // Act: Encode then decode
        let encoded = try ISCSIPDUParser.encodeBHS(original)
        let decoded = try ISCSIPDUParser.parseBHS(encoded)

        // Assert: Should match
        XCTAssertEqual(decoded.opcode, original.opcode)
        XCTAssertEqual(decoded.flags, original.flags)
        XCTAssertEqual(decoded.dataSegmentLength, original.dataSegmentLength)
        XCTAssertEqual(decoded.lun, original.lun)
        XCTAssertEqual(decoded.initiatorTaskTag, original.initiatorTaskTag)
    }

    func testParseBHS_ExtraBytes() throws {
        // Data with more than 48 bytes should parse successfully
        var data = Data(count: 60)  // 12 extra bytes
        data[0] = 0x01

        let bhs = try ISCSIPDUParser.parseBHS(data)
        XCTAssertEqual(bhs.opcode, 0x01)
    }

    func testEncodeBHS_DataSegmentLengthTooLarge() {
        var bhs = BasicHeaderSegment()
        bhs.dataSegmentLength = 0x01000000  // Exceeds 24-bit max

        XCTAssertThrowsError(try ISCSIPDUParser.encodeBHS(bhs)) { error in
            guard case PDUParseError.malformedPDU(let message) = error else {
                XCTFail("Expected malformedPDU error")
                return
            }
            XCTAssertTrue(message.contains("24-bit"))
        }
    }

    func testEncodeBHS_InvalidOpcodeSpecificSize() {
        var bhs = BasicHeaderSegment()
        bhs.opcodeSpecific = Data(count: 10)  // Wrong size

        XCTAssertThrowsError(try ISCSIPDUParser.encodeBHS(bhs)) { error in
            guard case PDUParseError.malformedPDU(let message) = error else {
                XCTFail("Expected malformedPDU error")
                return
            }
            XCTAssertTrue(message.contains("28 bytes"))
        }
    }
}
