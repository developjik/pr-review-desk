import SwiftUI
import PRReviewDeskCore

struct DraftEditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppL10n.string("Review Body"))
                .font(.headline)
            TextEditor(text: $model.reviewBody)
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
                .accessibilityLabel(AppL10n.string("Review Body"))

            Text(AppL10n.string("Inline Comments"))
                .font(.headline)
            if let draft = model.draft, !draft.inlineComments.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(ReviewViewSupport.commentsGroupedByPath(draft.inlineComments), id: \.path) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.path)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                ForEach(group.comments) { comment in
                                    InlineCommentEditorRow(
                                        model: model,
                                        comment: comment,
                                        isInvalid: model.isInlineCommentInvalid(comment)
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text(AppL10n.string("No inline comments generated yet."))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineCommentEditorRow: View {
    @ObservedObject var model: AppModel
    let comment: InlineCommentDraft
    let isInvalid: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { comment.isSelected },
                    set: { model.setInlineCommentSelection(id: comment.id, isSelected: $0) }
                )) {
                    HStack {
                        Text(comment.path)
                            .fontWeight(.medium)
                        Text(AppL10n.string("Position %d", comment.position))
                            .foregroundStyle(.secondary)
                        Text(comment.severity.localizedDisplayName)
                            .foregroundStyle(AppTheme.foreground(ReviewViewSupport.severityTone(comment.severity)))
                    }
                }
                .accessibilityLabel(AppL10n.string(
                    "%@ position %d %@",
                    comment.path,
                    comment.position,
                    comment.severity.localizedDisplayName
                ))

                Spacer()

                Button {
                    model.focusInlineComment(comment)
                } label: {
                    Label(AppL10n.string("Reveal in diff"), systemImage: "scope")
                        .labelStyle(.iconOnly)
                }
                .help(AppL10n.string("Reveal in diff"))
                .accessibilityLabel(AppL10n.string("Reveal in diff"))
            }
            if isInvalid {
                Text(AppL10n.string("Invalid selected target. Refresh safety or regenerate before submitting."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.foreground(.invalid))
            }
            TextEditor(text: Binding(
                get: { comment.body },
                set: { model.setInlineCommentBody(id: comment.id, body: $0) }
            ))
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary)
            }
            .accessibilityLabel(AppL10n.string(
                "Inline comment for %@ position %d",
                comment.path,
                comment.position
            ))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor)
        }
        .accessibilityElement(children: .contain)
    }

    private var borderColor: Color {
        if isInvalid {
            return AppTheme.border(.invalid)
        }

        if model.isFocusedInlineComment(comment) {
            return AppTheme.border(.focus)
        }

        return Color.secondary.opacity(0.25)
    }
}
