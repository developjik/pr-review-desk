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
        "PR metadata",
        "Reviewable patch content",
        "Selected repository and pull request identifiers",
        "Generated review prompt context"
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
