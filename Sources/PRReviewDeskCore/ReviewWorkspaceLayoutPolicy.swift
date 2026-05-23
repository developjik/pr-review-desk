import Foundation

public enum ReviewFileNavigationStyle: Equatable, Hashable, Sendable {
    case inline
    case sidebar
}

public enum ReviewWorkspaceLayoutPolicy {
    public static let defaultInspectorVisibility = false
    public static let defaultRepositoriesExpanded = false

    public static func fileNavigationStyle(fileCount: Int) -> ReviewFileNavigationStyle {
        fileCount <= 1 ? .inline : .sidebar
    }

    public static func shouldOpenInspectorAfterDraftGeneration(previousRevision: Int, currentRevision: Int) -> Bool {
        currentRevision > previousRevision
    }
}
