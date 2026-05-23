import Foundation
import PRReviewDeskCore

enum ReviewCommandAvailabilityTests {
    static func run() throws {
        try testCommandsAreDisabledWhileWorking()
        try testGenerateRequiresSelectedPullRequest()
        try testSubmitMatchesSubmittableDraftState()
        try testCodexLoginCommandRequiresReadyCLI()
        try testEveryReviewSubmissionEventRequiresConfirmation()
    }

    private static func testCommandsAreDisabledWhileWorking() throws {
        let availability = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: true,
            hasSubmittableDraft: true,
            isWorking: true,
            hasCancelableOperation: true
        )

        try expectEqual(availability.canRefreshActiveScope, false)
        try expectEqual(availability.canGenerateReview, false)
        try expectEqual(availability.canSubmitReview, false)
        try expectTrue(availability.canCancelCurrentOperation)
    }

    private static func testGenerateRequiresSelectedPullRequest() throws {
        let availability = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: false,
            hasSubmittableDraft: false,
            isWorking: false
        )

        try expectTrue(availability.canRefreshActiveScope)
        try expectEqual(availability.canGenerateReview, false)
    }

    private static func testSubmitMatchesSubmittableDraftState() throws {
        let unavailable = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: true,
            hasSubmittableDraft: false,
            isWorking: false
        )
        let available = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: true,
            hasSubmittableDraft: true,
            isWorking: false,
            hasCancelableOperation: true
        )

        try expectEqual(unavailable.canSubmitReview, false)
        try expectTrue(available.canSubmitReview)
        try expectTrue(available.canCancelCurrentOperation)
    }

    private static func testCodexLoginCommandRequiresReadyCLI() throws {
        let unavailable = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: true,
            hasSubmittableDraft: false,
            isWorking: false,
            canCopyCodexLoginCommand: false
        )
        let available = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: true,
            hasSubmittableDraft: false,
            isWorking: false,
            canCopyCodexLoginCommand: true
        )

        try expectEqual(unavailable.canCopyCodexLoginCommand, false)
        try expectTrue(available.canCopyCodexLoginCommand)
    }

    private static func testEveryReviewSubmissionEventRequiresConfirmation() throws {
        try expectTrue(ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: .comment))
        try expectTrue(ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: .approve))
        try expectTrue(ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: .requestChanges))
    }
}
