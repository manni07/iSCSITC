import Foundation

// MARK: - PDU Opcodes

public enum ISCSIPDUOpcode: UInt8, Sendable {
    // Initiator → Target
    case nopOut             = 0x00
    case scsiCommand        = 0x01
    case taskManagementReq  = 0x02
    case loginRequest       = 0x03
    case textRequest        = 0x04
    case dataOut            = 0x05
    case logoutRequest      = 0x06
    case snackRequest       = 0x10

    // Target → Initiator
    case nopIn              = 0x20
    case scsiResponse       = 0x21
    case taskManagementResp = 0x22
    case loginResponse      = 0x23
    case textResponse       = 0x24
    case dataIn             = 0x25
    case logoutResponse     = 0x26
    case r2t                = 0x31
    case asyncMessage       = 0x32
    case reject             = 0x3f
}

// MARK: - Basic Header Segment (BHS)

/// Basic Header Segment - 48 bytes (common to all PDUs)
public struct BasicHeaderSegment: Sendable {
    public var opcode: UInt8                    // Byte 0
    public var flags: UInt8                     // Byte 1
    public var totalAHSLength: UInt8            // Byte 4 (in 4-byte words)
    public var dataSegmentLength: UInt32        // Bytes 5-7 (24-bit, big-endian)
    public var lun: UInt64                      // Bytes 8-15
    public var initiatorTaskTag: UInt32         // Bytes 16-19
    public var opcodeSpecific: Data             // Bytes 20-47 (28 bytes)

    public init() {
        self.opcode = 0
        self.flags = 0
        self.totalAHSLength = 0
        self.dataSegmentLength = 0
        self.lun = 0
        self.initiatorTaskTag = 0
        self.opcodeSpecific = Data(count: 28)
    }

    public static let size = 48
}

// MARK: - Complete PDU

/// Complete iSCSI PDU
public struct ISCSIPDU: Sendable {
    public var bhs: BasicHeaderSegment
    public var ahs: [Data]?                     // Additional Header Segments
    public var headerDigest: UInt32?            // CRC32C (optional)
    public var dataSegment: Data?
    public var dataDigest: UInt32?              // CRC32C (optional)

    public init(opcode: ISCSIPDUOpcode) {
        self.bhs = BasicHeaderSegment()
        self.bhs.opcode = opcode.rawValue
    }
}
