import Foundation

public struct SettingsGitHubAccessPresentation: Equatable, Hashable, Sendable {
    public let caption: String

    public static func make(
        hasCredential: Bool,
        hasValidatedScopes: Bool
    ) -> SettingsGitHubAccessPresentation {
        if hasValidatedScopes {
            return SettingsGitHubAccessPresentation(
                caption: "GitHub is connected for repository review access. Reconnect or manage access if permissions change."
            )
        }

        if hasCredential {
            return SettingsGitHubAccessPresentation(
                caption: "GitHub sign-in is saved. Validate repository access before generating reviews."
            )
        }

        return SettingsGitHubAccessPresentation(
            caption: "Sign in with GitHub to authorize repository review access."
        )
    }
}
