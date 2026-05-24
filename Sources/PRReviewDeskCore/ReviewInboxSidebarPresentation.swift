import Foundation

public enum ReviewInboxSidebarPresentation {
    public static let reviewSectionTitle = "Inbox Filters"

    public static let sections: [ReviewInboxSection] = [
        .recents,
        .draftReady,
        .stale,
        .running,
        .needsSetup,
        .submitted
    ]

    public static func sections(isReady: Bool) -> [ReviewInboxSection] {
        if isReady {
            return sections.filter { $0 != .needsSetup }
        }

        return [.needsSetup]
    }
}
