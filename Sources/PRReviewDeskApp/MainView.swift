import SwiftUI
import PRReviewDeskCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @SceneStorage("main.selectedInboxSection") private var selectedInboxSectionRaw = ReviewInboxSection.draftReady.rawValue
    @SceneStorage("main.inspectorPresented.v3") private var isInspectorPresented = ReviewWorkspaceLayoutPolicy.defaultInspectorVisibility
    @State private var isCommandPanelPresented = false

    var body: some View {
        NavigationSplitView {
            ReviewInboxSidebarView(
                model: model,
                selectedSection: selectedInboxSectionBinding
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } content: {
            ReviewInboxView(
                model: model,
                selectedSection: selectedInboxSection
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
        } detail: {
            ReviewPaneView(model: model)
                .inspector(isPresented: $isInspectorPresented) {
                    ReviewInspectorView(model: model)
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
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
                isPresented: $isCommandPanelPresented
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
