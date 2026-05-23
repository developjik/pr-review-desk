import SwiftUI
import PRReviewDeskCore

struct ReviewControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.addSelectedPullRequestDraft()
            } label: {
                Label(AppL10n.string("Add Draft"), systemImage: "tray.and.arrow.down")
            }
            .disabled(!model.canAddDraftForSelectedPullRequest)
            .smokeAccessibilityIdentifier("review-controls.queue-pull-request")

            Button {
                model.openSelectedPullRequestInBrowser()
            } label: {
                Label(AppL10n.string("Open on GitHub"), systemImage: "arrow.up.right.square")
            }
            .disabled(model.selectedPullRequest == nil)

            if model.canCancelCurrentOperation {
                Button {
                    model.cancelCurrentOperation()
                } label: {
                    Label(AppL10n.string("Cancel Review Generation"), systemImage: "xmark.circle")
                }
                .keyboardShortcut(".", modifiers: [.command])
            }

            Spacer()
        }
        .controlSize(.small)
    }
}

struct AIReviewActionStripView: View {
    @ObservedObject var model: AppModel
    let pullRequest: PullRequest

    var body: some View {
        let presentation = model.aiReviewDraftActionPresentation

        VStack(alignment: .leading, spacing: 10) {
            PullRequestHeaderView(pullRequest: pullRequest)

            Divider()
                .padding(.vertical, 2)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Label(AppL10n.string("AI Review"), systemImage: "sparkles")
                            .font(.headline)
                        StatusBadge(
                            title: model.readinessChecklist.isReady ? AppL10n.string("Ready") : AppL10n.string("Needs setup"),
                            systemImage: model.readinessChecklist.isReady ? "checkmark.circle" : "exclamationmark.triangle",
                            tone: model.readinessChecklist.isReady ? .success : .warning
                        )
                    }

                    Text(AppL10n.string(presentation.subtitle))
                        .font(.subheadline)
                        .foregroundStyle(presentation.isEnabled ? .secondary : AppTheme.foreground(.warning))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    model.startGenerateReview()
                } label: {
                    Label(AppL10n.string(presentation.title), systemImage: presentation.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(presentation.isEnabled ? .accentColor : Color(nsColor: .disabledControlTextColor))
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!presentation.isEnabled)
                .help(AppL10n.string(presentation.subtitle))
            }

            if !model.readinessChecklist.isReady {
                ReadinessChecklistView(model: model, mode: .compact)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(model.readinessChecklist.isReady ? .info : .warning))
        }
    }
}
