import XCTest
@testable import ISCSIProtocol

final class LoginStateMachineTests: XCTestCase {

    func testInitialState() async {
        let isid = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let sm = LoginStateMachine(isid: isid)

        let state = await sm.currentState
        XCTAssertEqual(state, .free)
    }

    func testGenerateITT() async {
        let isid = Data(count: 6)
        let sm = LoginStateMachine(isid: isid)

        let itt1 = await sm.generateITT()
        let itt2 = await sm.generateITT()

        XCTAssertNotEqual(itt1, itt2)  // Should be unique
    }
}
