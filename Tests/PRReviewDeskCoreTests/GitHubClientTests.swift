import Foundation
import PRReviewDeskCore

enum GitHubClientTests {
    static func run() async throws {
        try await testListRepositoriesSendsBearerTokenAndDecodesResponse()
        try await testListRepositoriesReadsAuthorizationFromProvider()
        try await testListRepositoriesFollowsNextLinkAndPreservesHeadersAndQuery()
        try await testListRepositoriesRetriesTransientServerFailure()
        try await testListOpenPullRequestsFollowsNextLink()
        try await testPullRequestFilesFollowsNextLink()
        try await testValidateTokenReturnsLoginAndScopes()
        try await testSubmitReviewDoesNotRetryTransientServerFailure()
        try await testSubmitReviewEncodesEventBodyAndInlineComments()
    }

    private static func testListRepositoriesSendsBearerTokenAndDecodesResponse() async throws {
        let transport = FakeGitHubTransport(data: """
        [
          {
            "id": 1,
            "name": "desk",
            "full_name": "developjik/desk",
            "private": false,
            "owner": { "login": "developjik" }
          }
        ]
        """)
        let client = GitHubClient(token: "secret", transport: transport)

        let repositories = try await client.listRepositories()

        try expectEqual(repositories.count, 1)
        try expectEqual(repositories[0].fullName, "developjik/desk")
        try expectEqual(transport.requests.count, 1)
        let request = try unwrap(transport.requests.first)
        try expectEqual(request.httpMethod, "GET")
        try expectEqual(request.url?.path, "/user/repos")
        try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        try expectEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    private static func testListRepositoriesReadsAuthorizationFromProvider() async throws {
        let transport = FakeGitHubTransport(data: "[]")
        let provider = RecordingAccessTokenProvider(authorizationHeader: "Bearer provider-token")
        let client = GitHubClient(accessTokenProvider: provider, transport: transport)

        _ = try await client.listRepositories()

        try expectEqual(provider.authorizationRequestCount, 1)
        let request = try unwrap(transport.requests.first)
        try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer provider-token")
    }

    private static func testListRepositoriesFollowsNextLinkAndPreservesHeadersAndQuery() async throws {
        let transport = FakeGitHubTransport(responses: [
            FakeGitHubResponse(
                data: """
                [
                  {
                    "id": 1,
                    "name": "desk",
                    "full_name": "developjik/desk",
                    "private": false,
                    "owner": { "login": "developjik" }
                  }
                ]
                """,
                headers: [
                    "Link": "<https://api.github.com/user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page=2>; rel=\"next\", <https://api.github.com/user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page=2>; rel=\"last\""
                ]
            ),
            FakeGitHubResponse(
                data: """
                [
                  {
                    "id": 2,
                    "name": "review-desk",
                    "full_name": "developjik/review-desk",
                    "private": true,
                    "owner": { "login": "developjik" }
                  }
                ]
                """
            )
        ])
        let client = GitHubClient(token: "secret", transport: transport)

        let repositories = try await client.listRepositories()

        try expectEqual(repositories.map(\.fullName), ["developjik/desk", "developjik/review-desk"])
        try expectEqual(transport.requests.count, 2)
        let firstRequest = try unwrap(transport.requests.first)
        let secondRequest = try unwrap(transport.requests.last)
        try expectEqual(firstRequest.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        try expectEqual(secondRequest.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        try expectEqual(secondRequest.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        try expectEqual(try queryValue("affiliation", in: secondRequest), "owner,collaborator,organization_member")
        try expectEqual(try queryValue("sort", in: secondRequest), "updated")
        try expectEqual(try queryValue("per_page", in: secondRequest), "100")
        try expectEqual(try queryValue("page", in: secondRequest), "2")
    }

    private static func testListRepositoriesRetriesTransientServerFailure() async throws {
        let transport = FakeGitHubTransport(responses: [
            FakeGitHubResponse(data: #"{"message":"try later"}"#, statusCode: 503, headers: ["Retry-After": "0"]),
            FakeGitHubResponse(data: "[]")
        ])
        let client = GitHubClient(token: "secret", transport: transport)

        let repositories = try await client.listRepositories()

        try expectEqual(repositories, [])
        try expectEqual(transport.requests.count, 2)
    }

    private static func testListOpenPullRequestsFollowsNextLink() async throws {
        let transport = FakeGitHubTransport(responses: [
            FakeGitHubResponse(
                data: """
                [
                  {
                    "id": 7,
                    "number": 12,
                    "title": "Add workflow",
                    "html_url": "https://github.com/developjik/desk/pull/12",
                    "user": { "login": "contributor" },
                    "head": { "sha": "abc123" }
                  }
                ]
                """,
                headers: [
                    "Link": "<https://api.github.com/repos/developjik/desk/pulls?state=open&per_page=100&page=2>; rel=\"next\""
                ]
            ),
            FakeGitHubResponse(
                data: """
                [
                  {
                    "id": 8,
                    "number": 13,
                    "title": "Fix pagination",
                    "html_url": "https://github.com/developjik/desk/pull/13",
                    "user": { "login": "maintainer" },
                    "head": { "sha": "def456" }
                  }
                ]
                """
            )
        ])
        let client = GitHubClient(token: "secret", transport: transport)
        let repository = Repository(
            id: 1,
            owner: "developjik",
            name: "desk",
            fullName: "developjik/desk",
            isPrivate: false
        )

        let pullRequests = try await client.listOpenPullRequests(repository: repository)

        try expectEqual(pullRequests.map(\.number), [12, 13])
        try expectEqual(transport.requests.count, 2)
        let secondRequest = try unwrap(transport.requests.last)
        try expectEqual(secondRequest.url?.path, "/repos/developjik/desk/pulls")
        try expectEqual(try queryValue("state", in: secondRequest), "open")
        try expectEqual(try queryValue("per_page", in: secondRequest), "100")
        try expectEqual(try queryValue("page", in: secondRequest), "2")
    }

    private static func testPullRequestFilesFollowsNextLink() async throws {
        let transport = FakeGitHubTransport(responses: [
            FakeGitHubResponse(
                data: """
                [
                  {
                    "filename": "Sources/App.swift",
                    "status": "modified",
                    "additions": 3,
                    "deletions": 1,
                    "patch": "@@ -1 +1 @@"
                  }
                ]
                """,
                headers: [
                    "Link": "<https://api.github.com/repos/developjik/desk/pulls/12/files?per_page=100&page=2>; rel=\"next\""
                ]
            ),
            FakeGitHubResponse(
                data: """
                [
                  {
                    "filename": "Tests/AppTests.swift",
                    "status": "added",
                    "additions": 10,
                    "deletions": 0,
                    "patch": "@@ -0,0 +1,10 @@"
                  }
                ]
                """
            )
        ])
        let client = GitHubClient(token: "secret", transport: transport)
        let repository = Repository(
            id: 1,
            owner: "developjik",
            name: "desk",
            fullName: "developjik/desk",
            isPrivate: false
        )
        let pullRequest = PullRequest(
            id: 7,
            number: 12,
            title: "Add workflow",
            htmlURL: URL(string: "https://github.com/developjik/desk/pull/12")!,
            author: "contributor",
            headSha: "abc123"
        )

        let files = try await client.pullRequestFiles(repository: repository, pullRequest: pullRequest)

        try expectEqual(files.map(\.path), ["Sources/App.swift", "Tests/AppTests.swift"])
        try expectEqual(transport.requests.count, 2)
        let secondRequest = try unwrap(transport.requests.last)
        try expectEqual(secondRequest.url?.path, "/repos/developjik/desk/pulls/12/files")
        try expectEqual(try queryValue("per_page", in: secondRequest), "100")
        try expectEqual(try queryValue("page", in: secondRequest), "2")
    }

    private static func testValidateTokenReturnsLoginAndScopes() async throws {
        let transport = FakeGitHubTransport(
            responses: [
                FakeGitHubResponse(
                    data: #"{"login":"developjik"}"#,
                    headers: ["X-OAuth-Scopes": "repo, read:org"]
                )
            ]
        )
        let client = GitHubClient(token: "secret", transport: transport)

        let validation = try await client.validateToken()

        try expectEqual(validation.login, "developjik")
        try expectEqual(validation.scopes, ["repo", "read:org"])
        let request = try unwrap(transport.requests.first)
        try expectEqual(request.url?.path, "/user")
    }

    private static func testSubmitReviewDoesNotRetryTransientServerFailure() async throws {
        let transport = FakeGitHubTransport(responses: [
            FakeGitHubResponse(data: #"{"message":"try later"}"#, statusCode: 503, headers: ["Retry-After": "0"]),
            FakeGitHubResponse(data: #"{"id":99}"#)
        ])
        let client = GitHubClient(token: "secret", transport: transport)
        let repository = Repository(
            id: 1,
            owner: "developjik",
            name: "desk",
            fullName: "developjik/desk",
            isPrivate: false
        )
        let pullRequest = PullRequest(
            id: 7,
            number: 12,
            title: "Add workflow",
            htmlURL: URL(string: "https://github.com/developjik/desk/pull/12")!,
            author: "contributor",
            headSha: "abc123"
        )
        let submission = ReviewSubmission(event: .comment, body: "Body", commitID: "abc123", comments: [])

        do {
            try await client.submitReview(repository: repository, pullRequest: pullRequest, submission: submission)
            throw TestFailure(message: "expected submit review to fail without retry")
        } catch let error as GitHubError {
            try expectEqual(error, .requestFailed(statusCode: 503, message: #"{"message":"try later"}"#))
        }

        try expectEqual(transport.requests.count, 1)
    }

    private static func testSubmitReviewEncodesEventBodyAndInlineComments() async throws {
        let transport = FakeGitHubTransport(data: #"{"id":99}"#)
        let client = GitHubClient(token: "secret", transport: transport)
        let repository = Repository(
            id: 1,
            owner: "developjik",
            name: "desk",
            fullName: "developjik/desk",
            isPrivate: false
        )
        let pullRequest = PullRequest(
            id: 7,
            number: 12,
            title: "Add workflow",
            htmlURL: URL(string: "https://github.com/developjik/desk/pull/12")!,
            author: "contributor",
            headSha: "abc123"
        )
        let submission = ReviewSubmission(
            event: .requestChanges,
            body: "Please address the inline notes.",
            commitID: "abc123",
            comments: [
                InlineCommentDraft(
                    id: "comment-1",
                    path: "Sources/App.swift",
                    position: 8,
                    body: "This branch needs coverage.",
                    severity: .high,
                    isSelected: true
                ),
                InlineCommentDraft(
                    id: "comment-2",
                    path: "Sources/Unused.swift",
                    position: 2,
                    body: "This should not be submitted.",
                    severity: .low,
                    isSelected: false
                )
            ]
        )

        try await client.submitReview(repository: repository, pullRequest: pullRequest, submission: submission)

        let request = try unwrap(transport.requests.first)
        try expectEqual(request.httpMethod, "POST")
        try expectEqual(request.url?.path, "/repos/developjik/desk/pulls/12/reviews")
        let body = try unwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let payload = try unwrap(object)
        try expectEqual(payload["event"] as? String, "REQUEST_CHANGES")
        try expectEqual(payload["commit_id"] as? String, "abc123")
        try expectEqual(payload["body"] as? String, "Please address the inline notes.")
        let comments = try unwrap(payload["comments"] as? [[String: Any]])
        try expectEqual(comments.count, 1)
        try expectEqual(comments[0]["path"] as? String, "Sources/App.swift")
        try expectEqual(comments[0]["position"] as? Int, 8)
        try expectEqual(comments[0]["body"] as? String, "This branch needs coverage.")
    }
}

private struct FakeGitHubResponse {
    let data: Data
    let statusCode: Int
    let headers: [String: String]

    init(data: String, statusCode: Int = 200, headers: [String: String] = [:]) {
        self.data = Data(data.utf8)
        self.statusCode = statusCode
        self.headers = headers
    }
}

private final class FakeGitHubTransport: GitHubTransport, @unchecked Sendable {
    private var responses: [FakeGitHubResponse]
    private(set) var requests: [URLRequest] = []

    init(data: String, statusCode: Int = 200) {
        responses = [FakeGitHubResponse(data: data, statusCode: statusCode)]
    }

    init(responses: [FakeGitHubResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw TestFailure(message: "No fake GitHub response queued")
        }
        let nextResponse = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: nextResponse.statusCode,
            httpVersion: nil,
            headerFields: nextResponse.headers
        )!
        return (nextResponse.data, response)
    }
}

private final class RecordingAccessTokenProvider: AccessTokenProvider, @unchecked Sendable {
    private let authorizationHeaderValue: String
    private(set) var authorizationRequestCount = 0

    init(authorizationHeader: String) {
        authorizationHeaderValue = authorizationHeader
    }

    func authorizationHeader() throws -> String {
        authorizationRequestCount += 1
        return authorizationHeaderValue
    }
}

private func queryValue(_ name: String, in request: URLRequest) throws -> String? {
    let url = try unwrap(request.url)
    let components = try unwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return components.queryItems?.first { $0.name == name }?.value
}
