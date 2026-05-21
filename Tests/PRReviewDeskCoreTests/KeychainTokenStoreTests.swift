import Foundation
import PRReviewDeskCore

enum KeychainTokenStoreTests {
    static func run() throws {
        try testMemoryTokenStoreSavesLoadsAndDeletesToken()
        try testKeychainStoreCanBeConstructedWithoutTouchingSecrets()
    }

    private static func testMemoryTokenStoreSavesLoadsAndDeletesToken() throws {
        let store = InMemoryTokenStore()

        try expectEqual(try store.loadToken(), nil)
        try store.saveToken("ghp_test")
        try expectEqual(try store.loadToken(), "ghp_test")
        try store.deleteToken()
        try expectEqual(try store.loadToken(), nil)
    }

    private static func testKeychainStoreCanBeConstructedWithoutTouchingSecrets() throws {
        let store: TokenStore = KeychainTokenStore(service: "PRReviewDeskTests", account: "github")
        _ = store
    }
}
