import Foundation

/// Negotiates iSCSI session parameters per RFC 7143 Section 13
public actor ParameterNegotiator {
    private var initiatorParams: [String: String]
    private var negotiatedParams: [String: String] = [:]

    public init() {
        // RFC 7143 default values for initiator
        self.initiatorParams = [
            "MaxRecvDataSegmentLength": "262144",  // 256 KB
            "MaxBurstLength": "262144",
            "FirstBurstLength": "65536",  // 64 KB
            "DefaultTime2Wait": "2",
            "DefaultTime2Retain": "20",
            "MaxOutstandingR2T": "1",
            "ErrorRecoveryLevel": "0",
            "InitialR2T": "Yes",
            "ImmediateData": "Yes",
            "DataPDUInOrder": "Yes",
            "DataSequenceInOrder": "Yes"
        ]
    }

    /// Get initiator's offered parameters
    /// - Returns: Dictionary of parameter key-value pairs
    public func getInitiatorParameters() -> [String: String] {
        initiatorParams
    }

    /// Negotiate parameters with target's response
    /// - Parameter targetParameters: Target's offered/responded parameters
    /// - Throws: ISCSIError.protocolViolation if negotiation fails
    public func negotiate(targetParameters: [String: String]) throws {
        negotiatedParams = [:]

        for (key, targetValue) in targetParameters {
            guard let initiatorValue = initiatorParams[key] else {
                // Target offered parameter we don't support - ignore
                continue
            }

            let negotiated: String
            switch key {
            // Numerical parameters - take minimum
            case "MaxRecvDataSegmentLength", "MaxBurstLength", "FirstBurstLength",
                 "MaxOutstandingR2T", "ErrorRecoveryLevel":
                let initNum = UInt32(initiatorValue) ?? 0
                let targetNum = UInt32(targetValue) ?? 0
                negotiated = String(min(initNum, targetNum))

            case "DefaultTime2Wait", "DefaultTime2Retain":
                let initNum = UInt32(initiatorValue) ?? 0
                let targetNum = UInt32(targetValue) ?? 0
                negotiated = String(max(initNum, targetNum))

            // Boolean parameters - AND/OR logic
            case "InitialR2T", "DataPDUInOrder", "DataSequenceInOrder":
                // These use AND: both must be Yes for result to be Yes
                negotiated = (initiatorValue == "Yes" && targetValue == "Yes") ? "Yes" : "No"

            case "ImmediateData":
                // OR: either can enable it
                negotiated = (initiatorValue == "Yes" || targetValue == "Yes") ? "Yes" : "No"

            default:
                // Unknown parameter - use target value
                negotiated = targetValue
            }

            negotiatedParams[key] = negotiated
        }

        // Fill in any parameters not offered by target with our values
        for (key, value) in initiatorParams where negotiatedParams[key] == nil {
            negotiatedParams[key] = value
        }
    }

    /// Get negotiated parameters after negotiation
    /// - Returns: Dictionary of negotiated parameter key-value pairs
    public func getNegotiatedParameters() -> [String: String] {
        negotiatedParams.isEmpty ? initiatorParams : negotiatedParams
    }
}
