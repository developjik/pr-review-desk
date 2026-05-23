import SwiftUI
import PRReviewDeskCore

struct ReviewInspectorView: View {
    @ObservedObject var model: AppModel
    @State private var isDiscardConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppL10n.string("Review Inspector"))
                    .font(.headline)

                if model.selectedPullRequest == nil {
                    ContentUnavailableView(
                        AppL10n.string("No Pull Request Selected"),
                        systemImage: "sidebar.trailing",
                        description: Text(AppL10n.string("Select a pull request to edit drafts and submit reviews."))
                    )
                } else {
                    ReviewEventSection(model: model)

                    if model.draft != nil {
                        SubmitSafetyView(model: model)
                        TrustSummaryView(model: model)
                        DraftEditorView(model: model)
                    } else {
                        EmptyDraftInspectorView(model: model)
                    }

                    if model.draft != nil {
                        Button(role: .destructive) {
                            isDiscardConfirmationPresented = true
                        } label: {
                            Label(AppL10n.string("Discard Draft"), systemImage: "trash")
                        }
                        .confirmationDialog(
                            AppL10n.string("Discard this draft?"),
                            isPresented: $isDiscardConfirmationPresented,
                            titleVisibility: .visible
                        ) {
                            Button(AppL10n.string("Discard Draft"), role: .destructive) {
                                model.discardCurrentDraft()
                            }
                            Button(AppL10n.string("Cancel"), role: .cancel) {}
                        } message: {
                            Text(AppL10n.string("This removes the local editable draft. Nothing is posted to GitHub."))
                        }
                    }
                }
            }
            .padding()
            .padding(.top, CGFloat(ReviewWorkspaceLayoutPolicy.inspectorTopContentInset))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.bar)
    }
}

private struct EmptyDraftInspectorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppL10n.string("No Draft Yet"), systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            Text(AppL10n.string("Generate an AI review draft before editing or submitting a review."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.startGenerateReview()
            } label: {
                Label(AppL10n.string(model.aiReviewDraftActionPresentation.title), systemImage: "sparkles")
            }
            .disabled(!model.canGenerateReview)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(.neutral))
        }
    }
}

private struct ReviewEventSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                Picker(AppL10n.string("Review event"), selection: $model.selectedEvent) {
                    ForEach(ReviewEvent.allCases) { event in
                        Text(event.localizedDisplayName).tag(event)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppL10n.string("Review event"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(AppL10n.string("Review event"), selection: $model.selectedEvent) {
                        ForEach(ReviewEvent.allCases) { event in
                            Text(event.localizedDisplayName).tag(event)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }

            Button {
                model.requestSubmitReview()
            } label: {
                Label("\(AppL10n.string("Submit Review")) (\(model.selectedInlineCommentCount))", systemImage: "paperplane")
            }
            .disabled(!model.canSubmitReview)
        }
    }
}

private struct TrustSummaryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let summary = model.reviewCoverageSummary

        VStack(alignment: .leading, spacing: 8) {
            Label(AppL10n.string("AI Trust"), systemImage: "checkmark.shield")
                .font(.headline)

            InspectorMetricGroup(metrics: [
                InspectorMetric(
                    id: "generated",
                    title: AppL10n.string("Generated %@", ReviewViewSupport.shortSha(model.reviewedHeadShaForDisplay)),
                    systemImage: "number",
                    tone: .neutral
                ),
                InspectorMetric(
                    id: "omitted",
                    title: AppL10n.string("%d omitted", summary.omittedFileCount),
                    systemImage: "eye.slash",
                    tone: summary.omittedFileCount > 0 ? .warning : .success
                )
            ])

            if summary.omittedFileCount > 0 {
                DisclosureGroup(AppL10n.string("Omitted files")) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summary.omittedFiles) { file in
                            Text(file.path)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(summary.omittedFileCount > 0 ? .warning : .success))
        }
    }
}
