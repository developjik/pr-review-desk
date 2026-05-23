import SwiftUI
import PRReviewDeskCore

struct ReviewCommandPanelView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedSection: ReviewInboxSection
    @Binding var isInspectorPresented: Bool
    @Binding var isPresented: Bool
    let onDeferredSubmit: () -> Void
    @State private var query = ""
    @State private var selectedActionID: String?

    init(
        model: AppModel,
        selectedSection: Binding<ReviewInboxSection>,
        isInspectorPresented: Binding<Bool>,
        isPresented: Binding<Bool>,
        initialQuery: String = "",
        initialSelectedActionID: String? = nil,
        onDeferredSubmit: @escaping () -> Void
    ) {
        self.model = model
        self._selectedSection = selectedSection
        self._isInspectorPresented = isInspectorPresented
        self._isPresented = isPresented
        self.onDeferredSubmit = onDeferredSubmit
        self._query = State(initialValue: initialQuery)
        self._selectedActionID = State(initialValue: initialSelectedActionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(AppL10n.string("Search actions"), text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    performSelectedAction()
                }

            if filteredActions.isEmpty {
                ContentUnavailableView(
                    AppL10n.string("No matching actions"),
                    systemImage: "command",
                    description: Text(AppL10n.string("Clear the action search to show every command."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredActions, selection: $selectedActionID) { action in
                    Button {
                        selectedActionID = action.id
                        perform(action)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: action.systemImage)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(action.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(ReviewWorkspaceLayoutPolicy.commandSubtitleLineLimit)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if let shortcut = action.shortcut {
                                Text(shortcut)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(
                                        minWidth: CGFloat(ReviewWorkspaceLayoutPolicy.commandShortcutMinimumWidth),
                                        alignment: .trailing
                                    )
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
                    .tag(action.id)
                    .listRowBackground(
                        selectedActionID == action.id
                            ? AppTheme.background(.focus)
                            : Color.clear
                    )
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .frame(width: 520, height: 520)
        .onAppear {
            syncSelectedAction()
        }
        .onChange(of: query) { _, _ in
            syncSelectedAction()
        }
        .onChange(of: actions.map { "\($0.id):\($0.isEnabled)" }) { _, _ in
            syncSelectedAction()
        }
    }

    private var filteredActions: [ReviewCommandPanelAction] {
        ReviewCommandPanelPresentation.filteredActions(actions, query: query)
    }

    private func syncSelectedAction() {
        selectedActionID = ReviewCommandPanelPresentation.selectedActionID(
            currentSelectionID: selectedActionID,
            filteredActions: filteredActions
        )
    }

    private var actions: [ReviewCommandPanelAction] {
        let availability = model.commandAvailability
        return [
            ReviewCommandPanelAction(title: AppL10n.string("Open PR"), subtitle: availability.canOpenPullRequest ? AppL10n.string("Open the selected pull request on GitHub.") : AppL10n.string("Select a pull request first."), systemImage: "arrow.up.right.square", shortcut: "⌘O", isEnabled: availability.canOpenPullRequest, kind: .openPullRequest),
            ReviewCommandPanelAction(title: AppL10n.string(model.aiReviewDraftActionPresentation.title), subtitle: AppL10n.string(model.aiReviewDraftActionPresentation.subtitle), systemImage: "sparkles", shortcut: "⇧⌘R", isEnabled: model.canGenerateReview, kind: .generateReview),
            ReviewCommandPanelAction(title: AppL10n.string("Regenerate Selected File"), subtitle: AppL10n.string("Not available yet; regenerate the full review."), systemImage: "doc.badge.gearshape", shortcut: nil, isEnabled: availability.canRegenerateSelectedFile, kind: .regenerateSelectedFile),
            ReviewCommandPanelAction(title: AppL10n.string("Submit Review"), subtitle: model.canPreviewReviewSubmission ? AppL10n.string("Preview the review body and selected inline comments before posting.") : AppL10n.string("Generate a valid AI review draft before submitting."), systemImage: "paperplane", shortcut: "⌘↩", isEnabled: model.canPreviewReviewSubmission, kind: .submitReview),
            ReviewCommandPanelAction(title: AppL10n.string("Reveal Inline Comment"), subtitle: availability.canRevealInlineComment ? AppL10n.string("Scroll the diff to the focused comment.") : AppL10n.string("Focus an inline comment first."), systemImage: "scope", shortcut: nil, isEnabled: availability.canRevealInlineComment, kind: .revealInlineComment),
            ReviewCommandPanelAction(title: AppL10n.string("Copy Codex Login Command"), subtitle: AppL10n.string("Copy the terminal command for Codex login."), systemImage: "doc.on.doc", shortcut: nil, isEnabled: availability.canCopyCodexLoginCommand, kind: .copyCodexLoginCommand),
            ReviewCommandPanelAction(title: AppL10n.string("Toggle Inspector"), subtitle: isInspectorPresented ? AppL10n.string("Hide draft and submit controls.") : AppL10n.string("Show draft and submit controls."), systemImage: "sidebar.trailing", shortcut: "⌥⌘I", isEnabled: availability.canToggleInspector, kind: .toggleInspector)
        ] + ReviewInboxSection.allCases.map { section in
            ReviewCommandPanelAction(
                title: AppL10n.string("Filter %@", AppL10n.string(section.displayName)),
                subtitle: AppL10n.string("Show %@ inbox items.", AppL10n.string(section.displayName)),
                systemImage: section.systemImage,
                shortcut: nil,
                isEnabled: true,
                kind: .selectSection(section)
            )
        }
    }

    private func perform(_ action: ReviewCommandPanelAction) {
        guard action.isEnabled else {
            return
        }

        switch action.kind {
        case .openPullRequest:
            model.openSelectedPullRequestInBrowser()
        case .generateReview:
            model.startGenerateReview()
        case .regenerateSelectedFile:
            model.statusMessage = "Selected-file regeneration is not available yet; regenerate the full review."
        case .submitReview:
            onDeferredSubmit()
            return
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

    private func performSelectedAction() {
        guard let action = ReviewCommandPanelPresentation.actionToPerform(
            selectedActionID: selectedActionID,
            filteredActions: filteredActions
        ) else {
            return
        }

        perform(action)
    }
}
