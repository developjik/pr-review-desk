import Foundation
import PRReviewDeskCore

enum ReviewSubmissionPreviewTests {
    static func run() throws {
        try testPreviewSummarizesBodyAndSelectedInlineComments()
        try testPreviewPreservesFullSubmittedBodyAndCommentText()
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
}
