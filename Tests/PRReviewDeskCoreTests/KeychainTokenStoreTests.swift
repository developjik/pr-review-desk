import Foundation
import PRReviewDeskCore

enum KeychainTokenStoreTests {
    static func run() throws {
        try testMemoryTokenStoreSavesLoadsAndDeletesToken()
        try testPersonalAccessTokenCredentialStoreWrapsExistingTokenStore()
        try testStaticAccessTokenProviderBuildsBearerAuthorization()
        try testCredentialStoreAccessTokenProviderReadsCurrentCredential()
        try testVersionedCredentialStoreMigratesRawPersonalAccessToken()
        try testVersionedCredentialStoreRoundTripsEnvelopeMetadata()
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

    private static func testCredentialStoreAccessTokenProviderReadsCurrentCredential() throws {
        let tokenStore = InMemoryTokenStore(token: "first-token")
        let credentialStore = PersonalAccessTokenCredentialStore(tokenStore: tokenStore)
        let provider = CredentialStoreAccessTokenProvider(credentialStore: credentialStore)

        try expectEqual(try provider.authorizationHeader(), "Bearer first-token")

        try credentialStore.saveCredential(.personalAccessToken("second-token"))

        try expectEqual(try provider.authorizationHeader(), "Bearer second-token")
    }

    private static func testVersionedCredentialStoreMigratesRawPersonalAccessToken() throws {
        let tokenStore = InMemoryTokenStore(token: "legacy-token")
        let store = VersionedCredentialStore(tokenStore: tokenStore)

        try expectEqual(try store.loadCredential(), .personalAccessToken("legacy-token"))

        let storedToken = try unwrap(try tokenStore.loadToken())
        try expectTrue(storedToken.contains(#""version":1"#))
        try expectTrue(storedToken.contains(#""kind":"personalAccessToken""#))
        try expectTrue(storedToken.contains(#""accessToken":"legacy-token""#))

        let record = try unwrap(try store.loadStoredCredential())
        try expectEqual(record.credential, .personalAccessToken("legacy-token"))
        try expectEqual(record.login, nil)
        try expectEqual(record.scopes, [])
        try expectEqual(record.tokenType, "Bearer")
    }

    private static func testVersionedCredentialStoreRoundTripsEnvelopeMetadata() throws {
        let tokenStore = InMemoryTokenStore()
        let store = VersionedCredentialStore(tokenStore: tokenStore)
        let expiration = Date(timeIntervalSince1970: 1_800_000_000)

        try store.saveCredential(
            .oauthUserToken("oauth-token"),
            metadata: GitHubCredentialMetadata(
                login: "developjik",
                scopes: ["repo", "read:org"],
                tokenType: "Bearer",
                expiresAt: expiration
            )
        )

        try expectEqual(try store.loadCredential(), .oauthUserToken("oauth-token"))
        let record = try unwrap(try store.loadStoredCredential())
        try expectEqual(record.version, 1)
        try expectEqual(record.credential, .oauthUserToken("oauth-token"))
        try expectEqual(record.login, "developjik")
        try expectEqual(record.scopes, ["repo", "read:org"])
        try expectEqual(record.tokenType, "Bearer")
        try expectEqual(record.expiresAt, expiration)
        try expectTrue(record.updatedAt >= record.createdAt)
    }

    private static func testKeychainStoreCanBeConstructedWithoutTouchingSecrets() throws {
        let store: TokenStore = KeychainTokenStore(service: "PRReviewDeskTests", account: "github")
        _ = store
    }
}
