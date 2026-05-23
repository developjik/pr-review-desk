import SwiftUI
import PRReviewDeskCore

enum ReadinessChecklistMode: Equatable {
    case compact
    case detailed
}

struct ReadinessChecklistView: View {
    @ObservedObject var model: AppModel
    var mode: ReadinessChecklistMode = .detailed

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(AppL10n.string("Readiness"), systemImage: "checklist")
                    .font(.headline)
                Spacer()
                StatusBadge(
                    title: model.readinessChecklist.isReady ? AppL10n.string("Ready") : AppL10n.string("Needs setup"),
                    systemImage: model.readinessChecklist.isReady ? "checkmark.circle" : "exclamationmark.triangle",
                    tone: model.readinessChecklist.isReady ? .success : .warning
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(visibleItems) { item in
                    readinessRow(item)
                }
            }
        }
    }

    private var visibleItems: [ReadinessChecklistItem] {
        switch mode {
        case .compact:
            let blockedItems = model.readinessChecklist.items.filter { $0.state != .ready }
            return Array(blockedItems.prefix(2))
        case .detailed:
            return model.readinessChecklist.items
        }
    }

    private func readinessRow(_ item: ReadinessChecklistItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stateIcon(for: item.state))
                .foregroundStyle(stateColor(for: item.state))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppL10n.string(item.title))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if mode == .detailed {
                    Text(readinessDetail(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if item.state != .ready {
                    Button {
                        performAction(item.action)
                    } label: {
                        Label(AppL10n.string(item.actionTitle), systemImage: actionIcon(for: item.action))
                    }
                    .controlSize(.small)
                    .accessibilityHint(actionHint(for: item.action))
                    .disabled(isActionDisabled(item.action))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func performAction(_ action: ReadinessChecklistAction) {
        switch action {
        case .loadGitHubCredential:
            model.startOAuthDeviceSignIn()
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

    private func readinessDetail(for item: ReadinessChecklistItem) -> String {
        if item.id == .githubTokenValidation,
           item.state == .ready,
           !model.grantedGitHubScopes.isEmpty,
           let accountSummary = tokenValidationAccountSummary(from: item.detail) {
            return "\(accountSummary) \(AppL10n.string("%d scopes granted", model.grantedGitHubScopes.count))"
        }

        return AppL10n.string(item.detail)
    }

    private func tokenValidationAccountSummary(from detail: String) -> String? {
        guard let scopesRange = detail.range(of: ". Scopes:") else {
            return nil
        }

        return "\(detail[..<scopesRange.lowerBound])."
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
            return AppTheme.foreground(.success)
        case .needsAction:
            return AppTheme.foreground(.warning)
        case .unknown:
            return .secondary
        }
    }

    private func actionIcon(for action: ReadinessChecklistAction) -> String {
        switch action {
        case .loadGitHubCredential:
            return "person.crop.circle.badge.checkmark"
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

    private func actionHint(for action: ReadinessChecklistAction) -> String {
        switch action {
        case .loadGitHubCredential:
            return AppL10n.string("Opens GitHub sign-in and then checks repository access.")
        case .validateGitHubToken:
            return AppL10n.string("Checks that GitHub can read repositories and reviews for this account.")
        case .checkCodexReadiness:
            return AppL10n.string("Checks whether AI review setup is ready on this Mac.")
        case .copyCodexLoginCommand:
            return AppL10n.string("Copies the ChatGPT sign-in step.")
        case .acknowledgePrivacyDisclosure:
            return AppL10n.string("Marks the privacy disclosure as read so setup can continue.")
        }
    }
}
