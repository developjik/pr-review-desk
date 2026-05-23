import Foundation
import PRReviewDeskCore

enum ReviewWorkspaceLayoutPolicyTests {
    static func run() throws {
        try testInspectorIsHiddenByDefaultToProtectDiffWidth()
        try testSingleFilePullRequestUsesInlineFileNavigation()
        try testMultipleFilePullRequestUsesFileSidebar()
        try testRepositoriesAreCollapsedByDefault()
        try testInspectorOpensOnlyAfterGeneratedDraftRevisionAdvances()
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

    private static func testInspectorOpensOnlyAfterGeneratedDraftRevisionAdvances() throws {
        try expectTrue(ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(previousRevision: 1, currentRevision: 2))
        try expectEqual(ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(previousRevision: 2, currentRevision: 2), false)
        try expectEqual(ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(previousRevision: 3, currentRevision: 2), false)
    }
}
