import Foundation
import Security

public protocol TokenStore: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

public enum GitHubCredential: Equatable, Hashable, Sendable {
    case personalAccessToken(String)
    case oauthUserToken(String)
    case githubAppInstallationToken(String)

    public var accessToken: String {
        switch self {
        case let .personalAccessToken(token),
             let .oauthUserToken(token),
             let .githubAppInstallationToken(token):
            return token
        }
    }
}

public enum GitHubCredentialKind: String, Codable, Equatable, Hashable, Sendable {
    case personalAccessToken
    case oauthUserToken
    case githubAppInstallationToken

    public init(credential: GitHubCredential) {
        switch credential {
        case .personalAccessToken:
            self = .personalAccessToken
        case .oauthUserToken:
            self = .oauthUserToken
        case .githubAppInstallationToken:
            self = .githubAppInstallationToken
        }
    }
}

public struct GitHubCredentialMetadata: Equatable, Hashable, Sendable {
    public var login: String?
    public var scopes: [String]
    public var tokenType: String?
    public var expiresAt: Date?

    public init(
        login: String? = nil,
        scopes: [String] = [],
        tokenType: String? = "Bearer",
        expiresAt: Date? = nil
    ) {
        self.login = login
        self.scopes = scopes
        self.tokenType = tokenType
        self.expiresAt = expiresAt
    }
}

public struct StoredGitHubCredential: Codable, Equatable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var kind: GitHubCredentialKind
    public var accessToken: String
    public var login: String?
    public var scopes: [String]
    public var tokenType: String?
    public var expiresAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        version: Int = StoredGitHubCredential.currentVersion,
        kind: GitHubCredentialKind,
        accessToken: String,
        login: String? = nil,
        scopes: [String] = [],
        tokenType: String? = "Bearer",
        expiresAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.version = version
        self.kind = kind
        self.accessToken = accessToken
        self.login = login
        self.scopes = scopes
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var credential: GitHubCredential {
        switch kind {
        case .personalAccessToken:
            return .personalAccessToken(accessToken)
        case .oauthUserToken:
            return .oauthUserToken(accessToken)
        case .githubAppInstallationToken:
            return .githubAppInstallationToken(accessToken)
        }
    }
}

public enum CredentialStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case unsupportedCredentialKind

    public var description: String {
        switch self {
        case .unsupportedCredentialKind:
            return "This credential store only supports personal access tokens"
        }
    }
}

public protocol CredentialStore: Sendable {
    func loadCredential() throws -> GitHubCredential?
    func saveCredential(_ credential: GitHubCredential) throws
    func deleteCredential() throws
}

public protocol OAuthCredentialStoring: CredentialStore {
    func saveCredential(_ credential: GitHubCredential, metadata: GitHubCredentialMetadata) throws
}

public struct VersionedCredentialStore: CredentialStore, Sendable {
    private let tokenStore: any TokenStore
    private let now: @Sendable () -> Date

    public init(tokenStore: any TokenStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.tokenStore = tokenStore
        self.now = now
    }

    public static func keychainDefault() -> VersionedCredentialStore {
        VersionedCredentialStore(tokenStore: KeychainTokenStore())
    }

    public func loadCredential() throws -> GitHubCredential? {
        try loadStoredCredential()?.credential
    }

    public func loadStoredCredential() throws -> StoredGitHubCredential? {
        guard let token = try tokenStore.loadToken(), !token.isEmpty else {
            return nil
        }

        if let storedCredential = try? Self.decoder.decode(
            StoredGitHubCredential.self,
            from: Data(token.utf8)
        ) {
            return storedCredential
        }

        let timestamp = now()
        let migratedCredential = StoredGitHubCredential(
            kind: .personalAccessToken,
            accessToken: token,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try saveStoredCredential(migratedCredential)
        return migratedCredential
    }

    public func saveCredential(_ credential: GitHubCredential) throws {
        try saveCredential(credential, metadata: GitHubCredentialMetadata())
    }

    public func saveCredential(
        _ credential: GitHubCredential,
        metadata: GitHubCredentialMetadata
    ) throws {
        let timestamp = now()
        let existingCredential = try loadStoredCredential()
        let storedCredential = StoredGitHubCredential(
            kind: GitHubCredentialKind(credential: credential),
            accessToken: credential.accessToken,
            login: metadata.login,
            scopes: metadata.scopes,
            tokenType: metadata.tokenType,
            expiresAt: metadata.expiresAt,
            createdAt: existingCredential?.createdAt ?? timestamp,
            updatedAt: timestamp
        )

        try saveStoredCredential(storedCredential)
    }

    public func deleteCredential() throws {
        try tokenStore.deleteToken()
    }

    private func saveStoredCredential(_ credential: StoredGitHubCredential) throws {
        let data = try Self.encoder.encode(credential)
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainTokenStoreError.invalidTokenData
        }

        try tokenStore.saveToken(token)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension VersionedCredentialStore: OAuthCredentialStoring {}

public struct PersonalAccessTokenCredentialStore: CredentialStore, Sendable {
    private let tokenStore: any TokenStore

    public init(tokenStore: any TokenStore) {
        self.tokenStore = tokenStore
    }

    public static func keychainDefault() -> PersonalAccessTokenCredentialStore {
        PersonalAccessTokenCredentialStore(tokenStore: KeychainTokenStore())
    }

    public func loadCredential() throws -> GitHubCredential? {
        guard let token = try tokenStore.loadToken() else {
            return nil
        }

        return .personalAccessToken(token)
    }

    public func saveCredential(_ credential: GitHubCredential) throws {
        guard case let .personalAccessToken(token) = credential else {
            throw CredentialStoreError.unsupportedCredentialKind
        }

        try tokenStore.saveToken(token)
    }

    public func deleteCredential() throws {
        try tokenStore.deleteToken()
    }
}

public protocol AccessTokenProvider: Sendable {
    func authorizationHeader() throws -> String
}

public struct StaticAccessTokenProvider: AccessTokenProvider, Sendable {
    private let credential: GitHubCredential

    public init(credential: GitHubCredential) {
        self.credential = credential
    }

    public func authorizationHeader() throws -> String {
        "Bearer \(credential.accessToken)"
    }
}

public struct CredentialStoreAccessTokenProvider: AccessTokenProvider, Sendable {
    private let credentialStore: any CredentialStore

    public init(credentialStore: any CredentialStore) {
        self.credentialStore = credentialStore
    }

    public func authorizationHeader() throws -> String {
        guard let credential = try credentialStore.loadCredential() else {
            throw CredentialStoreError.unsupportedCredentialKind
        }

        return "Bearer \(credential.accessToken)"
    }
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func loadToken() throws -> String? {
        token
    }

    public func saveToken(_ token: String) throws {
        self.token = token
    }

    public func deleteToken() throws {
        token = nil
    }
}

public enum KeychainTokenStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidTokenData

    public var description: String {
        switch self {
        case let .unexpectedStatus(status):
            return "Keychain returned status \(status)"
        case .invalidTokenData:
            return "Keychain token data was not valid UTF-8"
        }
    }
}

public struct KeychainTokenStore: TokenStore, Sendable {
    private let service: String
    private let account: String

    public init(service: String = "PRReviewDesk", account: String = "github-token") {
        self.service = service
        self.account = account
    }

    public func loadToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }

        guard
            let data = result as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            throw KeychainTokenStoreError.invalidTokenData
        }

        return token
    }

    public func saveToken(_ token: String) throws {
        try deleteToken()

        var item = baseQuery()
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    public func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
