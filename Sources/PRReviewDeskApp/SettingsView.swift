import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue
    @State private var isPersonalAccessTokenEditorPresented = false

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
                    Text(AppL10n.string("Token"))
                    Spacer()
                    Text(model.hasToken ? AppL10n.string("Loaded") : AppL10n.string("Not loaded"))
                        .foregroundStyle(model.hasToken ? AppTheme.foreground(.success) : .secondary)
                }

                HStack {
                    Text(AppL10n.string("Credential type"))
                    Spacer()
                    Text(model.credentialKindDescription)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text(AppL10n.string("Granted scopes"))
                    Spacer()
                    Text(grantedScopesSummary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }

                if !model.grantedGitHubScopes.isEmpty {
                    grantedScopesDisclosure
                }

                personalAccessTokenControls

                DisclosureGroup(AppL10n.string("Advanced GitHub OAuth")) {
                    TextField(AppL10n.string("OAuth App client ID"), text: $model.oauthClientID)
                        .textFieldStyle(.roundedBorder)

                    Text(AppL10n.string("Use OAuth only when you already have a GitHub OAuth App client ID."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            model.startOAuthDeviceSignIn()
                        } label: {
                            Label(
                                model.hasToken ? AppL10n.string("Replace with GitHub OAuth") : AppL10n.string("Sign in with GitHub"),
                                systemImage: "person.crop.circle.badge.checkmark"
                            )
                        }
                        .disabled(model.isOAuthSignInPending || model.oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if model.isOAuthSignInPending {
                            Button {
                                model.cancelOAuthDeviceSignIn()
                            } label: {
                                Label(AppL10n.string("Cancel"), systemImage: "xmark.circle")
                            }
                        }

                        if let authorization = model.oauthAuthorization {
                            Button {
                                model.copyOAuthUserCode()
                            } label: {
                                Label(AppL10n.string("Copy Code"), systemImage: "doc.on.doc")
                            }

                            Link(AppL10n.string("Open GitHub"), destination: authorization.verificationURI)
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
                        Text(AppL10n.string("Revoke OAuth access"))
                        Spacer()
                        Link(AppL10n.string("Manage on GitHub"), destination: URL(string: "https://github.com/settings/applications")!)
                    }

                    Text(AppL10n.string("OAuth authorization must be revoked on GitHub. Deleting here only removes the local credential."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    .disabled(model.isWorking || !model.hasToken)
                    .smokeAccessibilityIdentifier("settings.github.validate")
                }
            }

            Section(AppL10n.string("Codex")) {
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
                    .disabled(model.isWorking)
                }
            }

            Section(AppL10n.string("Privacy")) {
                Text(AppL10n.string("When you generate a review, PR metadata and reviewable patch content may be sent to Codex and OpenAI. Omitted files without GitHub patch content are not sent to Codex by this app."))
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(AppL10n.string("I acknowledge this disclosure"), isOn: $model.isPrivacyDisclosureAcknowledged)

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
                .disabled(model.privateRepositoryConsentAcknowledgementCount == 0)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620)
    }

    private var grantedScopesDisclosure: some View {
        DisclosureGroup(AppL10n.string("Show granted scopes")) {
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

    @ViewBuilder
    private var personalAccessTokenControls: some View {
        if isPersonalAccessTokenEditorPresented {
            Text(AppL10n.string("Paste a GitHub token with repository access, save it locally, then validate scopes."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField(AppL10n.string("Personal access token"), text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    Task {
                        await model.saveTokenAndRefresh()
                    }
                } label: {
                    Label(AppL10n.string("Save or Replace with PAT"), systemImage: "key")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking || model.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .smokeAccessibilityIdentifier("settings.github.save-pat")

                Button {
                    model.loadStoredToken()
                } label: {
                    Label(AppL10n.string("Load"), systemImage: "lock.open")
                }
                .disabled(model.isWorking)
                .smokeAccessibilityIdentifier("settings.github.load")

                Button {
                    model.tokenInput = ""
                    isPersonalAccessTokenEditorPresented = false
                } label: {
                    Label(AppL10n.string("Cancel PAT entry"), systemImage: "xmark.circle")
                }
                .disabled(model.isWorking)
                .smokeAccessibilityIdentifier("settings.github.cancel-pat-entry")

                Button(role: .destructive) {
                    model.deleteStoredToken()
                } label: {
                    Label(AppL10n.string("Delete Local Credential"), systemImage: "trash")
                }
                .disabled(model.isWorking || !model.hasToken)
                .smokeAccessibilityIdentifier("settings.github.delete")
            }
        } else {
            Text(AppL10n.string("Personal access token entry is hidden until you choose to add or replace it."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    isPersonalAccessTokenEditorPresented = true
                } label: {
                    Label(
                        model.hasToken ? AppL10n.string("Replace personal access token") : AppL10n.string("Enter personal access token"),
                        systemImage: "key"
                    )
                }
                .disabled(model.isWorking)
                .smokeAccessibilityIdentifier(
                    "settings.github.show-pat-entry",
                    state: model.hasToken ? "replace" : "enter"
                )

                Button {
                    model.loadStoredToken()
                } label: {
                    Label(AppL10n.string("Load"), systemImage: "lock.open")
                }
                .disabled(model.isWorking)
                .smokeAccessibilityIdentifier("settings.github.load")

                Button(role: .destructive) {
                    model.deleteStoredToken()
                } label: {
                    Label(AppL10n.string("Delete Local Credential"), systemImage: "trash")
                }
                .disabled(model.isWorking || !model.hasToken)
                .smokeAccessibilityIdentifier("settings.github.delete")
            }
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
