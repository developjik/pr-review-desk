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
            "Search repositories",
            "No matching repositories",
            "Review Inspector",
            "Review Body",
            "Inline Comments",
            "Submit Review Preview",
            "Search actions",
            "Readiness"
        ]
    )

    public func renderedReport() -> String {
        (["ui_smoke=ready"]
            + surfaces.map { "surface=\($0.rawValue)" }
            + requiredLocalizationKeys.map { "localization=\($0)" })
            .joined(separator: "\n")
    }
}
