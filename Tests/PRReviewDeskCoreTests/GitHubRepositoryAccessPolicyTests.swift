import Foundation
import PRReviewDeskCore

enum GitHubRepositoryAccessPolicyTests {
    static func run() throws {
        try testRepoScopeAllowsPrivateAndPublicRepositories()
        try testPublicRepoScopeAllowsPublicRepositoriesOnly()
        try testKnownScopesWithoutRepoDenyPrivateRepositories()
        try testUnknownScopesDoNotBlockAccessLocally()
    }

    private static func testRepoScopeAllowsPrivateAndPublicRepositories() throws {
        try expectEqual(
            GitHubRepositoryAccessPolicy.reviewAccess(for: privateRepository, scopes: ["repo"]),
            .allowed
        )
        try expectEqual(
            GitHubRepositoryAccessPolicy.reviewAccess(for: publicRepository, scopes: ["repo"]),
            .allowed
        )
    }

    private static func testPublicRepoScopeAllowsPublicRepositoriesOnly() throws {
        try expectEqual(
            GitHubRepositoryAccessPolicy.reviewAccess(for: publicRepository, scopes: ["public_repo"]),
            .allowed
        )

        let decision = GitHubRepositoryAccessPolicy.reviewAccess(for: privateRepository, scopes: ["public_repo"])

        try expectEqual(decision, .denied(
            reason: "Private repositories require the repo OAuth scope.",
            recoverySuggestion: "Re-authorize GitHub with the repo scope or use a PAT that can read and review private pull requests."
        ))
    }

    private static func testKnownScopesWithoutRepoDenyPrivateRepositories() throws {
        let decision = GitHubRepositoryAccessPolicy.reviewAccess(for: privateRepository, scopes: ["read:org"])

        try expectEqual(decision.isAllowed, false)
        try expectTrue(decision.recoverySuggestion.contains("repo scope"))
    }

    private static func testUnknownScopesDoNotBlockAccessLocally() throws {
        try expectEqual(
            GitHubRepositoryAccessPolicy.reviewAccess(for: privateRepository, scopes: []),
            .allowed
        )
    }
}

private let publicRepository = Repository(
    id: 1,
    owner: "developjik",
    name: "public-desk",
    fullName: "developjik/public-desk",
    isPrivate: false
)

private let privateRepository = Repository(
    id: 2,
    owner: "developjik",
    name: "private-desk",
    fullName: "developjik/private-desk",
    isPrivate: true
)
