import SwiftUI
import PRReviewDeskCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @SceneStorage("main.selectedInboxSection.v4") private var selectedInboxSectionRaw = ReviewWorkspaceLayoutPolicy.defaultInboxSection.rawValue
    @SceneStorage("main.inspectorPresented.v3") private var isInspectorPresented = ReviewWorkspaceLayoutPolicy.defaultInspectorVisibility
    @State private var isCommandPanelPresented = false

    var body: some View {
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
                selectedSection: selectedInboxSection
            )
            .navigationSplitViewColumnWidth(
                min: CGFloat(ReviewWorkspaceLayoutPolicy.pullRequestListMinimumColumnWidth),
                ideal: CGFloat(ReviewWorkspaceLayoutPolicy.pullRequestListIdealColumnWidth),
                max: CGFloat(ReviewWorkspaceLayoutPolicy.pullRequestListMaximumColumnWidth)
            )
        } detail: {
            ReviewPaneView(model: model)
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
        .toolbar {
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
                .disabled(!model.canSubmitReview)
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
                onCancel: {
                    model.isSubmitConfirmationPresented = false
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
            if ReviewWorkspaceLayoutPolicy.shouldOpenInspectorAfterDraftGeneration(
                previousRevision: previousRevision,
                currentRevision: currentRevision
            ) {
                isInspectorPresented = true
            }
        }
    }

    private var selectedInboxSection: ReviewInboxSection {
        ReviewInboxSection(rawValue: selectedInboxSectionRaw) ?? .draftReady
    }

    private var selectedInboxSectionBinding: Binding<ReviewInboxSection> {
        Binding(
            get: { selectedInboxSection },
            set: { selectedInboxSectionRaw = $0.rawValue }
        )
    }
}
