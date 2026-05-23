import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage.preferred(from: languageRawValue) },
            set: { languageRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(AppL10n.string("Appearance")) {
                Picker(AppL10n.string("Appearance"), selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Picker(AppL10n.string("Language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .smokeAccessibilityIdentifier("settings.language")
            }

            Section(AppL10n.string("Readiness")) {
                ReadinessChecklistView(model: model, mode: .detailed)
            }

            Section(AppL10n.string("GitHub")) {
                HStack {
                    Text(AppL10n.string("GitHub sign-in"))
                    Spacer()
                    Text(model.hasToken ? AppL10n.string("Loaded") : AppL10n.string("Not loaded"))
                        .foregroundStyle(model.hasToken ? AppTheme.foreground(.success) : .secondary)
                }

                HStack {
                    Text(AppL10n.string("Sign-in type"))
                    Spacer()
                    Text(model.credentialKindDescription)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text(AppL10n.string("GitHub access"))
                    Spacer()
                    Text(grantedScopesSummary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }

                if !model.grantedGitHubScopes.isEmpty {
                    grantedScopesDisclosure
                }

                Text(AppL10n.string("Sign in with GitHub to authorize repository review access."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        model.startOAuthDeviceSignIn()
                    } label: {
                        Label(
                            model.hasToken ? AppL10n.string("Reconnect GitHub Sign-In") : AppL10n.string("Sign in with GitHub"),
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(AppL10n.string("Opens GitHub sign-in and then checks repository access."))
                    .disabled(model.isOAuthSignInPending)
                    .smokeAccessibilityIdentifier("settings.github.oauth")

                    if model.isOAuthSignInPending {
                        Button {
                            model.cancelOAuthDeviceSignIn()
                        } label: {
                            Label(AppL10n.string("Cancel"), systemImage: "xmark.circle")
                        }
                        .accessibilityHint(AppL10n.string("Cancels the current GitHub sign-in."))
                    }

                    if let authorization = model.oauthAuthorization {
                        Button {
                            model.copyOAuthUserCode()
                        } label: {
                            Label(AppL10n.string("Copy Code"), systemImage: "doc.on.doc")
                        }
                        .accessibilityHint(AppL10n.string("Copies the GitHub sign-in code to the clipboard."))

                        Link(AppL10n.string("Open GitHub"), destination: authorization.verificationURI)
                            .accessibilityHint(AppL10n.string("Opens GitHub so you can enter the copied sign-in code."))
                    }
                }

                if let authorization = model.oauthAuthorization {
                    HStack {
                        Text(AppL10n.string("Device code"))
                        Spacer()
                        Text(authorization.userCode)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Text(model.oauthStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(AppL10n.string("Manage GitHub access"))
                    Spacer()
                    Link(AppL10n.string("Manage on GitHub"), destination: URL(string: "https://github.com/settings/applications")!)
                }

                Text(AppL10n.string("To fully remove access, revoke PR Review Desk on GitHub. Deleting here only removes the sign-in saved on this Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(AppL10n.string("GitHub sign-in on this Mac"))
                    Spacer()
                    Button {
                        Task {
                            await model.retryGitHubSessionRestore()
                        }
                    } label: {
                        Label(AppL10n.string("Retry Restore"), systemImage: "arrow.clockwise")
                    }
                    .accessibilityHint(AppL10n.string("Uses a GitHub sign-in already saved on this Mac."))
                    .disabled(model.isWorking)
                    .smokeAccessibilityIdentifier("settings.github.restore")

                    Button(role: .destructive) {
                        model.deleteStoredToken()
                    } label: {
                        Label(AppL10n.string("Delete Local Credential"), systemImage: "trash")
                    }
                    .accessibilityHint(AppL10n.string("Deletes only the GitHub sign-in saved on this Mac."))
                    .disabled(model.isWorking || !model.hasToken)
                    .smokeAccessibilityIdentifier("settings.github.delete")
                }

                HStack {
                    Text(tokenValidationSummary)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await model.validateCurrentToken()
                        }
                    } label: {
                        Label(AppL10n.string("Validate"), systemImage: "checkmark.seal")
                    }
                    .accessibilityHint(AppL10n.string("Checks that GitHub can read repositories and reviews for this account."))
                    .disabled(model.isWorking || !model.hasToken)
                    .smokeAccessibilityIdentifier("settings.github.validate")
                }
            }

            Section(AppL10n.string("Codex for ChatGPT")) {
                Text(AppL10n.string("PR Review Desk uses Codex on this Mac. Sign in with ChatGPT to generate review drafts."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(model.codexCLIStatus)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await model.refreshCodexCLIStatus()
                        }
                    } label: {
                        Label(AppL10n.string("Check"), systemImage: "terminal")
                    }
                    .accessibilityHint(AppL10n.string("Checks whether Codex is ready for this app."))
                    .disabled(model.isWorking)
                }

                HStack {
                    Text(model.codexLoginStatus)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.copyCodexLoginCommand()
                    } label: {
                        Label(AppL10n.string("Copy sign-in step"), systemImage: "doc.on.doc")
                    }
                    .accessibilityHint(AppL10n.string("Copies the ChatGPT sign-in step."))
                    .disabled(!model.commandAvailability.canCopyCodexLoginCommand)
                    Button {
                        model.openTerminalForCodexLogin()
                    } label: {
                        Label(AppL10n.string("Open Terminal Sign-In Step"), systemImage: "terminal")
                    }
                    .accessibilityHint(AppL10n.string("Copies the Codex sign-in step, opens Terminal, and asks you to paste it."))
                    .disabled(!model.commandAvailability.canCopyCodexLoginCommand)
                }
            }

            Section(AppL10n.string("Privacy")) {
                Text(AppL10n.string("When you generate an AI review draft, pull request details and reviewable changes may be sent to Codex and OpenAI. Files without reviewable changes are not sent to Codex by this app."))
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(AppL10n.string("I acknowledge this disclosure"), isOn: $model.isPrivacyDisclosureAcknowledged)
                    .accessibilityHint(AppL10n.string("Marks the privacy disclosure as reviewed so review drafts can be created."))

                HStack {
                    Text(AppL10n.string("Private repository consent"))
                    Spacer()
                    Text(AppL10n.string("%d remembered", model.privateRepositoryConsentAcknowledgementCount))
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    model.clearPrivateRepositoryConsentAcknowledgements()
                } label: {
                    Label(AppL10n.string("Clear Remembered Private Repository Consent"), systemImage: "trash")
                }
                .accessibilityHint(AppL10n.string("Forgets private repository confirmations saved on this Mac."))
                .disabled(model.privateRepositoryConsentAcknowledgementCount == 0)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620)
    }

    private var grantedScopesDisclosure: some View {
        DisclosureGroup(AppL10n.string("Show GitHub access details")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.grantedGitHubScopes.sorted(), id: \.self) { scope in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(AppTheme.foreground(.success))
                        Text(scope)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(AppL10n.string("Granted scope %@", scope))
                }
            }
            .padding(.top, 4)
        }
    }

    private var grantedScopesSummary: String {
        if model.grantedGitHubScopes.isEmpty {
            return AppL10n.string("Unknown")
        }

        return AppL10n.string("%d scopes granted", model.grantedGitHubScopes.count)
    }

    private var tokenValidationSummary: String {
        guard !model.grantedGitHubScopes.isEmpty,
              let statusPrefix = tokenValidationStatusPrefix else {
            return model.tokenValidationStatus
        }

        return "\(statusPrefix) \(grantedScopesSummary)"
    }

    private var tokenValidationStatusPrefix: String? {
        guard let scopesRange = model.tokenValidationStatus.range(of: ". Scopes:") else {
            return nil
        }

        return "\(model.tokenValidationStatus[..<scopesRange.lowerBound])."
    }
}
