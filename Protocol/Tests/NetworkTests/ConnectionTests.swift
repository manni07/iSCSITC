import XCTest
import Network
@testable import ISCSINetwork

final class ConnectionTests: XCTestCase {

    func testConnectionInitialization() async {
        // Test that connection can be created
        let conn = ISCSIConnection(host: "192.168.1.10", port: 3260)
        XCTAssertNotNil(conn)
    }

    func testConnectionStateTransitions() async {
        let conn = ISCSIConnection(host: "127.0.0.1", port: 9999)

        // Initial state should be disconnected
        let initialState = await conn.currentState
        XCTAssertEqual(initialState, .disconnected)
    }
}
