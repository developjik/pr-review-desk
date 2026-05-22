import Foundation
import PRReviewDeskCore

enum ModelsTests {
    static func run() throws {
        try testRepositoryDecodesOwnerAndName()
        try testPullRequestDecodesHeadSha()
        try testPullRequestFileReviewabilityClassifiesPatchCoverage()
        try testReviewCoverageSummaryCountsOmittedFiles()
        try testReviewCoverageSummaryBlocksWhenNothingIsReviewable()
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

    private static func testPullRequestFileReviewabilityClassifiesPatchCoverage() throws {
        let included = PullRequestFile(
            path: "Sources/App.swift",
            status: "modified",
            additions: 3,
            deletions: 1,
            patch: "@@ -1 +1 @@"
        )
        let unavailable = PullRequestFile(
            path: "Assets/logo.png",
            status: "modified",
            additions: 1,
            deletions: 1,
            patch: nil
        )
        let metadataOnly = PullRequestFile(
            path: "Sources/Renamed.swift",
            status: "renamed",
            additions: 0,
            deletions: 0,
            patch: nil
        )

        try expectEqual(included.reviewability, .includedPatch)
        try expectEqual(unavailable.reviewability, .omitted(reason: .patchUnavailable))
        try expectEqual(metadataOnly.reviewability, .omitted(reason: .metadataOnly))
    }

    private static func testReviewCoverageSummaryCountsOmittedFiles() throws {
        let files = [
            PullRequestFile(
                path: "Sources/App.swift",
                status: "modified",
                additions: 3,
                deletions: 1,
                patch: "@@ -1 +1 @@"
            ),
            PullRequestFile(
                path: "Assets/logo.png",
                status: "modified",
                additions: 10,
                deletions: 2,
                patch: nil
            ),
            PullRequestFile(
                path: "Sources/Renamed.swift",
                status: "renamed",
                additions: 0,
                deletions: 0,
                patch: nil
            )
        ]

        let summary = ReviewCoverageSummary(files: files)

        try expectEqual(summary.totalFileCount, 3)
        try expectEqual(summary.reviewableFileCount, 1)
        try expectEqual(summary.omittedFileCount, 2)
        try expectEqual(summary.omittedAdditions, 10)
        try expectEqual(summary.omittedDeletions, 2)
        try expectEqual(summary.warningMessage, "2 of 3 changed files do not have reviewable patches and will not be sent to Codex.")
        try expectEqual(summary.generationBlockReason, nil)
    }

    private static func testReviewCoverageSummaryBlocksWhenNothingIsReviewable() throws {
        let files = [
            PullRequestFile(
                path: "Assets/logo.png",
                status: "modified",
                additions: 10,
                deletions: 2,
                patch: nil
            )
        ]

        let summary = ReviewCoverageSummary(files: files)

        try expectEqual(summary.totalFileCount, 1)
        try expectEqual(summary.reviewableFileCount, 0)
        try expectEqual(summary.omittedFileCount, 1)
        try expectEqual(summary.generationBlockReason, "No changed files have reviewable patches for Codex.")
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
