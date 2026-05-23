import Foundation
@testable import PRReviewDeskCore

enum KeychainTokenStoreTests {
    static func run() throws {
        try testMemoryTokenStoreSavesLoadsAndDeletesToken()
        try testPersonalAccessTokenCredentialStoreWrapsExistingTokenStore()
        try testStaticAccessTokenProviderBuildsBearerAuthorization()
        try testCredentialStoreAccessTokenProviderCachesLoadedCredentialUntilRecreated()
        try testVersionedCredentialStoreMigratesRawPersonalAccessToken()
        try testVersionedCredentialStoreRoundTripsEnvelopeMetadata()
        try testCredentialKindDisplayNamesDoNotExposeTokenValues()
        try testVersionedCredentialStoreReplacesOAuthCredentialWithPersonalAccessToken()
        try testVersionedCredentialStoreDeletesOAuthCredentialEnvelope()
        try testKeychainStoreUpdatesExistingItemWithoutDeletingIt()
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

    private static func testCredentialStoreAccessTokenProviderCachesLoadedCredentialUntilRecreated() throws {
        let tokenStore = InMemoryTokenStore(token: "first-token")
        let credentialStore = PersonalAccessTokenCredentialStore(tokenStore: tokenStore)
        let provider = CredentialStoreAccessTokenProvider(credentialStore: credentialStore)

        try expectEqual(try provider.authorizationHeader(), "Bearer first-token")

        try credentialStore.saveCredential(.personalAccessToken("second-token"))

        try expectEqual(try provider.authorizationHeader(), "Bearer first-token")

        let refreshedProvider = CredentialStoreAccessTokenProvider(credentialStore: credentialStore)
        try expectEqual(try refreshedProvider.authorizationHeader(), "Bearer second-token")
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

    private static func testCredentialKindDisplayNamesDoNotExposeTokenValues() throws {
        try expectEqual(GitHubCredentialKind.personalAccessToken.displayName, "Personal access token")
        try expectEqual(GitHubCredentialKind.oauthUserToken.displayName, "GitHub OAuth user token")
        try expectEqual(GitHubCredentialKind.githubAppInstallationToken.displayName, "GitHub App installation token")
    }

    private static func testVersionedCredentialStoreReplacesOAuthCredentialWithPersonalAccessToken() throws {
        let tokenStore = InMemoryTokenStore()
        let store = VersionedCredentialStore(tokenStore: tokenStore)

        try store.saveCredential(
            .oauthUserToken("oauth-token"),
            metadata: GitHubCredentialMetadata(
                login: "developjik",
                scopes: ["repo"],
                tokenType: "bearer"
            )
        )
        try store.saveCredential(.personalAccessToken("pat-token"))

        let record = try unwrap(try store.loadStoredCredential())
        try expectEqual(record.credential, .personalAccessToken("pat-token"))
        try expectEqual(record.kind.displayName, "Personal access token")
        try expectEqual(record.login, nil)
        try expectEqual(record.scopes, [])
        try expectEqual(record.tokenType, "Bearer")
    }

    private static func testVersionedCredentialStoreDeletesOAuthCredentialEnvelope() throws {
        let tokenStore = InMemoryTokenStore()
        let store = VersionedCredentialStore(tokenStore: tokenStore)

        try store.saveCredential(
            .oauthUserToken("oauth-token"),
            metadata: GitHubCredentialMetadata(scopes: ["repo"])
        )
        try store.deleteCredential()

        try expectEqual(try store.loadStoredCredential(), nil)
        try expectEqual(try store.loadCredential(), nil)
    }

    private static func testKeychainStoreUpdatesExistingItemWithoutDeletingIt() throws {
        let keychain = FakeKeychainItemAccessor(addStatuses: [errSecDuplicateItem], updateStatus: errSecSuccess)
        let store = KeychainTokenStore(service: "PRReviewDeskTests", account: "github", keychain: keychain)

        try store.saveToken("updated-token")

        try expectEqual(keychain.addCallCount, 1)
        try expectEqual(keychain.updateCallCount, 1)
        try expectEqual(keychain.deleteCallCount, 0)
        try expectEqual(keychain.storedToken, "updated-token")
    }

    private static func testKeychainStoreCanBeConstructedWithoutTouchingSecrets() throws {
        let store: TokenStore = KeychainTokenStore(service: "PRReviewDeskTests", account: "github")
        _ = store
    }
}

private final class FakeKeychainItemAccessor: KeychainItemAccessing, @unchecked Sendable {
    private var addStatuses: [OSStatus]
    private let updateStatus: OSStatus
    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var storedData: Data?

    var storedToken: String? {
        storedData.flatMap { String(data: $0, encoding: .utf8) }
    }

    init(addStatuses: [OSStatus] = [errSecSuccess], updateStatus: OSStatus = errSecSuccess) {
        self.addStatuses = addStatuses
        self.updateStatus = updateStatus
    }

    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        guard let storedData else {
            return errSecItemNotFound
        }

        result?.pointee = storedData as AnyObject
        return errSecSuccess
    }

    func add(_ item: [String: Any]) -> OSStatus {
        addCallCount += 1
        let status = addStatuses.isEmpty ? errSecSuccess : addStatuses.removeFirst()
        if status == errSecSuccess {
            storedData = item[kSecValueData as String] as? Data
        }
        return status
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateCallCount += 1
        guard updateStatus == errSecSuccess else {
            return updateStatus
        }

        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteCallCount += 1
        storedData = nil
        return errSecSuccess
    }
}
