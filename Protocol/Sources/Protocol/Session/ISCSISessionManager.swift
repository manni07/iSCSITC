import Foundation

/// Information about an active iSCSI session
public struct SessionInfo: Sendable {
    public let sessionID: String
    public let targetIQN: String
    public let portal: String
    public let connectedAt: Date

    public init(sessionID: String, targetIQN: String, portal: String, connectedAt: Date) {
        self.sessionID = sessionID
        self.targetIQN = targetIQN
        self.portal = portal
        self.connectedAt = connectedAt
    }
}

/// Manages multiple iSCSI sessions
/// Orchestrates discovery, login, logout, and session lifecycle
public actor ISCSISessionManager {
    public let initiatorName: String
    private var sessions: [String: SessionInfo] = [:]
    private var isidCounter: UInt32 = 0

    public init(initiatorName: String) {
        self.initiatorName = initiatorName
    }

    /// Generate unique ISID (Initiator Session ID)
    /// Format: 0x00 (OUI format) + 40-bit random/sequential value
    /// - Returns: 6-byte ISID
    public func generateISID() -> Data {
        var isid = Data(count: 6)
        isid[0] = 0x00  // OUI format

        // Increment counter for uniqueness
        isidCounter += 1

        // Use counter + timestamp for uniqueness
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let combined = (UInt64(timestamp) << 32) | UInt64(isidCounter)

        // Pack into bytes 1-5 (40 bits)
        isid[1] = UInt8((combined >> 32) & 0xFF)
        isid[2] = UInt8((combined >> 24) & 0xFF)
        isid[3] = UInt8((combined >> 16) & 0xFF)
        isid[4] = UInt8((combined >> 8) & 0xFF)
        isid[5] = UInt8(combined & 0xFF)

        return isid
    }

    /// Track a new session
    /// - Parameters:
    ///   - targetIQN: Target IQN
    ///   - portal: Portal address (host:port)
    /// - Returns: Session ID
    public func trackSession(targetIQN: String, portal: String) -> String {
        let sessionID = UUID().uuidString
        let info = SessionInfo(
            sessionID: sessionID,
            targetIQN: targetIQN,
            portal: portal,
            connectedAt: Date()
        )
        sessions[sessionID] = info
        return sessionID
    }

    /// Remove a session
    /// - Parameter sessionID: Session ID to remove
    public func removeSession(sessionID: String) {
        sessions.removeValue(forKey: sessionID)
    }

    /// List all active sessions
    /// - Returns: Array of session info
    public func listSessions() -> [SessionInfo] {
        Array(sessions.values)
    }

    /// Get session by ID
    /// - Parameter sessionID: Session ID
    /// - Returns: Session info or nil
    public func getSession(sessionID: String) -> SessionInfo? {
        sessions[sessionID]
    }
}
