import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
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
                    DisclosureGroup(AppL10n.string("Show granted scopes")) {
                        Text(model.grantedGitHubScopes.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                TextField(AppL10n.string("OAuth App client ID"), text: $model.oauthClientID)
                    .textFieldStyle(.roundedBorder)

                Text(AppL10n.string("Use OAuth when you have a GitHub OAuth App client ID. Otherwise use the personal access token fallback below."))
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
                    .buttonStyle(.borderedProminent)
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

                DisclosureGroup(AppL10n.string("Personal access token fallback")) {
                    Text(AppL10n.string("For personal use, paste a GitHub token with repository access, save it locally, then validate scopes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField(AppL10n.string("Personal access token"), text: $model.tokenInput)

                    HStack {
                        Button {
                            Task {
                                await model.saveTokenAndRefresh()
                            }
                        } label: {
                            Label(AppL10n.string("Save or Replace with PAT"), systemImage: "key")
                        }
                        .disabled(model.isWorking)

                        Button {
                            model.loadStoredToken()
                        } label: {
                            Label(AppL10n.string("Load"), systemImage: "lock.open")
                        }
                        .disabled(model.isWorking)

                        Button(role: .destructive) {
                            model.deleteStoredToken()
                        } label: {
                            Label(AppL10n.string("Delete Local Credential"), systemImage: "trash")
                        }
                        .disabled(model.isWorking || !model.hasToken)
                    }

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
