import Foundation

public enum SettingsGateDestination: Equatable, Hashable, Sendable {
    case setupRequired
    case reviewWorkspace
}

public enum SettingsGateAction: Equatable, Hashable, Sendable {
    case openSettings
}

public struct SettingsGatePresentation: Equatable, Hashable, Sendable {
    public let destination: SettingsGateDestination
    public let blockingItems: [ReadinessChecklistItem]
    public let primaryAction: SettingsGateAction
    public let allowsInlineSetupActions: Bool

    public static func make(readinessChecklist: ReadinessChecklist) -> SettingsGatePresentation {
        if readinessChecklist.isReady {
            return SettingsGatePresentation(
                destination: .reviewWorkspace,
                blockingItems: [],
                primaryAction: .openSettings,
                allowsInlineSetupActions: false
            )
        }

        return SettingsGatePresentation(
            destination: .setupRequired,
            blockingItems: readinessChecklist.items.filter { $0.state != .ready },
            primaryAction: .openSettings,
            allowsInlineSetupActions: false
        )
    }
}
