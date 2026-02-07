import Foundation

// SCSI Command Descriptor (80 bytes)
public struct SCSICommandDescriptor {
    public var taskTag: UInt64              // 8 bytes
    public var targetID: UInt32             // 4 bytes
    public var lun: UInt64                  // 8 bytes
    public var cdb: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)  // 16 bytes
    public var cdbLength: UInt8             // 1 byte
    public var dataDirection: UInt8         // 1 byte (0=none, 1=read, 2=write)
    public var padding1: UInt16             // 2 bytes padding for alignment
    public var transferLength: UInt32       // 4 bytes
    public var dataBufferOffset: UInt32     // 4 bytes
    public var reserved: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8)  // 28 bytes

    public init() {
        self.taskTag = 0
        self.targetID = 0
        self.lun = 0
        self.cdb = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        self.cdbLength = 0
        self.dataDirection = 0
        self.padding1 = 0
        self.transferLength = 0
        self.dataBufferOffset = 0
        self.reserved = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }
}

// SCSI Completion Descriptor (280 bytes)
public struct SCSICompletionDescriptor {
    public var taskTag: UInt64              // 8 bytes
    public var initiatorTaskTag: UInt32     // 4 bytes
    public var scsiStatus: UInt8            // 1 byte
    public var serviceResponse: UInt8       // 1 byte
    public var senseLength: UInt16          // 2 bytes
    public var senseData: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
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
                           UInt8, UInt8, UInt8, UInt8)  // 244 bytes (30.5 lines of 8)
    public var dataTransferCount: UInt32    // 4 bytes
    public var residualCount: UInt32        // 4 bytes
    public var reserved: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8)  // 12 bytes

    public init() {
        self.taskTag = 0
        self.initiatorTaskTag = 0
        self.scsiStatus = 0
        self.serviceResponse = 0
        self.senseLength = 0
        self.senseData = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        self.dataTransferCount = 0
        self.residualCount = 0
        self.reserved = (0,0,0,0,0,0,0,0,0,0,0,0)
    }
}

// Test Constants
public enum TestConstants {
    // Memory sizes
    public static let commandQueueSize: UInt64 = 65536      // 64 KB
    public static let completionQueueSize: UInt64 = 65536   // 64 KB
    public static let dataPoolSize: UInt64 = 67108864       // 64 MB

    // Queue capacities
    public static let commandQueueCapacity = 819    // 64KB / 80 bytes
    public static let completionQueueCapacity = 234 // 64KB / 280 bytes

    // SCSI constants
    public static let maxLUN: UInt64 = 63
    public static let maxTaskCount: UInt32 = 256
}
