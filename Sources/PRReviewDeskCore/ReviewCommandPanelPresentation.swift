import Foundation

public enum ReviewCommandPanelActionKind: Equatable, Hashable, Sendable {
    case refreshActiveScope
    case openPullRequest
    case generateReview
    case cancelReviewGeneration
    case queueSelectedPullRequest
    case queueSelectedRepository
    case regenerateSelectedFile
    case submitReview
    case nextInlineComment
    case previousInlineComment
    case nextFile
    case previousFile
    case nextHunk
    case previousHunk
    case revealInlineComment
    case startGitHubSignIn
    case validateGitHubAccess
    case checkCodexReadiness
    case copyCodexLoginCommand
    case openCodexLoginTerminal
    case acknowledgePrivacyDisclosure
    case toggleInspector
    case selectSection(ReviewInboxSection)

    public var stableID: String {
        switch self {
        case .refreshActiveScope:
            return "refresh-active-scope"
        case .openPullRequest:
            return "open-pull-request"
        case .generateReview:
            return "generate-review"
        case .cancelReviewGeneration:
            return "cancel-review-generation"
        case .queueSelectedPullRequest:
            return "queue-selected-pull-request"
        case .queueSelectedRepository:
            return "queue-selected-repository"
        case .regenerateSelectedFile:
            return "regenerate-selected-file"
        case .submitReview:
            return "submit-review"
        case .nextInlineComment:
            return "next-inline-comment"
        case .previousInlineComment:
            return "previous-inline-comment"
        case .nextFile:
            return "next-file"
        case .previousFile:
            return "previous-file"
        case .nextHunk:
            return "next-hunk"
        case .previousHunk:
            return "previous-hunk"
        case .revealInlineComment:
            return "reveal-inline-comment"
        case .startGitHubSignIn:
            return "start-github-sign-in"
        case .validateGitHubAccess:
            return "validate-github-access"
        case .checkCodexReadiness:
            return "check-codex-readiness"
        case .copyCodexLoginCommand:
            return "copy-codex-login-command"
        case .openCodexLoginTerminal:
            return "open-codex-login-terminal"
        case .acknowledgePrivacyDisclosure:
            return "acknowledge-privacy-disclosure"
        case .toggleInspector:
            return "toggle-inspector"
        case let .selectSection(section):
            return "select-section-\(section.rawValue)"
        }
    }
}

public struct ReviewCommandPanelAction: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let shortcut: String?
    public let isEnabled: Bool
    public let kind: ReviewCommandPanelActionKind

    public init(
        title: String,
        subtitle: String,
        systemImage: String,
        shortcut: String?,
        isEnabled: Bool,
        kind: ReviewCommandPanelActionKind
    ) {
        self.id = kind.stableID
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.kind = kind
    }
}

public enum ReviewCommandPanelPresentation {
    public static func filteredActions(
        _ actions: [ReviewCommandPanelAction],
        query: String
    ) -> [ReviewCommandPanelAction] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return actions
        }

        return actions.filter {
            $0.title.lowercased().contains(normalizedQuery)
                || $0.subtitle.lowercased().contains(normalizedQuery)
        }
    }

    public static func visibleActions(
        _ actions: [ReviewCommandPanelAction],
        query: String
    ) -> [ReviewCommandPanelAction] {
        let matchingActions = filteredActions(actions, query: query)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.isEmpty else {
            return matchingActions
        }

        return matchingActions
    }

    public static func selectedActionID(
        currentSelectionID: String?,
        filteredActions: [ReviewCommandPanelAction]
    ) -> String? {
        guard filteredActions.contains(where: { $0.id == currentSelectionID && $0.isEnabled }) else {
            return filteredActions.first(where: \.isEnabled)?.id
        }

        return currentSelectionID
    }

    public static func actionToPerform(
        selectedActionID: String?,
        filteredActions: [ReviewCommandPanelAction]
    ) -> ReviewCommandPanelAction? {
        let selectedAction = selectedActionID.flatMap { selectedActionID in
            filteredActions.first { $0.id == selectedActionID && $0.isEnabled }
        }

        return selectedAction ?? filteredActions.first(where: \.isEnabled)
    }

    public static func movedSelectionID(
        currentSelectionID: String?,
        filteredActions: [ReviewCommandPanelAction],
        offset: Int
    ) -> String? {
        let enabledActions = filteredActions.filter(\.isEnabled)
        guard !enabledActions.isEmpty else {
            return nil
        }

        let currentIndex = currentSelectionID.flatMap { currentSelectionID in
            enabledActions.firstIndex { $0.id == currentSelectionID }
        } ?? (offset > 0 ? -1 : enabledActions.count)
        let nextIndex = (currentIndex + offset + enabledActions.count) % enabledActions.count
        return enabledActions[nextIndex].id
    }
}
