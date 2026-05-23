import Foundation
import PRReviewDeskCore

enum RepositorySearchPresentationTests {
    static func run() throws {
        try testNoMatchesAppearsOnlyForActiveRepositoryFilters()
        try testTrimmedRepositoryQueryIsUsedForRecoveryCopy()
    }

    private static func testNoMatchesAppearsOnlyForActiveRepositoryFilters() throws {
        try expectEqual(
            RepositorySearchPresentation.showsNoMatches(totalRepositoryCount: 3, filteredRepositoryCount: 0, query: "cache"),
            true
        )
        try expectEqual(
            RepositorySearchPresentation.showsNoMatches(totalRepositoryCount: 3, filteredRepositoryCount: 0, query: "   "),
            false
        )
        try expectEqual(
            RepositorySearchPresentation.showsNoMatches(totalRepositoryCount: 0, filteredRepositoryCount: 0, query: "cache"),
            false
        )
        try expectEqual(
            RepositorySearchPresentation.showsNoMatches(totalRepositoryCount: 3, filteredRepositoryCount: 1, query: "cache"),
            false
        )
    }

    private static func testTrimmedRepositoryQueryIsUsedForRecoveryCopy() throws {
        try expectEqual(
            RepositorySearchPresentation.trimmedQuery("  developjik / desk  "),
            "developjik / desk"
        )
    }
}
