import Foundation

public enum ReviewCommandPanelActionKind: Equatable, Hashable, Sendable {
    case openPullRequest
    case generateReview
    case regenerateSelectedFile
    case submitReview
    case revealInlineComment
    case copyCodexLoginCommand
    case toggleInspector
    case selectSection(ReviewInboxSection)

    public var stableID: String {
        switch self {
        case .openPullRequest:
            return "open-pull-request"
        case .generateReview:
            return "generate-review"
        case .regenerateSelectedFile:
            return "regenerate-selected-file"
        case .submitReview:
            return "submit-review"
        case .revealInlineComment:
            return "reveal-inline-comment"
        case .copyCodexLoginCommand:
            return "copy-codex-login-command"
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
}
