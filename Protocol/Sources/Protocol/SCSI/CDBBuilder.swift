import Foundation

/// Builder for SCSI Command Descriptor Blocks (CDB)
/// Implements common SCSI-3 commands per SPC-4 and SBC-3
public struct CDBBuilder {

    /// INQUIRY command (0x12) - Get device identification
    /// - Parameter allocationLength: Response buffer size (typically 36 or 96)
    /// - Returns: 6-byte CDB
    public static func inquiry(allocationLength: UInt8 = 36) -> Data {
        var cdb = Data(count: 6)
        cdb[0] = 0x12  // INQUIRY opcode
        cdb[4] = allocationLength
        return cdb
    }

    /// READ(10) command (0x28) - Read blocks from device
    /// - Parameters:
    ///   - lba: Logical Block Address to start reading
    ///   - transferLength: Number of blocks to read (in blocks, not bytes)
    /// - Returns: 10-byte CDB
    public static func read10(lba: UInt32, transferLength: UInt16) -> Data {
        var cdb = Data(count: 10)
        cdb[0] = 0x28  // READ(10) opcode

        // LBA (big-endian, bytes 2-5)
        cdb[2] = UInt8((lba >> 24) & 0xFF)
        cdb[3] = UInt8((lba >> 16) & 0xFF)
        cdb[4] = UInt8((lba >> 8) & 0xFF)
        cdb[5] = UInt8(lba & 0xFF)

        // Transfer length (big-endian, bytes 7-8)
        cdb[7] = UInt8((transferLength >> 8) & 0xFF)
        cdb[8] = UInt8(transferLength & 0xFF)

        return cdb
    }

    /// WRITE(10) command (0x2A) - Write blocks to device
    /// - Parameters:
    ///   - lba: Logical Block Address to start writing
    ///   - transferLength: Number of blocks to write (in blocks, not bytes)
    /// - Returns: 10-byte CDB
    public static func write10(lba: UInt32, transferLength: UInt16) -> Data {
        var cdb = Data(count: 10)
        cdb[0] = 0x2A  // WRITE(10) opcode

        // LBA (big-endian, bytes 2-5)
        cdb[2] = UInt8((lba >> 24) & 0xFF)
        cdb[3] = UInt8((lba >> 16) & 0xFF)
        cdb[4] = UInt8((lba >> 8) & 0xFF)
        cdb[5] = UInt8(lba & 0xFF)

        // Transfer length (big-endian, bytes 7-8)
        cdb[7] = UInt8((transferLength >> 8) & 0xFF)
        cdb[8] = UInt8(transferLength & 0xFF)

        return cdb
    }

    /// TEST UNIT READY command (0x00) - Check if device is ready
    /// - Returns: 6-byte CDB
    public static func testUnitReady() -> Data {
        Data(count: 6)  // All zeros
    }

    /// READ CAPACITY(10) command (0x25) - Get device capacity
    /// - Returns: 10-byte CDB
    public static func readCapacity10() -> Data {
        var cdb = Data(count: 10)
        cdb[0] = 0x25  // READ CAPACITY(10) opcode
        return cdb
    }
}
