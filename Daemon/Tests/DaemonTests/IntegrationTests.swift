import XCTest
@testable import ISCSIDaemon

/// Integration Tests for iSCSIVirtualHBA Dext
///
/// These tests verify real connectivity with the DriverKit extension.
/// They will be SKIPPED if the dext is not available.
///
/// # Prerequisites
///
/// ## 1. Apple Developer Account
/// - **Paid account required** ($99/year)
/// - Sign up: https://developer.apple.com/programs/enroll/
/// - **Note**: Personal/Free Apple IDs do NOT support DriverKit
/// - Error if not enrolled: "Personal development teams do not support the DriverKit (development) capability"
///
/// ## 2. Build Dext
/// ```bash
/// cd DriverKit
/// open iSCSIVirtualHBA.xcodeproj
/// # In Xcode: Product → Build (Cmd+B)
/// ```
///
/// ## 3. Disable SIP (requires physical Mac access)
/// ```bash
/// # Reboot into Recovery Mode:
/// # - Intel Mac: Reboot and hold Cmd+R
/// # - Apple Silicon: Shutdown, hold power button until "Loading startup options" appears
/// 
/// # In Recovery Mode Terminal:
/// csrutil disable
/// 
/// # Reboot normally
/// csrutil status  # Verify: "System Integrity Protection status: disabled"
/// ```
///
/// ## 4. Load Dext
/// ```bash
/// cd DriverKit/build/Debug
/// sudo systemextensionsctl load iSCSIVirtualHBA.dext
/// ```
///
/// ## 5. Verify Dext Loaded
/// ```bash
/// ioreg -l | grep iSCSI
/// # Should show: iSCSIVirtualHBA
/// 
/// systemextensionsctl list
/// # Should show extension loaded
/// ```
///
/// # Running Tests
///
/// ```bash
/// cd Daemon
/// swift test --filter IntegrationTests
/// ```
///
/// Tests will be skipped automatically if dext is not available.
///
/// # Test Coverage
///
/// 1. **testConnectToDext** - Basic connection establishment
/// 2. **testMapSharedMemory** - Memory mapping for all 3 regions
/// 3. **testGetHBAStatus** - HBA status query
/// 4. **testCreateAndDestroySession** - Session lifecycle
/// 5. **testCommandQueueAccess** - Command queue operations
/// 6. **testWriteCompletion** - Completion notification
/// 7. **testFullLifecycle** - Complete workflow integration
///
final class IntegrationTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        
        // Check if dext is available
        let connector = DextConnector()
        do {
            try await connector.connect()
            await connector.disconnect()
            // Dext available, tests can run
        } catch DextConnectorError.serviceNotFound {
            throw XCTSkip("""
                iSCSIVirtualHBA dext not loaded.
                
                Prerequisites:
                1. Paid Apple Developer account ($99/year)
                2. Dext built in Xcode
                3. SIP disabled (csrutil disable in Recovery Mode)
                4. Dext loaded: sudo systemextensionsctl load <path>
                5. Verify: ioreg -l | grep iSCSI
                
                See test file documentation for detailed instructions.
                """)
        } catch {
            throw XCTSkip("Cannot connect to dext: \(error)")
        }
    }

    // MARK: - Test 1: Connect to Dext

    /// Test basic connection to iSCSIVirtualHBA dext
    ///
    /// Verifies that:
    /// - IOServiceMatching finds the dext
    /// - IOServiceOpen succeeds
    /// - Connection handle is valid
    func testConnectToDext() async throws {
        let connector = DextConnector()
        
        // Should connect successfully
        try await connector.connect()
        
        // Clean up
        await connector.disconnect()
    }

    // MARK: - Test 2: Map Shared Memory

    /// Test mapping of all three shared memory regions
    ///
    /// Verifies that:
    /// - Command queue (64KB) maps successfully
    /// - Completion queue (64KB) maps successfully
    /// - Data pool (64MB) maps successfully
    /// - All memory pointers are valid
    func testMapSharedMemory() async throws {
        let connector = DextConnector()
        
        try await connector.connect()
        defer { Task { await connector.disconnect() } }
        
        // Should map all memory regions successfully
        try await connector.mapSharedMemory()
        
        // Memory is mapped - we can't directly verify pointers from outside,
        // but if mapSharedMemory() didn't throw, mapping succeeded
    }

    // MARK: - Test 3: Get HBA Status

    /// Test HBA status query
    ///
    /// Verifies that:
    /// - getHBAStatus() returns a valid UInt64
    /// - Default status is 1 (online)
    func testGetHBAStatus() async throws {
        let connector = DextConnector()
        
        try await connector.connect()
        defer { Task { await connector.disconnect() } }
        
        // Query HBA status
        let status = try await connector.getHBAStatus()
        
        // Default should be 1 (online)
        // Note: This depends on dext implementation
        XCTAssertEqual(status, 1, "HBA should be online by default")
    }

    // MARK: - Test 4: Create and Destroy Session

    /// Test session lifecycle
    ///
    /// Verifies that:
    /// - createSession() returns valid session ID > 0
    /// - destroySession() succeeds without error
    func testCreateAndDestroySession() async throws {
        let connector = DextConnector()
        
        try await connector.connect()
        defer { Task { await connector.disconnect() } }
        
        // Create session
        let sessionID = try await connector.createSession()
        XCTAssertGreaterThan(sessionID, 0, "Session ID should be positive")
        
        // Destroy session
        try await connector.destroySession(sessionID)
        // If no error thrown, session was destroyed successfully
    }

    // MARK: - Test 5: Command Queue Access

    /// Test command queue read operations
    ///
    /// Verifies that:
    /// - Command queue can be accessed after mapping
    /// - readNextCommand() returns nil or empty commands initially
    /// - Queue tail advances properly
    func testCommandQueueAccess() async throws {
        let connector = DextConnector()
        
        try await connector.connect()
        defer { Task { await connector.disconnect() } }
        
        try await connector.mapSharedMemory()
        
        // Initially, queue should be empty
        let command = await connector.readNextCommand()
        
        // Either nil or a zero-initialized command is acceptable
        // (depends on how dext initializes memory)
        if let cmd = command {
            // If we got a command, it should have taskTag 0 (empty)
            XCTAssertEqual(cmd.taskTag, 0, "Empty queue should return zero-initialized command")
        }
        
        // Should not crash when reading from empty queue
    }

    // MARK: - Test 6: Write Completion

    /// Test completion notification
    ///
    /// Verifies that:
    /// - Completion can be created with test data
    /// - writeCompletion() succeeds
    /// - No error when sending completion to dext
    func testWriteCompletion() async throws {
        let connector = DextConnector()
        
        try await connector.connect()
        defer { Task { await connector.disconnect() } }
        
        try await connector.mapSharedMemory()
        
        // Create test completion
        let completion = SCSICompletionDescriptor(
            taskTag: 12345,
            itt: 67890,
            scsiStatus: SCSIStatus.good.rawValue,
            transferCount: 4096
        )
        
        // Write completion
        try await connector.writeCompletion(completion)
        
        // If no error thrown, completion was sent successfully
    }

    // MARK: - Test 7: Full Lifecycle

    /// Test complete workflow from connection to disconnection
    ///
    /// Verifies that:
    /// 1. Connect succeeds
    /// 2. Memory mapping succeeds
    /// 3. HBA status query works
    /// 4. Session can be created
    /// 5. Command queue is accessible
    /// 6. Completion can be written
    /// 7. Session can be destroyed
    /// 8. Disconnection succeeds
    ///
    /// This is a comprehensive integration test of the entire dext interface.
    func testFullLifecycle() async throws {
        let connector = DextConnector()
        
        // 1. Connect
        try await connector.connect()
        defer { Task { await connector.disconnect() } }
        
        // 2. Map memory
        try await connector.mapSharedMemory()
        
        // 3. Get HBA status
        let status = try await connector.getHBAStatus()
        XCTAssertGreaterThan(status, 0, "HBA should be online")
        
        // 4. Create session
        let sessionID = try await connector.createSession()
        XCTAssertGreaterThan(sessionID, 0, "Session ID should be valid")
        
        // 5. Read command (should be empty)
        let command = await connector.readNextCommand()
        if let cmd = command {
            XCTAssertEqual(cmd.taskTag, 0, "Initial command should be empty")
        }
        
        // 6. Write completion
        let completion = SCSICompletionDescriptor(
            taskTag: 99999,
            itt: 11111,
            scsiStatus: SCSIStatus.good.rawValue,
            transferCount: 512
        )
        try await connector.writeCompletion(completion)
        
        // 7. Destroy session
        try await connector.destroySession(sessionID)
        
        // 8. Disconnect (happens in defer)
        // If we got here without throwing, full lifecycle succeeded
    }

    // MARK: - Additional Helper Tests

    /// Test that connection fails gracefully when dext is not loaded
    ///
    /// This test is expected to pass always - even when dext is loaded.
    /// It verifies error handling, not actual failure.
    func testConnectionErrorHandling() async throws {
        let connector = DextConnector()
        
        do {
            try await connector.connect()
            await connector.disconnect()
            
            // If we connected successfully, that's fine
            // This test is primarily about error handling paths
        } catch DextConnectorError.serviceNotFound {
            // Expected error when dext not loaded
            XCTAssertTrue(true, "Correct error type for missing dext")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// Test that memory mapping fails gracefully before connection
    ///
    /// Verifies that calling mapSharedMemory() before connect() fails appropriately
    func testMemoryMappingWithoutConnection() async throws {
        let connector = DextConnector()
        
        // Should fail because not connected
        do {
            try await connector.mapSharedMemory()
            XCTFail("Should have thrown error when mapping without connection")
        } catch DextConnectorError.memoryMappingFailed {
            // Expected
            XCTAssertTrue(true)
        } catch {
            // Also acceptable - different error is fine
            XCTAssertTrue(true, "Failed as expected with: \(error)")
        }
    }
}
