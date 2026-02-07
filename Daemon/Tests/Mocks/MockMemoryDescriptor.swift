import Foundation

public enum MemoryDirection {
    case none
    case `in`
    case out
    case inOut
}

public enum MemoryError: Error {
    case writeBeyondBounds(offset: Int, length: Int, available: Int)
    case readBeyondBounds(offset: Int, length: Int, available: Int)
    case sizeTooLarge(requestedSize: UInt64, maxSize: Int)
}

public class MockMemoryDescriptor {
    public let size: UInt64
    public let direction: MemoryDirection
    public private(set) var data: Data

    public init(size: UInt64, direction: MemoryDirection = .inOut) throws {
        self.size = size
        self.direction = direction

        // Check for overflow
        guard size <= Int.max else {
            throw MemoryError.sizeTooLarge(requestedSize: size, maxSize: Int.max)
        }

        self.data = Data(count: Int(size))
    }

    public func writeData(_ newData: Data, at offset: Int) throws {
        guard offset + newData.count <= data.count else {
            throw MemoryError.writeBeyondBounds(
                offset: offset,
                length: newData.count,
                available: data.count
            )
        }
        data.replaceSubrange(offset..<(offset + newData.count), with: newData)
    }

    public func readData(at offset: Int, length: Int) throws -> Data {
        guard offset + length <= data.count else {
            throw MemoryError.readBeyondBounds(
                offset: offset,
                length: length,
                available: data.count
            )
        }
        return data.subdata(in: offset..<(offset + length))
    }
}
