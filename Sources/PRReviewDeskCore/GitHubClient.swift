import Foundation

public enum GitHubError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidRepositoryFullName(String)
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    public var description: String {
        switch self {
        case let .invalidRepositoryFullName(value):
            return "Invalid repository full name: \(value)"
        case .invalidResponse:
            return "GitHub returned a non-HTTP response"
        case let .requestFailed(statusCode, message):
            return "GitHub request failed with status \(statusCode): \(message)"
        }
    }
}

public protocol GitHubTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionGitHubTransport: GitHubTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public struct GitHubTokenValidation: Equatable, Hashable, Sendable {
    public let login: String
    public let scopes: [String]

    public init(login: String, scopes: [String]) {
        self.login = login
        self.scopes = scopes
    }
}

public final class GitHubClient: Sendable {
    private let accessTokenProvider: any AccessTokenProvider
    private let transport: GitHubTransport
    private let baseURL: URL

    public convenience init(
        token: String,
        baseURL: URL = URL(string: "https://api.github.com")!,
        transport: GitHubTransport = URLSessionGitHubTransport()
    ) {
        self.init(
            accessTokenProvider: StaticAccessTokenProvider(credential: .personalAccessToken(token)),
            baseURL: baseURL,
            transport: transport
        )
    }

    public init(
        accessTokenProvider: any AccessTokenProvider,
        baseURL: URL = URL(string: "https://api.github.com")!,
        transport: GitHubTransport = URLSessionGitHubTransport()
    ) {
        self.accessTokenProvider = accessTokenProvider
        self.baseURL = baseURL
        self.transport = transport
    }

    public func listRepositories() async throws -> [Repository] {
        let request = try makeRequest(
            method: "GET",
            path: "/user/repos",
            queryItems: [
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        return try await sendPaginated(request, as: [Repository].self)
    }

    public func listOpenPullRequests(repository: Repository) async throws -> [PullRequest] {
        let (owner, name) = try repositoryParts(repository)
        let request = try makeRequest(
            method: "GET",
            path: "/repos/\(owner)/\(name)/pulls",
            queryItems: [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        return try await sendPaginated(request, as: [PullRequest].self)
    }

    public func pullRequestDetails(repository: Repository, number: Int) async throws -> PullRequest {
        let (owner, name) = try repositoryParts(repository)
        let request = try makeRequest(method: "GET", path: "/repos/\(owner)/\(name)/pulls/\(number)")
        return try await send(request, as: PullRequest.self)
    }

    public func pullRequestFiles(repository: Repository, pullRequest: PullRequest) async throws -> [PullRequestFile] {
        let (owner, name) = try repositoryParts(repository)
        let request = try makeRequest(
            method: "GET",
            path: "/repos/\(owner)/\(name)/pulls/\(pullRequest.number)/files",
            queryItems: [URLQueryItem(name: "per_page", value: "100")]
        )
        return try await sendPaginated(request, as: [PullRequestFile].self)
    }

    public func validateToken() async throws -> GitHubTokenValidation {
        let request = try makeRequest(method: "GET", path: "/user")
        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data)
        let user = try JSONDecoder().decode(GitHubAuthenticatedUser.self, from: data)
        let scopes = (response.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return GitHubTokenValidation(login: user.login, scopes: scopes)
    }

    public func submitReview(
        repository: Repository,
        pullRequest: PullRequest,
        submission: ReviewSubmission
    ) async throws {
        let (owner, name) = try repositoryParts(repository)
        let selectedComments = submission.comments
            .filter(\.isSelected)
            .map { comment in
                ReviewCommentPayload(path: comment.path, position: comment.position, body: comment.body)
            }
        let payload = ReviewPayload(
            event: submission.event.rawValue,
            commitID: submission.commitID,
            body: submission.body,
            comments: selectedComments
        )
        var request = try makeRequest(
            method: "POST",
            path: "/repos/\(owner)/\(name)/pulls/\(pullRequest.number)/reviews"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        try await sendWithoutDecoding(request)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(type, from: data)
    }

    private func sendPaginated<T: Decodable>(_ request: URLRequest, as type: [T].Type) async throws -> [T] {
        var nextRequest: URLRequest? = request
        var items: [T] = []

        while let currentRequest = nextRequest {
            let (data, response) = try await transport.data(for: currentRequest)
            try validate(response: response, data: data)
            let pageItems = try JSONDecoder().decode(type, from: data)
            items.append(contentsOf: pageItems)
            if let nextPageURL = nextPageURL(from: response) {
                nextRequest = try makeRequest(method: "GET", url: nextPageURL)
            } else {
                nextRequest = nil
            }
        }

        return items
    }

    private func sendWithoutDecoding(_ request: URLRequest) async throws {
        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data)
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.requestFailed(statusCode: response.statusCode, message: message)
        }
    }

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        try applyDefaultHeaders(to: &request)
        return request
    }

    private func makeRequest(method: String, url: URL) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        try applyDefaultHeaders(to: &request)
        return request
    }

    private func applyDefaultHeaders(to request: inout URLRequest) throws {
        request.setValue(try accessTokenProvider.authorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PRReviewDesk", forHTTPHeaderField: "User-Agent")
    }

    private func nextPageURL(from response: HTTPURLResponse) -> URL? {
        guard let linkHeader = response.value(forHTTPHeaderField: "Link") else {
            return nil
        }

        for part in linkHeaderParts(linkHeader) {
            let link = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard link.contains("rel=\"next\"") else {
                continue
            }
            guard let openIndex = link.firstIndex(of: "<"),
                  let closeIndex = link[openIndex...].firstIndex(of: ">")
            else {
                return nil
            }
            let urlString = String(link[link.index(after: openIndex)..<closeIndex])
            guard let url = URL(string: urlString, relativeTo: baseURL),
                  url.scheme == baseURL.scheme,
                  url.host == baseURL.host
            else {
                return nil
            }
            return url.absoluteURL
        }

        return nil
    }

    private func linkHeaderParts(_ header: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isInsideURL = false

        for character in header {
            switch character {
            case "<":
                isInsideURL = true
                current.append(character)
            case ">":
                isInsideURL = false
                current.append(character)
            case "," where !isInsideURL:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }

    private func repositoryParts(_ repository: Repository) throws -> (String, String) {
        let pieces = repository.fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else {
            throw GitHubError.invalidRepositoryFullName(repository.fullName)
        }
        return (pieces[0], pieces[1])
    }
}

private struct ReviewPayload: Encodable {
    let event: String
    let commitID: String
    let body: String
    let comments: [ReviewCommentPayload]

    private enum CodingKeys: String, CodingKey {
        case event
        case commitID = "commit_id"
        case body
        case comments
    }
}

private struct GitHubAuthenticatedUser: Decodable {
    let login: String
}

private struct ReviewCommentPayload: Encodable {
    let path: String
    let position: Int
    let body: String
}
