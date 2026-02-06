import XCTest
@testable import ISCSIDaemon

final class SharedMemoryTests: XCTestCase {

    // MARK: - Command Queue Tests

    func testCommandQueueMapping() throws {
        // Test mapping command queue memory with correct size
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.commandQueueSize,
            direction: .inOut
        )

        XCTAssertEqual(descriptor.size, TestConstants.commandQueueSize)
        XCTAssertEqual(descriptor.direction, .inOut)
        XCTAssertEqual(descriptor.data.count, Int(TestConstants.commandQueueSize))
    }

    func testWriteCommandDescriptor() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.commandQueueSize,
            direction: .out
        )

        // Create a command descriptor
        var cmd = SCSICommandDescriptor()
        cmd.taskTag = 0x1234567890ABCDEF
        cmd.targetID = 1
        cmd.lun = 0
        cmd.cdb = (0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        cmd.cdbLength = 10
        cmd.dataDirection = 1
        cmd.transferLength = 4096
        cmd.dataBufferOffset = 0

        // Convert to Data
        let cmdData = withUnsafeBytes(of: cmd) { Data($0) }
        XCTAssertEqual(cmdData.count, 80)

        // Write at offset 0
        try descriptor.writeData(cmdData, at: 0)

        // Read back and verify
        let readData = try descriptor.readData(at: 0, length: 80)
        XCTAssertEqual(readData, cmdData)
    }

    func testReadCommandDescriptor() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.commandQueueSize,
            direction: .in
        )

        // Create and write a command descriptor
        var cmd = SCSICommandDescriptor()
        cmd.taskTag = 0xDEADBEEFCAFEBABE
        cmd.targetID = 2
        cmd.lun = 5

        let cmdData = withUnsafeBytes(of: cmd) { Data($0) }
        try descriptor.writeData(cmdData, at: 160) // Second entry (80 bytes offset)

        // Read back
        let readData = try descriptor.readData(at: 160, length: 80)

        // Convert back to struct
        let readCmd = readData.withUnsafeBytes { ptr in
            ptr.load(as: SCSICommandDescriptor.self)
        }

        XCTAssertEqual(readCmd.taskTag, cmd.taskTag)
        XCTAssertEqual(readCmd.targetID, cmd.targetID)
        XCTAssertEqual(readCmd.lun, cmd.lun)
    }

    func testCommandQueueConcurrentAccess() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.commandQueueSize,
            direction: .inOut
        )

        // Test writing multiple commands at different offsets (simulating concurrent queue usage)
        var cmd1 = SCSICommandDescriptor()
        cmd1.taskTag = 1
        cmd1.targetID = 0

        var cmd2 = SCSICommandDescriptor()
        cmd2.taskTag = 2
        cmd2.targetID = 1

        var cmd3 = SCSICommandDescriptor()
        cmd3.taskTag = 3
        cmd3.targetID = 2

        let cmd1Data = withUnsafeBytes(of: cmd1) { Data($0) }
        let cmd2Data = withUnsafeBytes(of: cmd2) { Data($0) }
        let cmd3Data = withUnsafeBytes(of: cmd3) { Data($0) }

        // Write at different offsets
        try descriptor.writeData(cmd1Data, at: 0)
        try descriptor.writeData(cmd2Data, at: 80)
        try descriptor.writeData(cmd3Data, at: 160)

        // Verify all can be read back correctly
        let read1 = try descriptor.readData(at: 0, length: 80)
        let read2 = try descriptor.readData(at: 80, length: 80)
        let read3 = try descriptor.readData(at: 160, length: 80)

        XCTAssertEqual(read1, cmd1Data)
        XCTAssertEqual(read2, cmd2Data)
        XCTAssertEqual(read3, cmd3Data)
    }

    func testCommandQueueBoundaryConditions() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.commandQueueSize,
            direction: .inOut
        )

        // Test last valid entry (capacity is 819, so index 818 = offset 65440)
        let lastValidOffset = (TestConstants.commandQueueCapacity - 1) * 80

        var cmd = SCSICommandDescriptor()
        cmd.taskTag = 0xFFFFFFFFFFFFFFFF
        let cmdData = withUnsafeBytes(of: cmd) { Data($0) }

        // Should succeed at last valid position
        try descriptor.writeData(cmdData, at: lastValidOffset)

        // Verify read
        let readData = try descriptor.readData(at: lastValidOffset, length: 80)
        XCTAssertEqual(readData, cmdData)

        // Should fail beyond bounds (one byte past capacity)
        let beyondOffset = Int(TestConstants.commandQueueSize) - 79
        XCTAssertThrowsError(try descriptor.writeData(cmdData, at: beyondOffset)) { error in
            guard case MemoryError.writeBeyondBounds = error else {
                XCTFail("Expected writeBeyondBounds error")
                return
            }
        }
    }

    // MARK: - Completion Queue Tests

    func testCompletionQueueMapping() throws {
        // Test mapping completion queue memory with correct size
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.completionQueueSize,
            direction: .inOut
        )

        XCTAssertEqual(descriptor.size, TestConstants.completionQueueSize)
        XCTAssertEqual(descriptor.direction, .inOut)
        XCTAssertEqual(descriptor.data.count, Int(TestConstants.completionQueueSize))
    }

    func testWriteCompletionDescriptor() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.completionQueueSize,
            direction: .out
        )

        // Create a completion descriptor
        var comp = SCSICompletionDescriptor()
        comp.taskTag = 0x1234567890ABCDEF
        comp.initiatorTaskTag = 0xDEADBEEF
        comp.scsiStatus = 0x00 // GOOD
        comp.serviceResponse = 0x00 // COMPLETE
        comp.senseLength = 0
        comp.dataTransferCount = 4096
        comp.residualCount = 0

        // Convert to Data
        let compData = withUnsafeBytes(of: comp) { Data($0) }
        XCTAssertEqual(compData.count, 280)

        // Write at offset 0
        try descriptor.writeData(compData, at: 0)

        // Read back and verify
        let readData = try descriptor.readData(at: 0, length: 280)
        XCTAssertEqual(readData, compData)
    }

    func testReadCompletionDescriptor() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.completionQueueSize,
            direction: .in
        )

        // Create and write a completion descriptor
        var comp = SCSICompletionDescriptor()
        comp.taskTag = 0xCAFEBABEDEADBEEF
        comp.initiatorTaskTag = 0x12345678
        comp.scsiStatus = 0x02 // CHECK_CONDITION
        comp.senseLength = 18
        comp.dataTransferCount = 2048

        let compData = withUnsafeBytes(of: comp) { Data($0) }
        try descriptor.writeData(compData, at: 560) // Second entry (280 bytes offset)

        // Read back
        let readData = try descriptor.readData(at: 560, length: 280)

        // Convert back to struct
        let readComp = readData.withUnsafeBytes { ptr in
            ptr.load(as: SCSICompletionDescriptor.self)
        }

        XCTAssertEqual(readComp.taskTag, comp.taskTag)
        XCTAssertEqual(readComp.initiatorTaskTag, comp.initiatorTaskTag)
        XCTAssertEqual(readComp.scsiStatus, comp.scsiStatus)
        XCTAssertEqual(readComp.senseLength, comp.senseLength)
        XCTAssertEqual(readComp.dataTransferCount, comp.dataTransferCount)
    }

    func testCompletionQueueConcurrentAccess() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.completionQueueSize,
            direction: .inOut
        )

        // Test writing multiple completions at different offsets
        var comp1 = SCSICompletionDescriptor()
        comp1.taskTag = 1
        comp1.scsiStatus = 0x00

        var comp2 = SCSICompletionDescriptor()
        comp2.taskTag = 2
        comp2.scsiStatus = 0x02

        var comp3 = SCSICompletionDescriptor()
        comp3.taskTag = 3
        comp3.scsiStatus = 0x08

        let comp1Data = withUnsafeBytes(of: comp1) { Data($0) }
        let comp2Data = withUnsafeBytes(of: comp2) { Data($0) }
        let comp3Data = withUnsafeBytes(of: comp3) { Data($0) }

        // Write at different offsets
        try descriptor.writeData(comp1Data, at: 0)
        try descriptor.writeData(comp2Data, at: 280)
        try descriptor.writeData(comp3Data, at: 560)

        // Verify all can be read back correctly
        let read1 = try descriptor.readData(at: 0, length: 280)
        let read2 = try descriptor.readData(at: 280, length: 280)
        let read3 = try descriptor.readData(at: 560, length: 280)

        XCTAssertEqual(read1, comp1Data)
        XCTAssertEqual(read2, comp2Data)
        XCTAssertEqual(read3, comp3Data)
    }

    func testCompletionQueueBoundaryConditions() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.completionQueueSize,
            direction: .inOut
        )

        // Test last valid entry (capacity is 234, so index 233 = offset 65240)
        let lastValidOffset = (TestConstants.completionQueueCapacity - 1) * 280

        var comp = SCSICompletionDescriptor()
        comp.taskTag = 0xFFFFFFFFFFFFFFFF
        let compData = withUnsafeBytes(of: comp) { Data($0) }

        // Should succeed at last valid position
        try descriptor.writeData(compData, at: lastValidOffset)

        // Verify read
        let readData = try descriptor.readData(at: lastValidOffset, length: 280)
        XCTAssertEqual(readData, compData)

        // Should fail beyond bounds (one byte past capacity)
        let beyondOffset = Int(TestConstants.completionQueueSize) - 279
        XCTAssertThrowsError(try descriptor.writeData(compData, at: beyondOffset)) { error in
            guard case MemoryError.writeBeyondBounds = error else {
                XCTFail("Expected writeBeyondBounds error")
                return
            }
        }
    }

    // MARK: - Data Pool Tests

    func testDataPoolMapping() throws {
        // Test mapping data pool memory with correct size
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.dataPoolSize,
            direction: .inOut
        )

        XCTAssertEqual(descriptor.size, TestConstants.dataPoolSize)
        XCTAssertEqual(descriptor.direction, .inOut)
        XCTAssertEqual(descriptor.data.count, Int(TestConstants.dataPoolSize))
    }

    func testWriteDataSegment() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.dataPoolSize,
            direction: .out
        )

        // Create a test data segment (simulating SCSI data)
        let testPattern = Data(repeating: 0xA5, count: 4096)

        // Write at offset 0
        try descriptor.writeData(testPattern, at: 0)

        // Read back and verify
        let readData = try descriptor.readData(at: 0, length: 4096)
        XCTAssertEqual(readData, testPattern)
    }

    func testReadDataSegment() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.dataPoolSize,
            direction: .in
        )

        // Create test data with specific pattern
        let testPattern = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])

        // Write at various offsets
        try descriptor.writeData(testPattern, at: 0)
        try descriptor.writeData(testPattern, at: 8192)
        try descriptor.writeData(testPattern, at: 1048576) // 1MB offset

        // Read back and verify
        let read1 = try descriptor.readData(at: 0, length: 8)
        let read2 = try descriptor.readData(at: 8192, length: 8)
        let read3 = try descriptor.readData(at: 1048576, length: 8)

        XCTAssertEqual(read1, testPattern)
        XCTAssertEqual(read2, testPattern)
        XCTAssertEqual(read3, testPattern)
    }

    func testDataPoolOffsetHandling() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.dataPoolSize,
            direction: .inOut
        )

        // Test data at various offsets to ensure offset calculation is correct
        let blockSize = 512
        let testData = Data(repeating: 0xFF, count: blockSize)

        // Write at different block-aligned offsets
        let offsets = [0, 512, 4096, 65536, 1048576, 16777216]

        for offset in offsets {
            try descriptor.writeData(testData, at: offset)
            let readBack = try descriptor.readData(at: offset, length: blockSize)
            XCTAssertEqual(readBack, testData, "Failed at offset \(offset)")
        }

        // Verify other regions remain zero
        let zeroCheck = try descriptor.readData(at: 1024, length: 512)
        XCTAssertEqual(zeroCheck, Data(repeating: 0, count: 512))
    }

    func testDataPoolConcurrentAccess() throws {
        let descriptor = try MockMemoryDescriptor(
            size: TestConstants.dataPoolSize,
            direction: .inOut
        )

        // Simulate concurrent writes to different regions of the data pool
        let pattern1 = Data(repeating: 0xAA, count: 8192)
        let pattern2 = Data(repeating: 0xBB, count: 8192)
        let pattern3 = Data(repeating: 0xCC, count: 8192)

        // Write to non-overlapping regions
        try descriptor.writeData(pattern1, at: 0)
        try descriptor.writeData(pattern2, at: 1048576)  // 1MB offset
        try descriptor.writeData(pattern3, at: 33554432) // 32MB offset

        // Verify all regions maintain their data
        let read1 = try descriptor.readData(at: 0, length: 8192)
        let read2 = try descriptor.readData(at: 1048576, length: 8192)
        let read3 = try descriptor.readData(at: 33554432, length: 8192)

        XCTAssertEqual(read1, pattern1)
        XCTAssertEqual(read2, pattern2)
        XCTAssertEqual(read3, pattern3)

        // Verify regions between writes are still zero
        let zeroBetween = try descriptor.readData(at: 8192, length: 4096)
        XCTAssertEqual(zeroBetween, Data(repeating: 0, count: 4096))
    }
}
