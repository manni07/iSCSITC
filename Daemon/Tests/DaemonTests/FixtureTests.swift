import XCTest
@testable import ISCSIDaemon

final class FixtureTests: XCTestCase {
    func testSCSICommandDescriptorSize() {
        XCTAssertEqual(MemoryLayout<SCSICommandDescriptor>.size, 80,
                      "SCSICommandDescriptor must be exactly 80 bytes")
    }

    func testSCSICompletionDescriptorSize() {
        XCTAssertEqual(MemoryLayout<SCSICompletionDescriptor>.size, 280,
                      "SCSICompletionDescriptor must be exactly 280 bytes")
    }
}
