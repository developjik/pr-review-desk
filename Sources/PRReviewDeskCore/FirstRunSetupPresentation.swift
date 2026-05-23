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
                actionTitle: hasGitHubCredential ? "Check GitHub Access" : "Sign in with GitHub",
                systemImage: "person.crop.circle.badge.checkmark",
                state: isGitHubReady ? .complete : .needsAction
            ),
            FirstRunSetupStep(
                id: "codex",
                title: "AI review setup",
                detail: isCodexCLIReady
                    ? "AI review drafting is ready on this Mac."
                    : "Check whether this Mac can create AI review drafts.",
                actionTitle: "Check Codex",
                systemImage: "terminal",
                state: isCodexCLIReady ? .complete : .needsAction
            ),
            FirstRunSetupStep(
                id: "codexLogin",
                title: "ChatGPT sign-in",
                detail: isCodexChatGPTLoginReady
                    ? "ChatGPT sign-in is ready."
                    : "Sign in to Codex with ChatGPT before generating reviews.",
                actionTitle: "Copy sign-in step",
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
            return "GitHub sign-in and repository access are ready."
        }

        if hasCredential {
            return "GitHub sign-in is saved. Check repository access before generating reviews."
        }

        return "Sign in with GitHub to authorize repository review access."
    }
}
