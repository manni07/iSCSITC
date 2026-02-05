import XCTest
@testable import ISCSIProtocol
import Security

final class KeychainManagerTests: XCTestCase {
    let testIQN = "iqn.2025-02.com.test:storage.target01"
    let testUsername = "testuser"
    let testSecret = "testpassword"

    override func setUp() async throws {
        // Clean up any existing test credentials
        let manager = KeychainManager()
        try? await manager.deleteCredential(iqn: testIQN)
    }

    override func tearDown() async throws {
        let manager = KeychainManager()
        try? await manager.deleteCredential(iqn: testIQN)
    }

    func testStoreAndRetrieveCredential() async throws {
        let manager = KeychainManager()

        // Store credential
        try await manager.storeCredential(iqn: testIQN, username: testUsername, secret: testSecret)

        // Retrieve credential
        let (username, secret) = try await manager.retrieveCredential(iqn: testIQN)

        XCTAssertEqual(username, testUsername)
        XCTAssertEqual(secret, testSecret)
    }

    func testRetrieveNonexistentCredential() async {
        let manager = KeychainManager()

        do {
            _ = try await manager.retrieveCredential(iqn: "iqn.nonexistent")
            XCTFail("Should throw keychainError")
        } catch ISCSIError.keychainError(let status) {
            XCTAssertEqual(status, errSecItemNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpdateExistingCredential() async throws {
        let manager = KeychainManager()

        // Store initial credential
        try await manager.storeCredential(iqn: testIQN, username: testUsername, secret: testSecret)

        // Update with new secret
        let newSecret = "newpassword"
        try await manager.storeCredential(iqn: testIQN, username: testUsername, secret: newSecret)

        // Verify updated secret
        let (_, secret) = try await manager.retrieveCredential(iqn: testIQN)
        XCTAssertEqual(secret, newSecret)
    }
}
