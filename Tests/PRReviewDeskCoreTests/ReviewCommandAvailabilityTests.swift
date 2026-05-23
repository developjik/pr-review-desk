import Foundation
import PRReviewDeskCore

enum ReviewCommandAvailabilityTests {
    static func run() throws {
        try testCommandsAreDisabledWhileWorking()
        try testGenerateRequiresSelectedPullRequest()
        try testSubmitMatchesSubmittableDraftState()
        try testEveryReviewSubmissionEventRequiresConfirmation()
    }

    private static func testCommandsAreDisabledWhileWorking() throws {
        let availability = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: true,
            hasSubmittableDraft: true,
            isWorking: true
        )

        try expectEqual(availability.canRefreshActiveScope, false)
        try expectEqual(availability.canGenerateReview, false)
        try expectEqual(availability.canSubmitReview, false)
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
            isWorking: false
        )

        try expectEqual(unavailable.canSubmitReview, false)
        try expectTrue(available.canSubmitReview)
    }

    private static func testEveryReviewSubmissionEventRequiresConfirmation() throws {
        try expectTrue(ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: .comment))
        try expectTrue(ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: .approve))
        try expectTrue(ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: .requestChanges))
    }
}
