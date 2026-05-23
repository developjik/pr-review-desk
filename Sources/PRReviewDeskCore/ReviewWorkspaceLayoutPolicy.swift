import Foundation

public enum ReviewFileNavigationStyle: Equatable, Hashable, Sendable {
    case inline
    case sidebar
}

public enum ReviewWorkspaceLayoutPolicy {
    public static let defaultInboxSection = ReviewInboxSection.needsSetup
    public static let defaultInspectorVisibility = false
    public static let defaultRepositoriesExpanded = false
    public static let inboxSidebarMinimumColumnWidth = 220.0
    public static let inboxSidebarIdealColumnWidth = 260.0
    public static let pullRequestListMinimumColumnWidth = 300.0
    public static let pullRequestListIdealColumnWidth = 360.0
    public static let pullRequestListMaximumColumnWidth = 480.0
    public static let changedFilesMinimumPaneWidth = 180.0
    public static let changedFilesIdealPaneWidth = 220.0
    public static let selectedFileMinimumPaneWidth = 420.0
    public static let selectedFileIdealPaneWidth = 680.0
    public static let inspectorMinimumColumnWidth = 320.0
    public static let inspectorIdealColumnWidth = 380.0
    public static let inspectorMaximumColumnWidth = 480.0
    public static let inspectorTopContentInset = 88.0
    public static let primaryColumnTopContentInset = 40.0
    public static let sidebarTopContentInset = 72.0
    public static let commandSubtitleLineLimit = 2
    public static let pullRequestTitleLineLimit = 2
    public static let pullRequestMetadataLineLimit = 2
    public static let repositoryOwnerLineLimit = 2
    public static let commandShortcutMinimumWidth = 44.0

    public static func fileNavigationStyle(fileCount: Int) -> ReviewFileNavigationStyle {
        fileCount <= 1 ? .inline : .sidebar
    }

    public static func shouldOpenInspectorAfterDraftGeneration(previousRevision: Int, currentRevision: Int) -> Bool {
        currentRevision > previousRevision
    }
}
