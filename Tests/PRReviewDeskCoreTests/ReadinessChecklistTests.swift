import Foundation
import PRReviewDeskCore

enum ReadinessChecklistTests {
    static func run() throws {
        try testChecklistIsReadyWhenEveryRequiredStateIsReady()
        try testChecklistReportsRecoveryActionsForMissingFirstRunSetup()
    }

    private static func testChecklistIsReadyWhenEveryRequiredStateIsReady() throws {
        let checklist = ReadinessChecklist(
            hasGitHubCredential: true,
            tokenValidation: .ready("Valid for @developjik. Scopes: repo."),
            codexCLI: .ready("Found at /opt/homebrew/bin/codex."),
            codexLogin: .ready("Logged in using ChatGPT."),
            isPrivacyDisclosureAcknowledged: true
        )

        try expectTrue(checklist.isReady)
        try expectEqual(checklist.items.map(\.state), Array(repeating: .ready, count: 5))
    }

    private static func testChecklistReportsRecoveryActionsForMissingFirstRunSetup() throws {
        let checklist = ReadinessChecklist(
            hasGitHubCredential: false,
            tokenValidation: .unknown("Not validated."),
            codexCLI: .needsAction("Not found on PATH."),
            codexLogin: .unknown("Not checked."),
            isPrivacyDisclosureAcknowledged: false
        )

        try expectTrue(!checklist.isReady)

        let itemsByID = Dictionary(uniqueKeysWithValues: checklist.items.map { ($0.id, $0) })
        try expectEqual(itemsByID[.githubCredential]?.state, .needsAction)
        try expectEqual(itemsByID[.githubCredential]?.action, .loadGitHubCredential)
        try expectEqual(itemsByID[.githubCredential]?.detail, "Sign in with GitHub OAuth.")
        try expectEqual(itemsByID[.githubCredential]?.actionTitle, "Sign in")
        try expectEqual(itemsByID[.githubTokenValidation]?.state, .unknown)
        try expectEqual(itemsByID[.githubTokenValidation]?.action, .validateGitHubToken)
        try expectEqual(itemsByID[.codexCLI]?.state, .needsAction)
        try expectEqual(itemsByID[.codexCLI]?.action, .checkCodexReadiness)
        try expectEqual(itemsByID[.codexLogin]?.state, .unknown)
        try expectEqual(itemsByID[.codexLogin]?.action, .copyCodexLoginCommand)
        try expectEqual(itemsByID[.privacyDisclosure]?.state, .needsAction)
        try expectEqual(itemsByID[.privacyDisclosure]?.action, .acknowledgePrivacyDisclosure)
    }
}
