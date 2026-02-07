import Foundation

// Mirror of iSCSIUserClientShared.h enums and structs

/// External method selectors (must match C++ enum)
enum UserClientSelector: UInt32 {
    case createSession = 0
    case destroySession = 1
    case completeSCSITask = 2
    case getPendingTask = 3
    case mapSharedMemory = 4
    case setHBAStatus = 5
    case getHBAStatus = 6
}

/// Shared memory types (must match C++ enum)
enum SharedMemoryType: UInt32 {
    case commandQueue = 0      // 64 KB - dext -> daemon
    case completionQueue = 1   // 64 KB - daemon -> dext
    case dataBufferPool = 2    // 64 MB - bidirectional
}

/// SCSI Command Descriptor (80 bytes, matches C++ struct)
struct SCSICommandDescriptor {
    var taskTag: UInt64                // Kernel task identifier
    var targetID: UInt32               // Target ID (0-255)
    var lun: UInt64                    // Logical Unit Number
    var cdb: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)  // 16 bytes
    var cdbLength: UInt8               // CDB length (6, 10, 12, or 16)
    var dataDirection: UInt8           // 0=none, 1=read, 2=write
    var padding1: UInt16               // 2 bytes padding for alignment
    var transferLength: UInt32         // Expected transfer length
    var dataBufferOffset: UInt32       // Offset in data pool
    var reserved: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8)  // 28 bytes padding

    static let size = 80

    /// Get CDB as an array for easier manipulation
    var cdbArray: [UInt8] {
        return [cdb.0, cdb.1, cdb.2, cdb.3, cdb.4, cdb.5, cdb.6, cdb.7,
                cdb.8, cdb.9, cdb.10, cdb.11, cdb.12, cdb.13, cdb.14, cdb.15]
    }

    /// Default initializer
    init() {
        taskTag = 0
        targetID = 0
        lun = 0
        cdb = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        cdbLength = 0
        dataDirection = 0
        padding1 = 0
        transferLength = 0
        dataBufferOffset = 0
        reserved = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    /// Initialize from raw pointer
    init(from pointer: UnsafeRawPointer) {
        self = pointer.load(as: SCSICommandDescriptor.self)
    }
}

/// SCSI Completion Descriptor (280 bytes, matches C++ struct)
struct SCSICompletionDescriptor {
    var taskTag: UInt64                // Kernel task identifier
    var initiatorTaskTag: UInt32       // iSCSI ITT
    var scsiStatus: UInt8              // SCSI status byte
    var serviceResponse: UInt8         // iSCSI response code
    var senseLength: UInt16            // Sense data length
    var senseData: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8)  // 244 bytes
    var dataTransferCount: UInt32      // Actual bytes transferred
    var residualCount: UInt32          // Residual count
    var reserved: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8)  // 12 bytes padding

    static let size = 280

    init() {
        taskTag = 0
        initiatorTaskTag = 0
        scsiStatus = 0
        serviceResponse = 0
        senseLength = 0
        senseData = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        dataTransferCount = 0
        residualCount = 0
        reserved = (0,0,0,0,0,0,0,0,0,0,0,0)
    }

    init(taskTag: UInt64, itt: UInt32, scsiStatus: UInt8, transferCount: UInt32) {
        self.init()
        self.taskTag = taskTag
        self.initiatorTaskTag = itt
        self.scsiStatus = scsiStatus
        self.serviceResponse = 0  // 0 = success
        self.dataTransferCount = transferCount
    }

    /// Write to raw pointer
    func write(to pointer: UnsafeMutableRawPointer) {
        withUnsafeBytes(of: self) { bytes in
            pointer.copyMemory(from: bytes.baseAddress!, byteCount: MemoryLayout<SCSICompletionDescriptor>.size)
        }
    }
}

/// Data direction for SCSI commands
enum SCSIDataDirection: UInt8 {
    case none = 0
    case read = 1   // Device -> Host
    case write = 2  // Host -> Device
}

/// SCSI Status codes
enum SCSIStatus: UInt8 {
    case good = 0x00
    case checkCondition = 0x02
    case conditionMet = 0x04
    case busy = 0x08
    case intermediate = 0x10
    case intermediateConditionMet = 0x14
    case reservationConflict = 0x18
    case commandTerminated = 0x22
    case queueFull = 0x28
    case aCAActive = 0x30
    case taskAborted = 0x40
}

/// Service Response codes
enum ServiceResponse: UInt8 {
    case success = 0
    case targetFailure = 1
}
