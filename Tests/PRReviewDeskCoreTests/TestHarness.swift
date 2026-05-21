import Foundation

@main
enum TestHarness {
    static func main() async {
        do {
            try ModelsTests.run()
            try DiffPositionMapperTests.run()
            try await GitHubClientTests.run()
            print("PRReviewDeskCoreTests passed")
        } catch {
            fputs("PRReviewDeskCoreTests failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
