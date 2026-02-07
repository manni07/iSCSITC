import Foundation
@testable import ISCSIDaemon

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
