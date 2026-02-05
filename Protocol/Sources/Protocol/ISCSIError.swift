import Foundation

public enum ISCSIError: Error, LocalizedError {
    // Connection errors
    case notConnected
    case alreadyConnected
    case connectionTimeout
    case connectionFailed(Error)
    case daemonNotConnected

    // Protocol errors
    case invalidPDU
    case invalidState
    case loginFailed(statusClass: UInt8, statusDetail: UInt8)
    case invalidLoginStage(current: UInt8, next: UInt8)
    case protocolViolation(String)

    // Session errors
    case sessionNotFound
    case sessionAlreadyExists
    case targetNotFound

    // Authentication errors
    case authenticationFailed
    case keychainError(status: OSStatus)

    // I/O errors
    case commandFailed(status: UInt8)
    case dataTransferError

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to target"
        case .alreadyConnected:
            return "Already connected"
        case .connectionTimeout:
            return "Connection timeout"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .daemonNotConnected:
            return "Daemon not connected"

        case .invalidPDU:
            return "Invalid PDU received"
        case .invalidState:
            return "Invalid state for operation"
        case .loginFailed(let statusClass, let statusDetail):
            return "Login failed: class=\(statusClass) detail=\(statusDetail)"
        case .invalidLoginStage(let current, let next):
            return "Invalid login stage transition: \(current) → \(next)"
        case .protocolViolation(let message):
            return "Protocol violation: \(message)"

        case .sessionNotFound:
            return "Session not found"
        case .sessionAlreadyExists:
            return "Session already exists"
        case .targetNotFound:
            return "Target not found"

        case .authenticationFailed:
            return "Authentication failed"
        case .keychainError(let status):
            return "Keychain error: \(status)"

        case .commandFailed(let status):
            return "SCSI command failed with status: 0x\(String(format: "%02x", status))"
        case .dataTransferError:
            return "Data transfer error"
        }
    }
}
