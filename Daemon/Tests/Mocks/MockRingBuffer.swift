import Foundation

/// Errors that can occur during ring buffer operations
public enum RingBufferError: Error {
    case bufferFull(capacity: Int)
    case bufferEmpty
    case invalidCapacity
}

/// Mock implementation of a ring buffer for testing queue operations
public class MockRingBuffer<T> {
    private var buffer: [T?]
    private(set) var head: Int
    private(set) var tail: Int
    private(set) var count: Int
    public let capacity: Int

    /// Initialize ring buffer with given capacity
    public init(capacity: Int) throws {
        guard capacity > 0 else {
            throw RingBufferError.invalidCapacity
        }

        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
        self.head = 0
        self.tail = 0
        self.count = 0
    }

    /// Enqueue an element to the ring buffer
    public func enqueue(_ element: T) throws {
        guard count < capacity else {
            throw RingBufferError.bufferFull(capacity: capacity)
        }

        buffer[tail] = element
        tail = (tail + 1) % capacity
        count += 1
    }

    /// Dequeue an element from the ring buffer
    public func dequeue() throws -> T {
        guard count > 0 else {
            throw RingBufferError.bufferEmpty
        }

        guard let element = buffer[head] else {
            throw RingBufferError.bufferEmpty
        }

        buffer[head] = nil
        head = (head + 1) % capacity
        count -= 1

        return element
    }

    /// Peek at the front element without removing it
    public func peek() throws -> T {
        guard count > 0 else {
            throw RingBufferError.bufferEmpty
        }

        guard let element = buffer[head] else {
            throw RingBufferError.bufferEmpty
        }

        return element
    }

    /// Check if buffer is empty
    public var isEmpty: Bool {
        return count == 0
    }

    /// Check if buffer is full
    public var isFull: Bool {
        return count == capacity
    }

    /// Clear all elements from the buffer
    public func clear() {
        buffer = Array(repeating: nil, count: capacity)
        head = 0
        tail = 0
        count = 0
    }
}
