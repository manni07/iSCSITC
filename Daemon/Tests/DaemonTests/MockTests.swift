import XCTest
@testable import ISCSIDaemon

final class MockTests: XCTestCase {
    func testMockIOServiceCreation() {
        let service = MockIOService(name: "iSCSIVirtualHBA")
        XCTAssertEqual(service.name, "iSCSIVirtualHBA")
        XCTAssertEqual(service.state, .running)
    }

    func testMockIOServiceStateTransitions() {
        let service = MockIOService(name: "test")
        XCTAssertEqual(service.state, .running)

        service.stop()
        XCTAssertEqual(service.state, .stopped)

        service.start()
        XCTAssertEqual(service.state, .running)

        service.setError()
        XCTAssertEqual(service.state, .error)
    }

    func testMockMemoryDescriptorReadWrite() throws {
        let descriptor = try MockMemoryDescriptor(size: 1024, direction: .inOut)

        let writeData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try descriptor.writeData(writeData, at: 0)

        let readData = try descriptor.readData(at: 0, length: 4)
        XCTAssertEqual(readData, writeData)
        XCTAssertEqual(descriptor.size, 1024)
    }

    func testMockMemoryDescriptorBoundsChecking() throws {
        let descriptor = try MockMemoryDescriptor(size: 100, direction: .inOut)

        // Test write beyond bounds
        let largeData = Data(repeating: 0xFF, count: 200)
        XCTAssertThrowsError(try descriptor.writeData(largeData, at: 0)) { error in
            guard case MemoryError.writeBeyondBounds = error else {
                XCTFail("Expected writeBeyondBounds error")
                return
            }
        }

        // Test read beyond bounds
        XCTAssertThrowsError(try descriptor.readData(at: 50, length: 100)) { error in
            guard case MemoryError.readBeyondBounds = error else {
                XCTFail("Expected readBeyondBounds error")
                return
            }
        }
    }

    func testMockMemoryDescriptorSizeOverflow() {
        let hugeSize: UInt64 = UInt64(Int.max) + 1
        XCTAssertThrowsError(try MockMemoryDescriptor(size: hugeSize)) { error in
            guard case MemoryError.sizeTooLarge = error else {
                XCTFail("Expected sizeTooLarge error")
                return
            }
        }
    }
}
