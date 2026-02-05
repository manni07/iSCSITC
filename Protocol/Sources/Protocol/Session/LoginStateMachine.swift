import Foundation

/// Login state machine for iSCSI session establishment
public actor LoginStateMachine {

    public enum State: Sendable, Equatable {
        case free
        case securityNegotiation
        case operationalNegotiation
        case fullFeaturePhase
        case failed(String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.free, .free),
                 (.securityNegotiation, .securityNegotiation),
                 (.operationalNegotiation, .operationalNegotiation),
                 (.fullFeaturePhase, .fullFeaturePhase):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) public var currentState: State = .free
    private let isid: Data
    private var tsih: UInt16 = 0
    private var itt: UInt32 = 0
    private var cmdSN: UInt32 = 0
    private var expStatSN: UInt32 = 0

    // Negotiated parameters
    private var negotiatedParams: [String: String] = [:]

    public init(isid: Data) {
        self.isid = isid
    }

    /// Generate unique ITT
    public func generateITT() -> UInt32 {
        itt += 1
        return itt
    }

    /// Build initial login PDU
    public func buildInitialLoginPDU(
        initiatorName: String
    ) -> LoginRequestPDU {
        var loginPDU = LoginRequestPDU()
        loginPDU.transit = true
        loginPDU.currentStageCode = 0  // Security negotiation
        loginPDU.nextStageCode = 1     // Operational negotiation
        loginPDU.versionMax = 0
        loginPDU.versionMin = 0
        loginPDU.isid = isid
        loginPDU.tsih = 0
        loginPDU.initiatorTaskTag = generateITT()
        loginPDU.cid = 0
        loginPDU.cmdSN = cmdSN
        loginPDU.expStatSN = expStatSN

        loginPDU.keyValuePairs = [
            "InitiatorName": initiatorName,
            "SessionType": "Normal",
            "AuthMethod": "None"
        ]

        return loginPDU
    }

    /// Process login response
    public func processLoginResponse(_ response: LoginResponsePDU) throws {
        // Check status
        if response.statusClass != 0 {
            let error = ISCSIError.loginFailed(
                statusClass: response.statusClass,
                statusDetail: response.statusDetail
            )
            currentState = .failed(error.localizedDescription)
            throw error
        }

        // Update sequence numbers
        expStatSN = response.statSN + 1
        cmdSN = response.expCmdSN

        // Update TSIH if provided
        if response.tsih != 0 {
            tsih = response.tsih
        }

        // Store negotiated parameters
        for (key, value) in response.keyValuePairs {
            negotiatedParams[key] = value
        }

        // Update state based on stage transition
        if response.transit {
            switch response.nextStageCode {
            case 1:
                currentState = .operationalNegotiation
            case 3:
                currentState = .fullFeaturePhase
            default:
                break
            }
        }
    }

    /// Get negotiated parameter value
    public func getNegotiatedParameter(_ key: String) -> String? {
        return negotiatedParams[key]
    }
}
