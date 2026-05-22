import Foundation
import PRReviewDeskCore

enum GitHubOAuthDeviceFlowClientTests {
    static func run() async throws {
        try await testStartDeviceFlowPostsClientAndScopes()
        try await testPollAccessTokenMapsPendingSlowDownAndSuccess()
        try await testPollAccessTokenMapsTerminalErrors()
        try await testPollUntilAuthorizedPersistsOAuthCredentialAndBacksOffSlowDown()
        try await testPollUntilAuthorizedReturnsCancelledWithoutPersistingCredential()
    }

    private static func testStartDeviceFlowPostsClientAndScopes() async throws {
        let transport = FakeOAuthTransport(responses: [
            FakeOAuthResponse(data: """
            {
              "device_code": "device-code",
              "user_code": "ABCD-EFGH",
              "verification_uri": "https://github.com/login/device",
              "expires_in": 900,
              "interval": 5
            }
            """)
        ])
        let client = GitHubOAuthDeviceFlowClient(transport: transport)

        let authorization = try await client.startDeviceFlow(clientID: "client-123", scopes: ["repo", "read:org"])

        try expectEqual(authorization.deviceCode, "device-code")
        try expectEqual(authorization.userCode, "ABCD-EFGH")
        try expectEqual(authorization.verificationURI, URL(string: "https://github.com/login/device")!)
        try expectEqual(authorization.expiresIn, 900)
        try expectEqual(authorization.interval, 5)
        let request = try unwrap(transport.requests.first)
        try expectEqual(request.httpMethod, "POST")
        try expectEqual(request.url?.path, "/login/device/code")
        try expectEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        try expectEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(data: try unwrap(request.httpBody), encoding: .utf8)
        try expectEqual(body, "client_id=client-123&scope=repo%20read%3Aorg")
    }

    private static func testPollAccessTokenMapsPendingSlowDownAndSuccess() async throws {
        let transport = FakeOAuthTransport(responses: [
            FakeOAuthResponse(data: #"{"error":"authorization_pending"}"#),
            FakeOAuthResponse(data: #"{"error":"slow_down"}"#),
            FakeOAuthResponse(data: #"{"access_token":"oauth-token","token_type":"bearer","scope":"repo,read:org"}"#)
        ])
        let client = GitHubOAuthDeviceFlowClient(transport: transport)

        try expectEqual(
            try await client.pollAccessToken(clientID: "client-123", deviceCode: "device-code"),
            .pending
        )
        try expectEqual(
            try await client.pollAccessToken(clientID: "client-123", deviceCode: "device-code"),
            .slowDown
        )
        try expectEqual(
            try await client.pollAccessToken(clientID: "client-123", deviceCode: "device-code"),
            .success(OAuthAccessToken(accessToken: "oauth-token", tokenType: "bearer", scopes: ["repo", "read:org"]))
        )
    }

    private static func testPollAccessTokenMapsTerminalErrors() async throws {
        let transport = FakeOAuthTransport(responses: [
            FakeOAuthResponse(data: #"{"error":"expired_token"}"#),
            FakeOAuthResponse(data: #"{"error":"access_denied"}"#)
        ])
        let client = GitHubOAuthDeviceFlowClient(transport: transport)

        try expectEqual(
            try await client.pollAccessToken(clientID: "client-123", deviceCode: "device-code"),
            .expiredToken
        )
        try expectEqual(
            try await client.pollAccessToken(clientID: "client-123", deviceCode: "device-code"),
            .accessDenied
        )
    }

    private static func testPollUntilAuthorizedPersistsOAuthCredentialAndBacksOffSlowDown() async throws {
        let transport = FakeOAuthTransport(responses: [
            FakeOAuthResponse(data: #"{"error":"authorization_pending"}"#),
            FakeOAuthResponse(data: #"{"error":"slow_down"}"#),
            FakeOAuthResponse(data: #"{"access_token":"oauth-token","token_type":"bearer","scope":"repo,read:org"}"#)
        ])
        let client = GitHubOAuthDeviceFlowClient(transport: transport)
        let tokenStore = InMemoryTokenStore()
        let credentialStore = VersionedCredentialStore(tokenStore: tokenStore)
        let authorization = OAuthDeviceAuthorization(
            deviceCode: "device-code",
            userCode: "ABCD-EFGH",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 900,
            interval: 5
        )
        let sleepRecorder = SleepRecorder()

        let completion = try await client.pollUntilAuthorized(
            authorization: authorization,
            clientID: "client-123",
            credentialStore: credentialStore,
            sleep: { seconds in sleepRecorder.record(seconds) }
        )

        try expectEqual(completion, .success(OAuthAccessToken(accessToken: "oauth-token", tokenType: "bearer", scopes: ["repo", "read:org"])))
        try expectEqual(sleepRecorder.values, [5, 10])
        let stored = try unwrap(try credentialStore.loadStoredCredential())
        try expectEqual(stored.credential, .oauthUserToken("oauth-token"))
        try expectEqual(stored.scopes, ["repo", "read:org"])
        try expectEqual(stored.tokenType, "bearer")
    }

    private static func testPollUntilAuthorizedReturnsCancelledWithoutPersistingCredential() async throws {
        let transport = FakeOAuthTransport(responses: [
            FakeOAuthResponse(data: #"{"error":"authorization_pending"}"#)
        ])
        let client = GitHubOAuthDeviceFlowClient(transport: transport)
        let tokenStore = InMemoryTokenStore()
        let credentialStore = VersionedCredentialStore(tokenStore: tokenStore)
        let authorization = OAuthDeviceAuthorization(
            deviceCode: "device-code",
            userCode: "ABCD-EFGH",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 900,
            interval: 5
        )

        let completion = try await client.pollUntilAuthorized(
            authorization: authorization,
            clientID: "client-123",
            credentialStore: credentialStore,
            sleep: { _ in throw CancellationError() }
        )

        try expectEqual(completion, .cancelled)
        try expectEqual(try credentialStore.loadCredential(), nil)
    }
}

private struct FakeOAuthResponse {
    let data: Data
    let statusCode: Int

    init(data: String, statusCode: Int = 200) {
        self.data = Data(data.utf8)
        self.statusCode = statusCode
    }
}

private final class FakeOAuthTransport: GitHubTransport, @unchecked Sendable {
    private var responses: [FakeOAuthResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [FakeOAuthResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw TestFailure(message: "No fake OAuth response queued")
        }
        let nextResponse = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: nextResponse.statusCode,
            httpVersion: nil,
            headerFields: [:]
        )!
        return (nextResponse.data, response)
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [TimeInterval] = []

    var values: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }

    func record(_ value: TimeInterval) {
        lock.lock()
        recordedValues.append(value)
        lock.unlock()
    }
}
