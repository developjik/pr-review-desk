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
                ScrollViewReader { proxy in
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
                                        .id(comment.id)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        scrollToFocusedComment(proxy)
                    }
                    .onChange(of: model.focusedInlineCommentTarget) { _, _ in
                        scrollToFocusedComment(proxy)
                    }
                }
            } else {
                Text(AppL10n.string("No inline comments generated yet."))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollToFocusedComment(_ proxy: ScrollViewProxy) {
        guard let target = model.focusedInlineCommentTarget else {
            return
        }

        proxy.scrollTo(target.commentID, anchor: .center)
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
                        Text(AppL10n.string("Comment spot %d", comment.position))
                            .foregroundStyle(.secondary)
                        Text(comment.severity.localizedDisplayName)
                            .foregroundStyle(AppTheme.foreground(ReviewViewSupport.severityTone(comment.severity)))
                    }
                }
                .accessibilityLabel(AppL10n.string(
                    "%@ comment spot %d %@",
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
                Text(AppL10n.string("This selected comment no longer matches the PR. Check again or regenerate before posting."))
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
                "Inline comment for %@ comment spot %d",
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
