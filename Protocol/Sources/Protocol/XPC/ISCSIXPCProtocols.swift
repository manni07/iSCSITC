import Foundation

// MARK: - Data Models

/// Represents an iSCSI target
@objc public final class ISCSITarget: NSObject, NSSecureCoding, Sendable {
    public static var supportsSecureCoding: Bool { true }

    @objc public let iqn: String
    @objc public let portal: String  // IP:Port
    @objc public let targetPortalGroupTag: UInt16

    public init(iqn: String, portal: String, tpgt: UInt16 = 1) {
        self.iqn = iqn
        self.portal = portal
        self.targetPortalGroupTag = tpgt
    }

    public required init?(coder: NSCoder) {
        guard let iqn = coder.decodeObject(of: NSString.self, forKey: "iqn") as? String,
              let portal = coder.decodeObject(of: NSString.self, forKey: "portal") as? String else {
            return nil
        }
        self.iqn = iqn
        self.portal = portal
        self.targetPortalGroupTag = UInt16(coder.decodeInteger(forKey: "tpgt"))
    }

    public func encode(with coder: NSCoder) {
        coder.encode(iqn as NSString, forKey: "iqn")
        coder.encode(portal as NSString, forKey: "portal")
        coder.encode(Int(targetPortalGroupTag), forKey: "tpgt")
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ISCSITarget else { return false }
        return iqn == other.iqn && portal == other.portal
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(iqn)
        hasher.combine(portal)
        return hasher.finalize()
    }
}

/// Session state
@objc public enum ISCSISessionState: Int, Sendable {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case loggedIn = 3
    case failed = 4
}

/// Session information
@objc public final class ISCSISessionInfo: NSObject, NSSecureCoding, Sendable {
    public static var supportsSecureCoding: Bool { true }

    @objc public let target: ISCSITarget
    @objc public let state: ISCSISessionState
    @objc public let sessionID: String
    @objc public let connectedAt: Date?

    public init(target: ISCSITarget,
                state: ISCSISessionState,
                sessionID: String,
                connectedAt: Date? = nil) {
        self.target = target
        self.state = state
        self.sessionID = sessionID
        self.connectedAt = connectedAt
    }

    public required init?(coder: NSCoder) {
        guard let target = coder.decodeObject(of: ISCSITarget.self, forKey: "target"),
              let sessionID = coder.decodeObject(of: NSString.self, forKey: "sessionID") as? String else {
            return nil
        }
        self.target = target
        self.state = ISCSISessionState(rawValue: coder.decodeInteger(forKey: "state")) ?? .disconnected
        self.sessionID = sessionID
        self.connectedAt = coder.decodeObject(of: NSDate.self, forKey: "connectedAt") as? Date
    }

    public func encode(with coder: NSCoder) {
        coder.encode(target, forKey: "target")
        coder.encode(state.rawValue, forKey: "state")
        coder.encode(sessionID as NSString, forKey: "sessionID")
        if let connectedAt = connectedAt {
            coder.encode(connectedAt as NSDate, forKey: "connectedAt")
        }
    }
}

// MARK: - XPC Protocols

/// Main daemon protocol for app/CLI → daemon communication
@objc public protocol ISCSIDaemonXPCProtocol {

    /// Discover targets at a portal
    func discoverTargets(
        portal: String,
        completion: @escaping ([ISCSITarget]?, Error?) -> Void
    )

    /// Login to a target
    func loginToTarget(
        iqn: String,
        portal: String,
        username: String?,
        secret: String?,
        completion: @escaping (Error?) -> Void
    )

    /// Logout from a session
    func logoutFromTarget(
        sessionID: String,
        completion: @escaping (Error?) -> Void
    )

    /// List active sessions
    func listSessions(
        completion: @escaping ([ISCSISessionInfo], Error?) -> Void
    )

    /// Get daemon status
    func getStatus(
        completion: @escaping ([String: Any], Error?) -> Void
    )
}

/// Callback protocol for daemon → app notifications
@objc public protocol ISCSIDaemonCallbackProtocol {

    /// Session state changed
    func sessionStateChanged(sessionID: String, newState: ISCSISessionState)

    /// Connection lost
    func connectionLost(sessionID: String, error: Error)
}
