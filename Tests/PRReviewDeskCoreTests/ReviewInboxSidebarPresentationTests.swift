import Foundation
import PRReviewDeskCore

enum ReviewInboxSidebarPresentationTests {
    static func run() throws {
        try testReviewInboxIsFirstSelectableSidebarDestination()
        try testReadyWorkspaceHidesSetupOnlyFilter()
        try testBlockedWorkspaceOnlyShowsSetupFilter()
    }

    private static func testReviewInboxIsFirstSelectableSidebarDestination() throws {
        try expectEqual(ReviewInboxSidebarPresentation.reviewSectionTitle, "Inbox Filters")
        try expectEqual(ReviewInboxSidebarPresentation.sections.first, .recents)
        try expectEqual(ReviewInboxSidebarPresentation.sections, [
            .recents,
            .draftReady,
            .stale,
            .running,
            .needsSetup,
            .submitted
        ])
        try expectEqual(ReviewInboxSection.recents.displayName, "Review Inbox")
    }

    private static func testReadyWorkspaceHidesSetupOnlyFilter() throws {
        try expectEqual(ReviewInboxSidebarPresentation.sections(isReady: true), [
            .recents,
            .draftReady,
            .stale,
            .running,
            .submitted
        ])
    }

    private static func testBlockedWorkspaceOnlyShowsSetupFilter() throws {
        try expectEqual(ReviewInboxSidebarPresentation.sections(isReady: false), [
            .needsSetup
        ])
    }
}
