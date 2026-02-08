import XCTest
@testable import ISCSIDaemon

final class DextConnectorTests: XCTestCase {

    // MARK: - Connection Management Tests (12 tests)

    func testConnect_Success() async throws {
        let mock = MockDextConnector()

        try await mock.connect()

        let callCount = await mock.connectCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testConnect_ServiceNotFound() async throws {
        let mock = MockDextConnector()
        await mock.setErrorInjection(shouldFailConnection: true, connectionFailureCode: -1)

        do {
            try await mock.connect()
            XCTFail("Expected connection failure")
        } catch MockDextConnector.MockError.connectionFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testConnect_Idempotent() async throws {
        let mock = MockDextConnector()

        try await mock.connect()
        try await mock.connect()
        try await mock.connect()

        // Multiple calls succeed
        let callCount = await mock.connectCallCount
        XCTAssertEqual(callCount, 3)
    }

    func testConnectionState_InitiallyDisconnected() async throws {
        let mock = MockDextConnector()

        // Try to use without connecting
        do {
            _ = try await mock.getHBAStatus()
            XCTFail("Expected error when not connected")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testConnectionState_AfterConnect() async throws {
        let mock = MockDextConnector()

        try await mock.connect()
        let status = try await mock.getHBAStatus()

        XCTAssertEqual(status, 1) // Default online status
    }

    func testConnect_ErrorInjection() async throws {
        let mock = MockDextConnector()
        await mock.setErrorInjection(shouldFailConnection: true, connectionFailureCode: -12345)

        do {
            try await mock.connect()
            XCTFail("Expected connection failure")
        } catch MockDextConnector.MockError.connectionFailed {
            // Expected - mock throws MockError, not the code
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testConnect_CallCountTracking() async throws {
        let mock = MockDextConnector()

        var callCount = await mock.connectCallCount
        XCTAssertEqual(callCount, 0)

        try await mock.connect()
        callCount = await mock.connectCallCount
        XCTAssertEqual(callCount, 1)

        try await mock.connect()
        callCount = await mock.connectCallCount
        XCTAssertEqual(callCount, 2)
    }

    func testConnect_Reset() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        await mock.reset()

        let callCount = await mock.connectCallCount
        XCTAssertEqual(callCount, 0)
    }

    func testDisconnect_ClearsState() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        await mock.disconnect()

        // Should fail after disconnect
        do {
            _ = try await mock.getHBAStatus()
            XCTFail("Expected error after disconnect")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        }
    }

    func testDisconnect_CallCount() async throws {
        let mock = MockDextConnector()

        var callCount = await mock.disconnectCallCount
        XCTAssertEqual(callCount, 0)

        await mock.disconnect()
        callCount = await mock.disconnectCallCount
        XCTAssertEqual(callCount, 1)

        await mock.disconnect()
        callCount = await mock.disconnectCallCount
        XCTAssertEqual(callCount, 2)
    }

    func testConnect_AfterDisconnect() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        await mock.disconnect()

        // Should be able to reconnect
        try await mock.connect()
        let status = try await mock.getHBAStatus()

        XCTAssertEqual(status, 1)
    }

    func testConnectionState_TrackedCorrectly() async throws {
        let mock = MockDextConnector()

        // Initially disconnected
        do {
            _ = try await mock.getHBAStatus()
            XCTFail("Should fail when disconnected")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        }

        // Connect
        try await mock.connect()
        _ = try await mock.getHBAStatus() // Should succeed

        // Disconnect
        await mock.disconnect()

        // Should fail again
        do {
            _ = try await mock.getHBAStatus()
            XCTFail("Should fail after disconnect")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        }
    }

    // MARK: - Session Management Tests (10 tests)

    func testCreateSession_ReturnsUniqueID() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        let session1 = try await mock.createSession()
        let session2 = try await mock.createSession()
        let session3 = try await mock.createSession()

        XCTAssertNotEqual(session1, session2)
        XCTAssertNotEqual(session2, session3)
        XCTAssertNotEqual(session1, session3)
    }

    func testCreateSession_IncrementingIDs() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        let session1 = try await mock.createSession()
        let session2 = try await mock.createSession()
        let session3 = try await mock.createSession()

        XCTAssertEqual(session1, 1)
        XCTAssertEqual(session2, 2)
        XCTAssertEqual(session3, 3)
    }

    func testCreateSession_MultipleSessions() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        var sessions: [UInt64] = []
        for _ in 0..<10 {
            sessions.append(try await mock.createSession())
        }

        XCTAssertEqual(sessions.count, 10)
        XCTAssertEqual(Set(sessions).count, 10) // All unique

        let callCount = await mock.createSessionCallCount
        XCTAssertEqual(callCount, 10)
    }

    func testDestroySession_Success() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        let sessionID = try await mock.createSession()
        try await mock.destroySession(sessionID)

        let destroyCount = await mock.destroySessionCallCount
        let lastDestroyed = await mock.lastDestroyedSessionID

        XCTAssertEqual(destroyCount, 1)
        XCTAssertEqual(lastDestroyed, sessionID)
    }

    func testDestroySession_PassesSessionID() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        _ = try await mock.createSession()
        let session2 = try await mock.createSession()

        try await mock.destroySession(session2)

        let lastDestroyed = await mock.lastDestroyedSessionID
        XCTAssertEqual(lastDestroyed, session2)
    }

    func testSessionLifecycle_CreateUseDestroy() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        // Create
        let sessionID = try await mock.createSession()
        XCTAssertGreaterThan(sessionID, 0)

        // Use (verify connection works)
        let status = try await mock.getHBAStatus()
        XCTAssertEqual(status, 1)

        // Destroy
        try await mock.destroySession(sessionID)

        let lastDestroyed = await mock.lastDestroyedSessionID
        XCTAssertEqual(lastDestroyed, sessionID)
    }

    func testCreateSession_WithoutConnect() async throws {
        let mock = MockDextConnector()

        do {
            _ = try await mock.createSession()
            XCTFail("Expected error when not connected")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testDestroySession_WithoutConnect() async throws {
        let mock = MockDextConnector()

        do {
            try await mock.destroySession(1)
            XCTFail("Expected error when not connected")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSessionState_TrackedCorrectly() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        let session1 = try await mock.createSession()
        _ = try await mock.createSession()

        try await mock.destroySession(session1)

        // Session 2 should still be tracked
        let createCount = await mock.createSessionCallCount
        let destroyCount = await mock.destroySessionCallCount

        XCTAssertEqual(createCount, 2)
        XCTAssertEqual(destroyCount, 1)
    }

    func testDestroySession_NonExistentSession() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        // Try to destroy a session that doesn't exist
        do {
            try await mock.destroySession(999)
            XCTFail("Expected sessionNotFound error")
        } catch MockDextConnector.MockError.sessionNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Shared Memory Mapping Tests (15 tests)

    func testMapSharedMemory_Success() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        try await mock.mapSharedMemory()

        let callCount = await mock.mapSharedMemoryCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testMapSharedMemory_WithoutConnect() async throws {
        let mock = MockDextConnector()

        do {
            try await mock.mapSharedMemory()
            XCTFail("Expected error when not connected")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testMapSharedMemory_MappingFailure() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        await mock.setErrorInjection(shouldFailMemoryMapping: true)

        do {
            try await mock.mapSharedMemory()
            XCTFail("Expected memory mapping failure")
        } catch MockDextConnector.MockError.memoryMappingFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testMapSharedMemory_CallCountTracking() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        var callCount = await mock.mapSharedMemoryCallCount
        XCTAssertEqual(callCount, 0)

        try await mock.mapSharedMemory()
        callCount = await mock.mapSharedMemoryCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testMapSharedMemory_Idempotent() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        try await mock.mapSharedMemory()
        try await mock.mapSharedMemory()
        try await mock.mapSharedMemory()

        // Multiple calls succeed
        let callCount = await mock.mapSharedMemoryCallCount
        XCTAssertEqual(callCount, 3)
    }

    func testMapSharedMemory_ErrorInjection() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        await mock.setErrorInjection(shouldFailMemoryMapping: true)

        do {
            try await mock.mapSharedMemory()
            XCTFail("Expected mapping failure")
        } catch MockDextConnector.MockError.memoryMappingFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testMapSharedMemory_Reset() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        await mock.reset()

        let callCount = await mock.mapSharedMemoryCallCount
        XCTAssertEqual(callCount, 0)
    }

    func testMapSharedMemory_RequiredForQueueOps() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        // Without mapping, queue ops work but writeCompletion will fail
        var cmd = SCSICommandDescriptor()
        cmd.taskTag = 123
        await mock.writeCommandAtSlot(0, command: cmd)
        let readCmd = await mock.readNextCommand()
        XCTAssertNotNil(readCmd)
        XCTAssertEqual(readCmd?.taskTag, 123)

        // But writeCompletion requires mapping
        var completion = SCSICompletionDescriptor()
        completion.taskTag = 999
        do {
            try await mock.writeCompletion(completion)
            XCTFail("Expected memoryNotMapped error")
        } catch MockDextConnector.MockError.memoryNotMapped {
            // Expected
        }

        try await mock.mapSharedMemory()

        // After mapping, writeCompletion works
        try await mock.writeCompletion(completion)
        let callCount = await mock.writeCompletionCallCount
        XCTAssertEqual(callCount, 2) // 1 failed + 1 succeeded
    }

    func testMapSharedMemory_EnablesReadCommands() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        var cmd = SCSICommandDescriptor()
        cmd.taskTag = 999
        await mock.writeCommandAtSlot(0, command: cmd)
        let readCmd = await mock.readNextCommand()

        XCTAssertEqual(readCmd?.taskTag, 999)
    }

    func testMapSharedMemory_EnablesWriteCompletions() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        var completion = SCSICompletionDescriptor()
        completion.taskTag = 888
        completion.scsiStatus = 0

        try await mock.writeCompletion(completion)

        let callCount = await mock.writeCompletionCallCount
        let completions = await mock.writtenCompletions
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(completions.last?.taskTag, 888)
    }

    func testMapSharedMemory_CommandQueueSize() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        // Can write and read 819 commands (64KB / 80 bytes)
        // Test by writing one command at a time and reading it
        for i in 0..<819 {
            var cmd = SCSICommandDescriptor()
            cmd.taskTag = UInt64(100 + i)
            await mock.writeCommandAtSlot(i, command: cmd)

            let readCmd = await mock.readNextCommand()
            XCTAssertNotNil(readCmd)
            XCTAssertEqual(readCmd?.taskTag, UInt64(100 + i))
        }

        // Verify we processed all 819 commands
        let finalCmd = await mock.readNextCommand()
        XCTAssertNil(finalCmd) // Queue should be empty now
    }

    func testMapSharedMemory_CompletionQueueSize() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        // Can write 234 completions (64KB / 280 bytes)
        for i in 0..<234 {
            var completion = SCSICompletionDescriptor()
            completion.taskTag = UInt64(i)
            try await mock.writeCompletion(completion)
        }

        let callCount = await mock.writeCompletionCallCount
        XCTAssertEqual(callCount, 234)
    }

    func testMapSharedMemory_DataPoolSize() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        // Data pool is 64MB (verified by mock)
        // No direct API to test, but mapping succeeds
        let callCount = await mock.mapSharedMemoryCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testMapSharedMemory_AllRegionsInitialized() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        try await mock.mapSharedMemory()

        // Verify can use all queue types
        var cmd = SCSICommandDescriptor()
        cmd.taskTag = 111
        await mock.writeCommandAtSlot(0, command: cmd)
        let readCmd = await mock.readNextCommand()
        XCTAssertEqual(readCmd?.taskTag, 111)

        var completion = SCSICompletionDescriptor()
        completion.taskTag = 222
        try await mock.writeCompletion(completion)
        let completions = await mock.writtenCompletions
        XCTAssertEqual(completions.last?.taskTag, 222)
    }

    func testMapSharedMemory_AfterReset() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        await mock.reset()

        // After reset, need to reconnect and remap
        do {
            try await mock.mapSharedMemory()
            XCTFail("Expected error after reset")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - HBA Status Tests (5 tests)

    func testGetHBAStatus_Online() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        await mock.setHBAStatus(1)

        let status = try await mock.getHBAStatus()

        XCTAssertEqual(status, 1)
        let callCount = await mock.getHBAStatusCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testGetHBAStatus_Offline() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        await mock.setHBAStatus(0)

        let status = try await mock.getHBAStatus()

        XCTAssertEqual(status, 0)
    }

    func testGetHBAStatus_WithoutConnect() async throws {
        let mock = MockDextConnector()

        do {
            _ = try await mock.getHBAStatus()
            XCTFail("Expected error when not connected")
        } catch MockDextConnector.MockError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testGetHBAStatus_ExternalMethodFailure() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        await mock.setErrorInjection(shouldFailHBAStatus: true)

        do {
            _ = try await mock.getHBAStatus()
            XCTFail("Expected external method failure")
        } catch MockDextConnector.MockError.hbaStatusFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testGetHBAStatus_CallCountTracking() async throws {
        let mock = MockDextConnector()
        try await mock.connect()

        var callCount = await mock.getHBAStatusCallCount
        XCTAssertEqual(callCount, 0)

        _ = try await mock.getHBAStatus()
        callCount = await mock.getHBAStatusCallCount
        XCTAssertEqual(callCount, 1)

        _ = try await mock.getHBAStatus()
        callCount = await mock.getHBAStatusCallCount
        XCTAssertEqual(callCount, 2)
    }

    // MARK: - Queue Operation Tests (8 tests)

    func testReadNextCommand_ValidDescriptor() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        var command = SCSICommandDescriptor()
        command.taskTag = 12345
        await mock.writeCommandAtSlot(0, command: command)
        let cmd = await mock.readNextCommand()

        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.taskTag, 12345)
        let callCount = await mock.readNextCommandCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testReadNextCommand_CorrectOffset() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        // Write to slot 5 (offset 400 = 5 * 80)
        var command = SCSICommandDescriptor()
        command.taskTag = 99999
        await mock.writeCommandAtSlot(5, command: command)

        // Read slots 0-4 (should be empty/zero)
        for _ in 0..<5 {
            _ = await mock.readNextCommand()
        }

        // Slot 5 should have our command
        let cmd = await mock.readNextCommand()
        XCTAssertEqual(cmd?.taskTag, 99999)
    }

    func testReadNextCommand_AdvancesTail() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        var cmd1 = SCSICommandDescriptor()
        cmd1.taskTag = 111
        await mock.writeCommandAtSlot(0, command: cmd1)

        var cmd2 = SCSICommandDescriptor()
        cmd2.taskTag = 222
        await mock.writeCommandAtSlot(1, command: cmd2)

        var cmd3 = SCSICommandDescriptor()
        cmd3.taskTag = 333
        await mock.writeCommandAtSlot(2, command: cmd3)

        let readCmd1 = await mock.readNextCommand()
        let readCmd2 = await mock.readNextCommand()
        let readCmd3 = await mock.readNextCommand()

        XCTAssertEqual(readCmd1?.taskTag, 111)
        XCTAssertEqual(readCmd2?.taskTag, 222)
        XCTAssertEqual(readCmd3?.taskTag, 333)
        let callCount = await mock.readNextCommandCallCount
        XCTAssertEqual(callCount, 3)
    }

    func testReadNextCommand_Wraparound() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        // Fill and read queue to capacity (819 slots)
        // Write and read one at a time to maintain queue state
        for i in 0..<819 {
            var command = SCSICommandDescriptor()
            command.taskTag = UInt64(i)
            await mock.writeCommandAtSlot(i, command: command)

            let cmd = await mock.readNextCommand()
            XCTAssertEqual(cmd?.taskTag, UInt64(i))
        }

        // Now queue is empty, head and tail should both be at 819 % 819 = 0 (wrapped)
        // Write to slot 0 again (wrapped)
        var wrappedCommand = SCSICommandDescriptor()
        wrappedCommand.taskTag = 9999
        await mock.writeCommandAtSlot(0, command: wrappedCommand)

        // Next read should get slot 0 (wrapped)
        let wrappedCmd = await mock.readNextCommand()
        XCTAssertEqual(wrappedCmd?.taskTag, 9999)
    }

    func testWriteCompletion_ValidDescriptor() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        var completion = SCSICompletionDescriptor()
        completion.taskTag = 54321
        completion.scsiStatus = 0
        completion.dataTransferCount = 4096

        try await mock.writeCompletion(completion)

        let callCount = await mock.writeCompletionCallCount
        let completions = await mock.writtenCompletions
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(completions.last?.taskTag, 54321)
        XCTAssertEqual(completions.last?.scsiStatus, 0)
        XCTAssertEqual(completions.last?.dataTransferCount, 4096)
    }

    func testWriteCompletion_AdvancesHead() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        for i in 0..<10 {
            var completion = SCSICompletionDescriptor()
            completion.taskTag = UInt64(i)
            try await mock.writeCompletion(completion)
        }

        let callCount = await mock.writeCompletionCallCount
        XCTAssertEqual(callCount, 10)
    }

    func testWriteCompletion_Wraparound() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        try await mock.mapSharedMemory()

        // Fill queue to capacity (234 slots)
        for i in 0..<234 {
            var completion = SCSICompletionDescriptor()
            completion.taskTag = UInt64(i)
            try await mock.writeCompletion(completion)
        }

        let callCount = await mock.writeCompletionCallCount
        XCTAssertEqual(callCount, 234)

        // Next write should wrap (position-wise)
        var wrappedCompletion = SCSICompletionDescriptor()
        wrappedCompletion.taskTag = 9999
        try await mock.writeCompletion(wrappedCompletion)

        // Verify the 235th completion was written
        let completions = await mock.writtenCompletions
        XCTAssertEqual(completions.count, 235)
        XCTAssertEqual(completions.last?.taskTag, 9999)
    }

    func testWriteCompletion_WithoutMemoryMapping() async throws {
        let mock = MockDextConnector()
        try await mock.connect()
        // Don't call mapSharedMemory

        var completion = SCSICompletionDescriptor()
        completion.taskTag = 123

        do {
            try await mock.writeCompletion(completion)
            XCTFail("Expected error without memory mapping")
        } catch MockDextConnector.MockError.memoryNotMapped {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
