import SwiftUI

struct StatusBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.statusMessage)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct RecoverableErrorPanel: View {
    let error: RecoverableErrorDetails
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(error.operation, systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(AppTheme.foreground(.warning))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Label(AppL10n.string("Dismiss error"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help(AppL10n.string("Dismiss error"))
                .accessibilityLabel(AppL10n.string("Dismiss error"))
            }

            Text(error.summary)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(error.details)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(error.recoverySuggestion)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.border(.warning))
                .frame(height: 1)
        }
    }
}
