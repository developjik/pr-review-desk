import Foundation
import PRReviewDeskCore

enum KeychainTokenStoreTests {
    static func run() throws {
        try testMemoryTokenStoreSavesLoadsAndDeletesToken()
        try testPersonalAccessTokenCredentialStoreWrapsExistingTokenStore()
        try testStaticAccessTokenProviderBuildsBearerAuthorization()
        try testKeychainStoreCanBeConstructedWithoutTouchingSecrets()
    }

    private static func testMemoryTokenStoreSavesLoadsAndDeletesToken() throws {
        let store = InMemoryTokenStore()

        try expectEqual(try store.loadToken(), nil)
        try store.saveToken("test-token")
        try expectEqual(try store.loadToken(), "test-token")
        try store.deleteToken()
        try expectEqual(try store.loadToken(), nil)
    }

    private static func testPersonalAccessTokenCredentialStoreWrapsExistingTokenStore() throws {
        let tokenStore = InMemoryTokenStore(token: "test-token")
        let credentialStore = PersonalAccessTokenCredentialStore(tokenStore: tokenStore)

        try expectEqual(try credentialStore.loadCredential(), .personalAccessToken("test-token"))

        try credentialStore.saveCredential(.personalAccessToken("new-token"))
        try expectEqual(try tokenStore.loadToken(), "new-token")

        try credentialStore.deleteCredential()
        try expectEqual(try credentialStore.loadCredential(), nil)
    }

    private static func testStaticAccessTokenProviderBuildsBearerAuthorization() throws {
        let provider = StaticAccessTokenProvider(credential: .personalAccessToken("test-token"))

        try expectEqual(try provider.authorizationHeader(), "Bearer test-token")
    }

    private static func testKeychainStoreCanBeConstructedWithoutTouchingSecrets() throws {
        let store: TokenStore = KeychainTokenStore(service: "PRReviewDeskTests", account: "github")
        _ = store
    }
}
