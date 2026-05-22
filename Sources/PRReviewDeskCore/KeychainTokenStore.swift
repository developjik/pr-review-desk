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

public struct PersonalAccessTokenCredentialStore: CredentialStore, Sendable {
    private let tokenStore: any TokenStore

    public init(tokenStore: any TokenStore) {
        self.tokenStore = tokenStore
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
