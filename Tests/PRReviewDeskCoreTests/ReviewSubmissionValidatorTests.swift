import Foundation
import PRReviewDeskCore

enum ReviewSubmissionValidatorTests {
    static func run() throws {
        try testRejectsStalePullRequestHead()
        try testRejectsSelectedInlineCommentOutsideFetchedDiff()
        try testAllowsSelectedInlineCommentInsideFetchedDiff()
        try testIgnoresUnselectedInlineCommentOutsideFetchedDiff()
        try testSafetyStateReportsStaleAndInvalidSelectedComments()
    }

    private static func testRejectsStalePullRequestHead() throws {
        let draft = ReviewDraft(summary: "Summary", risks: [], inlineComments: [])

        do {
            try ReviewSubmissionValidator.validate(
                reviewedHeadSha: "old-sha",
                currentHeadSha: "new-sha",
                draft: draft,
                files: []
            )
            throw TestFailure(message: "expected stale head validation to fail")
        } catch let error as ReviewSubmissionValidationError {
            try expectEqual(error, .staleHead(reviewed: "old-sha", current: "new-sha"))
        }
    }

    private static func testRejectsSelectedInlineCommentOutsideFetchedDiff() throws {
        let draft = ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "bad-comment",
                    path: "Sources/App.swift",
                    position: 99,
                    body: "Invalid position",
                    severity: .high,
                    isSelected: true
                )
            ]
        )
        let files = [
            PullRequestFile(
                path: "Sources/App.swift",
                status: "modified",
                additions: 1,
                deletions: 0,
                patch: """
                @@ -1,1 +1,2 @@
                 let old = true
                +let new = true
                """
            )
        ]

        do {
            try ReviewSubmissionValidator.validate(
                reviewedHeadSha: "same-sha",
                currentHeadSha: "same-sha",
                draft: draft,
                files: files
            )
            throw TestFailure(message: "expected invalid inline comment validation to fail")
        } catch let error as ReviewSubmissionValidationError {
            try expectEqual(
                error,
                .invalidInlineComments([
                    InvalidInlineComment(path: "Sources/App.swift", position: 99)
                ])
            )
        }
    }

    private static func testAllowsSelectedInlineCommentInsideFetchedDiff() throws {
        let draft = ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "good-comment",
                    path: "Sources/App.swift",
                    position: 2,
                    body: "Valid position",
                    severity: .medium,
                    isSelected: true
                )
            ]
        )
        let files = [
            PullRequestFile(
                path: "Sources/App.swift",
                status: "modified",
                additions: 1,
                deletions: 0,
                patch: """
                @@ -1,1 +1,2 @@
                 let old = true
                +let new = true
                """
            )
        ]

        try ReviewSubmissionValidator.validate(
            reviewedHeadSha: "same-sha",
            currentHeadSha: "same-sha",
            draft: draft,
            files: files
        )
    }

    private static func testIgnoresUnselectedInlineCommentOutsideFetchedDiff() throws {
        let draft = ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "unselected-comment",
                    path: "Sources/App.swift",
                    position: 99,
                    body: "Invalid but not selected",
                    severity: .low,
                    isSelected: false
                )
            ]
        )
        let files = [
            PullRequestFile(
                path: "Sources/App.swift",
                status: "modified",
                additions: 1,
                deletions: 0,
                patch: """
                @@ -1,1 +1,2 @@
                 let old = true
                +let new = true
                """
            )
        ]

        try ReviewSubmissionValidator.validate(
            reviewedHeadSha: "same-sha",
            currentHeadSha: "same-sha",
            draft: draft,
            files: files
        )
    }

    private static func testSafetyStateReportsStaleAndInvalidSelectedComments() throws {
        let draft = ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "bad-comment",
                    path: "Sources/App.swift",
                    position: 99,
                    body: "Invalid position",
                    severity: .high,
                    isSelected: true
                )
            ]
        )
        let files = [
            PullRequestFile(
                path: "Sources/App.swift",
                status: "modified",
                additions: 1,
                deletions: 0,
                patch: """
                @@ -1,1 +1,2 @@
                 let old = true
                +let new = true
                """
            )
        ]

        let state = try ReviewSubmissionValidator.safetyState(
            reviewedHeadSha: "old-sha",
            currentHeadSha: "new-sha",
            draft: draft,
            files: files
        )

        try expectTrue(state.isStale)
        try expectTrue(!state.canSubmit)
        try expectEqual(state.invalidSelectedInlineComments, [
            InvalidInlineComment(path: "Sources/App.swift", position: 99)
        ])
    }
}
