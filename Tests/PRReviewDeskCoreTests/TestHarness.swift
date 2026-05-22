import Foundation

@main
enum TestHarness {
    static func main() async {
        do {
            try ModelsTests.run()
            try ReviewCommandAvailabilityTests.run()
            try ReadinessChecklistTests.run()
            try DiffPositionMapperTests.run()
            try await GitHubClientTests.run()
            try await CodexReviewAgentTests.run()
            try ReviewSubmissionValidatorTests.run()
            try await ReviewSubmissionWorkflowTests.run()
            try KeychainTokenStoreTests.run()
            print("PRReviewDeskCoreTests passed")
        } catch {
            fputs("PRReviewDeskCoreTests failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
