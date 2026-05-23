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
        try expectTrue(manifest.requiredLocalizationKeys.contains("Guided setup path"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Save PAT"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Advanced GitHub OAuth"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Technical readiness details"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Submit Review Preview"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Refresh Safety"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Refreshing Safety"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Last checked at %@ UTC."))
        try expectTrue(manifest.requiredLocalizationKeys.contains("No matching repositories"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Clear search"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("No open pull requests in this repository."))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Watch all"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Awaiting selection"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Regenerate"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Replace personal access token"))
        try expectTrue(manifest.requiredLocalizationKeys.contains("Cancel Review Generation"))
        try expectEqual(Set(manifest.requiredLocalizationKeys).count, manifest.requiredLocalizationKeys.count)
    }

    private static func testManifestHasStableReportOutputForScripts() throws {
        let report = UISmokeManifest.current.renderedReport()

        try expectTrue(report.contains("ui_smoke=ready"))
        try expectTrue(report.contains("surface=review-inspector"))
        try expectTrue(report.contains("localization=Submit Review Preview"))
    }
}
