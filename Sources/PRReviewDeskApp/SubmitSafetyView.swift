import SwiftUI
import PRReviewDeskCore

struct SubmitSafetyView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let state = model.submitSafetyState

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    model.submitSafetyMessage,
                    systemImage: state.canSubmit ? "checkmark.shield" : "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(state.canSubmit ? AppTheme.foreground(.success) : AppTheme.foreground(.warning))
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if state.isStale {
                        Button {
                            model.startGenerateReview()
                        } label: {
                            Label(AppL10n.string("Regenerate"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!model.canGenerateReview)
                    }

                    Button {
                        Task {
                            await model.refreshSubmitSafety()
                        }
                    } label: {
                        Label(AppL10n.string("Refresh Safety"), systemImage: "shield.lefthalf.filled")
                    }
                    .disabled(model.isWorking)
                }
            }

            InspectorMetricGroup(metrics: [
                InspectorMetric(
                    id: "event",
                    title: AppL10n.string("Event %@", model.selectedEvent.localizedDisplayName),
                    systemImage: "arrow.triangle.branch",
                    tone: .neutral
                ),
                InspectorMetric(
                    id: "selected",
                    title: AppL10n.string("Selected %d", state.selectedInlineCommentCount),
                    systemImage: "text.bubble",
                    tone: .info
                ),
                InspectorMetric(
                    id: "invalid",
                    title: AppL10n.string("Invalid %d", state.invalidSelectedInlineComments.count),
                    systemImage: state.invalidSelectedInlineComments.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                    tone: state.invalidSelectedInlineComments.isEmpty ? .success : .invalid
                ),
                InspectorMetric(
                    id: "reviewed",
                    title: AppL10n.string("Reviewed %@", ReviewViewSupport.shortSha(state.reviewedHeadSha)),
                    systemImage: "number",
                    tone: .neutral
                ),
                InspectorMetric(
                    id: "current",
                    title: AppL10n.string("Current %@", ReviewViewSupport.shortSha(state.currentHeadSha)),
                    systemImage: "number",
                    tone: .neutral
                )
            ])
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(state.canSubmit ? AppTheme.border(.success) : AppTheme.border(.warning))
        }
    }
}
