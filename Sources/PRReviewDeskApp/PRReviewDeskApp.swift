import Foundation
import SwiftUI
import PRReviewDeskCore

@main
struct PRReviewDeskApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var language: AppLanguage {
        AppLanguage.preferred(from: languageRawValue)
    }

    private var locale: Locale {
        guard let localizationIdentifier = language.localizationIdentifier else {
            return .current
        }

        return Locale(identifier: localizationIdentifier)
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

        if CommandLine.arguments.contains("--ui-smoke-command-keyboard") {
            let report = MainActor.assumeIsolated {
                UISmokeRenderRunner.commandPanelKeyboardReport()
            }
            print(report)
            Foundation.exit(0)
        }

        if CommandLine.arguments.contains("--ui-smoke-command-selection-visual") {
            let report = MainActor.assumeIsolated {
                UISmokeRenderRunner.commandPanelSelectionVisualReport()
            }
            print(report)
            Foundation.exit(0)
        }

        if let smokeLanguageSwitch = Self.commandLineArgument(after: "--ui-smoke-language-switch-defaults") {
            let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
            UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
            let report = MainActor.assumeIsolated {
                let model = AppModel()
                UserDefaults.standard.set(smokeLanguageSwitch, forKey: AppLanguage.storageKey)
                model.refreshLocalizedDefaults()
                return [
                    "language_switch_default=credentialKindDescription:\(model.credentialKindDescription)",
                    "language_switch_default=tokenValidationStatus:\(model.tokenValidationStatus)",
                    "language_switch_default=codexCLIStatus:\(model.codexCLIStatus)",
                    "language_switch_default=codexLoginStatus:\(model.codexLoginStatus)"
                ].joined(separator: "\n")
            }
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            }
            print(report)
            Foundation.exit(0)
        }

        if CommandLine.arguments.contains("--ui-smoke-layout-contract") {
            let report = MainActor.assumeIsolated {
                UISmokeRenderRunner.layoutContractReport()
            }
            print(report)
            Foundation.exit(0)
        }

        if CommandLine.arguments.contains("--ui-smoke-accessibility-contract") {
            let report = MainActor.assumeIsolated {
                UISmokeRenderRunner.accessibilityReport()
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

    private static func commandLineArgument(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return arguments[valueIndex]
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainView(model: model)
                    .id(languageRawValue)
            }
                .frame(minWidth: 1180, minHeight: 720)
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, locale)
                .task {
                    await model.restoreGitHubSessionOnLaunchIfNeeded()
                }
                .onChange(of: languageRawValue) { _, _ in
                    model.refreshLocalizedDefaults()
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

                Button(AppL10n.string("Cancel Review Generation")) {
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
                .environment(\.locale, locale)
                .id(languageRawValue)
        }
    }
}
