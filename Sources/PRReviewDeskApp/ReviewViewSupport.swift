import SwiftUI
import PRReviewDeskCore

enum ReviewViewSupport {
    static func shortSha(_ sha: String?) -> String {
        guard let sha else {
            return "-"
        }

        return String(sha.prefix(8))
    }

    static func commentsGroupedByPath(_ comments: [InlineCommentDraft]) -> [(path: String, comments: [InlineCommentDraft])] {
        Dictionary(grouping: comments, by: \.path)
            .map { path, comments in
                (
                    path: path,
                    comments: comments.sorted { $0.position < $1.position }
                )
            }
            .sorted { $0.path < $1.path }
    }

    static func severityTone(_ severity: CommentSeverity) -> AppStatusTone {
        switch severity {
        case .low:
            return .neutral
        case .medium:
            return .warning
        case .high:
            return .error
        }
    }
}

extension ReviewEvent {
    var localizedDisplayName: String {
        AppL10n.string(displayName)
    }
}

extension CommentSeverity {
    var localizedDisplayName: String {
        AppL10n.string(rawValue)
    }
}
