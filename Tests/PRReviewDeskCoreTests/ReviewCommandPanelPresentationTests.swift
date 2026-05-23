import Foundation
import PRReviewDeskCore

enum ReviewCommandPanelPresentationTests {
    static func run() throws {
        try testReturnExecutesSelectedEnabledAction()
        try testSelectionFallsBackToFirstEnabledFilteredAction()
        try testKeyboardMoveSelectsNextEnabledAction()
        try testEmptyQueryShowsDisabledActionsWithGuidance()
        try testCoreMenuActionsHaveStableCommandPanelIDs()
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

    private static func testKeyboardMoveSelectsNextEnabledAction() throws {
        let actions = sampleActions()
        let filtered = ReviewCommandPanelPresentation.filteredActions(actions, query: "filter")

        let nextID = ReviewCommandPanelPresentation.movedSelectionID(
            currentSelectionID: ReviewCommandPanelActionKind.selectSection(.draftReady).stableID,
            filteredActions: filtered,
            offset: 1
        )
        let previousID = ReviewCommandPanelPresentation.movedSelectionID(
            currentSelectionID: nextID,
            filteredActions: filtered,
            offset: -1
        )

        try expectEqual(nextID, ReviewCommandPanelActionKind.selectSection(.stale).stableID)
        try expectEqual(previousID, ReviewCommandPanelActionKind.selectSection(.draftReady).stableID)
    }

    private static func testEmptyQueryShowsDisabledActionsWithGuidance() throws {
        let actions = sampleActions()

        let defaultVisibleActions = ReviewCommandPanelPresentation.visibleActions(actions, query: "")
        let searchedActions = ReviewCommandPanelPresentation.visibleActions(actions, query: "submit")

        try expectEqual(defaultVisibleActions.map(\.kind), [
            .generateReview,
            .submitReview,
            .selectSection(.draftReady),
            .selectSection(.stale)
        ])
        try expectEqual(searchedActions.map(\.kind), [
            .submitReview
        ])
    }

    private static func testCoreMenuActionsHaveStableCommandPanelIDs() throws {
        try expectEqual(ReviewCommandPanelActionKind.cancelReviewGeneration.stableID, "cancel-review-generation")
        try expectEqual(ReviewCommandPanelActionKind.copyCodexLoginCommand.stableID, "copy-codex-login-command")
        try expectEqual(ReviewCommandPanelActionKind.startGitHubSignIn.stableID, "start-github-sign-in")
        try expectEqual(ReviewCommandPanelActionKind.validateGitHubAccess.stableID, "validate-github-access")
        try expectEqual(ReviewCommandPanelActionKind.checkCodexReadiness.stableID, "check-codex-readiness")
        try expectEqual(ReviewCommandPanelActionKind.openCodexLoginTerminal.stableID, "open-codex-login-terminal")
        try expectEqual(ReviewCommandPanelActionKind.acknowledgePrivacyDisclosure.stableID, "acknowledge-privacy-disclosure")
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
