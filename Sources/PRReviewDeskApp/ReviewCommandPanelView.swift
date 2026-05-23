import SwiftUI
import PRReviewDeskCore

struct ReviewCommandPanelView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedSection: ReviewInboxSection
    @Binding var isInspectorPresented: Bool
    @Binding var isPresented: Bool
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(AppL10n.string("Search actions"), text: $query)
                .textFieldStyle(.roundedBorder)

            List(filteredActions) { action in
                Button {
                    perform(action)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: action.systemImage)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .fontWeight(.medium)
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let shortcut = action.shortcut {
                            Text(shortcut)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!action.isEnabled)
            }
            .listStyle(.inset)
        }
        .padding()
        .frame(width: 520, height: 520)
    }

    private var filteredActions: [ReviewCommandAction] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return actions
        }

        return actions.filter {
            $0.title.lowercased().contains(normalizedQuery)
        }
    }

    private var actions: [ReviewCommandAction] {
        let availability = model.commandAvailability
        return [
            ReviewCommandAction(title: AppL10n.string("Open PR"), subtitle: availability.canOpenPullRequest ? AppL10n.string("Open the selected pull request on GitHub.") : AppL10n.string("Select a pull request first."), systemImage: "arrow.up.right.square", shortcut: "O", isEnabled: availability.canOpenPullRequest, kind: .openPullRequest),
            ReviewCommandAction(title: AppL10n.string(model.aiReviewDraftActionPresentation.title), subtitle: AppL10n.string(model.aiReviewDraftActionPresentation.subtitle), systemImage: "sparkles", shortcut: "⇧⌘R", isEnabled: model.canGenerateReview, kind: .generateReview),
            ReviewCommandAction(title: AppL10n.string("Regenerate Selected File"), subtitle: AppL10n.string("Not available yet; regenerate the full review."), systemImage: "doc.badge.gearshape", shortcut: nil, isEnabled: availability.canRegenerateSelectedFile, kind: .regenerateSelectedFile),
            ReviewCommandAction(title: AppL10n.string("Submit Review"), subtitle: model.canSubmitReview ? AppL10n.string("Submit the selected comments and review body.") : AppL10n.string("Generate a valid AI review draft before submitting."), systemImage: "paperplane", shortcut: nil, isEnabled: model.canSubmitReview, kind: .submitReview),
            ReviewCommandAction(title: AppL10n.string("Reveal Inline Comment"), subtitle: availability.canRevealInlineComment ? AppL10n.string("Scroll the diff to the focused comment.") : AppL10n.string("Focus an inline comment first."), systemImage: "scope", shortcut: nil, isEnabled: availability.canRevealInlineComment, kind: .revealInlineComment),
            ReviewCommandAction(title: AppL10n.string("Copy Codex Login Command"), subtitle: AppL10n.string("Copy the terminal command for Codex login."), systemImage: "doc.on.doc", shortcut: nil, isEnabled: availability.canCopyCodexLoginCommand, kind: .copyCodexLoginCommand),
            ReviewCommandAction(title: AppL10n.string("Toggle Inspector"), subtitle: isInspectorPresented ? AppL10n.string("Hide draft and submit controls.") : AppL10n.string("Show draft and submit controls."), systemImage: "sidebar.trailing", shortcut: nil, isEnabled: availability.canToggleInspector, kind: .toggleInspector)
        ] + ReviewInboxSection.allCases.map { section in
            ReviewCommandAction(
                title: AppL10n.string("Filter %@", AppL10n.string(section.displayName)),
                subtitle: AppL10n.string("Show %@ inbox items.", AppL10n.string(section.displayName)),
                systemImage: section.systemImage,
                shortcut: nil,
                isEnabled: true,
                kind: .selectSection(section)
            )
        }
    }

    private func perform(_ action: ReviewCommandAction) {
        switch action.kind {
        case .openPullRequest:
            model.openSelectedPullRequestInBrowser()
        case .generateReview:
            model.startGenerateReview()
        case .regenerateSelectedFile:
            model.statusMessage = "Selected-file regeneration is not available yet; regenerate the full review."
        case .submitReview:
            model.requestSubmitReview()
        case .revealInlineComment:
            model.revealFocusedInlineComment()
        case .copyCodexLoginCommand:
            model.copyCodexLoginCommand()
        case .toggleInspector:
            isInspectorPresented.toggle()
        case let .selectSection(section):
            selectedSection = section
        }
        isPresented = false
    }
}

private struct ReviewCommandAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let shortcut: String?
    let isEnabled: Bool
    let kind: ReviewCommandActionKind
}

private enum ReviewCommandActionKind {
    case openPullRequest
    case generateReview
    case regenerateSelectedFile
    case submitReview
    case revealInlineComment
    case copyCodexLoginCommand
    case toggleInspector
    case selectSection(ReviewInboxSection)
}
