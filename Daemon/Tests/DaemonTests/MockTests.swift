import XCTest
@testable import ISCSIDaemon

final class MockTests: XCTestCase {
    func testMockIOServiceCreation() {
        let service = MockIOService(name: "iSCSIVirtualHBA")
        XCTAssertEqual(service.name, "iSCSIVirtualHBA")
        XCTAssertEqual(service.state, .running)
    }

    func testMockMemoryDescriptorReadWrite() {
        let descriptor = MockMemoryDescriptor(size: 1024, direction: .inOut)

        let writeData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        descriptor.writeData(writeData, at: 0)

        let readData = descriptor.readData(at: 0, length: 4)
        XCTAssertEqual(readData, writeData)
        XCTAssertEqual(descriptor.size, 1024)
    }
}
