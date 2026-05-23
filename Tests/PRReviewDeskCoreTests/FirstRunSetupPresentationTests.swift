import Foundation
import PRReviewDeskCore

enum FirstRunSetupPresentationTests {
    static func run() throws {
        try testGuidedSetupPresentsSinglePathInOrder()
        try testGuidedSetupMarksCompletedSteps()
        try testGitHubStepRequiresCredentialValidation()
    }

    private static func testGuidedSetupPresentsSinglePathInOrder() throws {
        let steps = FirstRunSetupPresentation.steps(
            hasGitHubCredential: false,
            isGitHubReady: false,
            isCodexCLIReady: false,
            isCodexChatGPTLoginReady: false,
            isPrivacyAcknowledged: false
        )

        try expectEqual(steps.map(\.title), [
            "GitHub access",
            "AI review setup",
            "ChatGPT sign-in",
            "Privacy acknowledgement"
        ])
        try expectEqual(steps.map(\.actionTitle), [
            "Sign in with GitHub",
            "Check Codex",
            "Copy sign-in step",
            "Acknowledge privacy"
        ])
        try expectTrue(!steps[0].detail.localizedCaseInsensitiveContains("personal access token"))
        try expectTrue(!steps[0].detail.localizedCaseInsensitiveContains("PAT"))
        try expectTrue(!steps.map(\.detail).joined(separator: " ").localizedCaseInsensitiveContains("API key"))
        try expectTrue(!steps[1].detail.localizedCaseInsensitiveContains("PATH"))
        try expectEqual(steps.map(\.state), [.needsAction, .needsAction, .needsAction, .needsAction])
    }

    private static func testGuidedSetupMarksCompletedSteps() throws {
        let steps = FirstRunSetupPresentation.steps(
            hasGitHubCredential: true,
            isGitHubReady: true,
            isCodexCLIReady: true,
            isCodexChatGPTLoginReady: true,
            isPrivacyAcknowledged: false
        )

        try expectEqual(steps.map(\.state), [.complete, .complete, .complete, .needsAction])
        try expectEqual(steps[0].detail, "GitHub sign-in and repository access are ready.")
        try expectEqual(steps[3].detail, "Confirm what private repository context can be sent before generating reviews.")
    }

    private static func testGitHubStepRequiresCredentialValidation() throws {
        let steps = FirstRunSetupPresentation.steps(
            hasGitHubCredential: true,
            isGitHubReady: false,
            isCodexCLIReady: false,
            isCodexChatGPTLoginReady: false,
            isPrivacyAcknowledged: false
        )

        try expectEqual(steps[0].state, .needsAction)
        try expectEqual(steps[0].detail, "GitHub sign-in is saved. Check repository access before generating reviews.")
        try expectEqual(steps[0].actionTitle, "Check GitHub Access")
    }
}
