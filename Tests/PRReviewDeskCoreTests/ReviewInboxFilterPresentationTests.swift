import Foundation
import PRReviewDeskCore

enum ReviewInboxFilterPresentationTests {
    static func run() throws {
        try testActiveSearchSummaryUsesTrimmedQuery()
        try testPullRequestCountUsesSingularAndPluralCopy()
        try testFilteredEmptyDescriptionExplainsHiddenRows()
        try testSelectedRepositoryEmptyDescriptionExplainsNoOpenPullRequests()
        try testHiddenSelectionClearsOnlyForActiveSearch()
        try testSelectionClearedMessageMentionsSavedDraftRecovery()
    }

    private static func testActiveSearchSummaryUsesTrimmedQuery() throws {
        try expectEqual(
            ReviewInboxFilterPresentation.activeSearchSummary(query: "  cache  ", visibleCount: 2),
            "Search \"cache\" - 2 visible"
        )
        try expectEqual(
            ReviewInboxFilterPresentation.activeSearchSummary(query: "   ", visibleCount: 0),
            nil
        )
    }

    private static func testPullRequestCountUsesSingularAndPluralCopy() throws {
        try expectEqual(
            ReviewInboxFilterPresentation.pullRequestCountTitle(1),
            "1 pull request"
        )
        try expectEqual(
            ReviewInboxFilterPresentation.pullRequestCountTitle(2),
            "2 pull requests"
        )
    }

    private static func testFilteredEmptyDescriptionExplainsHiddenRows() throws {
        try expectEqual(
            ReviewInboxFilterPresentation.emptyDescription(
                section: .recents,
                query: "cache",
                hasSelectedRepository: true
            ),
            "Search \"cache\" is hiding pull requests in this repository. Clear search to show saved drafts and open PRs again."
        )
    }

    private static func testSelectedRepositoryEmptyDescriptionExplainsNoOpenPullRequests() throws {
        try expectEqual(
            ReviewInboxFilterPresentation.emptyDescription(
                section: .recents,
                query: "",
                hasSelectedRepository: true
            ),
            "No open pull requests in this repository."
        )
        try expectEqual(
            ReviewInboxFilterPresentation.emptyDescription(
                section: .recents,
                query: "",
                hasSelectedRepository: false
            ),
            "Select a repository to load open pull requests."
        )
    }

    private static func testHiddenSelectionClearsOnlyForActiveSearch() throws {
        try expectEqual(
            ReviewInboxFilterPresentation.shouldClearHiddenSelection(query: "", hasLocalSelection: false),
            false
        )
        try expectEqual(
            ReviewInboxFilterPresentation.shouldClearHiddenSelection(query: "   ", hasLocalSelection: false),
            false
        )
        try expectTrue(
            ReviewInboxFilterPresentation.shouldClearHiddenSelection(query: "stale", hasLocalSelection: false)
        )
        try expectEqual(
            ReviewInboxFilterPresentation.shouldClearHiddenSelection(query: "stale", hasLocalSelection: true),
            false
        )
    }

    private static func testSelectionClearedMessageMentionsSavedDraftRecovery() throws {
        try expectEqual(
            ReviewInboxFilterPresentation.selectionClearedStatus(hasVisibleRows: true),
            "Selected pull request is hidden by the current filter. Saved drafts remain available when the filter is cleared."
        )
        try expectEqual(
            ReviewInboxFilterPresentation.selectionClearedStatus(hasVisibleRows: false),
            "No pull requests match the current filter. Clear search to return to saved drafts and recents."
        )
    }
}
