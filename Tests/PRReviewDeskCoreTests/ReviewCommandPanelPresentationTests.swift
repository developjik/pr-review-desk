import Foundation
import PRReviewDeskCore

enum ReviewCommandPanelPresentationTests {
    static func run() throws {
        try testReturnExecutesSelectedEnabledAction()
        try testSelectionFallsBackToFirstEnabledFilteredAction()
    }

    private static func testReturnExecutesSelectedEnabledAction() throws {
        let actions = sampleActions()
        let filtered = ReviewCommandPanelPresentation.filteredActions(actions, query: "filter")

        let action = try unwrap(ReviewCommandPanelPresentation.actionToPerform(
            selectedActionID: ReviewCommandPanelActionKind.selectSection(.stale).stableID,
            filteredActions: filtered
        ))

        try expectEqual(action.kind, .selectSection(.stale))
    }

    private static func testSelectionFallsBackToFirstEnabledFilteredAction() throws {
        let actions = sampleActions()
        let filtered = ReviewCommandPanelPresentation.filteredActions(actions, query: "review")

        let selectedID = ReviewCommandPanelPresentation.selectedActionID(
            currentSelectionID: ReviewCommandPanelActionKind.submitReview.stableID,
            filteredActions: filtered
        )
        let action = try unwrap(ReviewCommandPanelPresentation.actionToPerform(
            selectedActionID: selectedID,
            filteredActions: filtered
        ))

        try expectEqual(selectedID, ReviewCommandPanelActionKind.generateReview.stableID)
        try expectEqual(action.kind, .generateReview)
    }

    private static func sampleActions() -> [ReviewCommandPanelAction] {
        [
            ReviewCommandPanelAction(
                title: "Generate AI Review Draft",
                subtitle: "Create a draft.",
                systemImage: "sparkles",
                shortcut: "⇧⌘R",
                isEnabled: true,
                kind: .generateReview
            ),
            ReviewCommandPanelAction(
                title: "Submit Review",
                subtitle: "Generate a valid draft before submitting.",
                systemImage: "paperplane",
                shortcut: "⌘↩",
                isEnabled: false,
                kind: .submitReview
            ),
            ReviewCommandPanelAction(
                title: "Filter Draft Ready",
                subtitle: "Show Draft Ready inbox items.",
                systemImage: "doc.text",
                shortcut: nil,
                isEnabled: true,
                kind: .selectSection(.draftReady)
            ),
            ReviewCommandPanelAction(
                title: "Filter Stale",
                subtitle: "Show Stale inbox items.",
                systemImage: "exclamationmark.triangle",
                shortcut: nil,
                isEnabled: true,
                kind: .selectSection(.stale)
            )
        ]
    }
}
