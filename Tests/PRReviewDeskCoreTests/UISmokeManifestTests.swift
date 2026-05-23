import Foundation
import PRReviewDeskCore

enum UISmokeManifestTests {
    static func run() throws {
        try testManifestCoversCriticalReviewWorkflowSurfaces()
        try testManifestHasStableReportOutputForScripts()
    }

    private static func testManifestCoversCriticalReviewWorkflowSurfaces() throws {
        let manifest = UISmokeManifest.current

        try expectEqual(Set(manifest.surfaces), Set(UISmokeSurface.allCases))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Finish setup"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Submit Review Preview"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("No matching repositories"))
        try expectEqual(Set(manifest.requiredLocalizationKeys).count, manifest.requiredLocalizationKeys.count)
    }

    private static func testManifestHasStableReportOutputForScripts() throws {
        let report = UISmokeManifest.current.renderedReport()

        try expectTrue(report.contains("ui_smoke=ready"))
        try expectTrue(report.contains("surface=review-inspector"))
        try expectTrue(report.contains("localization=Submit Review Preview"))
    }
}
