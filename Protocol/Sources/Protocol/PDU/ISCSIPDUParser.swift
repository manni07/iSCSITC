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

    // MARK: - Key-Value Parsing

    /// Parse key=value pairs from text data segment
    public static func parseKeyValuePairs(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var pairs: [String: String] = [:]

        // Split by null terminators
        let entries = text.components(separatedBy: "\0").filter { !$0.isEmpty }

        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                pairs[String(parts[0])] = String(parts[1])
            }
        }

        return pairs
    }

    /// Encode key=value pairs to text data segment
    public static func encodeKeyValuePairs(_ pairs: [String: String]) -> Data {
        var text = ""

        for (key, value) in pairs.sorted(by: { $0.key < $1.key }) {
            text += "\(key)=\(value)\0"
        }

        // iSCSI text data must be null-terminated
        if !text.isEmpty && !text.hasSuffix("\0") {
            text += "\0"
        }

        return text.data(using: .utf8) ?? Data()
    }

    // MARK: - Complete PDU Parsing

    /// Parse complete PDU
    public static func parsePDU(_ data: Data) throws -> ISCSIPDU {
        let bhs = try parseBHS(data)

        var pdu = ISCSIPDU(opcode: ISCSIPDUOpcode(rawValue: bhs.opcode & 0x3F) ?? .nopOut)
        pdu.bhs = bhs

        var offset = BasicHeaderSegment.size

        // Parse AHS if present
        if bhs.totalAHSLength > 0 {
            let ahsLength = Int(bhs.totalAHSLength) * 4  // In 4-byte words
            guard data.count >= offset + ahsLength else {
                throw PDUParseError.insufficientData
            }
            offset += ahsLength
        }

        // Parse data segment if present
        if bhs.dataSegmentLength > 0 {
            let dataLength = Int(bhs.dataSegmentLength)
            let paddedLength = (dataLength + 3) & ~3  // Pad to 4-byte boundary

            guard data.count >= offset + paddedLength else {
                throw PDUParseError.insufficientData
            }

            pdu.dataSegment = data.subdata(in: offset..<(offset + dataLength))
            offset += paddedLength
        }

        return pdu
    }

    /// Encode complete PDU
    public static func encodePDU(_ pdu: ISCSIPDU) throws -> Data {
        var data = try encodeBHS(pdu.bhs)

        // Add data segment if present
        if let dataSegment = pdu.dataSegment, !dataSegment.isEmpty {
            data.append(dataSegment)

            // Add padding to 4-byte boundary
            let padding = (4 - (dataSegment.count % 4)) % 4
            if padding > 0 {
                data.append(Data(count: padding))
            }
        }

        return data
    }

    // MARK: - Login PDU Parsing

    public static func parseLoginRequest(_ pdu: ISCSIPDU) throws -> LoginRequestPDU {
        var login = LoginRequestPDU()

        let flags = pdu.bhs.flags
        login.transit = (flags & 0x80) != 0
        login.continue = (flags & 0x40) != 0
        login.currentStageCode = (flags >> 2) & 0x03
        login.nextStageCode = flags & 0x03

        let spec = pdu.bhs.opcodeSpecific
        login.versionMax = spec[0]
        login.versionMin = spec[1]
        login.isid = spec.subdata(in: 4..<10)
        login.tsih = spec.subdata(in: 10..<12).withUnsafeBytes {
            $0.loadUnaligned(as: UInt16.self).bigEndian
        }
        login.initiatorTaskTag = pdu.bhs.initiatorTaskTag
        login.cid = spec.subdata(in: 12..<14).withUnsafeBytes {
            $0.loadUnaligned(as: UInt16.self).bigEndian
        }
        login.cmdSN = spec.subdata(in: 16..<20).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        login.expStatSN = spec.subdata(in: 20..<24).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }

        if let data = pdu.dataSegment {
            login.keyValuePairs = parseKeyValuePairs(data)
        }

        return login
    }

    public static func encodeLoginRequest(_ login: LoginRequestPDU) throws -> Data {
        var pdu = ISCSIPDU(opcode: .loginRequest)

        // Flags
        var flags: UInt8 = 0
        if login.transit { flags |= 0x80 }
        if login.continue { flags |= 0x40 }
        flags |= (login.currentStageCode & 0x03) << 2
        flags |= login.nextStageCode & 0x03
        pdu.bhs.flags = flags

        // Opcode-specific
        var spec = Data(count: 28)
        spec[0] = login.versionMax
        spec[1] = login.versionMin
        spec.replaceSubrange(4..<10, with: login.isid)

        withUnsafeBytes(of: login.tsih.bigEndian) { bytes in
            spec.replaceSubrange(10..<12, with: bytes)
        }

        pdu.bhs.initiatorTaskTag = login.initiatorTaskTag

        withUnsafeBytes(of: login.cid.bigEndian) { bytes in
            spec.replaceSubrange(12..<14, with: bytes)
        }
        withUnsafeBytes(of: login.cmdSN.bigEndian) { bytes in
            spec.replaceSubrange(16..<20, with: bytes)
        }
        withUnsafeBytes(of: login.expStatSN.bigEndian) { bytes in
            spec.replaceSubrange(20..<24, with: bytes)
        }

        pdu.bhs.opcodeSpecific = spec

        // Data segment
        if !login.keyValuePairs.isEmpty {
            let data = encodeKeyValuePairs(login.keyValuePairs)
            pdu.bhs.dataSegmentLength = UInt32(data.count)
            pdu.dataSegment = data
        }

        return try encodePDU(pdu)
    }

    public static func parseLoginResponse(_ pdu: ISCSIPDU) throws -> LoginResponsePDU {
        var login = LoginResponsePDU()

        let flags = pdu.bhs.flags
        login.transit = (flags & 0x80) != 0
        login.continue = (flags & 0x40) != 0
        login.currentStageCode = (flags >> 2) & 0x03
        login.nextStageCode = flags & 0x03

        let spec = pdu.bhs.opcodeSpecific
        login.versionMax = spec[0]
        login.versionActive = spec[1]
        login.isid = spec.subdata(in: 4..<10)
        login.tsih = spec.subdata(in: 10..<12).withUnsafeBytes {
            $0.loadUnaligned(as: UInt16.self).bigEndian
        }
        login.initiatorTaskTag = pdu.bhs.initiatorTaskTag
        login.statSN = spec.subdata(in: 16..<20).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        login.expCmdSN = spec.subdata(in: 20..<24).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        login.maxCmdSN = spec.subdata(in: 24..<28).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        login.statusClass = spec[12]
        login.statusDetail = spec[13]

        if let data = pdu.dataSegment {
            login.keyValuePairs = parseKeyValuePairs(data)
        }

        return login
    }
}
