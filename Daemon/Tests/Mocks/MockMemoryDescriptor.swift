import Foundation

public enum MemoryDirection {
    case none
    case `in`
    case out
    case inOut
}

public class MockMemoryDescriptor {
    public let size: UInt64
    public let direction: MemoryDirection
    public private(set) var data: Data

    public init(size: UInt64, direction: MemoryDirection = .inOut) {
        self.size = size
        self.direction = direction
        self.data = Data(count: Int(size))
    }

    public func writeData(_ newData: Data, at offset: Int) {
        guard offset + newData.count <= data.count else {
            fatalError("Write beyond memory bounds")
        }
        data.replaceSubrange(offset..<(offset + newData.count), with: newData)
    }

    public func readData(at offset: Int, length: Int) -> Data {
        guard offset + length <= data.count else {
            fatalError("Read beyond memory bounds")
        }
        return data.subdata(in: offset..<(offset + length))
    }
}
