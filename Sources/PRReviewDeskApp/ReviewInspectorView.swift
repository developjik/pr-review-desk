import SwiftUI
import PRReviewDeskCore

struct ReviewInspectorView: View {
    @ObservedObject var model: AppModel

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
                    }

                    DraftEditorView(model: model)

                    if model.draft != nil {
                        Button(role: .destructive) {
                            model.discardCurrentDraft()
                        } label: {
                            Label(AppL10n.string("Discard Draft"), systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .background(.bar)
    }
}

private struct ReviewEventSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(AppL10n.string("Review event"), selection: $model.selectedEvent) {
                ForEach(ReviewEvent.allCases) { event in
                    Text(event.localizedDisplayName).tag(event)
                }
            }
            .pickerStyle(.segmented)

            Button {
                model.requestSubmitReview()
            } label: {
                Label("\(AppL10n.string("Submit Review")) (\(model.selectedInlineCommentCount))", systemImage: "paperplane")
            }
            .disabled(!model.canSubmitReview)
            .confirmationDialog(
                AppL10n.string("Submit %@ review?", model.selectedEvent.localizedDisplayName),
                isPresented: $model.isSubmitConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(AppL10n.string("Submit %@ Review", model.selectedEvent.localizedDisplayName)) {
                    Task {
                        await model.submitReview()
                    }
                }
                Button(AppL10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text(AppL10n.string(
                    "This will post a %@ review with %d selected inline comments to GitHub.",
                    model.selectedEvent.localizedDisplayName,
                    model.selectedInlineCommentCount
                ))
            }
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

            HStack(spacing: 8) {
                StatusBadge(title: AppL10n.string("Generated %@", ReviewViewSupport.shortSha(model.reviewedHeadShaForDisplay)), systemImage: "number", tone: .neutral)
                StatusBadge(title: AppL10n.string("%d omitted", summary.omittedFileCount), systemImage: "eye.slash", tone: summary.omittedFileCount > 0 ? .warning : .success)
            }

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
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(summary.omittedFileCount > 0 ? .warning : .success))
        }
    }
}
