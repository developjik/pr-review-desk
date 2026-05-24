import Foundation
import PRReviewDeskCore

enum SettingsGatePresentationTests {
    static func run() throws {
        try testIncompleteReadinessRoutesMainWindowToSetup()
        try testCompleteReadinessRoutesMainWindowToReviewWorkspace()
        try testSetupRequiredMainWindowOnlyOffersSettingsAction()
    }

    private static func testIncompleteReadinessRoutesMainWindowToSetup() throws {
        let checklist = ReadinessChecklist(
            hasGitHubCredential: false,
            tokenValidation: .unknown("Not validated."),
            codexCLI: .needsAction("Codex is not ready."),
            codexLogin: .unknown("Not checked."),
            isPrivacyDisclosureAcknowledged: false
        )

        let presentation = SettingsGatePresentation.make(readinessChecklist: checklist)

        try expectEqual(presentation.destination, .setupRequired)
        try expectEqual(presentation.blockingItems.map(\.id), checklist.items.map(\.id))
    }

    private static func testCompleteReadinessRoutesMainWindowToReviewWorkspace() throws {
        let checklist = ReadinessChecklist(
            hasGitHubCredential: true,
            tokenValidation: .ready("Valid for @developjik."),
            codexCLI: .ready("Codex is ready."),
            codexLogin: .ready("Logged in using ChatGPT."),
            isPrivacyDisclosureAcknowledged: true
        )

        let presentation = SettingsGatePresentation.make(readinessChecklist: checklist)

        try expectEqual(presentation.destination, .reviewWorkspace)
        try expectEqual(presentation.blockingItems, [])
    }

    private static func testSetupRequiredMainWindowOnlyOffersSettingsAction() throws {
        let checklist = ReadinessChecklist(
            hasGitHubCredential: true,
            tokenValidation: .ready("Valid for @developjik."),
            codexCLI: .ready("Codex is installed. Finish Codex sign-in before generating reviews."),
            codexLogin: .needsAction("Not logged in."),
            isPrivacyDisclosureAcknowledged: false
        )

        let presentation = SettingsGatePresentation.make(readinessChecklist: checklist)

        try expectEqual(presentation.destination, .setupRequired)
        try expectEqual(presentation.primaryAction, .openSettings)
        try expectTrue(presentation.allowsInlineSetupActions == false)
    }
}
