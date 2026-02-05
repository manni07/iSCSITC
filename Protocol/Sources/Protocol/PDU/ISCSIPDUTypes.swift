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

// MARK: - Login PDU

public struct LoginRequestPDU: Sendable {
    // Flags (byte 1)
    public var transit: Bool                    // T bit
    public var `continue`: Bool                 // C bit
    public var currentStageCode: UInt8          // CSG (2 bits)
    public var nextStageCode: UInt8             // NSG (2 bits)

    // Fields
    public var versionMax: UInt8                // Byte 2
    public var versionMin: UInt8                // Byte 3
    public var isid: Data                       // Bytes 8-13 (6 bytes)
    public var tsih: UInt16                     // Bytes 14-15
    public var initiatorTaskTag: UInt32         // Bytes 16-19
    public var cid: UInt16                      // Bytes 20-21 (Connection ID)
    public var cmdSN: UInt32                    // Bytes 24-27
    public var expStatSN: UInt32                // Bytes 28-31

    // Data segment (text key=value pairs)
    public var keyValuePairs: [String: String]

    public init() {
        self.transit = false
        self.continue = false
        self.currentStageCode = 0
        self.nextStageCode = 0
        self.versionMax = 0
        self.versionMin = 0
        self.isid = Data(count: 6)
        self.tsih = 0
        self.initiatorTaskTag = 0
        self.cid = 0
        self.cmdSN = 0
        self.expStatSN = 0
        self.keyValuePairs = [:]
    }
}

public struct LoginResponsePDU: Sendable {
    // Flags
    public var transit: Bool
    public var `continue`: Bool
    public var currentStageCode: UInt8
    public var nextStageCode: UInt8

    // Fields
    public var versionMax: UInt8
    public var versionActive: UInt8
    public var isid: Data
    public var tsih: UInt16
    public var initiatorTaskTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var statusClass: UInt8
    public var statusDetail: UInt8

    // Data segment
    public var keyValuePairs: [String: String]

    public init() {
        self.transit = false
        self.continue = false
        self.currentStageCode = 0
        self.nextStageCode = 0
        self.versionMax = 0
        self.versionActive = 0
        self.isid = Data(count: 6)
        self.tsih = 0
        self.initiatorTaskTag = 0
        self.statSN = 0
        self.expCmdSN = 0
        self.maxCmdSN = 0
        self.statusClass = 0
        self.statusDetail = 0
        self.keyValuePairs = [:]
    }
}

// MARK: - SCSI Command PDU

public struct SCSICommandPDU: Sendable {
    public struct Flags: Sendable {
        public var read: Bool
        public var write: Bool
        public var final: Bool

        public init(read: Bool, write: Bool, final: Bool) {
            self.read = read
            self.write = write
            self.final = final
        }
    }

    public var lun: UInt64
    public var initiatorTaskTag: UInt32
    public var expectedDataTransferLength: UInt32
    public var cmdSN: UInt32
    public var expStatSN: UInt32
    public var cdb: Data  // Command Descriptor Block (up to 16 bytes)
    public var flags: Flags

    public init(
        lun: UInt64,
        initiatorTaskTag: UInt32,
        expectedDataTransferLength: UInt32,
        cmdSN: UInt32,
        expStatSN: UInt32,
        cdb: Data,
        flags: Flags
    ) {
        self.lun = lun
        self.initiatorTaskTag = initiatorTaskTag
        self.expectedDataTransferLength = expectedDataTransferLength
        self.cmdSN = cmdSN
        self.expStatSN = expStatSN
        self.cdb = cdb
        self.flags = flags
    }
}

// MARK: - SCSI Response PDU

public struct SCSIResponsePDU: Sendable {
    public var initiatorTaskTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var status: UInt8  // SCSI status
    public var response: UInt8  // iSCSI response code
    public var residualCount: UInt32
    public var senseData: Data

    public init(
        initiatorTaskTag: UInt32,
        statSN: UInt32,
        expCmdSN: UInt32,
        maxCmdSN: UInt32,
        status: UInt8,
        response: UInt8,
        residualCount: UInt32,
        senseData: Data
    ) {
        self.initiatorTaskTag = initiatorTaskTag
        self.statSN = statSN
        self.expCmdSN = expCmdSN
        self.maxCmdSN = maxCmdSN
        self.status = status
        self.response = response
        self.residualCount = residualCount
        self.senseData = senseData
    }
}

// MARK: - Data-In PDU

public struct DataInPDU: Sendable {
    public struct Flags: Sendable {
        public var final: Bool
        public var acknowledge: Bool
        public var overflow: Bool
        public var underflow: Bool
        public var statusPresent: Bool

        public init(final: Bool, acknowledge: Bool, overflow: Bool, underflow: Bool, statusPresent: Bool) {
            self.final = final
            self.acknowledge = acknowledge
            self.overflow = overflow
            self.underflow = underflow
            self.statusPresent = statusPresent
        }
    }

    public var lun: UInt64
    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var dataSequenceNumber: UInt32
    public var bufferOffset: UInt32
    public var residualCount: UInt32
    public var flags: Flags
    public var status: UInt8?  // Present only if statusPresent flag is set
    public var data: Data

    public init(
        lun: UInt64,
        initiatorTaskTag: UInt32,
        targetTransferTag: UInt32,
        statSN: UInt32,
        expCmdSN: UInt32,
        maxCmdSN: UInt32,
        dataSequenceNumber: UInt32,
        bufferOffset: UInt32,
        residualCount: UInt32,
        flags: Flags,
        status: UInt8?,
        data: Data
    ) {
        self.lun = lun
        self.initiatorTaskTag = initiatorTaskTag
        self.targetTransferTag = targetTransferTag
        self.statSN = statSN
        self.expCmdSN = expCmdSN
        self.maxCmdSN = maxCmdSN
        self.dataSequenceNumber = dataSequenceNumber
        self.bufferOffset = bufferOffset
        self.residualCount = residualCount
        self.flags = flags
        self.status = status
        self.data = data
    }
}
