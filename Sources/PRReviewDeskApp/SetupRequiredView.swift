import SwiftUI
import PRReviewDeskCore

struct SetupRequiredView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let presentation = model.settingsGatePresentation

        VStack(alignment: .leading, spacing: 18) {
            Label(AppL10n.string("Complete setup in Settings"), systemImage: "gearshape.2")
                .font(.title2)
                .fontWeight(.semibold)

            Text(AppL10n.string("PR Review Desk keeps setup changes in Settings."))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.blockingItems) { item in
                    SetupBlockingItemRow(item: item)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.panelBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border(.warning))
            }

            SettingsLink {
                Label(AppL10n.string("Open Settings"), systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text(AppL10n.string("After setup is complete, the PR review workspace appears automatically."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .center)
        .smokeAccessibilityIdentifier("setup-gate.open-settings")
    }
}

private struct SetupBlockingItemRow: View {
    let item: ReadinessChecklistItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppL10n.string(item.title))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(AppL10n.string(item.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var icon: String {
        switch item.state {
        case .ready:
            return "checkmark.circle.fill"
        case .needsAction:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var color: Color {
        switch item.state {
        case .ready:
            return AppTheme.foreground(.success)
        case .needsAction:
            return AppTheme.foreground(.warning)
        case .unknown:
            return .secondary
        }
    }
}
