import Foundation

public enum SearchFilter {
    public static func repositories(_ repositories: [Repository], matching query: String) -> [Repository] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else {
            return repositories
        }

        return repositories.filter { repository in
            normalized(repository.name).contains(normalizedQuery)
                || normalized(repository.owner).contains(normalizedQuery)
                || normalized(repository.fullName).contains(normalizedQuery)
        }
    }

    public static func pullRequests(_ pullRequests: [PullRequest], matching query: String) -> [PullRequest] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else {
            return pullRequests
        }

        return pullRequests.filter { pullRequest in
            normalized("#\(pullRequest.number)").contains(normalizedQuery)
                || normalized("\(pullRequest.number)").contains(normalizedQuery)
                || normalized(pullRequest.title).contains(normalizedQuery)
                || normalized(pullRequest.author).contains(normalizedQuery)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum StableSelection {
    public static func repository(
        afterRefresh repositories: [Repository],
        previousSelection: Repository?
    ) -> Repository? {
        if let previousSelection,
           let refreshedSelection = repositories.first(where: { $0.id == previousSelection.id }) {
            return refreshedSelection
        }

        return repositories.first
    }

    public static func pullRequest(
        afterRefresh pullRequests: [PullRequest],
        previousSelection: PullRequest?
    ) -> PullRequest? {
        guard let previousSelection else {
            return nil
        }

        return pullRequests.first { $0.id == previousSelection.id }
    }
}
