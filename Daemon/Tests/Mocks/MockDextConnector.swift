// MockDextConnector.swift
// IMPORTANT: This file must use the REAL SCSICommandDescriptor and SCSICompletionDescriptor
// from DextTypes.swift, NOT the test fixture versions from TestFixtures.swift.
// To avoid ambiguity, we do NOT import Foundation (which TestFixtures uses).
// We only import ISCSIDaemon.

@testable import ISCSIDaemon

/// Mock implementation of DextConnectorProtocol for testing
actor MockDextConnector: DextConnectorProtocol {
    // MARK: - State Management

    /// Connection state
    private(set) var isConnected = false

    /// Memory mapping state
    private(set) var isMemoryMapped = false

    /// Active sessions (sessionID -> created)
    private(set) var sessions: [UInt64: Bool] = [:]

    /// Next session ID to assign
    private var nextSessionID: UInt64 = 1

    /// HBA status value
    private var hbaStatus: UInt64 = 0

    /// Command queue (simulated ring buffer)
    private var commandQueue: [SCSICommandDescriptor] = []
    private var commandQueueHead = 0
    private var commandQueueTail = 0
    private let commandQueueSize = 819  // 64KB / 80 bytes

    /// Completion queue (simulated ring buffer)
    private var completionQueue: [SCSICompletionDescriptor] = []
    private var completionQueueHead = 0
    private var completionQueueTail = 0
    private let completionQueueSize = 234  // 64KB / 280 bytes

    // MARK: - Error Injection

    /// Should connect() throw an error
    var shouldFailConnection = false

    /// Should mapSharedMemory() throw an error
    var shouldFailMemoryMapping = false

    /// Should getHBAStatus() throw an error
    var shouldFailHBAStatus = false

    /// Should createSession() throw an error
    var shouldFailCreateSession = false

    /// Should destroySession() throw an error
    var shouldFailDestroySession = false

    /// Should writeCompletion() throw an error
    var shouldFailWriteCompletion = false

    // MARK: - Call Tracking

    /// Number of times connect() was called
    private(set) var connectCallCount = 0

    /// Number of times mapSharedMemory() was called
    private(set) var mapSharedMemoryCallCount = 0

    /// Number of times getHBAStatus() was called
    private(set) var getHBAStatusCallCount = 0

    /// Number of times createSession() was called
    private(set) var createSessionCallCount = 0

    /// Number of times destroySession() was called
    private(set) var destroySessionCallCount = 0

    /// Session IDs passed to destroySession()
    private(set) var destroyedSessionIDs: [UInt64] = []

    /// Number of times hasPendingCommands() was called
    private(set) var hasPendingCommandsCallCount = 0

    /// Number of times readNextCommand() was called
    private(set) var readNextCommandCallCount = 0

    /// Number of times writeCompletion() was called
    private(set) var writeCompletionCallCount = 0

    /// Completions written via writeCompletion()
    private(set) var writtenCompletions: [SCSICompletionDescriptor] = []

    /// Number of times disconnect() was called
    private(set) var disconnectCallCount = 0

    // MARK: - Errors

    enum MockError: Error {
        case connectionFailed
        case memoryMappingFailed
        case hbaStatusFailed
        case createSessionFailed
        case destroySessionFailed
        case writeCompletionFailed
        case sessionNotFound
        case notConnected
        case memoryNotMapped
    }

    // MARK: - DextConnectorProtocol Implementation

    func connect() async throws {
        connectCallCount += 1

        if shouldFailConnection {
            throw MockError.connectionFailed
        }

        isConnected = true
    }

    func mapSharedMemory() async throws {
        mapSharedMemoryCallCount += 1

        if shouldFailMemoryMapping {
            throw MockError.memoryMappingFailed
        }

        guard isConnected else {
            throw MockError.notConnected
        }

        isMemoryMapped = true
    }

    func getHBAStatus() async throws -> UInt64 {
        getHBAStatusCallCount += 1

        if shouldFailHBAStatus {
            throw MockError.hbaStatusFailed
        }

        guard isConnected else {
            throw MockError.notConnected
        }

        return hbaStatus
    }

    func createSession() async throws -> UInt64 {
        createSessionCallCount += 1

        if shouldFailCreateSession {
            throw MockError.createSessionFailed
        }

        guard isConnected else {
            throw MockError.notConnected
        }

        let sessionID = nextSessionID
        nextSessionID += 1
        sessions[sessionID] = true

        return sessionID
    }

    func destroySession(_ sessionID: UInt64) async throws {
        destroySessionCallCount += 1
        destroyedSessionIDs.append(sessionID)

        if shouldFailDestroySession {
            throw MockError.destroySessionFailed
        }

        guard isConnected else {
            throw MockError.notConnected
        }

        guard sessions[sessionID] != nil else {
            throw MockError.sessionNotFound
        }

        sessions.removeValue(forKey: sessionID)
    }

    func hasPendingCommands() async -> Bool {
        hasPendingCommandsCallCount += 1
        return commandQueueHead != commandQueueTail
    }

    func readNextCommand() async -> SCSICommandDescriptor? {
        readNextCommandCallCount += 1

        guard commandQueueHead != commandQueueTail else {
            return nil
        }

        let command = commandQueue[commandQueueHead]
        commandQueueHead = (commandQueueHead + 1) % commandQueueSize

        return command
    }

    func writeCompletion(_ completion: SCSICompletionDescriptor) async throws {
        writeCompletionCallCount += 1
        writtenCompletions.append(completion)

        if shouldFailWriteCompletion {
            throw MockError.writeCompletionFailed
        }

        guard isConnected else {
            throw MockError.notConnected
        }

        guard isMemoryMapped else {
            throw MockError.memoryNotMapped
        }

        // Simulate writing to completion queue
        completionQueue.append(completion)
        completionQueueTail = (completionQueueTail + 1) % completionQueueSize
    }

    func disconnect() async {
        disconnectCallCount += 1
        isConnected = false
        isMemoryMapped = false
    }

    // MARK: - Test Helpers

    /// Set the HBA status value for testing
    func setHBAStatus(_ status: UInt64) {
        hbaStatus = status
    }

    /// Reset all state and counters
    func reset() {
        isConnected = false
        isMemoryMapped = false
        sessions.removeAll()
        nextSessionID = 1
        hbaStatus = 0

        commandQueue.removeAll()
        commandQueueHead = 0
        commandQueueTail = 0

        completionQueue.removeAll()
        completionQueueHead = 0
        completionQueueTail = 0

        shouldFailConnection = false
        shouldFailMemoryMapping = false
        shouldFailHBAStatus = false
        shouldFailCreateSession = false
        shouldFailDestroySession = false
        shouldFailWriteCompletion = false

        connectCallCount = 0
        mapSharedMemoryCallCount = 0
        getHBAStatusCallCount = 0
        createSessionCallCount = 0
        destroySessionCallCount = 0
        destroyedSessionIDs.removeAll()
        hasPendingCommandsCallCount = 0
        readNextCommandCallCount = 0
        writeCompletionCallCount = 0
        writtenCompletions.removeAll()
        disconnectCallCount = 0
    }

    /// Write a command to the command queue at a specific slot for testing
    func writeCommandAtSlot(_ slot: Int, command: SCSICommandDescriptor) {
        guard slot >= 0 && slot < commandQueueSize else {
            return
        }

        // Ensure queue is large enough
        while commandQueue.count <= slot {
            commandQueue.append(SCSICommandDescriptor())
        }

        commandQueue[slot] = command
        commandQueueTail = (slot + 1) % commandQueueSize
    }

    /// Read completion queue at specific slot for testing
    func readCompletionAtSlot(_ slot: Int) -> SCSICompletionDescriptor? {
        guard slot >= 0 && slot < completionQueue.count else {
            return nil
        }
        return completionQueue[slot]
    }

    /// Get current command queue head position
    func getCommandQueueHead() -> Int {
        return commandQueueHead
    }

    /// Get current command queue tail position
    func getCommandQueueTail() -> Int {
        return commandQueueTail
    }

    /// Get number of pending commands
    func getPendingCommandCount() -> Int {
        if commandQueueTail >= commandQueueHead {
            return commandQueueTail - commandQueueHead
        } else {
            return commandQueueSize - commandQueueHead + commandQueueTail
        }
    }
}
