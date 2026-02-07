import Foundation

/// Protocol abstraction for DextConnector to enable testing
protocol DextConnectorProtocol: Actor {
    /// Connect to the iSCSIVirtualHBA dext
    func connect() async throws

    /// Map all shared memory regions
    func mapSharedMemory() async throws

    /// Get HBA status
    func getHBAStatus() async throws -> UInt64

    /// Create a session
    func createSession() async throws -> UInt64

    /// Destroy a session
    func destroySession(_ sessionID: UInt64) async throws

    /// Check if there are pending commands in the queue
    func hasPendingCommands() async -> Bool

    /// Read next command from command queue
    func readNextCommand() async -> SCSICommandDescriptor?

    /// Write completion to completion queue
    func writeCompletion(_ completion: SCSICompletionDescriptor) async throws

    /// Disconnect from dext
    func disconnect() async
}
