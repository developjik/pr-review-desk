import Foundation

public enum ReviewInboxSelectionDecision: Equatable, Hashable, Sendable {
    case keep(rowID: String)
    case select(rowID: String)
    case moveSection(ReviewInboxSection, rowID: String)
    case clear
}

public enum ReviewInboxSelectionReason: Equatable, Hashable, Sendable {
    case contentChanged
    case userSelectedFilter
}

public enum ReviewInboxSelectionPolicy {
    public static func decision(
        selectedRow: PullRequestTriageRow?,
        visibleRows: [PullRequestTriageRow],
        selectedSection: ReviewInboxSection,
        reason: ReviewInboxSelectionReason = .contentChanged
    ) -> ReviewInboxSelectionDecision {
        if let selectedRow,
           visibleRows.contains(where: { $0.id == selectedRow.id }) {
            return .keep(rowID: selectedRow.id)
        }

        if let selectedRow,
           selectedRow.section != selectedSection,
           reason == .contentChanged {
            return .moveSection(selectedRow.section, rowID: selectedRow.id)
        }

        if let firstVisibleRow = visibleRows.first {
            return .select(rowID: firstVisibleRow.id)
        }

        return .clear
    }
}
