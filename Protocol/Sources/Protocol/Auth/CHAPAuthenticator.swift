import Foundation
import CryptoKit

/// CHAP (Challenge-Handshake Authentication Protocol) authenticator
/// Implements RFC 1994 CHAP using MD5 algorithm per RFC 7143 Section 11.1.4
public actor CHAPAuthenticator {
    public init() {}

    /// Compute CHAP response: MD5(identifier + secret + challenge)
    /// - Parameters:
    ///   - identifier: CHAP identifier byte
    ///   - secret: Shared secret (password)
    ///   - challenge: Challenge bytes from target
    /// - Returns: 16-byte MD5 hash
    public func computeCHAPResponse(
        identifier: UInt8,
        secret: String,
        challenge: Data
    ) -> Data {
        var hasher = Insecure.MD5()
        hasher.update(data: Data([identifier]))
        hasher.update(data: Data(secret.utf8))
        hasher.update(data: challenge)
        return Data(hasher.finalize())
    }
}
