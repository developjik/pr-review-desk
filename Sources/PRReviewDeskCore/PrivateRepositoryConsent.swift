import Foundation

public struct PrivateRepositoryConsentRequest: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { repositoryFullName }

    public let repositoryFullName: String
    public let outboundDataDescriptions: [String]

    public init(
        repositoryFullName: String,
        outboundDataDescriptions: [String] = PrivateRepositoryConsentPolicy.outboundDataDescriptions
    ) {
        self.repositoryFullName = repositoryFullName
        self.outboundDataDescriptions = outboundDataDescriptions
    }
}

public enum PrivateRepositoryConsentPolicy {
    public static let outboundDataDescriptions = [
        "Pull request title, description, and author",
        "Reviewable code changes",
        "Existing comments and check summaries",
        "Selected repository and pull request names",
        "Information needed to write the review draft"
    ]

    public static func request(
        for repository: Repository,
        acknowledgedRepositories: Set<String>
    ) -> PrivateRepositoryConsentRequest? {
        guard repository.isPrivate else {
            return nil
        }

        guard !acknowledgedRepositories.contains(repository.fullName) else {
            return nil
        }

        return PrivateRepositoryConsentRequest(repositoryFullName: repository.fullName)
    }
}
