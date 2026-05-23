import Foundation

public enum ReviewInboxFilterPresentation {
    public static func activeSearchSummary(query: String, visibleCount: Int) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return "Search \"\(trimmed)\" - \(visibleCount) visible"
    }

    public static func emptyDescription(
        section: ReviewInboxSection,
        query: String,
        hasSelectedRepository: Bool
    ) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let scope = hasSelectedRepository ? "in this repository" : "in the current scope"
            return "Search \"\(trimmed)\" is hiding pull requests \(scope). Clear search to show saved drafts and open PRs again."
        }

        switch section {
        case .draftReady:
            return "No generated drafts are waiting for review."
        case .stale:
            return "No stale or failed drafts need attention."
        case .running:
            return "No queued reviews are running."
        case .needsSetup:
            return "The app is ready."
        case .submitted:
            return "No reviews have been submitted from this queue."
        case .recents:
            return "Select a repository to load open pull requests."
        }
    }

    public static func selectionClearedStatus(hasVisibleRows: Bool) -> String {
        hasVisibleRows
            ? "Selected pull request is hidden by the current filter. Saved drafts remain available when the filter is cleared."
            : "No pull requests match the current filter. Clear search to return to saved drafts and recents."
    }
}
