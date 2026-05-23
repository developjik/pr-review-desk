import Foundation

public enum FirstRunSetupStepState: Equatable, Hashable, Sendable {
    case complete
    case needsAction
}

public struct FirstRunSetupStep: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let actionTitle: String
    public let systemImage: String
    public let state: FirstRunSetupStepState
}

public enum FirstRunSetupPresentation {
    public static func steps(
        hasGitHubCredential: Bool,
        isGitHubReady: Bool,
        isCodexCLIReady: Bool,
        isCodexChatGPTLoginReady: Bool,
        isPrivacyAcknowledged: Bool
    ) -> [FirstRunSetupStep] {
        [
            FirstRunSetupStep(
                id: "github",
                title: "GitHub access",
                detail: gitHubDetail(hasCredential: hasGitHubCredential, isReady: isGitHubReady),
                actionTitle: hasGitHubCredential ? "Validate GitHub" : "Sign in with GitHub",
                systemImage: "person.crop.circle.badge.checkmark",
                state: isGitHubReady ? .complete : .needsAction
            ),
            FirstRunSetupStep(
                id: "codex",
                title: "Codex CLI",
                detail: isCodexCLIReady
                    ? "Codex CLI is available on PATH."
                    : "Check that Codex CLI is installed and available on PATH.",
                actionTitle: "Check Codex",
                systemImage: "terminal",
                state: isCodexCLIReady ? .complete : .needsAction
            ),
            FirstRunSetupStep(
                id: "codexLogin",
                title: "ChatGPT Codex login",
                detail: isCodexChatGPTLoginReady
                    ? "Codex is signed in with ChatGPT."
                    : "Run `codex login` and sign in with ChatGPT before generating reviews.",
                actionTitle: "Copy command",
                systemImage: "person.crop.circle.badge.checkmark",
                state: isCodexChatGPTLoginReady ? .complete : .needsAction
            ),
            FirstRunSetupStep(
                id: "privacy",
                title: "Privacy acknowledgement",
                detail: isPrivacyAcknowledged
                    ? "Privacy disclosure is acknowledged."
                    : "Confirm what private repository context can be sent before generating reviews.",
                actionTitle: "Acknowledge privacy",
                systemImage: "hand.raised",
                state: isPrivacyAcknowledged ? .complete : .needsAction
            )
        ]
    }

    private static func gitHubDetail(hasCredential: Bool, isReady: Bool) -> String {
        if isReady {
            return "GitHub credential and scopes are ready."
        }

        if hasCredential {
            return "GitHub credential is loaded. Validate scopes before generating reviews."
        }

        return "Sign in with GitHub OAuth to authorize repository review access."
    }
}
