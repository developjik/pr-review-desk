import Foundation
import PRReviewDeskCore

enum ReviewSubmissionPreviewTests {
    static func run() throws {
        try testPreviewSummarizesBodyAndSelectedInlineComments()
        try testPreviewPreservesFullSubmittedBodyAndCommentText()
        try testPreviewIncludesSafetyStateAndBlocksUnsafeSubmission()
        try testPreviewBlocksWhenDiffPositionsCouldNotBeValidated()
        try testPreviewReportsWhenSafetyWasLastChecked()
    }

    private static func testPreviewSummarizesBodyAndSelectedInlineComments() throws {
        let draft = ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "first",
                    path: "Sources/App.swift",
                    position: 42,
                    body: "Tighten this branch before submitting.",
                    severity: .high,
                    isSelected: true
                ),
                InlineCommentDraft(
                    id: "second",
                    path: "Tests/AppTests.swift",
                    position: 9,
                    body: "Not selected.",
                    severity: .low,
                    isSelected: false
                ),
                InlineCommentDraft(
                    id: "third",
                    path: "Sources/Model.swift",
                    position: 7,
                    body: "Add a fallback for empty state recovery.",
                    severity: .medium,
                    isSelected: true
                )
            ]
        )

        let preview = ReviewSubmissionPreview.make(
            event: .requestChanges,
            body: "Line 1\nLine 2\nLine 3",
            draft: draft
        )

        try expectEqual(preview.summaryLine, "Request changes review - 2 selected inline comments")
        try expectEqual(preview.bodyPreview, "Line 1\nLine 2\nLine 3")
        try expectEqual(preview.selectedInlineCommentCount, 2)
        try expectEqual(preview.selectedInlineComments.map(\.location), [
            "Sources/App.swift:42",
            "Sources/Model.swift:7"
        ])
        try expectEqual(preview.selectedInlineComments.map(\.bodyPreview), [
            "Tighten this branch before submitting.",
            "Add a fallback for empty state recovery."
        ])
    }

    private static func testPreviewPreservesFullSubmittedBodyAndCommentText() throws {
        let longComment = String(repeating: "a", count: 160)
        let fullBody = "one\ntwo\nthree\nfour"
        let draft = ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "comment",
                    path: "Sources/App.swift",
                    position: 1,
                    body: longComment,
                    severity: .medium,
                    isSelected: true
                )
            ]
        )

        let preview = ReviewSubmissionPreview.make(
            event: .comment,
            body: fullBody,
            draft: draft
        )

        try expectEqual(preview.bodyPreview, fullBody)
        try expectEqual(preview.selectedInlineComments[0].bodyPreview, longComment)
    }

    private static func testPreviewIncludesSafetyStateAndBlocksUnsafeSubmission() throws {
        let draft = ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "bad-comment",
                    path: "Sources/App.swift",
                    position: 99,
                    body: "Invalid target",
                    severity: .high,
                    isSelected: true
                )
            ]
        )
        let safetyState = ReviewSubmissionSafetyState(
            reviewedHeadSha: "reviewed-sha",
            currentHeadSha: "current-sha",
            selectedInlineCommentCount: 1,
            invalidSelectedInlineComments: [
                InvalidInlineComment(path: "Sources/App.swift", position: 99)
            ]
        )

        let preview = ReviewSubmissionPreview.make(
            event: .requestChanges,
            body: "Please fix this before merging.",
            draft: draft,
            safetyState: safetyState
        )

        try expectEqual(preview.canSubmit, false)
        try expectEqual(preview.safetyMessage, "Draft is stale. Regenerate before submitting.")
        try expectEqual(preview.safetyState.invalidSelectedInlineComments, [
            InvalidInlineComment(path: "Sources/App.swift", position: 99)
        ])
    }

    private static func testPreviewBlocksWhenDiffPositionsCouldNotBeValidated() throws {
        let draft = ReviewDraft(summary: "Summary", risks: [], inlineComments: [])
        let safetyState = ReviewSubmissionSafetyState(
            reviewedHeadSha: "same-sha",
            currentHeadSha: "same-sha",
            selectedInlineCommentCount: 0,
            invalidSelectedInlineComments: [],
            couldValidateDiffPositions: false
        )

        let preview = ReviewSubmissionPreview.make(
            event: .comment,
            body: "Review body",
            draft: draft,
            safetyState: safetyState
        )

        try expectEqual(preview.canSubmit, false)
        try expectEqual(preview.safetyMessage, "Refresh safety before submitting.")
    }

    private static func testPreviewReportsWhenSafetyWasLastChecked() throws {
        let checkedAt = Date(timeIntervalSince1970: 1_777_777_777)
        let preview = ReviewSubmissionPreview.make(
            event: .approve,
            body: "Ready.",
            draft: ReviewDraft(summary: "Summary", risks: [], inlineComments: []),
            safetyState: ReviewSubmissionSafetyState(
                reviewedHeadSha: "same-sha",
                currentHeadSha: "same-sha",
                selectedInlineCommentCount: 0,
                invalidSelectedInlineComments: []
            ),
            safetyCheckedAt: checkedAt
        )

        try expectEqual(preview.safetyCheckedAt, checkedAt)
        try expectEqual(preview.safetyCheckedAtDisplay, "2026-05-03 03:09")
        try expectEqual(preview.safetyCheckedMessage, "Last checked at 2026-05-03 03:09 UTC.")
    }
}
