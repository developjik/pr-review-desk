import SwiftUI
import PRReviewDeskCore

enum AppStatusTone {
    case success
    case warning
    case error
    case info
    case neutral
    case addition
    case deletion
    case focus
    case invalid
    case omitted
}

enum AppTheme {
    static func foreground(_ tone: AppStatusTone) -> Color {
        switch tone {
        case .success, .addition:
            return Color(nsColor: .systemGreen)
        case .warning, .omitted:
            return Color(nsColor: .systemOrange)
        case .error, .deletion, .invalid:
            return Color(nsColor: .systemRed)
        case .info:
            return Color(nsColor: .systemBlue)
        case .focus:
            return .accentColor
        case .neutral:
            return .secondary
        }
    }

    static func background(_ tone: AppStatusTone) -> Color {
        foreground(tone).opacity(0.12)
    }

    static func border(_ tone: AppStatusTone) -> Color {
        foreground(tone).opacity(0.55)
    }

    static var panelBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var secondaryPanelBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static func diffForeground(for kind: AnnotatedDiffLineKind) -> Color {
        switch kind {
        case .addition:
            return foreground(.addition)
        case .deletion:
            return foreground(.deletion)
        case .hunk:
            return foreground(.info)
        case .omitted:
            return foreground(.omitted)
        case .context, .metadata:
            return .primary
        }
    }

    static func diffBackground(for kind: AnnotatedDiffLineKind) -> Color {
        switch kind {
        case .addition:
            return background(.addition)
        case .deletion:
            return background(.deletion)
        case .hunk:
            return background(.info)
        case .omitted:
            return background(.omitted)
        case .context, .metadata:
            return .clear
        }
    }
}

struct StatusBadge: View {
    let title: String
    let systemImage: String
    let tone: AppStatusTone

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(AppTheme.foreground(tone))
            .background(AppTheme.background(tone), in: Capsule())
            .accessibilityLabel(title)
    }
}
