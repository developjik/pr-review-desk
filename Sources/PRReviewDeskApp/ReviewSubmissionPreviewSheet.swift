import SwiftUI
import PRReviewDeskCore

struct ReviewSubmissionPreviewSheet: View {
    let preview: ReviewSubmissionPreview?
    let eventDisplayName: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewSummary(preview)
                        bodyPreview(preview.bodyPreview)
                        inlineCommentsPreview(preview.selectedInlineComments)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    AppL10n.string("No Draft Yet"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(AppL10n.string("Generate an AI review draft before editing or submitting a review."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 620)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperplane")
                .foregroundStyle(AppTheme.foreground(.focus))
            VStack(alignment: .leading, spacing: 2) {
                Text(AppL10n.string("Submit Review Preview"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(AppL10n.string("Review exactly what will be posted to GitHub."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button(AppL10n.string("Cancel"), role: .cancel) {
                onCancel()
            }
            Spacer()
            Button {
                onSubmit()
            } label: {
                Label(AppL10n.string("Submit %@ Review", eventDisplayName), systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .disabled(preview == nil)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding()
    }

    private func previewSummary(_ preview: ReviewSubmissionPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                AppL10n.string(
                    "%@ review - %d selected inline comments",
                    eventDisplayName,
                    preview.selectedInlineCommentCount
                ),
                systemImage: "checklist.checked"
            )
                .font(.headline)
            Text(AppL10n.string("Nothing is posted until you confirm this preview."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(.focus))
        }
    }

    private func bodyPreview(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AppL10n.string("Review Body"), systemImage: "text.alignleft")
                .font(.headline)
            Text(body)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(.neutral))
        }
    }

    private func inlineCommentsPreview(_ comments: [ReviewSubmissionPreview.InlineCommentPreview]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AppL10n.string("Inline Comments"), systemImage: "text.bubble")
                .font(.headline)

            if comments.isEmpty {
                Text(AppL10n.string("No inline comments selected. Only the review body will be posted."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comment.location)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            StatusBadge(
                                title: comment.severity.localizedDisplayName,
                                systemImage: "exclamationmark.bubble",
                                tone: ReviewViewSupport.severityTone(comment.severity)
                            )
                        }
                        Text(comment.bodyPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(.neutral))
        }
    }
}
