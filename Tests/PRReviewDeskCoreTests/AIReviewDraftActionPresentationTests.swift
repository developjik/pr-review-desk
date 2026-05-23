import Foundation
import PRReviewDeskCore

enum AIReviewDraftActionPresentationTests {
    static func run() throws {
        try testGenerateActionUsesDraftSafeCopy()
        try testRegenerateActionUsesDraftSafeCopy()
        try testDisabledActionShowsNearbyReason()
    }

    private static func testGenerateActionUsesDraftSafeCopy() throws {
        let presentation = AIReviewDraftActionPresentation(
            hasDraft: false,
            isEnabled: true,
            disabledReason: nil
        )

        try expectEqual(presentation.title, "Generate AI Review Draft")
        try expectEqual(
            presentation.subtitle,
            "Create an editable AI review draft. Nothing is posted to GitHub."
        )
        try expectEqual(presentation.systemImage, "sparkles")
        try expectTrue(presentation.isProminent)
        try expectTrue(presentation.isEnabled)
    }

    private static func testRegenerateActionUsesDraftSafeCopy() throws {
        let presentation = AIReviewDraftActionPresentation(
            hasDraft: true,
            isEnabled: true,
            disabledReason: nil
        )

        try expectEqual(presentation.title, "Regenerate AI Review Draft")
        try expectEqual(
            presentation.subtitle,
            "Replace the current editable draft. Nothing is posted to GitHub."
        )
    }

    private static func testDisabledActionShowsNearbyReason() throws {
        let presentation = AIReviewDraftActionPresentation(
            hasDraft: false,
            isEnabled: false,
            disabledReason: "Select a pull request first."
        )

        try expectEqual(presentation.title, "Generate AI Review Draft")
        try expectEqual(presentation.subtitle, "Select a pull request first.")
        try expectTrue(!presentation.isEnabled)
    }
}
