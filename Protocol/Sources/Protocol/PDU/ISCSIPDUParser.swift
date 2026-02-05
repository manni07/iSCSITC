import Foundation

public enum PDUParseError: Error {
    case insufficientData
    case invalidOpcode(UInt8)
    case invalidHeaderDigest
    case invalidDataDigest
    case malformedPDU(String)
}

public struct ISCSIPDUParser {

    /// Parse BHS from data
    public static func parseBHS(_ data: Data) throws -> BasicHeaderSegment {
        guard data.count >= BasicHeaderSegment.size else {
            throw PDUParseError.insufficientData
        }

        var bhs = BasicHeaderSegment()

        // Byte 0: Opcode
        bhs.opcode = data[0]

        // Byte 1: Flags
        bhs.flags = data[1]

        // Byte 4: TotalAHSLength
        bhs.totalAHSLength = data[4]

        // Bytes 5-7: DataSegmentLength (24-bit, big-endian)
        bhs.dataSegmentLength = UInt32(data[5]) << 16 |
                                UInt32(data[6]) << 8 |
                                UInt32(data[7])

        // Bytes 8-15: LUN (big-endian)
        bhs.lun = data.subdata(in: 8..<16).withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self).bigEndian
        }

        // Bytes 16-19: ITT (big-endian)
        bhs.initiatorTaskTag = data.subdata(in: 16..<20).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }

        // Bytes 20-47: Opcode-specific
        bhs.opcodeSpecific = data.subdata(in: 20..<48)

        return bhs
    }

    /// Encode BHS to data
    public static func encodeBHS(_ bhs: BasicHeaderSegment) throws -> Data {
        // Validate 24-bit DataSegmentLength
        guard bhs.dataSegmentLength <= 0xFFFFFF else {
            throw PDUParseError.malformedPDU("DataSegmentLength exceeds 24-bit maximum: \(bhs.dataSegmentLength)")
        }

        // Validate opcodeSpecific size
        guard bhs.opcodeSpecific.count == 28 else {
            throw PDUParseError.malformedPDU("opcodeSpecific must be 28 bytes, got \(bhs.opcodeSpecific.count)")
        }

        var data = Data(count: BasicHeaderSegment.size)

        data[0] = bhs.opcode
        data[1] = bhs.flags
        data[2] = 0  // Reserved
        data[3] = 0  // Reserved
        data[4] = bhs.totalAHSLength

        // DataSegmentLength (24-bit, big-endian)
        data[5] = UInt8((bhs.dataSegmentLength >> 16) & 0xFF)
        data[6] = UInt8((bhs.dataSegmentLength >> 8) & 0xFF)
        data[7] = UInt8(bhs.dataSegmentLength & 0xFF)

        // LUN (big-endian)
        withUnsafeBytes(of: bhs.lun.bigEndian) { bytes in
            data.replaceSubrange(8..<16, with: bytes)
        }

        // ITT (big-endian)
        withUnsafeBytes(of: bhs.initiatorTaskTag.bigEndian) { bytes in
            data.replaceSubrange(16..<20, with: bytes)
        }

        // Opcode-specific
        data.replaceSubrange(20..<48, with: bhs.opcodeSpecific)

        return data
    }
}
