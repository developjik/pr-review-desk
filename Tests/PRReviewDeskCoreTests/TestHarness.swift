import Foundation

@main
enum TestHarness {
    static func main() {
        do {
            try ModelsTests.run()
            try DiffPositionMapperTests.run()
            print("PRReviewDeskCoreTests passed")
        } catch {
            fputs("PRReviewDeskCoreTests failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
