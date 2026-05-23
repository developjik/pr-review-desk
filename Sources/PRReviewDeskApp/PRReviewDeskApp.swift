import Foundation
import SwiftUI
import PRReviewDeskCore

@main
struct PRReviewDeskApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    init() {
        if CommandLine.arguments.contains("--ui-smoke-localization") {
            let language = CommandLine.arguments.last == "--ui-smoke-localization" ? "en" : CommandLine.arguments.last ?? "en"
            print("localized_sample=submit-preview-title:\(Self.localizedString("Submit Review Preview", language: language))")
            Foundation.exit(0)
        }

        if CommandLine.arguments.contains("--ui-smoke-command-interaction") {
            let report = MainActor.assumeIsolated {
                UISmokeRenderRunner.commandPanelInteractionReport()
            }
            print(report)
            Foundation.exit(0)
        }

        if CommandLine.arguments.contains("--ui-smoke") {
            let report = MainActor.assumeIsolated {
                UISmokeRenderRunner.run()
            }
            print(report)
            Foundation.exit(0)
        }
    }

    private static func localizedString(_ key: String, language: String) -> String {
        guard let languageBundlePath = Bundle.module.path(forResource: language, ofType: "lproj"),
              let languageBundle = Bundle(path: languageBundlePath) else {
            return AppL10n.string(key)
        }

        return languageBundle.localizedString(forKey: key, value: nil, table: nil)
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
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canPreviewReviewSubmission)

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
