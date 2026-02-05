import Foundation

// MARK: - Text Request PDU

public struct TextRequestPDU: Sendable {
    public struct Flags: Sendable {
        public var final: Bool
        public var `continue`: Bool

        public init(final: Bool, `continue`: Bool) {
            self.final = final
            self.continue = `continue`
        }
    }

    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var cmdSN: UInt32
    public var expStatSN: UInt32
    public var keyValuePairs: [String: String]
    public var flags: Flags

    public init(
        initiatorTaskTag: UInt32,
        targetTransferTag: UInt32,
        cmdSN: UInt32,
        expStatSN: UInt32,
        keyValuePairs: [String: String],
        flags: Flags
    ) {
        self.initiatorTaskTag = initiatorTaskTag
        self.targetTransferTag = targetTransferTag
        self.cmdSN = cmdSN
        self.expStatSN = expStatSN
        self.keyValuePairs = keyValuePairs
        self.flags = flags
    }
}

// MARK: - Text Response PDU

public struct TextResponsePDU: Sendable {
    public struct Flags: Sendable {
        public var final: Bool
        public var `continue`: Bool

        public init(final: Bool, `continue`: Bool) {
            self.final = final
            self.continue = `continue`
        }
    }

    public var initiatorTaskTag: UInt32
    public var targetTransferTag: UInt32
    public var statSN: UInt32
    public var expCmdSN: UInt32
    public var maxCmdSN: UInt32
    public var keyValuePairs: [String: String]
    public var flags: Flags

    public init(
        initiatorTaskTag: UInt32,
        targetTransferTag: UInt32,
        statSN: UInt32,
        expCmdSN: UInt32,
        maxCmdSN: UInt32,
        keyValuePairs: [String: String],
        flags: Flags
    ) {
        self.initiatorTaskTag = initiatorTaskTag
        self.targetTransferTag = targetTransferTag
        self.statSN = statSN
        self.expCmdSN = expCmdSN
        self.maxCmdSN = maxCmdSN
        self.keyValuePairs = keyValuePairs
        self.flags = flags
    }
}

// MARK: - Discovered Target

/// Represents an iSCSI target discovered via SendTargets
public struct DiscoveredTarget: Sendable {
    /// Portal information
    public struct Portal: Sendable {
        public var address: String
        public var port: UInt16
        public var groupTag: UInt16

        public init(address: String, port: UInt16, groupTag: UInt16) {
            self.address = address
            self.port = port
            self.groupTag = groupTag
        }
    }

    public var iqn: String
    public var portals: [Portal]

    public init(iqn: String, portals: [Portal]) {
        self.iqn = iqn
        self.portals = portals
    }
}

// MARK: - SendTargets Parser

public struct TextPDU {
    /// Parse SendTargets response into discovered targets
    /// - Parameter keyValuePairs: Key-value pairs from text response
    /// - Returns: Array of discovered targets
    public static func parseSendTargetsResponse(_ keyValuePairs: [String: String]) -> [DiscoveredTarget] {
        guard let targetName = keyValuePairs["TargetName"],
              let targetAddress = keyValuePairs["TargetAddress"] else {
            return []
        }

        // Parse portal address: "host:port,tag"
        let portal = parsePortalAddress(targetAddress)

        return [DiscoveredTarget(iqn: targetName, portals: [portal])]
    }

    /// Parse portal address string into Portal struct
    /// - Parameter address: Address string in format "host:port,tag"
    /// - Returns: Portal struct
    private static func parsePortalAddress(_ address: String) -> DiscoveredTarget.Portal {
        let parts = address.split(separator: ",")
        let addressPart = String(parts[0])
        let groupTag = parts.count > 1 ? UInt16(parts[1]) ?? 1 : 1

        let hostPort = addressPart.split(separator: ":")
        let host = String(hostPort[0])
        let port = hostPort.count > 1 ? UInt16(hostPort[1]) ?? 3260 : 3260

        return DiscoveredTarget.Portal(address: host, port: port, groupTag: groupTag)
    }
}
