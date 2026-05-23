import Foundation

public enum RepositorySearchPresentation {
    public static func trimmedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func showsNoMatches(
        totalRepositoryCount: Int,
        filteredRepositoryCount: Int,
        query: String
    ) -> Bool {
        totalRepositoryCount > 0
            && filteredRepositoryCount == 0
            && !trimmedQuery(query).isEmpty
    }
}
