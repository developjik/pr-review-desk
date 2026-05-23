import Foundation

public enum UISmokeSurface: String, CaseIterable, Hashable, Sendable {
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
