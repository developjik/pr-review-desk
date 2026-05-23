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
            isCodexReady: false,
            isPrivacyAcknowledged: false
        )

        try expectEqual(steps.map(\.title), [
            "GitHub access",
            "Codex readiness",
            "Privacy acknowledgement"
        ])
        try expectEqual(steps.map(\.actionTitle), [
            "Save PAT",
            "Check Codex",
            "Acknowledge privacy"
        ])
        try expectEqual(steps.map(\.state), [.needsAction, .needsAction, .needsAction])
    }

    private static func testGuidedSetupMarksCompletedSteps() throws {
        let steps = FirstRunSetupPresentation.steps(
            hasGitHubCredential: true,
            isGitHubReady: true,
            isCodexReady: true,
            isPrivacyAcknowledged: false
        )

        try expectEqual(steps.map(\.state), [.complete, .complete, .needsAction])
        try expectEqual(steps[0].detail, "GitHub credential and scopes are ready.")
        try expectEqual(steps[2].detail, "Confirm what private repository context can be sent before generating reviews.")
    }

    private static func testGitHubStepRequiresCredentialValidation() throws {
        let steps = FirstRunSetupPresentation.steps(
            hasGitHubCredential: true,
            isGitHubReady: false,
            isCodexReady: false,
            isPrivacyAcknowledged: false
        )

        try expectEqual(steps[0].state, .needsAction)
        try expectEqual(steps[0].detail, "GitHub credential is loaded. Validate scopes before generating reviews.")
        try expectEqual(steps[0].actionTitle, "Validate GitHub")
    }
}
