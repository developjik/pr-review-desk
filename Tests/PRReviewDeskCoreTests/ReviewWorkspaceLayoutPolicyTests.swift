import Foundation
import PRReviewDeskCore

enum ReviewWorkspaceLayoutPolicyTests {
    static func run() throws {
        try testInspectorIsHiddenByDefaultToProtectDiffWidth()
        try testSingleFilePullRequestUsesInlineFileNavigation()
        try testMultipleFilePullRequestUsesFileSidebar()
        try testRepositoriesAreCollapsedByDefault()
        try testNeedsSetupIsDefaultInboxSection()
        try testInspectorOpensOnlyAfterGeneratedDraftRevisionAdvances()
        try testReviewWorkspaceUsesCompactReadableColumnWidths()
        try testInspectorHasReadablePreferredColumnWidths()
        try testInspectorContentClearsWindowToolbar()
        try testDenseWorkflowTextUsesMultiLineFallbacks()
    }

    private static func testInspectorIsHiddenByDefaultToProtectDiffWidth() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.defaultInspectorVisibility, false)
    }

    private static func testSingleFilePullRequestUsesInlineFileNavigation() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.fileNavigationStyle(fileCount: 1), .inline)
    }

    private static func testMultipleFilePullRequestUsesFileSidebar() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.fileNavigationStyle(fileCount: 2), .sidebar)
    }

    private static func testRepositoriesAreCollapsedByDefault() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.defaultRepositoriesExpanded, false)
    }

    private static func testNeedsSetupIsDefaultInboxSection() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.defaultInboxSection, .needsSetup)
    }

    private static func testInspectorOpensOnlyAfterGeneratedDraftRevisionAdvances() throws {
        try expectTrue(ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(previousRevision: 1, currentRevision: 2))
        try expectEqual(ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(previousRevision: 2, currentRevision: 2), false)
        try expectEqual(ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(previousRevision: 3, currentRevision: 2), false)
    }

    private static func testReviewWorkspaceUsesCompactReadableColumnWidths() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.inboxSidebarMinimumColumnWidth, 220)
        try expectEqual(ReviewWorkspaceLayoutPolicy.inboxSidebarIdealColumnWidth, 260)
        try expectEqual(ReviewWorkspaceLayoutPolicy.pullRequestListMinimumColumnWidth, 300)
        try expectEqual(ReviewWorkspaceLayoutPolicy.pullRequestListIdealColumnWidth, 360)
        try expectEqual(ReviewWorkspaceLayoutPolicy.pullRequestListMaximumColumnWidth, 480)
        try expectEqual(ReviewWorkspaceLayoutPolicy.changedFilesMinimumPaneWidth, 180)
        try expectEqual(ReviewWorkspaceLayoutPolicy.changedFilesIdealPaneWidth, 220)
        try expectEqual(ReviewWorkspaceLayoutPolicy.selectedFileMinimumPaneWidth, 420)
        try expectEqual(ReviewWorkspaceLayoutPolicy.selectedFileIdealPaneWidth, 680)
    }

    private static func testInspectorHasReadablePreferredColumnWidths() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.inspectorMinimumColumnWidth, 320)
        try expectEqual(ReviewWorkspaceLayoutPolicy.inspectorIdealColumnWidth, 380)
        try expectEqual(ReviewWorkspaceLayoutPolicy.inspectorMaximumColumnWidth, 480)
    }

    private static func testInspectorContentClearsWindowToolbar() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.inspectorTopContentInset, 88)
    }

    private static func testDenseWorkflowTextUsesMultiLineFallbacks() throws {
        try expectEqual(ReviewWorkspaceLayoutPolicy.commandSubtitleLineLimit, 2)
        try expectEqual(ReviewWorkspaceLayoutPolicy.pullRequestTitleLineLimit, 2)
        try expectEqual(ReviewWorkspaceLayoutPolicy.pullRequestMetadataLineLimit, 2)
        try expectEqual(ReviewWorkspaceLayoutPolicy.repositoryOwnerLineLimit, 2)
        try expectEqual(ReviewWorkspaceLayoutPolicy.commandShortcutMinimumWidth, 44)
    }
}
