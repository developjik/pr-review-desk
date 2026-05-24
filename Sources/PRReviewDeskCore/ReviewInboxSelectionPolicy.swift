import Foundation

public enum ReviewInboxSelectionDecision: Equatable, Hashable, Sendable {
    case keep(rowID: String)
    case select(rowID: String)
    case moveSection(ReviewInboxSection, rowID: String)
    case clear
}

public enum ReviewInboxSelectionPolicy {
    public static func decision(
        selectedRow: PullRequestTriageRow?,
        visibleRows: [PullRequestTriageRow],
        selectedSection: ReviewInboxSection
    ) -> ReviewInboxSelectionDecision {
        if let selectedRow,
           visibleRows.contains(where: { $0.id == selectedRow.id }) {
            return .keep(rowID: selectedRow.id)
        }

        if let selectedRow,
           selectedRow.section != selectedSection {
            return .moveSection(selectedRow.section, rowID: selectedRow.id)
        }

        if let firstVisibleRow = visibleRows.first {
            return .select(rowID: firstVisibleRow.id)
        }

        return .clear
    }
}
