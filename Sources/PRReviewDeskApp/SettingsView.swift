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
