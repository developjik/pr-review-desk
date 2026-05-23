import Foundation
import PRReviewDeskCore

enum CredentialStoreAccessTokenProviderTests {
    static func run() async throws {
        try await testGitHubRequestsReuseCredentialLoadedFromStore()
    }

    private static func testGitHubRequestsReuseCredentialLoadedFromStore() async throws {
        let credentialStore = CountingCredentialStore(credential: .personalAccessToken("cached-token"))
        let provider = CredentialStoreAccessTokenProvider(credentialStore: credentialStore)
        let transport = RepeatingGitHubUserTransport()
        let client = GitHubClient(
            accessTokenProvider: provider,
            baseURL: URL(string: "https://api.github.test")!,
            transport: transport
        )

        _ = try await client.validateToken()
        _ = try await client.validateToken()

        try expectEqual(credentialStore.loadCredentialCount, 1)
        try expectEqual(transport.authorizationHeaders, ["Bearer cached-token", "Bearer cached-token"])
    }
}

private final class CountingCredentialStore: CredentialStore, @unchecked Sendable {
    private let credential: GitHubCredential?
    private(set) var loadCredentialCount = 0

    init(credential: GitHubCredential?) {
        self.credential = credential
    }

    func loadCredential() throws -> GitHubCredential? {
        loadCredentialCount += 1
        return credential
    }

    func saveCredential(_ credential: GitHubCredential) throws {}

    func deleteCredential() throws {}
}

private final class RepeatingGitHubUserTransport: GitHubTransport, @unchecked Sendable {
    private(set) var authorizationHeaders: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["X-OAuth-Scopes": "repo"]
        )!
        return (Data(#"{"login":"developjik"}"#.utf8), response)
    }
}
