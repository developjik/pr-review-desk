import SwiftUI
import PRReviewDeskCore

@main
struct PRReviewDeskApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 1180, minHeight: 720)
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    model.loadStoredToken()
                    if model.hasToken {
                        await model.refreshRepositories()
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu(AppL10n.string("Review")) {
                Button(AppL10n.string("Refresh")) {
                    Task {
                        await model.refreshActiveScope()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRefreshActiveScope)

                Button(AppL10n.string("Generate AI Review Draft")) {
                    model.startGenerateReview()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.canGenerateReview)

                Button(AppL10n.string("Cancel")) {
                    model.cancelCurrentOperation()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canCancelCurrentOperation)

                Divider()

                Button(AppL10n.string("Submit Review")) {
                    model.requestSubmitReview()
                }
                .disabled(!model.canSubmitReview)

                Button(AppL10n.string("Open PR")) {
                    model.openSelectedPullRequestInBrowser()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(!model.commandAvailability.canOpenPullRequest)

                Divider()

                Button(AppL10n.string("Next Inline Comment")) {
                    model.focusNextInlineComment()
                }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(model.draft?.inlineComments.isEmpty ?? true)

                Button(AppL10n.string("Previous Inline Comment")) {
                    model.focusPreviousInlineComment()
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(model.draft?.inlineComments.isEmpty ?? true)

                Button(AppL10n.string("Next File")) {
                    model.selectNextChangedFile()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(model.changedFiles.isEmpty)

                Button(AppL10n.string("Previous File")) {
                    model.selectPreviousChangedFile()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(model.changedFiles.isEmpty)

                Button(AppL10n.string("Next Hunk")) {
                    model.focusNextHunk()
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(model.selectedChangedFile == nil)

                Button(AppL10n.string("Previous Hunk")) {
                    model.focusPreviousHunk()
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(model.selectedChangedFile == nil)

                Button(AppL10n.string("Reveal Inline Comment")) {
                    model.revealFocusedInlineComment()
                }
                .disabled(!model.commandAvailability.canRevealInlineComment)

                Divider()

                Button(AppL10n.string("Copy Codex Login Command")) {
                    model.copyCodexLoginCommand()
                }
            }
        }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
