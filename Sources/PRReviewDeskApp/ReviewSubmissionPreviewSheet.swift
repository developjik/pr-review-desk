import SwiftUI
import PRReviewDeskCore

struct ReviewSubmissionPreviewSheet: View {
    let preview: ReviewSubmissionPreview?
    let eventDisplayName: String
    let isRefreshingSafety: Bool
    let onCancel: () -> Void
    let onRefreshSafety: () -> Void
    let onRegenerate: () -> Void
    let onRevealInvalidComment: (InvalidInlineComment) -> Void
    let onDeselectInvalidComment: (InvalidInlineComment) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewSummary(preview)
                        preflightPreview(preview)
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
        .frame(minWidth: 520, idealWidth: 640, maxWidth: 640, minHeight: 620, idealHeight: 620)
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
            if preview?.canSubmit != true {
                Button {
                    onRefreshSafety()
                } label: {
                    Label(
                        isRefreshingSafety ? AppL10n.string("Checking") : AppL10n.string("Check Again"),
                        systemImage: "shield.lefthalf.filled"
                    )
                }
                .disabled(isRefreshingSafety)
                .smokeAccessibilityIdentifier(
                    "submit-preview.refresh-safety",
                    state: isRefreshingSafety ? "disabled" : "enabled"
                )
                Button {
                    onRegenerate()
                } label: {
                    Label(AppL10n.string("Regenerate"), systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityHint(AppL10n.string("Creates a fresh draft when comments no longer match the PR."))
                .disabled(isRefreshingSafety)
                .smokeAccessibilityIdentifier(
                    "submit-preview.regenerate",
                    state: isRefreshingSafety ? "disabled" : "enabled"
                )
            }
            Spacer()
            Button {
                onSubmit()
            } label: {
                Label(AppL10n.string("Submit %@ Review", eventDisplayName), systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .disabled(preview?.canSubmit != true)
            .keyboardShortcut(.return, modifiers: [.command])
            .smokeAccessibilityIdentifier(
                "submit-preview.submit",
                state: preview?.canSubmit == true ? "enabled" : "disabled"
            )
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

    private func preflightPreview(_ preview: ReviewSubmissionPreview) -> some View {
        let state = preview.safetyState

        return VStack(alignment: .leading, spacing: 8) {
            Label(
                AppL10n.string(preview.safetyMessage),
                systemImage: state.canSubmit ? "checkmark.shield" : "exclamationmark.triangle"
            )
            .font(.headline)
            .foregroundStyle(state.canSubmit ? AppTheme.foreground(.success) : AppTheme.foreground(.warning))
            .fixedSize(horizontal: false, vertical: true)

            Text(safetyCheckedText(for: preview))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            InspectorMetricGroup(metrics: [
                InspectorMetric(
                    id: "selected",
                    title: AppL10n.string("Selected %d", state.selectedInlineCommentCount),
                    systemImage: "text.bubble",
                    tone: .info
                ),
                InspectorMetric(
                    id: "invalid",
                    title: AppL10n.string("Needs fix %d", state.invalidSelectedInlineComments.count),
                    systemImage: state.invalidSelectedInlineComments.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                    tone: state.invalidSelectedInlineComments.isEmpty ? .success : .invalid
                )
            ])

            DisclosureGroup(AppL10n.string("Version details")) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        AppL10n.string("Draft version %@", ReviewViewSupport.shortSha(state.reviewedHeadSha)),
                        systemImage: "number"
                    )
                    Label(
                        AppL10n.string("Latest version %@", ReviewViewSupport.shortSha(state.currentHeadSha)),
                        systemImage: "number"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .font(.caption)

            if !state.invalidSelectedInlineComments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppL10n.string("Comments to review:"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.foreground(.invalid))

                    ForEach(state.invalidSelectedInlineComments, id: \.self) { comment in
                        HStack(spacing: 8) {
                            Text(AppL10n.string("%@ comment spot %d", comment.path, comment.position))
                                .font(.caption)
                                .foregroundStyle(AppTheme.foreground(.invalid))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button {
                                onRevealInvalidComment(comment)
                            } label: {
                                Label(AppL10n.string("Reveal"), systemImage: "scope")
                            }
                            .accessibilityHint(AppL10n.string("Opens this comment in the review inspector. Its original diff spot may no longer exist."))
                            .smokeAccessibilityIdentifier(
                                "submit-preview.invalid.reveal",
                                state: "enabled",
                                details: AppL10n.string("Opens this comment in the review inspector. Its original diff spot may no longer exist.")
                            )
                            Button {
                                onDeselectInvalidComment(comment)
                            } label: {
                                Label(AppL10n.string("Deselect"), systemImage: "checkmark.circle")
                            }
                            .accessibilityHint(AppL10n.string("Removes this comment from the submission preview."))
                            .smokeAccessibilityIdentifier(
                                "submit-preview.invalid.deselect",
                                state: "enabled",
                                details: AppL10n.string("Removes this comment from the submission preview.")
                            )
                        }
                    }
                }

                Text(AppL10n.string("Regenerate the draft, reveal a comment, or deselect comments that need fixing."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(state.canSubmit ? AppTheme.border(.success) : AppTheme.border(.warning))
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
                            Text(displayLocation(for: comment))
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

    private func safetyCheckedText(for preview: ReviewSubmissionPreview) -> String {
        guard let display = preview.safetyCheckedAtDisplay else {
            return AppL10n.string(preview.safetyCheckedMessage)
        }

        return AppL10n.string("Last checked at %@ UTC.", display)
    }

    private func displayLocation(for comment: ReviewSubmissionPreview.InlineCommentPreview) -> String {
        AppL10n.string("%@ comment spot %d", comment.path, comment.position)
    }
}
