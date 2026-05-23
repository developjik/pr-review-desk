import Foundation

public struct AIReviewDraftActionPresentation: Equatable, Hashable, Sendable {
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let isEnabled: Bool
    public let isProminent: Bool

    public init(
        hasDraft: Bool,
        isEnabled: Bool,
        disabledReason: String?
    ) {
        title = hasDraft ? "Regenerate AI Review Draft" : "Generate AI Review Draft"
        systemImage = "sparkles"
        self.isEnabled = isEnabled
        isProminent = true

        if let disabledReason, !isEnabled {
            subtitle = disabledReason
        } else if hasDraft {
            subtitle = "Replace the current editable draft. Nothing is posted to GitHub."
        } else {
            subtitle = "Create an editable AI review draft. Nothing is posted to GitHub."
        }
    }
}
