import Foundation

public struct OAuthDeviceAuthorization: Codable, Equatable, Hashable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: TimeInterval
    public let interval: TimeInterval

    public init(
        deviceCode: String,
        userCode: String,
        verificationURI: URL,
        expiresIn: TimeInterval,
        interval: TimeInterval
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresIn = expiresIn
        self.interval = interval
    }

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct OAuthAccessToken: Codable, Equatable, Hashable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let scopes: [String]

    public init(accessToken: String, tokenType: String, scopes: [String]) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scopes = scopes
    }
}

public enum OAuthDeviceTokenPollResult: Equatable, Hashable, Sendable {
    case pending
    case slowDown
    case expiredToken
    case accessDenied
    case success(OAuthAccessToken)
}

public enum OAuthDeviceFlowCompletion: Equatable, Hashable, Sendable {
    case success(OAuthAccessToken)
    case expiredToken
    case accessDenied
    case cancelled
}

public enum GitHubOAuthDeviceFlowError: Error, Equatable, CustomStringConvertible, Sendable {
    case unsupportedResponse(String)

    public var description: String {
        switch self {
        case let .unsupportedResponse(value):
            return "Unsupported OAuth device flow response: \(value)"
        }
    }
}

public struct GitHubOAuthDeviceFlowClient: Sendable {
    private let transport: GitHubTransport
    private let baseURL: URL
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL = URL(string: "https://github.com")!,
        transport: GitHubTransport = URLSessionGitHubTransport()
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func startDeviceFlow(clientID: String, scopes: [String]) async throws -> OAuthDeviceAuthorization {
        let request = try makeFormRequest(
            path: "/login/device/code",
            parameters: [
                ("client_id", clientID),
                ("scope", scopes.joined(separator: " "))
            ]
        )
        return try await send(request, as: OAuthDeviceAuthorization.self)
    }

    public func pollAccessToken(clientID: String, deviceCode: String) async throws -> OAuthDeviceTokenPollResult {
        let request = try makeFormRequest(
            path: "/login/oauth/access_token",
            parameters: [
                ("client_id", clientID),
                ("device_code", deviceCode),
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
            ]
        )
        let response = try await send(request, as: OAuthAccessTokenResponse.self)

        if let accessToken = response.accessToken {
            return .success(OAuthAccessToken(
                accessToken: accessToken,
                tokenType: response.tokenType ?? "bearer",
                scopes: Self.parseScopes(response.scope)
            ))
        }

        switch response.error {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown
        case "expired_token":
            return .expiredToken
        case "access_denied":
            return .accessDenied
        default:
            throw GitHubOAuthDeviceFlowError.unsupportedResponse(response.error ?? "missing access_token")
        }
    }

    public func pollUntilAuthorized(
        authorization: OAuthDeviceAuthorization,
        clientID: String,
        credentialStore: any OAuthCredentialStoring,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) async throws -> OAuthDeviceFlowCompletion {
        var pollingInterval = authorization.interval

        do {
            while true {
                try Task.checkCancellation()
                switch try await pollAccessToken(clientID: clientID, deviceCode: authorization.deviceCode) {
                case .pending:
                    try await sleep(pollingInterval)
                case .slowDown:
                    pollingInterval += 5
                    try await sleep(pollingInterval)
                case .expiredToken:
                    return .expiredToken
                case .accessDenied:
                    return .accessDenied
                case let .success(token):
                    try credentialStore.saveCredential(
                        .oauthUserToken(token.accessToken),
                        metadata: GitHubCredentialMetadata(
                            scopes: token.scopes,
                            tokenType: token.tokenType
                        )
                    )
                    return .success(token)
                }
            }
        } catch is CancellationError {
            return .cancelled
        }
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.requestFailed(statusCode: response.statusCode, message: message)
        }
        return try decoder.decode(type, from: data)
    }

    private func makeFormRequest(path: String, parameters: [(String, String)]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.path = path

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(parameters).data(using: .utf8)
        return request
    }

    private static func formEncoded(_ parameters: [(String, String)]) -> String {
        parameters
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/? ")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func parseScopes(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct OAuthAccessTokenResponse: Decodable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
    }
}
