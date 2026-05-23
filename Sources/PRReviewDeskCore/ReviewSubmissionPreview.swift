import Foundation

public struct ReviewSubmissionPreview: Equatable, Hashable, Sendable {
    public struct InlineCommentPreview: Identifiable, Equatable, Hashable, Sendable {
        public let id: String
        public let path: String
        public let position: Int
        public let severity: CommentSeverity
        public let bodyPreview: String

        public var location: String {
            "\(path):\(position)"
        }
    }

    public let event: ReviewEvent
    public let summaryLine: String
    public let bodyPreview: String
    public let selectedInlineComments: [InlineCommentPreview]
    public let safetyState: ReviewSubmissionSafetyState

    public var selectedInlineCommentCount: Int {
        selectedInlineComments.count
    }

    public var canSubmit: Bool {
        safetyState.canSubmit
    }

    public var safetyMessage: String {
        if safetyState.isStale {
            return "Draft is stale. Regenerate before submitting."
        }

        if !safetyState.invalidSelectedInlineComments.isEmpty {
            return "\(safetyState.invalidSelectedInlineComments.count) selected inline comments target invalid diff positions."
        }

        if !safetyState.couldValidateDiffPositions {
            return "Refresh safety before submitting."
        }

        if !safetyState.canSubmit {
            return "Refresh safety before submitting."
        }

        return "Ready to submit."
    }

    public static func make(
        event: ReviewEvent,
        body: String,
        draft: ReviewDraft,
        safetyState: ReviewSubmissionSafetyState? = nil
    ) -> ReviewSubmissionPreview {
        let selectedComments = draft.inlineComments.filter(\.isSelected)
        return ReviewSubmissionPreview(
            event: event,
            summaryLine: "\(event.displayName) review - \(selectedComments.count) selected inline comments",
            bodyPreview: previewBody(body),
            selectedInlineComments: selectedComments.map { comment in
                InlineCommentPreview(
                    id: comment.id,
                    path: comment.path,
                    position: comment.position,
                    severity: comment.severity,
                    bodyPreview: previewText(comment.body)
                )
            },
            safetyState: safetyState ?? ReviewSubmissionSafetyState(
                reviewedHeadSha: nil,
                currentHeadSha: nil,
                selectedInlineCommentCount: selectedComments.count,
                invalidSelectedInlineComments: []
            )
        )
    }

    private static func previewBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No review body."
        }

        return trimmed
    }

    private static func previewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No comment body."
        }

        return trimmed
    }
}
