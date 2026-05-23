import Foundation

public enum ReviewInboxFilterPresentation {
    public static func activeSearchSummary(query: String, visibleCount: Int) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return "Search \"\(trimmed)\" - \(visibleCount) visible"
    }

    public static func pullRequestCountTitle(_ count: Int) -> String {
        "\(count) \(count == 1 ? "pull request" : "pull requests")"
    }

    public static func pullRequestCountLocalizationKey(for count: Int) -> String {
        count == 1 ? "%d pull request" : "%d pull requests"
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
            return "No generated drafts are waiting for review. Add drafts for this repository or generate a draft from an open PR."
        case .stale:
            return "No drafts need attention. Refresh GitHub to check for updated PRs."
        case .running:
            return "No drafts are being created. Add drafts for a repository to fill this list."
        case .needsSetup:
            return "Setup is complete. Load repositories to start a review."
        case .submitted:
            return "No reviews have been submitted from saved drafts. Load repositories to continue reviewing."
        case .recents:
            return hasSelectedRepository
                ? "No open pull requests in this repository. Refresh or choose another repository."
                : "Select a repository to load open pull requests."
        }
    }

    public static func shouldClearHiddenSelection(query: String, hasLocalSelection: Bool) -> Bool {
        !hasLocalSelection && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func selectionClearedStatus(hasVisibleRows: Bool) -> String {
        hasVisibleRows
            ? "Selected pull request is hidden by the current filter. Saved drafts remain available when the filter is cleared."
            : "No pull requests match the current filter. Clear search to return to saved drafts and recents."
    }
}
