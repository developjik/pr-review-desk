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

    public var selectedInlineCommentCount: Int {
        selectedInlineComments.count
    }

    public static func make(
        event: ReviewEvent,
        body: String,
        draft: ReviewDraft
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
            }
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
