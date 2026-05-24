import Foundation
import PRReviewDeskCore

enum SettingsGitHubAccessPresentationTests {
    static func run() throws {
        try testSignedOutStateUsesAuthorizationCopy()
        try testLoadedStateAsksForValidation()
        try testReadyStateUsesMaintenanceCopy()
    }

    private static func testSignedOutStateUsesAuthorizationCopy() throws {
        let presentation = SettingsGitHubAccessPresentation.make(
            hasCredential: false,
            hasValidatedScopes: false
        )

        try expectEqual(
            presentation.caption,
            "Sign in with GitHub to authorize repository review access."
        )
    }

    private static func testLoadedStateAsksForValidation() throws {
        let presentation = SettingsGitHubAccessPresentation.make(
            hasCredential: true,
            hasValidatedScopes: false
        )

        try expectEqual(
            presentation.caption,
            "GitHub sign-in is saved. Validate repository access before generating reviews."
        )
    }

    private static func testReadyStateUsesMaintenanceCopy() throws {
        let presentation = SettingsGitHubAccessPresentation.make(
            hasCredential: true,
            hasValidatedScopes: true
        )

        try expectEqual(
            presentation.caption,
            "GitHub is connected for repository review access. Reconnect or manage access if permissions change."
        )
    }
}
