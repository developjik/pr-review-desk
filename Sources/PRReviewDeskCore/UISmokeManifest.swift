import Foundation

public enum UISmokeSurface: String, CaseIterable, Hashable, Sendable {
    case setupGate = "setup-gate"
    case reviewWorkspace = "review-workspace"
    case firstRunSetup = "first-run-setup"
    case repositorySidebar = "repository-sidebar"
    case reviewInbox = "review-inbox"
    case diffWorkspace = "diff-workspace"
    case reviewInspector = "review-inspector"
    case submitPreview = "submit-preview"
    case commandPanel = "command-panel"
    case settingsReadiness = "settings-readiness"
}

public struct UISmokeManifest: Equatable, Hashable, Sendable {
    public let surfaces: [UISmokeSurface]
    public let requiredLocalizationKeys: [String]

    public static let current = UISmokeManifest(
        surfaces: UISmokeSurface.allCases,
        requiredLocalizationKeys: [
            "Complete setup in Settings",
            "Open Settings",
            "PR Review Desk keeps setup changes in Settings.",
            "Finish setup",
            "Guided setup path",
            "Sign in with GitHub",
            "Setup details",
            "Search repositories",
            "No matching repositories",
            "Clear search",
            "No open pull requests in this repository. Refresh or choose another repository.",
            "Add drafts",
            "Review Inspector",
            "Awaiting selection",
            "Review Body",
            "Inline Comments",
            "Submit Review Preview",
            "Check Again",
            "Checking",
            "Regenerate",
            "Last checked at %@ UTC.",
            "Search actions",
            "Readiness",
            "Reconnect GitHub Sign-In",
            "GitHub sign-in is saved. Validate repository access before generating reviews.",
            "GitHub is connected for repository review access. Reconnect or manage access if permissions change.",
            "Shortcut: %@",
            "Cancel Review Generation"
        ]
    )

    public func renderedReport() -> String {
        (["ui_smoke=ready"]
            + surfaces.map { "surface=\($0.rawValue)" }
            + requiredLocalizationKeys.map { "localization=\($0)" })
            .joined(separator: "\n")
    }
}
