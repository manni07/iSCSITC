import XCTest
@testable import ISCSIDaemon

final class QueueManagementTests: XCTestCase {

    // MARK: - Basic Operations

    func testRingBufferEnqueueDequeue() throws {
        let buffer = try MockRingBuffer<Int>(capacity: 5)

        // Enqueue elements
        try buffer.enqueue(1)
        try buffer.enqueue(2)
        try buffer.enqueue(3)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertFalse(buffer.isEmpty)
        XCTAssertFalse(buffer.isFull)

        // Dequeue elements in FIFO order
        XCTAssertEqual(try buffer.dequeue(), 1)
        XCTAssertEqual(try buffer.dequeue(), 2)
        XCTAssertEqual(try buffer.dequeue(), 3)

        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testRingBufferEmptyState() throws {
        let buffer = try MockRingBuffer<String>(capacity: 3)

        // Buffer starts empty
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.head, 0)
        XCTAssertEqual(buffer.tail, 0)

        // Dequeue from empty buffer should throw
        XCTAssertThrowsError(try buffer.dequeue()) { error in
            guard case RingBufferError.bufferEmpty = error else {
                XCTFail("Expected bufferEmpty error")
                return
            }
        }

        // Peek empty buffer should throw
        XCTAssertThrowsError(try buffer.peek()) { error in
            guard case RingBufferError.bufferEmpty = error else {
                XCTFail("Expected bufferEmpty error")
                return
            }
        }
    }

    func testRingBufferFullState() throws {
        let buffer = try MockRingBuffer<Int>(capacity: 3)

        // Fill buffer to capacity
        try buffer.enqueue(10)
        try buffer.enqueue(20)
        try buffer.enqueue(30)

        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertFalse(buffer.isEmpty)

        // Enqueue to full buffer should throw
        XCTAssertThrowsError(try buffer.enqueue(40)) { error in
            guard case RingBufferError.bufferFull(let capacity) = error else {
                XCTFail("Expected bufferFull error")
                return
            }
            XCTAssertEqual(capacity, 3)
        }
    }

    // MARK: - Wraparound Behavior

    func testRingBufferWraparound() throws {
        let buffer = try MockRingBuffer<Int>(capacity: 4)

        // Fill buffer
        try buffer.enqueue(1)
        try buffer.enqueue(2)
        try buffer.enqueue(3)
        try buffer.enqueue(4)

        XCTAssertTrue(buffer.isFull)

        // Dequeue two elements (head advances to 2)
        XCTAssertEqual(try buffer.dequeue(), 1)
        XCTAssertEqual(try buffer.dequeue(), 2)

        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.head, 2)
        XCTAssertEqual(buffer.tail, 0)

        // Enqueue two more elements (tail wraps around)
        try buffer.enqueue(5)
        try buffer.enqueue(6)

        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.tail, 2)

        // Verify FIFO order with wraparound
        XCTAssertEqual(try buffer.dequeue(), 3)
        XCTAssertEqual(try buffer.dequeue(), 4)
        XCTAssertEqual(try buffer.dequeue(), 5)
        XCTAssertEqual(try buffer.dequeue(), 6)

        XCTAssertTrue(buffer.isEmpty)
    }

    func testRingBufferMultipleWraparounds() throws {
        let buffer = try MockRingBuffer<Int>(capacity: 3)

        // Perform multiple fill/drain cycles to test wraparound
        for cycle in 0..<5 {
            let base = cycle * 100

            // Fill buffer
            try buffer.enqueue(base + 1)
            try buffer.enqueue(base + 2)
            try buffer.enqueue(base + 3)

            XCTAssertTrue(buffer.isFull)

            // Drain buffer
            XCTAssertEqual(try buffer.dequeue(), base + 1)
            XCTAssertEqual(try buffer.dequeue(), base + 2)
            XCTAssertEqual(try buffer.dequeue(), base + 3)

            XCTAssertTrue(buffer.isEmpty)
        }
    }

    // MARK: - Capacity and Boundary Conditions

    func testRingBufferCapacityLimits() throws {
        // Test minimum valid capacity
        let smallBuffer = try MockRingBuffer<Int>(capacity: 1)
        XCTAssertEqual(smallBuffer.capacity, 1)

        try smallBuffer.enqueue(42)
        XCTAssertTrue(smallBuffer.isFull)
        XCTAssertEqual(try smallBuffer.dequeue(), 42)
        XCTAssertTrue(smallBuffer.isEmpty)

        // Test invalid capacity
        XCTAssertThrowsError(try MockRingBuffer<Int>(capacity: 0)) { error in
            guard case RingBufferError.invalidCapacity = error else {
                XCTFail("Expected invalidCapacity error")
                return
            }
        }

        XCTAssertThrowsError(try MockRingBuffer<Int>(capacity: -1)) { error in
            guard case RingBufferError.invalidCapacity = error else {
                XCTFail("Expected invalidCapacity error")
                return
            }
        }
    }

    func testRingBufferLargeCapacity() throws {
        // Test with large capacity matching real queue sizes
        let commandQueueCapacity = 819 // 64KB / 80 bytes
        let buffer = try MockRingBuffer<Int>(capacity: commandQueueCapacity)

        XCTAssertEqual(buffer.capacity, commandQueueCapacity)
        XCTAssertTrue(buffer.isEmpty)

        // Fill to capacity
        for i in 0..<commandQueueCapacity {
            try buffer.enqueue(i)
        }

        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.count, commandQueueCapacity)

        // Verify all elements in order
        for i in 0..<commandQueueCapacity {
            XCTAssertEqual(try buffer.dequeue(), i)
        }

        XCTAssertTrue(buffer.isEmpty)
    }

    // MARK: - Peek Operations

    func testRingBufferPeek() throws {
        let buffer = try MockRingBuffer<String>(capacity: 3)

        try buffer.enqueue("first")
        try buffer.enqueue("second")

        // Peek should return front element without removing it
        XCTAssertEqual(try buffer.peek(), "first")
        XCTAssertEqual(buffer.count, 2)

        // Peek again - should return same element
        XCTAssertEqual(try buffer.peek(), "first")
        XCTAssertEqual(buffer.count, 2)

        // Dequeue and verify peek updates
        XCTAssertEqual(try buffer.dequeue(), "first")
        XCTAssertEqual(try buffer.peek(), "second")
        XCTAssertEqual(buffer.count, 1)
    }

    // MARK: - Clear Operations

    func testRingBufferClear() throws {
        let buffer = try MockRingBuffer<Int>(capacity: 5)

        // Fill buffer
        try buffer.enqueue(1)
        try buffer.enqueue(2)
        try buffer.enqueue(3)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertFalse(buffer.isEmpty)

        // Clear buffer
        buffer.clear()

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.head, 0)
        XCTAssertEqual(buffer.tail, 0)

        // Should be able to use buffer after clear
        try buffer.enqueue(100)
        XCTAssertEqual(try buffer.dequeue(), 100)
    }

    // MARK: - Concurrent Access Patterns

    func testRingBufferInterleavedOperations() throws {
        let buffer = try MockRingBuffer<Int>(capacity: 4)

        // Simulate interleaved enqueue/dequeue pattern
        try buffer.enqueue(1)
        try buffer.enqueue(2)
        XCTAssertEqual(try buffer.dequeue(), 1)

        try buffer.enqueue(3)
        XCTAssertEqual(try buffer.dequeue(), 2)

        try buffer.enqueue(4)
        try buffer.enqueue(5)
        XCTAssertEqual(try buffer.dequeue(), 3)

        try buffer.enqueue(6)

        // Verify remaining elements
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(try buffer.dequeue(), 4)
        XCTAssertEqual(try buffer.dequeue(), 5)
        XCTAssertEqual(try buffer.dequeue(), 6)
        XCTAssertTrue(buffer.isEmpty)
    }
}
