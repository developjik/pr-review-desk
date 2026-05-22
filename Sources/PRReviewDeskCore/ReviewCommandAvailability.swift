import Foundation

public struct ReviewCommandAvailability: Equatable, Hashable, Sendable {
    public let canRefreshActiveScope: Bool
    public let canGenerateReview: Bool
    public let canSubmitReview: Bool

    public init(
        hasToken: Bool,
        hasSelectedPullRequest: Bool,
        hasSubmittableDraft: Bool,
        isWorking: Bool
    ) {
        canRefreshActiveScope = hasToken && !isWorking
        canGenerateReview = hasSelectedPullRequest && !isWorking
        canSubmitReview = hasSubmittableDraft && !isWorking
    }
}
