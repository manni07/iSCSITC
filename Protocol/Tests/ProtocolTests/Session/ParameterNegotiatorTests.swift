import XCTest
@testable import ISCSIProtocol

final class ParameterNegotiatorTests: XCTestCase {
    func testDefaultParameters() async {
        let negotiator = ParameterNegotiator()
        let defaults = await negotiator.getInitiatorParameters()

        XCTAssertEqual(defaults["MaxRecvDataSegmentLength"], "262144")
        XCTAssertEqual(defaults["MaxBurstLength"], "262144")
        XCTAssertEqual(defaults["FirstBurstLength"], "65536")
        XCTAssertEqual(defaults["DefaultTime2Wait"], "2")
        XCTAssertEqual(defaults["DefaultTime2Retain"], "20")
        XCTAssertEqual(defaults["MaxOutstandingR2T"], "1")
        XCTAssertEqual(defaults["ErrorRecoveryLevel"], "0")
        XCTAssertEqual(defaults["InitialR2T"], "Yes")
        XCTAssertEqual(defaults["ImmediateData"], "Yes")
        XCTAssertEqual(defaults["DataPDUInOrder"], "Yes")
        XCTAssertEqual(defaults["DataSequenceInOrder"], "Yes")
    }

    func testNegotiateMaxRecvDataSegmentLength() async throws {
        let negotiator = ParameterNegotiator()

        // Target offers smaller value - should take minimum
        var targetParams = ["MaxRecvDataSegmentLength": "131072"]
        try await negotiator.negotiate(targetParameters: targetParams)
        var result = await negotiator.getNegotiatedParameters()
        XCTAssertEqual(result["MaxRecvDataSegmentLength"], "131072")

        // Target offers larger value - should keep our value
        targetParams = ["MaxRecvDataSegmentLength": "524288"]
        try await negotiator.negotiate(targetParameters: targetParams)
        result = await negotiator.getNegotiatedParameters()
        XCTAssertEqual(result["MaxRecvDataSegmentLength"], "262144")
    }

    func testNegotiateBooleanParameters() async throws {
        let negotiator = ParameterNegotiator()

        // InitialR2T: Yes AND Yes = Yes
        var targetParams = ["InitialR2T": "Yes"]
        try await negotiator.negotiate(targetParameters: targetParams)
        var result = await negotiator.getNegotiatedParameters()
        XCTAssertEqual(result["InitialR2T"], "Yes")

        // InitialR2T: Yes AND No = No (OR operation)
        targetParams = ["InitialR2T": "No"]
        try await negotiator.negotiate(targetParameters: targetParams)
        result = await negotiator.getNegotiatedParameters()
        XCTAssertEqual(result["InitialR2T"], "No")
    }

    func testNegotiateErrorRecoveryLevel() async throws {
        let negotiator = ParameterNegotiator()

        // Target supports higher level - use minimum
        let targetParams = ["ErrorRecoveryLevel": "2"]
        try await negotiator.negotiate(targetParameters: targetParams)
        let result = await negotiator.getNegotiatedParameters()
        XCTAssertEqual(result["ErrorRecoveryLevel"], "0")
    }
}
