import Foundation
import PRReviewDeskCore

enum GitHubClientTests {
    static func run() async throws {
        try await testListRepositoriesSendsBearerTokenAndDecodesResponse()
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
        try expectEqual(payload["body"] as? String, "Please address the inline notes.")
        let comments = try unwrap(payload["comments"] as? [[String: Any]])
        try expectEqual(comments.count, 1)
        try expectEqual(comments[0]["path"] as? String, "Sources/App.swift")
        try expectEqual(comments[0]["position"] as? Int, 8)
        try expectEqual(comments[0]["body"] as? String, "This branch needs coverage.")
    }
}

private final class FakeGitHubTransport: GitHubTransport, @unchecked Sendable {
    private let data: Data
    private let statusCode: Int
    private(set) var requests: [URLRequest] = []

    init(data: String, statusCode: Int = 200) {
        self.data = Data(data.utf8)
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
