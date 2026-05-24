import SwiftUI
import PRReviewDeskCore

extension Notification.Name {
    static let openReviewCommandPanel = Notification.Name("PRReviewDesk.openReviewCommandPanel")
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @SceneStorage("main.selectedInboxSection.v4") private var selectedInboxSectionRaw = ReviewWorkspaceLayoutPolicy.defaultInboxSection.rawValue
    @SceneStorage("main.inspectorPresented.v3") private var isInspectorPresented = ReviewWorkspaceLayoutPolicy.defaultInspectorVisibility
    @State private var isCommandPanelPresented = false

    var body: some View {
        content
            .toolbar {
                toolbarContent
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if let recoverableError = model.recoverableError {
                        RecoverableErrorPanel(
                            error: recoverableError,
                            onDismiss: {
                                model.dismissRecoverableError()
                            }
                        )
                    }
                    StatusBarView(model: model)
                }
            }
            .sheet(isPresented: $isCommandPanelPresented) {
                ReviewCommandPanelView(
                    model: model,
                    selectedSection: selectedInboxSectionBinding,
                    isInspectorPresented: $isInspectorPresented,
                    isPresented: $isCommandPanelPresented,
                    onDeferredSubmit: {
                        isCommandPanelPresented = false
                        Task { @MainActor in
                            await Task.yield()
                            model.requestSubmitReview()
                        }
                    }
                )
            }
            .sheet(item: $model.pendingPrivateRepositoryConsent) { request in
                PrivateRepositoryConsentSheet(
                    request: request,
                    onCancel: {
                        model.cancelPrivateRepositoryConsent()
                    },
                    onAcknowledge: {
                        model.confirmPrivateRepositoryConsentAndGenerate()
                    }
                )
            }
            .sheet(isPresented: $model.isSubmitConfirmationPresented) {
                ReviewSubmissionPreviewSheet(
                    preview: model.submissionPreview,
                    eventDisplayName: model.selectedEvent.localizedDisplayName,
                    isRefreshingSafety: model.isWorking,
                    onCancel: {
                        model.isSubmitConfirmationPresented = false
                    },
                    onRefreshSafety: {
                        Task {
                            await model.refreshSubmitSafety()
                        }
                    },
                    onRegenerate: {
                        model.isSubmitConfirmationPresented = false
                        model.startGenerateReview()
                    },
                    onRevealInvalidComment: { comment in
                        model.isSubmitConfirmationPresented = false
                        model.revealInlineComment(path: comment.path, position: comment.position)
                        isInspectorPresented = true
                    },
                    onDeselectInvalidComment: { comment in
                        model.deselectInlineComment(path: comment.path, position: comment.position)
                    },
                    onSubmit: {
                        model.isSubmitConfirmationPresented = false
                        Task {
                            await model.submitReview()
                        }
                    }
                )
            }
            .onChange(of: model.generatedDraftPresentationRevision) { previousRevision, currentRevision in
                if isReviewWorkspace,
                   ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(
                    previousRevision: previousRevision,
                    currentRevision: currentRevision
                   ) {
                    isInspectorPresented = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openReviewCommandPanel)) { _ in
                if isReviewWorkspace {
                    isCommandPanelPresented = true
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isReviewWorkspace {
            reviewWorkspace
        } else {
            SetupRequiredView(model: model)
        }
    }

    private var reviewWorkspace: some View {
        NavigationSplitView {
            ReviewInboxSidebarView(
                model: model,
                selectedSection: selectedInboxSectionBinding
            )
            .navigationSplitViewColumnWidth(
                min: CGFloat(ReviewWorkspaceLayoutPolicy.inboxSidebarMinimumColumnWidth),
                ideal: CGFloat(ReviewWorkspaceLayoutPolicy.inboxSidebarIdealColumnWidth),
                max: 340
            )
        } content: {
            ReviewInboxView(
                model: model,
                selectedSection: selectedInboxSectionBinding
            )
            .navigationSplitViewColumnWidth(
                min: CGFloat(ReviewWorkspaceLayoutPolicy.pullRequestListMinimumColumnWidth),
                ideal: CGFloat(ReviewWorkspaceLayoutPolicy.pullRequestListIdealColumnWidth),
                max: CGFloat(ReviewWorkspaceLayoutPolicy.pullRequestListMaximumColumnWidth)
            )
        } detail: {
            ReviewPaneView(model: model) {
                isInspectorPresented = true
            }
                .inspector(isPresented: $isInspectorPresented) {
                    ReviewInspectorView(model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .inspectorColumnWidth(
                            min: CGFloat(ReviewWorkspaceLayoutPolicy.inspectorMinimumColumnWidth),
                            ideal: CGFloat(ReviewWorkspaceLayoutPolicy.inspectorIdealColumnWidth),
                            max: CGFloat(ReviewWorkspaceLayoutPolicy.inspectorMaximumColumnWidth)
                        )
                }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(
            text: $model.pullRequestSearchText,
            placement: .toolbar,
            prompt: AppL10n.string("Search pull requests")
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isReviewWorkspace {
            ToolbarItemGroup {
                Button {
                    isCommandPanelPresented = true
                } label: {
                    Label(AppL10n.string("Actions"), systemImage: "command")
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button {
                    Task {
                        await model.refreshActiveScope()
                    }
                } label: {
                    Label(AppL10n.string("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(!model.canRefreshActiveScope)

                Button {
                    model.startGenerateReview()
                } label: {
                    Label(AppL10n.string("Generate AI Review Draft"), systemImage: "sparkles")
                }
                .disabled(!model.canGenerateReview)

                Button {
                    model.requestSubmitReview()
                } label: {
                    Label(AppL10n.string("Submit Review"), systemImage: "paperplane")
                }
                .disabled(!model.canPreviewReviewSubmission)
                .keyboardShortcut(.return, modifiers: [.command])

                if model.canCancelCurrentOperation {
                    Button {
                        model.cancelCurrentOperation()
                    } label: {
                        Label(AppL10n.string("Cancel"), systemImage: "xmark.circle")
                    }
                }

                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label(AppL10n.string("Toggle Inspector"), systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                SettingsLink {
                    Label(AppL10n.string("Settings"), systemImage: "gear")
                }
            }
        } else {
            ToolbarItemGroup {
                SettingsLink {
                    Label(AppL10n.string("Open Settings"), systemImage: "gear")
                }
            }
        }
    }

    private var isReviewWorkspace: Bool {
        model.settingsGatePresentation.destination == .reviewWorkspace
    }

    private var selectedInboxSection: ReviewInboxSection {
        let storedSection = ReviewInboxSection(rawValue: selectedInboxSectionRaw) ?? ReviewWorkspaceLayoutPolicy.defaultInboxSection
        return ReviewWorkspaceLayoutPolicy.effectiveInboxSection(
            storedSection: storedSection,
            isReady: model.readinessChecklist.isReady
        )
    }

    private var selectedInboxSectionBinding: Binding<ReviewInboxSection> {
        Binding(
            get: { selectedInboxSection },
            set: { selectedInboxSectionRaw = $0.rawValue }
        )
    }
}
