import Foundation

public enum GitHubRepositoryAccessDecision: Equatable, Hashable, Sendable {
    case allowed
    case denied(reason: String, recoverySuggestion: String)

    public var isAllowed: Bool {
        switch self {
        case .allowed:
            return true
        case .denied:
            return false
        }
    }

    public var reason: String? {
        switch self {
        case .allowed:
            return nil
        case let .denied(reason, _):
            return reason
        }
    }

    public var recoverySuggestion: String {
        switch self {
        case .allowed:
            return ""
        case let .denied(_, recoverySuggestion):
            return recoverySuggestion
        }
    }
}

public enum GitHubRepositoryAccessPolicy {
    public static func reviewAccess(for repository: Repository, scopes: [String]) -> GitHubRepositoryAccessDecision {
        let normalizedScopes = Set(scopes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        guard !normalizedScopes.isEmpty else {
            return .allowed
        }

        if normalizedScopes.contains("repo") {
            return .allowed
        }

        if !repository.isPrivate && normalizedScopes.contains("public_repo") {
            return .allowed
        }

        if repository.isPrivate {
            return .denied(
                reason: "Private repositories require the repo OAuth scope.",
                recoverySuggestion: "Re-authorize GitHub with the repo scope or use a PAT that can read and review private pull requests."
            )
        }

        return .denied(
            reason: "Public repository review requires public_repo or repo OAuth scope.",
            recoverySuggestion: "Re-authorize GitHub with public_repo or repo scope, or use a PAT that can read and review public pull requests."
        )
    }
}
