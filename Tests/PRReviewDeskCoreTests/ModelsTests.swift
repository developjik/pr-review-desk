import Foundation
import PRReviewDeskCore

enum ModelsTests {
    static func run() throws {
        try testRepositoryDecodesOwnerAndName()
        try testPullRequestDecodesHeadSha()
        try testReviewDraftRoundTripsThroughJSON()
        testReviewEventUsesGitHubValues()
    }

    private static func testRepositoryDecodesOwnerAndName() throws {
        let json = """
        {
          "id": 42,
          "name": "desk",
          "full_name": "developjik/desk",
          "private": true,
          "owner": { "login": "developjik" }
        }
        """.data(using: .utf8)!

        let repository = try JSONDecoder().decode(Repository.self, from: json)

        try expectEqual(repository.id, 42)
        try expectEqual(repository.owner, "developjik")
        try expectEqual(repository.name, "desk")
        try expectEqual(repository.fullName, "developjik/desk")
        try expectTrue(repository.isPrivate)
    }

    private static func testPullRequestDecodesHeadSha() throws {
        let json = """
        {
          "id": 7,
          "number": 12,
          "title": "Add review workflow",
          "html_url": "https://github.com/developjik/desk/pull/12",
          "user": { "login": "contributor" },
          "head": { "sha": "abc123" }
        }
        """.data(using: .utf8)!

        let pullRequest = try JSONDecoder().decode(PullRequest.self, from: json)

        try expectEqual(pullRequest.id, 7)
        try expectEqual(pullRequest.number, 12)
        try expectEqual(pullRequest.title, "Add review workflow")
        try expectEqual(pullRequest.author, "contributor")
        try expectEqual(pullRequest.headSha, "abc123")
    }

    private static func testReviewDraftRoundTripsThroughJSON() throws {
        let draft = ReviewDraft(
            summary: "Looks reasonable after one small fix.",
            risks: ["Missing regression test"],
            inlineComments: [
                InlineCommentDraft(
                    path: "Sources/App.swift",
                    position: 6,
                    body: "Please cover this branch with a test.",
                    severity: .medium,
                    isSelected: true
                )
            ]
        )

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(ReviewDraft.self, from: data)

        try expectEqual(decoded, draft)
    }

    private static func testReviewEventUsesGitHubValues() {
        precondition(ReviewEvent.comment.rawValue == "COMMENT")
        precondition(ReviewEvent.approve.rawValue == "APPROVE")
        precondition(ReviewEvent.requestChanges.rawValue == "REQUEST_CHANGES")
    }
}
