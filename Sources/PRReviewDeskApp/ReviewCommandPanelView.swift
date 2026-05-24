import SwiftUI
import PRReviewDeskCore

private struct ReviewCommandPanelActionGroup: Identifiable {
    let title: String
    let actions: [ReviewCommandPanelAction]

    var id: String { title }
}

struct ReviewCommandPanelView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedSection: ReviewInboxSection
    @Binding var isInspectorPresented: Bool
    @Binding var isPresented: Bool
    let onDeferredSubmit: () -> Void
    @State private var query = ""
    @State private var selectedActionID: String?
    @FocusState private var isSearchFocused: Bool

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
                .smokeAccessibilityIdentifier("command-panel.search")
                .focused($isSearchFocused)
                .onSubmit {
                    performSelectedAction()
                }
                .onKeyPress(.downArrow) {
                    moveSelection(offset: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(offset: -1)
                    return .handled
                }

            if filteredActions.isEmpty {
                ContentUnavailableView(
                    AppL10n.string("No matching actions"),
                    systemImage: "command",
                    description: Text(AppL10n.string("Clear the action search to show commands with next-step guidance."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedActionID) {
                    ForEach(filteredActionGroups) { group in
                        Section(AppL10n.string(group.title)) {
                            ForEach(group.actions) { action in
                                actionRow(action)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .frame(width: 520, height: 640)
        .focusable()
        .onExitCommand {
            isPresented = false
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                moveSelection(offset: 1)
            case .up:
                moveSelection(offset: -1)
            default:
                break
            }
        }
        .onAppear {
            syncSelectedAction()
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in
            syncSelectedAction()
        }
        .onChange(of: actions.map { "\($0.id):\($0.isEnabled)" }) { _, _ in
            syncSelectedAction()
        }
    }

    private var filteredActions: [ReviewCommandPanelAction] {
        filteredActionGroups.flatMap(\.actions)
    }

    private var filteredActionGroups: [ReviewCommandPanelActionGroup] {
        actionGroups.compactMap { group in
            let filtered = ReviewCommandPanelPresentation.visibleActions(group.actions, query: query)
            guard !filtered.isEmpty else {
                return nil
            }

            return ReviewCommandPanelActionGroup(title: group.title, actions: filtered)
        }
    }

    private func syncSelectedAction() {
        selectedActionID = ReviewCommandPanelPresentation.selectedActionID(
            currentSelectionID: selectedActionID,
            filteredActions: filteredActions
        )
    }

    private var actions: [ReviewCommandPanelAction] {
        actionGroups.flatMap(\.actions)
    }

    private var actionGroups: [ReviewCommandPanelActionGroup] {
        let availability = model.commandAvailability
        let hasInlineComments = !(model.draft?.inlineComments.isEmpty ?? true)
        let hasChangedFiles = !model.changedFiles.isEmpty
        let hasSelectedFile = model.selectedChangedFile != nil
        var reviewActions = [
            ReviewCommandPanelAction(title: AppL10n.string("Refresh"), subtitle: availability.canRefreshActiveScope ? AppL10n.string("Load repositories or refresh the selected pull request.") : AppL10n.string("Sign in with GitHub before refreshing."), systemImage: "arrow.clockwise", shortcut: "⌘R", isEnabled: availability.canRefreshActiveScope, kind: .refreshActiveScope),
            ReviewCommandPanelAction(title: AppL10n.string("Open PR"), subtitle: availability.canOpenPullRequest ? AppL10n.string("Open the selected pull request on GitHub.") : AppL10n.string("Select a pull request first."), systemImage: "arrow.up.right.square", shortcut: "⌘O", isEnabled: availability.canOpenPullRequest, kind: .openPullRequest),
            ReviewCommandPanelAction(title: AppL10n.string(model.aiReviewDraftActionPresentation.title), subtitle: AppL10n.string(model.aiReviewDraftActionPresentation.subtitle), systemImage: "sparkles", shortcut: "⇧⌘R", isEnabled: model.canGenerateReview, kind: .generateReview),
            ReviewCommandPanelAction(title: AppL10n.string("Cancel Review Generation"), subtitle: AppL10n.string("Stop the current review draft generation."), systemImage: "xmark.circle", shortcut: "⌘.", isEnabled: availability.canCancelCurrentOperation, kind: .cancelReviewGeneration),
            ReviewCommandPanelAction(title: AppL10n.string("Submit Review"), subtitle: model.canPreviewReviewSubmission ? AppL10n.string("Preview the review body and selected inline comments before posting.") : AppL10n.string("Generate a valid AI review draft before submitting."), systemImage: "paperplane", shortcut: "⌘↩", isEnabled: model.canPreviewReviewSubmission, kind: .submitReview)
        ]

        if availability.canRegenerateSelectedFile {
            reviewActions.insert(
                ReviewCommandPanelAction(title: AppL10n.string("Regenerate Selected File"), subtitle: AppL10n.string("Replace the selected file's comments with a fresh draft."), systemImage: "doc.badge.gearshape", shortcut: nil, isEnabled: true, kind: .regenerateSelectedFile),
                at: 3
            )
        }

        return [
            ReviewCommandPanelActionGroup(title: "Review Actions", actions: reviewActions),
            ReviewCommandPanelActionGroup(title: "Draft Lists", actions: [
                ReviewCommandPanelAction(title: AppL10n.string("Add Draft"), subtitle: model.canAddDraftForSelectedPullRequest ? AppL10n.string("Create a local draft for the selected pull request.") : AppL10n.string("Select a pull request before adding a draft."), systemImage: "tray.and.arrow.down", shortcut: nil, isEnabled: model.canAddDraftForSelectedPullRequest, kind: .queueSelectedPullRequest),
                ReviewCommandPanelAction(title: AppL10n.string("Add Repository Drafts"), subtitle: model.canAddDraftsForSelectedRepository ? AppL10n.string("Create local drafts for all open pull requests in this repository.") : AppL10n.string("Select a repository with open pull requests before adding drafts."), systemImage: "tray.full", shortcut: nil, isEnabled: model.canAddDraftsForSelectedRepository, kind: .queueSelectedRepository)
            ]),
            ReviewCommandPanelActionGroup(title: "Navigation", actions: [
            ReviewCommandPanelAction(title: AppL10n.string("Next Inline Comment"), subtitle: hasInlineComments ? AppL10n.string("Move to the next generated inline comment.") : AppL10n.string("Generate a draft with inline comments first."), systemImage: "text.bubble", shortcut: "⌘]", isEnabled: hasInlineComments, kind: .nextInlineComment),
            ReviewCommandPanelAction(title: AppL10n.string("Previous Inline Comment"), subtitle: hasInlineComments ? AppL10n.string("Move to the previous generated inline comment.") : AppL10n.string("Generate a draft with inline comments first."), systemImage: "text.bubble", shortcut: "⌘[", isEnabled: hasInlineComments, kind: .previousInlineComment),
            ReviewCommandPanelAction(title: AppL10n.string("Next File"), subtitle: hasChangedFiles ? AppL10n.string("Move to the next changed file.") : AppL10n.string("Load pull request files first."), systemImage: "doc.on.doc", shortcut: "⇧⌘]", isEnabled: hasChangedFiles, kind: .nextFile),
            ReviewCommandPanelAction(title: AppL10n.string("Previous File"), subtitle: hasChangedFiles ? AppL10n.string("Move to the previous changed file.") : AppL10n.string("Load pull request files first."), systemImage: "doc.on.doc", shortcut: "⇧⌘[", isEnabled: hasChangedFiles, kind: .previousFile),
            ReviewCommandPanelAction(title: AppL10n.string("Next Change Block"), subtitle: hasSelectedFile ? AppL10n.string("Move to the next changed block in the selected file.") : AppL10n.string("Select a changed file first."), systemImage: "arrow.down.to.line", shortcut: "⌥⌘]", isEnabled: hasSelectedFile, kind: .nextHunk),
            ReviewCommandPanelAction(title: AppL10n.string("Previous Change Block"), subtitle: hasSelectedFile ? AppL10n.string("Move to the previous changed block in the selected file.") : AppL10n.string("Select a changed file first."), systemImage: "arrow.up.to.line", shortcut: "⌥⌘[", isEnabled: hasSelectedFile, kind: .previousHunk),
            ReviewCommandPanelAction(title: AppL10n.string("Reveal Inline Comment"), subtitle: availability.canRevealInlineComment ? AppL10n.string("Show the focused comment in the changes.") : AppL10n.string("Focus an inline comment first."), systemImage: "scope", shortcut: nil, isEnabled: availability.canRevealInlineComment, kind: .revealInlineComment),
            ]),
            ReviewCommandPanelActionGroup(title: "View", actions: [
                ReviewCommandPanelAction(title: AppL10n.string("Toggle Inspector"), subtitle: isInspectorPresented ? AppL10n.string("Hide draft and submit controls.") : AppL10n.string("Show draft and submit controls."), systemImage: "sidebar.trailing", shortcut: "⌥⌘I", isEnabled: availability.canToggleInspector, kind: .toggleInspector)
            ]),
            ReviewCommandPanelActionGroup(title: "Inbox Filters", actions: ReviewInboxSidebarPresentation.sections.map { section in
                ReviewCommandPanelAction(
                    title: AppL10n.string("Filter %@", AppL10n.string(section.displayName)),
                    subtitle: AppL10n.string("Show %@ inbox items.", AppL10n.string(section.displayName)),
                    systemImage: section.systemImage,
                    shortcut: nil,
                    isEnabled: true,
                    kind: .selectSection(section)
                )
            })
        ]
    }

    private var isGitHubAccessReady: Bool {
        model.readinessChecklist.items
            .filter { $0.id == .githubCredential || $0.id == .githubTokenValidation }
            .allSatisfy { $0.state == .ready }
    }

    private var isCodexReady: Bool {
        model.readinessChecklist.items
            .filter { $0.id == .codexCLI }
            .allSatisfy { $0.state == .ready }
    }

    private func actionRow(_ action: ReviewCommandPanelAction) -> some View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                selectedActionID == action.id
                    ? Color(nsColor: .systemBlue).opacity(0.12)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                if selectedActionID == action.id {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .systemBlue).opacity(0.55), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .smokeAccessibilityIdentifier(
            "command-panel.action.\(action.id)",
            state: accessibilityState(for: action),
            details: accessibilityHint(for: action)
        )
        .accessibilityLabel(action.title)
        .accessibilityHint(accessibilityHint(for: action))
        .accessibilityValue(selectedActionID == action.id ? AppL10n.string("Selected") : "")
        .accessibilityAddTraits(selectedActionID == action.id ? [.isSelected] : [])
        .disabled(!action.isEnabled)
        .tag(action.id)
        .listRowBackground(Color.clear)
    }

    private func perform(_ action: ReviewCommandPanelAction) {
        guard action.isEnabled else {
            return
        }

        switch action.kind {
        case .refreshActiveScope:
            Task {
                await model.refreshActiveScope()
            }
        case .openPullRequest:
            model.openSelectedPullRequestInBrowser()
        case .generateReview:
            model.startGenerateReview()
        case .cancelReviewGeneration:
            model.cancelCurrentOperation()
        case .queueSelectedPullRequest:
            model.addSelectedPullRequestDraft()
        case .queueSelectedRepository:
            model.addSelectedRepositoryDrafts()
        case .regenerateSelectedFile:
            model.statusMessage = AppL10n.string("Selected-file regeneration is not available yet; regenerate the full review.")
        case .submitReview:
            onDeferredSubmit()
            return
        case .nextInlineComment:
            model.focusNextInlineComment()
        case .previousInlineComment:
            model.focusPreviousInlineComment()
        case .nextFile:
            model.selectNextChangedFile()
        case .previousFile:
            model.selectPreviousChangedFile()
        case .nextHunk:
            model.focusNextHunk()
        case .previousHunk:
            model.focusPreviousHunk()
        case .revealInlineComment:
            model.revealFocusedInlineComment()
        case .startGitHubSignIn:
            model.startOAuthDeviceSignIn()
        case .validateGitHubAccess:
            Task {
                await model.validateCurrentToken()
            }
        case .checkCodexReadiness:
            Task {
                await model.refreshCodexCLIStatus()
            }
        case .copyCodexLoginCommand:
            model.copyCodexLoginCommand()
        case .openCodexLoginTerminal:
            model.openTerminalForCodexLogin()
        case .acknowledgePrivacyDisclosure:
            model.acknowledgePrivacyDisclosure()
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

    private func moveSelection(offset: Int) {
        selectedActionID = ReviewCommandPanelPresentation.movedSelectionID(
            currentSelectionID: selectedActionID,
            filteredActions: filteredActions,
            offset: offset
        )
    }

    private func accessibilityState(for action: ReviewCommandPanelAction) -> String {
        if !action.isEnabled {
            return "disabled"
        }

        if selectedActionID == action.id {
            return "selected"
        }

        return "enabled"
    }

    private func accessibilityHint(for action: ReviewCommandPanelAction) -> String {
        guard let shortcut = action.shortcut else {
            return action.subtitle
        }

        return "\(action.subtitle) \(AppL10n.string("Shortcut: %@", shortcut))"
    }
}
