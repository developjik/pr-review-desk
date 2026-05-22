import Foundation
import PRReviewDeskCore

enum InlineCommentNavigationTests {
    static func run() throws {
        try testFileCountsSelectedAndTotalInlineComments()
    }

    private static func testFileCountsSelectedAndTotalInlineComments() throws {
        let comments = [
            InlineCommentDraft(id: "a", path: "Sources/App.swift", position: 2, body: "A", severity: .high, isSelected: true),
            InlineCommentDraft(id: "b", path: "Sources/App.swift", position: 4, body: "B", severity: .medium, isSelected: false),
            InlineCommentDraft(id: "c", path: "Tests/AppTests.swift", position: 1, body: "C", severity: .low, isSelected: true)
        ]

        let count = InlineCommentFileCount.count(for: "Sources/App.swift", comments: comments)

        try expectEqual(count.total, 2)
        try expectEqual(count.selected, 1)
        try expectEqual(count.displayText, "1/2")
    }
}
