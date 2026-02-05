import XCTest
@testable import ISCSIProtocol
import CryptoKit

final class CHAPAuthenticatorTests: XCTestCase {
    func testCHAPResponseGeneration() async throws {
        let authenticator = CHAPAuthenticator()
        let identifier: UInt8 = 123
        let secret = "mySecretPassword"
        let challenge = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

        let response = await authenticator.computeCHAPResponse(
            identifier: identifier,
            secret: secret,
            challenge: challenge
        )

        // Verify MD5(identifier + secret + challenge)
        var hasher = Insecure.MD5()
        hasher.update(data: Data([identifier]))
        hasher.update(data: Data(secret.utf8))
        hasher.update(data: challenge)
        let expected = Data(hasher.finalize())

        XCTAssertEqual(response, expected, "CHAP response should match MD5 hash")
    }

    func testEmptySecretHandling() async {
        let authenticator = CHAPAuthenticator()
        let response = await authenticator.computeCHAPResponse(
            identifier: 1,
            secret: "",
            challenge: Data([0x01])
        )
        XCTAssertEqual(response.count, 16, "MD5 hash should always be 16 bytes")
    }
}
