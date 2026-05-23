import Foundation

public struct ReviewCommandAvailability: Equatable, Hashable, Sendable {
    public let canRefreshActiveScope: Bool
    public let canGenerateReview: Bool
    public let canSubmitReview: Bool
    public let canOpenPullRequest: Bool
    public let canRegenerateSelectedFile: Bool
    public let canRevealInlineComment: Bool
    public let canToggleInspector: Bool
    public let canFocusSearch: Bool
    public let canCopyCodexLoginCommand: Bool

    public init(
        hasToken: Bool,
        hasSelectedPullRequest: Bool,
        hasSubmittableDraft: Bool,
        isWorking: Bool,
        hasSelectedFile: Bool = false,
        hasFocusedInlineComment: Bool = false,
        supportsSelectedFileRegeneration: Bool = false
    ) {
        canRefreshActiveScope = hasToken && !isWorking
        canGenerateReview = hasSelectedPullRequest && !isWorking
        canSubmitReview = hasSubmittableDraft && !isWorking
        canOpenPullRequest = hasSelectedPullRequest
        canRegenerateSelectedFile = hasSelectedPullRequest
            && hasSelectedFile
            && supportsSelectedFileRegeneration
            && !isWorking
        canRevealInlineComment = hasFocusedInlineComment
        canToggleInspector = true
        canFocusSearch = true
        canCopyCodexLoginCommand = true
    }
}
