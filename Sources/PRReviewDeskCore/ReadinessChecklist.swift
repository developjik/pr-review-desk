import Foundation

public enum ReadinessChecklistItemID: String, Equatable, Hashable, Sendable {
    case githubCredential
    case githubTokenValidation
    case codexCLI
    case codexLogin
    case privacyDisclosure
}

public enum ReadinessChecklistItemState: Equatable, Hashable, Sendable {
    case ready
    case needsAction
    case unknown
}

public enum ReadinessChecklistAction: String, Equatable, Hashable, Sendable {
    case loadGitHubCredential
    case validateGitHubToken
    case checkCodexReadiness
    case copyCodexLoginCommand
    case acknowledgePrivacyDisclosure
}

public enum ReadinessProbeState: Equatable, Hashable, Sendable {
    case ready(String)
    case needsAction(String)
    case unknown(String)

    public var itemState: ReadinessChecklistItemState {
        switch self {
        case .ready:
            return .ready
        case .needsAction:
            return .needsAction
        case .unknown:
            return .unknown
        }
    }

    public var detail: String {
        switch self {
        case let .ready(detail),
             let .needsAction(detail),
             let .unknown(detail):
            return detail
        }
    }
}

public struct ReadinessChecklistItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: ReadinessChecklistItemID
    public let title: String
    public let detail: String
    public let state: ReadinessChecklistItemState
    public let action: ReadinessChecklistAction
    public let actionTitle: String

    public init(
        id: ReadinessChecklistItemID,
        title: String,
        detail: String,
        state: ReadinessChecklistItemState,
        action: ReadinessChecklistAction,
        actionTitle: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.action = action
        self.actionTitle = actionTitle
    }
}

public struct ReadinessChecklist: Equatable, Hashable, Sendable {
    public let items: [ReadinessChecklistItem]

    public init(
        hasGitHubCredential: Bool,
        tokenValidation: ReadinessProbeState,
        codexCLI: ReadinessProbeState,
        codexLogin: ReadinessProbeState,
        isPrivacyDisclosureAcknowledged: Bool
    ) {
        items = [
            ReadinessChecklistItem(
                id: .githubCredential,
                title: "GitHub credential",
                detail: hasGitHubCredential ? "Token loaded from Keychain." : "Save or load a GitHub token.",
                state: hasGitHubCredential ? .ready : .needsAction,
                action: .loadGitHubCredential,
                actionTitle: "Load"
            ),
            ReadinessChecklistItem(
                id: .githubTokenValidation,
                title: "GitHub scopes",
                detail: tokenValidation.detail,
                state: tokenValidation.itemState,
                action: .validateGitHubToken,
                actionTitle: "Validate"
            ),
            ReadinessChecklistItem(
                id: .codexCLI,
                title: "Codex CLI",
                detail: codexCLI.detail,
                state: codexCLI.itemState,
                action: .checkCodexReadiness,
                actionTitle: "Check"
            ),
            ReadinessChecklistItem(
                id: .codexLogin,
                title: "Codex login",
                detail: codexLogin.detail,
                state: codexLogin.itemState,
                action: .copyCodexLoginCommand,
                actionTitle: "Copy command"
            ),
            ReadinessChecklistItem(
                id: .privacyDisclosure,
                title: "Privacy disclosure",
                detail: isPrivacyDisclosureAcknowledged
                    ? "PR metadata and reviewable patches disclosure acknowledged."
                    : "Review generation may send PR metadata and reviewable patches to Codex and OpenAI.",
                state: isPrivacyDisclosureAcknowledged ? .ready : .needsAction,
                action: .acknowledgePrivacyDisclosure,
                actionTitle: "Acknowledge"
            )
        ]
    }

    public var isReady: Bool {
        items.allSatisfy { $0.state == .ready }
    }
}
