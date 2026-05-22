import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Readiness") {
                ReadinessChecklistView(model: model)
            }

            Section("GitHub") {
                HStack {
                    Text("Token")
                    Spacer()
                    Text(model.hasToken ? "Loaded" : "Not loaded")
                        .foregroundStyle(model.hasToken ? .green : .secondary)
                }

                SecureField("Personal access token", text: $model.tokenInput)

                HStack {
                    Button {
                        Task {
                            await model.saveTokenAndRefresh()
                        }
                    } label: {
                        Label("Save or Replace", systemImage: "key")
                    }
                    .disabled(model.isWorking)

                    Button {
                        model.loadStoredToken()
                    } label: {
                        Label("Load", systemImage: "lock.open")
                    }
                    .disabled(model.isWorking)

                    Button(role: .destructive) {
                        model.deleteStoredToken()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(model.isWorking || !model.hasToken)
                }

                Divider()

                TextField("OAuth App client ID", text: $model.oauthClientID)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        model.startOAuthDeviceSignIn()
                    } label: {
                        Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(model.isOAuthSignInPending || model.oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if model.isOAuthSignInPending {
                        Button {
                            model.cancelOAuthDeviceSignIn()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    }

                    if let authorization = model.oauthAuthorization {
                        Button {
                            model.copyOAuthUserCode()
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }

                        Link("Open GitHub", destination: authorization.verificationURI)
                    }
                }

                if let authorization = model.oauthAuthorization {
                    HStack {
                        Text("Device code")
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
                    Text(model.tokenValidationStatus)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await model.validateCurrentToken()
                        }
                    } label: {
                        Label("Validate", systemImage: "checkmark.seal")
                    }
                    .disabled(model.isWorking || !model.hasToken)
                }
            }

            Section("Codex") {
                HStack {
                    Text(model.codexCLIStatus)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await model.refreshCodexCLIStatus()
                        }
                    } label: {
                        Label("Check", systemImage: "terminal")
                    }
                    .disabled(model.isWorking)
                }
            }

            Section("Privacy") {
                Text("When you generate a review, PR metadata and reviewable patch content may be sent to Codex and OpenAI. Omitted files without GitHub patch content are not sent to Codex by this app.")
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("I acknowledge this disclosure", isOn: $model.isPrivacyDisclosureAcknowledged)

                HStack {
                    Text("Private repository consent")
                    Spacer()
                    Text("\(model.privateRepositoryConsentAcknowledgementCount) remembered")
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    model.clearPrivateRepositoryConsentAcknowledgements()
                } label: {
                    Label("Clear Remembered Private Repository Consent", systemImage: "trash")
                }
                .disabled(model.privateRepositoryConsentAcknowledgementCount == 0)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620)
    }
}
