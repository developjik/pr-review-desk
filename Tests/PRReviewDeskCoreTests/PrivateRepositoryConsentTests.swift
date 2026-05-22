import Foundation
import PRReviewDeskCore

enum PrivateRepositoryConsentTests {
    static func run() throws {
        try testPublicRepositoryDoesNotRequireConsent()
        try testPrivateRepositoryRequiresConsentUntilRepositoryIsAcknowledged()
    }

    private static func testPublicRepositoryDoesNotRequireConsent() throws {
        let repository = Repository(
            id: 1,
            owner: "developjik",
            name: "public-desk",
            fullName: "developjik/public-desk",
            isPrivate: false
        )

        try expectEqual(
            PrivateRepositoryConsentPolicy.request(for: repository, acknowledgedRepositories: []),
            nil
        )
    }

    private static func testPrivateRepositoryRequiresConsentUntilRepositoryIsAcknowledged() throws {
        let repository = Repository(
            id: 2,
            owner: "developjik",
            name: "private-desk",
            fullName: "developjik/private-desk",
            isPrivate: true
        )

        let request = try unwrap(
            PrivateRepositoryConsentPolicy.request(for: repository, acknowledgedRepositories: [])
        )
        try expectEqual(request.repositoryFullName, "developjik/private-desk")
        try expectTrue(request.outboundDataDescriptions.contains("PR metadata"))
        try expectTrue(request.outboundDataDescriptions.contains("Reviewable patch content"))

        try expectEqual(
            PrivateRepositoryConsentPolicy.request(
                for: repository,
                acknowledgedRepositories: ["developjik/private-desk"]
            ),
            nil
        )
    }
}
