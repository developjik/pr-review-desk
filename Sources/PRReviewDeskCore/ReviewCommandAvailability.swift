import Foundation

public struct ReviewCommandAvailability: Equatable, Hashable, Sendable {
    public let canRefreshActiveScope: Bool
    public let canGenerateReview: Bool
    public let canSubmitReview: Bool
    public let canPreviewReviewSubmission: Bool
    public let canOpenPullRequest: Bool
    public let canRegenerateSelectedFile: Bool
    public let canRevealInlineComment: Bool
    public let canToggleInspector: Bool
    public let canCopyCodexLoginCommand: Bool
    public let canCancelCurrentOperation: Bool

    public init(
        hasToken: Bool,
        hasSelectedPullRequest: Bool,
        hasSubmittableDraft: Bool,
        hasDraft: Bool = false,
        isWorking: Bool,
        hasCancelableOperation: Bool = false,
        hasSelectedFile: Bool = false,
        hasFocusedInlineComment: Bool = false,
        supportsSelectedFileRegeneration: Bool = false,
        canCopyCodexLoginCommand: Bool = true
    ) {
        canRefreshActiveScope = hasToken && !isWorking
        canGenerateReview = hasSelectedPullRequest && !isWorking
        canSubmitReview = hasSubmittableDraft && !isWorking
        canPreviewReviewSubmission = hasDraft && !isWorking
        canOpenPullRequest = hasSelectedPullRequest
        canRegenerateSelectedFile = hasSelectedPullRequest
            && hasSelectedFile
            && supportsSelectedFileRegeneration
            && !isWorking
        canRevealInlineComment = hasFocusedInlineComment
        canToggleInspector = true
        self.canCopyCodexLoginCommand = canCopyCodexLoginCommand && !isWorking
        canCancelCurrentOperation = hasCancelableOperation
    }
}
