import Foundation
import IOKit

// Note: DextTypes.swift is expected to be in the same module
// and defines: UserClientSelector, SharedMemoryType, SCSICommandDescriptor, SCSICompletionDescriptor

/// Errors that can occur during dext connection
enum DextConnectorError: Error {
    case serviceNotFound
    case connectionFailed(Int32)
    case memoryMappingFailed(Int32)
    case externalMethodFailed(Int32)
    case invalidMemoryPointer
}

/// Manages connection to iSCSIVirtualHBA dext and shared memory access
actor DextConnector: DextConnectorProtocol {
    private var connection: io_connect_t = 0

    // Mapped memory pointers
    private var commandQueuePointer: UnsafeMutableRawPointer?
    private var completionQueuePointer: UnsafeMutableRawPointer?
    private var dataPoolPointer: UnsafeMutableRawPointer?

    // Memory sizes
    private let commandQueueSize: UInt64 = 65536      // 64 KB
    private let completionQueueSize: UInt64 = 65536   // 64 KB
    private let dataPoolSize: UInt64 = 67108864       // 64 MB

    // Queue management
    private var commandQueueTail: UInt32 = 0  // Next command to read
    private var completionQueueHead: UInt32 = 0  // Next slot to write completion

    // Constants
    private let maxCommandDescriptors: UInt32 = 819   // 64KB / 80 bytes
    private let maxCompletionDescriptors: UInt32 = 234 // 64KB / 280 bytes

    /// Connect to the iSCSIVirtualHBA dext
    func connect() throws {
        // Find iSCSIVirtualHBA service
        let matching = IOServiceMatching("iSCSIVirtualHBA")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)

        guard service != 0 else {
            throw DextConnectorError.serviceNotFound
        }

        // Open connection
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard result == KERN_SUCCESS else {
            throw DextConnectorError.connectionFailed(result)
        }

        print("✓ Connected to iSCSIVirtualHBA dext")
    }

    /// Map all shared memory regions
    func mapSharedMemory() throws {
        try mapMemoryRegion(type: .commandQueue, pointer: &commandQueuePointer, size: commandQueueSize)
        try mapMemoryRegion(type: .completionQueue, pointer: &completionQueuePointer, size: completionQueueSize)
        try mapMemoryRegion(type: .dataBufferPool, pointer: &dataPoolPointer, size: dataPoolSize)

        print("✓ Mapped all shared memory regions")
    }

    /// Map a single memory region
    private func mapMemoryRegion(
        type: SharedMemoryType,
        pointer: inout UnsafeMutableRawPointer?,
        size expectedSize: UInt64
    ) throws {
        var address: mach_vm_address_t = 0
        var size: mach_vm_size_t = 0

        let result = IOConnectMapMemory64(
            connection,
            type.rawValue,
            mach_task_self_,
            &address,
            &size,
            kIOMapAnywhere | kIOMapDefaultCache)

        guard result == KERN_SUCCESS else {
            throw DextConnectorError.memoryMappingFailed(result)
        }

        if size != expectedSize {
            print("⚠ Warning: Memory region \(type) size mismatch (expected \(expectedSize), got \(size))")
        }

        pointer = UnsafeMutableRawPointer(bitPattern: UInt(address))

        guard pointer != nil else {
            throw DextConnectorError.invalidMemoryPointer
        }

        print("  ✓ Mapped \(type): \(size) bytes at 0x\(String(format: "%llx", address))")
    }

    /// Get HBA status
    func getHBAStatus() throws -> UInt64 {
        var status: UInt64 = 0
        var outputCount: UInt32 = 1

        let result = IOConnectCallScalarMethod(
            connection,
            UserClientSelector.getHBAStatus.rawValue,
            nil,
            0,
            &status,
            &outputCount)

        guard result == KERN_SUCCESS else {
            throw DextConnectorError.externalMethodFailed(result)
        }

        return status
    }

    /// Create a session
    func createSession() throws -> UInt64 {
        var sessionID: UInt64 = 0
        var outputCount: UInt32 = 1

        let result = IOConnectCallScalarMethod(
            connection,
            UserClientSelector.createSession.rawValue,
            nil,
            0,
            &sessionID,
            &outputCount)

        guard result == KERN_SUCCESS else {
            throw DextConnectorError.externalMethodFailed(result)
        }

        return sessionID
    }

    /// Destroy a session
    func destroySession(_ sessionID: UInt64) throws {
        var inputs: [UInt64] = [sessionID]

        let result = IOConnectCallScalarMethod(
            connection,
            UserClientSelector.destroySession.rawValue,
            &inputs,
            1,
            nil,
            nil)

        guard result == KERN_SUCCESS else {
            throw DextConnectorError.externalMethodFailed(result)
        }
    }

    /// Check if there are pending commands in the queue
    func hasPendingCommands() -> Bool {
        guard commandQueuePointer != nil else { return false }

        // Compare head (written by dext) with our tail (what we've read)
        // For now, we don't have a way to read the head pointer from dext
        // In a real implementation, we'd need a control structure for this
        // For Phase 5, we'll implement polling

        return false  // Placeholder
    }

    /// Read next command from command queue
    func readNextCommand() -> SCSICommandDescriptor? {
        guard let pointer = commandQueuePointer else { return nil }

        // For now, simple implementation: read from current tail position
        let commandPointer = pointer.advanced(by: Int(commandQueueTail) * SCSICommandDescriptor.size)
        let command = SCSICommandDescriptor(from: commandPointer)

        // Advance tail
        commandQueueTail = (commandQueueTail + 1) % maxCommandDescriptors

        return command
    }

    /// Write completion to completion queue
    func writeCompletion(_ completion: SCSICompletionDescriptor) throws {
        guard let pointer = completionQueuePointer else {
            throw DextConnectorError.invalidMemoryPointer
        }

        // Check if queue is full
        let nextHead = (completionQueueHead + 1) % maxCompletionDescriptors
        // TODO: Need to track tail from dext to detect full queue

        // Write completion
        let completionPointer = pointer.advanced(by: Int(completionQueueHead) * SCSICompletionDescriptor.size)
        completion.write(to: completionPointer)

        // Advance head
        completionQueueHead = nextHead

        // Notify dext via external method
        try sendCompletion(completion)
    }

    /// Send completion to dext via external method
    private func sendCompletion(_ completion: SCSICompletionDescriptor) throws {
        var completionCopy = completion

        // Convert to raw bytes
        let completionData = withUnsafeBytes(of: &completionCopy) { Data($0) }

        try completionData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                throw DextConnectorError.externalMethodFailed(-1)
            }

            let result = IOConnectCallStructMethod(
                connection,
                UserClientSelector.completeSCSITask.rawValue,
                baseAddress,
                SCSICompletionDescriptor.size,
                nil,
                nil)

            guard result == KERN_SUCCESS else {
                throw DextConnectorError.externalMethodFailed(result)
            }
        }
    }

    /// Read data from data pool
    func readDataFromPool(offset: UInt32, length: UInt32) -> Data? {
        guard let pointer = dataPoolPointer else { return nil }
        guard offset + length <= dataPoolSize else { return nil }

        let dataPointer = pointer.advanced(by: Int(offset))
        return Data(bytes: dataPointer, count: Int(length))
    }

    /// Write data to data pool
    func writeDataToPool(data: Data, offset: UInt32) -> Bool {
        guard let pointer = dataPoolPointer else { return false }
        guard offset + UInt32(data.count) <= dataPoolSize else { return false }

        let dataPointer = pointer.advanced(by: Int(offset))
        data.withUnsafeBytes { bytes in
            dataPointer.copyMemory(from: bytes.baseAddress!, byteCount: data.count)
        }

        return true
    }

    /// Disconnect from dext
    func disconnect() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
            print("✓ Disconnected from dext")
        }

        // Clear memory pointers (memory is automatically unmapped by kernel)
        commandQueuePointer = nil
        completionQueuePointer = nil
        dataPoolPointer = nil
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }
}

extension SharedMemoryType: CustomStringConvertible {
    var description: String {
        switch self {
        case .commandQueue: return "CommandQueue"
        case .completionQueue: return "CompletionQueue"
        case .dataBufferPool: return "DataBufferPool"
        }
    }
}
