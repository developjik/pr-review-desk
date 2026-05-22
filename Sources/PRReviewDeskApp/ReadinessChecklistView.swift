import SwiftUI
import PRReviewDeskCore

struct ReadinessChecklistView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Readiness", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text(model.readinessChecklist.isReady ? "Ready" : "Needs setup")
                    .font(.caption)
                    .foregroundStyle(model.readinessChecklist.isReady ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.readinessChecklist.items) { item in
                    readinessRow(item)
                }
            }
        }
    }

    private func readinessRow(_ item: ReadinessChecklistItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stateIcon(for: item.state))
                .foregroundStyle(stateColor(for: item.state))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if item.state != .ready {
                    Button {
                        performAction(item.action)
                    } label: {
                        Label(item.actionTitle, systemImage: actionIcon(for: item.action))
                    }
                    .controlSize(.small)
                    .disabled(isActionDisabled(item.action))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func performAction(_ action: ReadinessChecklistAction) {
        switch action {
        case .loadGitHubCredential:
            model.loadStoredToken()
            Task {
                await model.refreshRepositories()
            }
        case .validateGitHubToken:
            Task {
                await model.validateCurrentToken()
            }
        case .checkCodexReadiness:
            Task {
                await model.refreshCodexCLIStatus()
            }
        case .copyCodexLoginCommand:
            model.copyCodexLoginCommand()
        case .acknowledgePrivacyDisclosure:
            model.acknowledgePrivacyDisclosure()
        }
    }

    private func isActionDisabled(_ action: ReadinessChecklistAction) -> Bool {
        switch action {
        case .loadGitHubCredential, .checkCodexReadiness:
            return model.isWorking
        case .validateGitHubToken:
            return model.isWorking || !model.hasToken
        case .copyCodexLoginCommand, .acknowledgePrivacyDisclosure:
            return model.isWorking
        }
    }

    private func stateIcon(for state: ReadinessChecklistItemState) -> String {
        switch state {
        case .ready:
            return "checkmark.circle.fill"
        case .needsAction:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func stateColor(for state: ReadinessChecklistItemState) -> Color {
        switch state {
        case .ready:
            return .green
        case .needsAction:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private func actionIcon(for action: ReadinessChecklistAction) -> String {
        switch action {
        case .loadGitHubCredential:
            return "lock.open"
        case .validateGitHubToken:
            return "checkmark.seal"
        case .checkCodexReadiness:
            return "terminal"
        case .copyCodexLoginCommand:
            return "doc.on.doc"
        case .acknowledgePrivacyDisclosure:
            return "checkmark.shield"
        }
    }
}
