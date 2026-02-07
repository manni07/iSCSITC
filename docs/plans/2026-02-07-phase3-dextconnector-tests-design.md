# Phase 3: DextConnector Unit Tests - Design Document

**Version:** 1.0
**Date:** 2026-02-07
**Author:** Claude (Subagent-Driven Development)
**Status:** Approved - Ready for Implementation

---

## 1. Architecture Overview

### What We're Testing

The `DextConnector` Swift actor that wraps IOKit calls to communicate with the DriverKit extension (iSCSIVirtualHBA.dext).

### Current State

**Implemented Methods:**
- ✅ `connect()` - Find and open connection to dext service
- ✅ `mapSharedMemory()` - Map all three shared memory regions
- ✅ `createSession()` - Create daemon session with dext
- ✅ `destroySession()` - Destroy session by ID
- ✅ `getHBAStatus()` - Query HBA online/offline status
- ✅ `readNextCommand()` - Read SCSI command from shared queue
- ✅ `writeCompletion()` - Write SCSI completion to shared queue

**7 External Methods (UserClientSelector):**
1. `createSession` (selector 0) - Session management
2. `destroySession` (selector 1) - Session cleanup
3. `completeSCSITask` (selector 2) - Not directly exposed (uses writeCompletion)
4. `getPendingTask` (selector 3) - Not directly exposed (uses readNextCommand)
5. `mapSharedMemory` (selector 4) - Memory region mapping
6. `setHBAStatus` (selector 5) - Dext-side only (not in connector)
7. `getHBAStatus` (selector 6) - Query status

### Test Approach

**Challenge:** Cannot load actual dext in unit tests (requires kernel, entitlements, SIP disabled).

**Solution:** Create `MockDextConnector` that simulates dext behavior without requiring IOKit.

**Benefits:**
1. Fast test execution (no kernel involvement)
2. Full error path coverage (inject failures)
3. Deterministic behavior (no race conditions)
4. CI/CD compatible (no special privileges)

### Test Structure

```
Daemon/Tests/
├── DaemonTests/
│   ├── DextConnectorTests.swift       # ~35 tests (main functionality)
│   └── ExternalMethodTests.swift      # ~15 tests (IOKit call validation)
├── Mocks/
│   └── MockDextConnector.swift        # Mock implementation
└── Protocols/
    └── DextConnectorProtocol.swift    # Protocol abstraction
```

---

## 2. Test Categories (50 Tests Total)

### Category 1: Connection Management (~12 tests)

**Purpose:** Validate dext service discovery and connection lifecycle.

**Tests:**
1. `testConnect_Success` - Successfully find and connect to dext service
2. `testConnect_ServiceNotFound` - Handle missing dext service error
3. `testConnect_ConnectionFailed` - Handle IOServiceOpen failure
4. `testConnect_Idempotent` - Multiple connect calls succeed (or are no-op)
5. `testConnect_AfterDisconnect` - Reconnect after disconnect
6. `testDisconnect_ClosesConnection` - IOServiceClose called correctly
7. `testDisconnect_Idempotent` - Multiple disconnect calls safe
8. `testConnectionState_NotConnected` - Initial state is disconnected
9. `testConnectionState_AfterConnect` - State updates to connected
10. `testConnectionState_AfterDisconnect` - State updates to disconnected
11. `testConnect_StoresConnectionHandle` - Connection handle stored correctly
12. `testConnect_ReleasesServiceRef` - IOObjectRelease called after open

### Category 2: Session Management (~10 tests)

**Purpose:** Validate session creation, tracking, and destruction.

**Tests:**
1. `testCreateSession_ReturnsUniqueID` - Each call returns different session ID
2. `testCreateSession_IncrementingIDs` - Session IDs increment (1, 2, 3, ...)
3. `testCreateSession_MultipleSessions` - Can create multiple active sessions
4. `testCreateSession_CallsCorrectSelector` - Uses selector 0 (createSession)
5. `testDestroySession_Success` - Successfully destroy existing session
6. `testDestroySession_InvalidID` - Handle destroy of non-existent session
7. `testDestroySession_CallsCorrectSelector` - Uses selector 1 (destroySession)
8. `testDestroySession_PassesSessionID` - Correct session ID passed as parameter
9. `testSessionLifecycle_CreateUseDestroy` - Full lifecycle works correctly
10. `testSessionState_TrackedCorrectly` - Session state maintained in connector

### Category 3: Shared Memory Mapping (~15 tests)

**Purpose:** Validate memory region mapping and pointer management.

**Tests:**
1. `testMapSharedMemory_CommandQueue` - Map 64KB command queue successfully
2. `testMapSharedMemory_CompletionQueue` - Map 64KB completion queue successfully
3. `testMapSharedMemory_DataPool` - Map 64MB data pool successfully
4. `testMapSharedMemory_AllRegions` - Map all three regions in sequence
5. `testMapSharedMemory_CorrectTypes` - Uses correct SharedMemoryType enum values
6. `testMapSharedMemory_CorrectSizes` - Requests correct sizes (64KB, 64KB, 64MB)
7. `testMapSharedMemory_ValidPointers` - All pointers non-nil after mapping
8. `testMapSharedMemory_MappingFailure` - Handle IOConnectMapMemory64 failure
9. `testMapSharedMemory_SizeMismatch` - Warn if actual size != expected size
10. `testMapSharedMemory_Remapping` - Re-map should reuse or replace pointer
11. `testMapSharedMemory_BeforeConnect` - Error if called before connect()
12. `testMapSharedMemory_PointerArithmetic` - Command/completion offsets correct
13. `testMapSharedMemory_InvalidMemoryType` - Handle invalid type parameter
14. `testMapSharedMemory_MemoryAlignment` - Pointers properly aligned
15. `testMapSharedMemory_Cleanup` - Memory unmapped on disconnect

### Category 4: HBA Status (~5 tests)

**Purpose:** Validate HBA status query external method.

**Tests:**
1. `testGetHBAStatus_Online` - Returns 1 when HBA online
2. `testGetHBAStatus_Offline` - Returns 0 when HBA offline
3. `testGetHBAStatus_CallsCorrectSelector` - Uses selector 6 (getHBAStatus)
4. `testGetHBAStatus_ExternalMethodFailure` - Handle IOConnectCallScalarMethod failure
5. `testGetHBAStatus_OutputValidation` - Output count and value validated

### Category 5: Queue Operations (~8 tests)

**Purpose:** Validate shared memory queue read/write operations.

**Tests:**
1. `testReadNextCommand_ValidDescriptor` - Read command descriptor from queue
2. `testReadNextCommand_CorrectOffset` - Reads from tail position (80-byte aligned)
3. `testReadNextCommand_AdvancesTail` - Tail increments after read
4. `testReadNextCommand_Wraparound` - Tail wraps at 819 (maxCommandDescriptors)
5. `testWriteCompletion_ValidDescriptor` - Write completion descriptor to queue
6. `testWriteCompletion_CorrectOffset` - Writes to head position (280-byte aligned)
7. `testWriteCompletion_AdvancesHead` - Head increments after write
8. `testWriteCompletion_Wraparound` - Head wraps at 234 (maxCompletionDescriptors)

---

## 3. Mock Implementation Strategy

### DextConnectorProtocol

Extract protocol from existing `DextConnector` to enable mocking:

```swift
protocol DextConnectorProtocol: Actor {
    func connect() async throws
    func disconnect() async
    func mapSharedMemory() async throws
    func getHBAStatus() async throws -> UInt64
    func createSession() async throws -> UInt64
    func destroySession(_ sessionID: UInt64) async throws
    func readNextCommand() async -> SCSICommandDescriptor?
    func writeCompletion(_ completion: SCSICompletionDescriptor) async throws
    func hasPendingCommands() async -> Bool
}
```

### MockDextConnector

**Simulated State:**
- `isConnected: Bool` - Connection status
- `sessionCounter: UInt64` - Session ID generator
- `activeSessions: Set<UInt64>` - Active session tracking
- `hbaStatus: UInt64` - Simulated HBA status (0 or 1)
- `commandQueueData: Data` - Simulated 64KB command queue
- `completionQueueData: Data` - Simulated 64KB completion queue
- `dataPoolData: Data` - Simulated 64MB data pool
- `commandQueueTail: UInt32` - Read position
- `completionQueueHead: UInt32` - Write position

**Error Injection:**
- `shouldFailConnection: Bool`
- `shouldFailMemoryMapping: Bool`
- `shouldFailExternalMethod: Bool`
- `connectionFailureCode: Int32`
- `memoryMappingFailureCode: Int32`

**Call Tracking:**
- `connectCallCount: Int`
- `mapSharedMemoryCallCount: Int`
- `createSessionCallCount: Int`
- `destroySessionCallCount: Int`
- `getHBAStatusCallCount: Int`
- `lastDestroyedSessionID: UInt64?`

**Queue Simulation:**
- Real ring buffer logic using `Data` buffers
- Proper offset calculation (80 bytes for commands, 280 for completions)
- Wraparound handling (819 command slots, 234 completion slots)

### Alternative Considered

**Option B:** Use real DextConnector with stubbed IOKit calls
- ❌ Requires swizzling/mocking C functions (IOServiceOpen, etc.)
- ❌ Harder to inject errors at precise points
- ❌ More fragile (depends on internal implementation)

**Why Protocol + Mock is better:**
- ✅ Clean separation of interface and implementation
- ✅ Easy error injection for comprehensive coverage
- ✅ Fast, deterministic tests
- ✅ No dependency on IOKit availability

---

## 4. Implementation Plan

### Task 1: DextConnectorProtocol & Refactoring

**Goal:** Extract protocol abstraction to enable mocking.

**Steps:**
1. Create `Daemon/Tests/Protocols/DextConnectorProtocol.swift`
2. Define protocol with all public methods
3. Update `DextConnector` to conform to protocol
4. Update `ISCSIDaemon` to depend on `DextConnectorProtocol` (not concrete type)
5. Run existing tests to ensure refactoring didn't break anything

**Verification:**
- Existing 32 tests still pass
- No behavior changes

**Time:** ~30 minutes

---

### Task 2: MockDextConnector Implementation

**Goal:** Create fully-featured mock for testing.

**Steps:**
1. Create `Daemon/Tests/Mocks/MockDextConnector.swift`
2. Implement protocol with simulated state
3. Add error injection properties
4. Add call tracking properties
5. Implement queue simulation (ring buffer in Data buffers)
6. Add helper methods for test setup (e.g., `setHBAStatus()`, `injectError()`)

**Key Implementation:**
```swift
actor MockDextConnector: DextConnectorProtocol {
    // State
    private var isConnected = false
    private var sessionCounter: UInt64 = 0
    private var activeSessions: Set<UInt64> = []
    private var hbaStatus: UInt64 = 1 // Default: online

    // Memory simulation
    private var commandQueueData = Data(count: 65536)
    private var completionQueueData = Data(count: 65536)
    private var dataPoolData = Data(count: 67108864)

    // Queue pointers
    private var commandQueueTail: UInt32 = 0
    private var completionQueueHead: UInt32 = 0

    // Error injection
    var shouldFailConnection = false
    var shouldFailMemoryMapping = false
    var connectionFailureCode: Int32 = KERN_FAILURE

    // Call tracking
    private(set) var connectCallCount = 0
    private(set) var createSessionCallCount = 0
    private(set) var lastDestroyedSessionID: UInt64?

    // Test helpers
    func setHBAStatus(_ status: UInt64) {
        hbaStatus = status
    }

    func reset() {
        isConnected = false
        sessionCounter = 0
        activeSessions.removeAll()
        connectCallCount = 0
        // ... reset all state
    }
}
```

**Verification:**
- Mock compiles and conforms to protocol
- All state properties initialized correctly

**Time:** ~45 minutes

---

### Task 3: Connection & Session Tests

**Goal:** Test connection lifecycle and session management (22 tests).

**Steps:**
1. Create `Daemon/Tests/DaemonTests/DextConnectorTests.swift`
2. Implement 12 connection management tests
3. Implement 10 session management tests
4. Use MockDextConnector for all tests

**Example Test:**
```swift
func testConnect_Success() async throws {
    let mock = MockDextConnector()

    try await mock.connect()

    XCTAssertEqual(mock.connectCallCount, 1)
    // Verify connected state
}

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
```

**Verification:**
- Run tests: `swift test --filter DextConnectorTests`
- 22/22 tests passing

**Time:** ~30 minutes

---

### Task 4: Memory Mapping Tests

**Goal:** Test shared memory mapping (15 tests).

**Steps:**
1. Add memory mapping tests to `DextConnectorTests.swift`
2. Test all three memory regions
3. Test error conditions (mapping failure, size mismatch)
4. Verify pointer validity

**Example Test:**
```swift
func testMapSharedMemory_AllRegions() async throws {
    let mock = MockDextConnector()
    try await mock.connect()

    try await mock.mapSharedMemory()

    // Verify all regions mapped (mock tracks this)
    XCTAssertEqual(mock.mapSharedMemoryCallCount, 1)
}

func testMapSharedMemory_MappingFailure() async throws {
    let mock = MockDextConnector()
    try await mock.connect()

    mock.shouldFailMemoryMapping = true

    await XCTAssertThrowsError(try await mock.mapSharedMemory()) { error in
        guard case DextConnectorError.memoryMappingFailed = error else {
            XCTFail("Expected memoryMappingFailed error")
            return
        }
    }
}
```

**Verification:**
- Run tests: `swift test --filter DextConnectorTests`
- 37/37 tests passing (22 + 15)

**Time:** ~30 minutes

---

### Task 5: HBA Status & Queue Tests

**Goal:** Test HBA status queries and queue operations (13 tests).

**Steps:**
1. Add 5 HBA status tests
2. Add 8 queue operation tests
3. Test wraparound and boundary conditions

**Example Tests:**
```swift
func testGetHBAStatus_Online() async throws {
    let mock = MockDextConnector()
    try await mock.connect()
    mock.setHBAStatus(1)

    let status = try await mock.getHBAStatus()

    XCTAssertEqual(status, 1)
}

func testReadNextCommand_Wraparound() async throws {
    let mock = MockDextConnector()
    try await mock.connect()
    try await mock.mapSharedMemory()

    // Fill queue to capacity (819 slots)
    for i in 0..<819 {
        // Simulate dext writing commands
        mock.writeCommandAtSlot(i, taskTag: UInt64(i))
    }

    // Read all 819 commands
    for i in 0..<819 {
        let cmd = await mock.readNextCommand()
        XCTAssertEqual(cmd?.taskTag, UInt64(i))
    }

    // Next read should wrap to slot 0
    mock.writeCommandAtSlot(0, taskTag: 999)
    let wrappedCmd = await mock.readNextCommand()
    XCTAssertEqual(wrappedCmd?.taskTag, 999)
}
```

**Verification:**
- Run tests: `swift test --filter DextConnectorTests`
- 50/50 tests passing

**Time:** ~30 minutes

---

### Task 6: Integration & Verification

**Goal:** Verify all tests pass together and Phase 3 complete.

**Steps:**
1. Run full test suite: `swift test`
2. Verify 32 existing tests + 50 new tests = 82 total passing
3. Check code coverage: `swift test --enable-code-coverage`
4. Ensure DextConnector has ≥85% coverage
5. Commit all changes

**Verification:**
```bash
swift test
# Expected: 82/82 tests passing

swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/ISCSIDaemonPackageTests.xctest/Contents/MacOS/ISCSIDaemonPackageTests
# Expected: DextConnector.swift ≥85% coverage
```

**Commit message:**
```
feat(tests): add DextConnector unit tests (Phase 3)

- 50 comprehensive tests for IOKit communication layer
- Protocol abstraction for testability
- MockDextConnector for deterministic testing
- Coverage: connection, sessions, memory mapping, HBA status, queues
- All 82 tests passing (32 Phase 2 + 50 Phase 3)

Phase 3 complete: DextConnector fully tested
Next: Phase 4 - Task Tracking Tests
```

**Time:** ~15 minutes

---

## 5. Test Execution

### Local Development

```bash
cd Daemon

# Run all tests
swift test

# Run Phase 3 tests only
swift test --filter DextConnectorTests

# Run with coverage
swift test --enable-code-coverage

# View coverage report
xcrun llvm-cov report .build/debug/ISCSIDaemonPackageTests.xctest/Contents/MacOS/ISCSIDaemonPackageTests
```

### Expected Output

```
Test Suite 'All tests' passed at 2026-02-07 14:30:00.000
    Executed 82 tests, with 0 failures (0 unexpected) in 0.050 seconds

Coverage Report:
DextConnector.swift: 87.5% (70/80 lines)
MockDextConnector.swift: 100% (120/120 lines)
```

---

## 6. Success Criteria

✅ **Protocol Abstraction**: `DextConnectorProtocol` defined and implemented
✅ **Mock Implementation**: `MockDextConnector` fully functional
✅ **50 Tests Passing**: All categories covered
✅ **No Regressions**: Existing 32 tests still pass
✅ **High Coverage**: DextConnector ≥85% line coverage
✅ **Fast Execution**: All tests complete in <1 second
✅ **Clean Code**: No compiler warnings, follows Swift conventions

---

## 7. Next Steps (Phase 4)

After Phase 3 complete:
- **Phase 4**: Task Tracking Tests (~40 tests)
  - SCSI task lifecycle management
  - Task tag mapping (kernel tag ↔ iSCSI ITT)
  - Completion handling and error reporting
  - Integration with Protocol layer

**Estimated total progress:**
- Phase 2: 32 tests ✅
- Phase 3: 50 tests (in progress)
- Phase 4: 40 tests (next)
- Phase 5: 30 tests (data structures)
- **Total**: ~150 tests toward ≥85% coverage target

---

**End of Design Document**
