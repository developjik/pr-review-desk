import Foundation

@main
enum TestHarness {
    static func main() async {
        do {
            try ModelsTests.run()
            try ReviewInboxTests.run()
            try AIReviewDraftActionPresentationTests.run()
            try ReviewWorkspaceLayoutPolicyTests.run()
            try ReviewCommandAvailabilityTests.run()
            try ReviewCommandPanelPresentationTests.run()
            try ReviewSubmissionPreviewTests.run()
            try RepositorySearchPresentationTests.run()
            try ReviewInboxFilterPresentationTests.run()
            try FirstRunSetupPresentationTests.run()
            try UISmokeManifestTests.run()
            try ReadinessChecklistTests.run()
            try PrivateRepositoryConsentTests.run()
            try SearchAndSelectionTests.run()
            try DiffPositionMapperTests.run()
            try InlineCommentNavigationTests.run()
            try ReviewDraftStoreTests.run()
            try BackgroundReviewQueueTests.run()
            try GitHubRepositoryAccessPolicyTests.run()
            try await CredentialStoreAccessTokenProviderTests.run()
            try await GitHubClientTests.run()
            try await GitHubOAuthDeviceFlowClientTests.run()
            try await CodexAuthenticationTests.run()
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
