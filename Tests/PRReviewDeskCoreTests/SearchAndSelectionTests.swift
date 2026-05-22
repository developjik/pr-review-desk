import Foundation
import PRReviewDeskCore

enum SearchAndSelectionTests {
    static func run() throws {
        try testRepositorySearchMatchesOwnerNameAndFullName()
        try testPullRequestSearchMatchesNumberTitleAndAuthor()
        try testRepositorySelectionPreservesRefreshedInstanceByID()
        try testPullRequestSelectionPreservesRefreshedInstanceByID()
    }

    private static func testRepositorySearchMatchesOwnerNameAndFullName() throws {
        let repositories = [
            repository(id: 1, owner: "developjik", name: "PRReviewDesk"),
            repository(id: 2, owner: "openai", name: "codex"),
            repository(id: 3, owner: "developjik", name: "notes")
        ]

        try expectEqual(
            SearchFilter.repositories(repositories, matching: "review").map(\.id),
            [1]
        )
        try expectEqual(
            SearchFilter.repositories(repositories, matching: "OPENAI").map(\.id),
            [2]
        )
        try expectEqual(
            SearchFilter.repositories(repositories, matching: "developjik/notes").map(\.id),
            [3]
        )
    }

    private static func testPullRequestSearchMatchesNumberTitleAndAuthor() throws {
        let pullRequests = [
            pullRequest(id: 1, number: 12, title: "Add readiness checklist", author: "alice"),
            pullRequest(id: 2, number: 32, title: "Repository search", author: "bob")
        ]

        try expectEqual(
            SearchFilter.pullRequests(pullRequests, matching: "#12").map(\.id),
            [1]
        )
        try expectEqual(
            SearchFilter.pullRequests(pullRequests, matching: "search").map(\.id),
            [2]
        )
        try expectEqual(
            SearchFilter.pullRequests(pullRequests, matching: "ALICE").map(\.id),
            [1]
        )
    }

    private static func testRepositorySelectionPreservesRefreshedInstanceByID() throws {
        let previousSelection = repository(id: 2, owner: "developjik", name: "old-name")
        let refreshed = [
            repository(id: 1, owner: "developjik", name: "first"),
            repository(id: 2, owner: "developjik", name: "new-name")
        ]

        try expectEqual(
            StableSelection.repository(afterRefresh: refreshed, previousSelection: previousSelection)?.name,
            "new-name"
        )
        try expectEqual(
            StableSelection.repository(afterRefresh: refreshed, previousSelection: repository(id: 99, owner: "x", name: "missing"))?.id,
            1
        )
    }

    private static func testPullRequestSelectionPreservesRefreshedInstanceByID() throws {
        let previousSelection = pullRequest(id: 2, number: 8, title: "Old title", author: "bob")
        let refreshed = [
            pullRequest(id: 1, number: 7, title: "Other PR", author: "alice"),
            pullRequest(id: 2, number: 8, title: "New title", author: "bob")
        ]

        try expectEqual(
            StableSelection.pullRequest(afterRefresh: refreshed, previousSelection: previousSelection)?.title,
            "New title"
        )
        try expectEqual(
            StableSelection.pullRequest(
                afterRefresh: refreshed,
                previousSelection: pullRequest(id: 99, number: 99, title: "Missing", author: "nobody")
            ),
            nil
        )
    }

    private static func repository(id: Int, owner: String, name: String) -> Repository {
        Repository(id: id, owner: owner, name: name, fullName: "\(owner)/\(name)", isPrivate: false)
    }

    private static func pullRequest(id: Int, number: Int, title: String, author: String) -> PullRequest {
        PullRequest(
            id: id,
            number: number,
            title: title,
            htmlURL: URL(string: "https://github.com/developjik/desk/pull/\(number)")!,
            author: author,
            headSha: "sha-\(id)"
        )
    }
}
