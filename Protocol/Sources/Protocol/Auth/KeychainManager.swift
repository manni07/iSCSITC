import Foundation
import Security

/// Manages iSCSI credentials in the macOS Keychain
public actor KeychainManager {
    private let service = "com.opensource.iscsi.initiator"

    public init() {}

    /// Store CHAP credentials for a target
    /// - Parameters:
    ///   - iqn: Target IQN
    ///   - username: CHAP username
    ///   - secret: CHAP secret (password)
    /// - Throws: ISCSIError.keychainError on failure
    public func storeCredential(iqn: String, username: String, secret: String) throws {
        let credentialData = "\(username):\(secret)".data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: iqn,
            kSecValueData as String: credentialData
        ]

        // Try to delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ISCSIError.keychainError(status: status)
        }
    }

    /// Retrieve CHAP credentials for a target
    /// - Parameter iqn: Target IQN
    /// - Returns: Tuple of (username, secret)
    /// - Throws: ISCSIError.keychainError if not found
    public func retrieveCredential(iqn: String) throws -> (String, String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: iqn,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw ISCSIError.keychainError(status: status)
        }

        let credentialString = String(data: data, encoding: .utf8)!
        let components = credentialString.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else {
            throw ISCSIError.keychainError(status: errSecInternalError)
        }

        return (String(components[0]), String(components[1]))
    }

    /// Delete credentials for a target
    /// - Parameter iqn: Target IQN
    /// - Throws: ISCSIError.keychainError on failure
    public func deleteCredential(iqn: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: iqn
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ISCSIError.keychainError(status: status)
        }
    }
}
