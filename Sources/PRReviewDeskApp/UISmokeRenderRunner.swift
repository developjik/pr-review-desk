import AppKit
import SwiftUI
import Vision
import PRReviewDeskCore

@MainActor
enum UISmokeRenderRunner {
    static func run() -> String {
        var lines = UISmokeManifest.current.renderedReport()
            .split(separator: "\n")
            .map(String.init)
        lines.append("ui_language=\(AppL10n.languageIdentifier)")
        lines.append("localized_sample=submit-preview-title:\(AppL10n.string("Submit Review Preview"))")

        for surface in UISmokeSurface.allCases {
            do {
                lines.append(try render(surface: surface))
            } catch {
                lines.append("render_failed=\(surface.rawValue):\(error)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func render(surface: UISmokeSurface) throws -> String {
        try render(surface: surface, size: .desktop)
            + "\n"
            + render(surface: surface, size: .compact)
    }

    private static func render(surface: UISmokeSurface, size: UISmokeRenderSize) throws -> String {
        let hostingView = NSHostingView(
            rootView: AnyView(
                view(for: surface)
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height))
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw UISmokeRenderError.bitmapUnavailable
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]), !data.isEmpty else {
            throw UISmokeRenderError.pngUnavailable
        }

        let checksum = data.reduce(UInt64(0)) { partial, byte in
            ((partial &* 31) &+ UInt64(byte)) & 0x00ff_ffff_ffff_ffff
        }

        let recognizedText = try recognizedStrings(from: bitmap)
        let semanticExpectations = semanticExpectations(for: surface, size: size)
        let missingContent = semanticExpectations.filter { expected in
            !recognizedText.contains { text in
                text.localizedStandardContains(expected)
            }
        }
        guard missingContent.isEmpty else {
            throw UISmokeRenderError.missingSemanticContent(
                surface: surface.rawValue,
                size: size.name,
                missing: missingContent,
                recognized: Array(recognizedText.prefix(12))
            )
        }

        return [
            "render=\(surface.rawValue):\(size.name):\(bitmap.pixelsWide)x\(bitmap.pixelsHigh):bytes=\(data.count):checksum=\(checksum)",
            "semantic=\(surface.rawValue):\(size.name):ocr=\(recognizedText.count):matched=\(semanticExpectations.count)",
            "assert=\(surface.rawValue):\(assertions(for: surface).joined(separator: ","))"
        ].joined(separator: "\n")
    }

    private static func recognizedStrings(from bitmap: NSBitmapImageRep) throws -> [String] {
        guard let cgImage = bitmap.cgImage else {
            throw UISmokeRenderError.pngUnavailable
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = AppL10n.languageIdentifier == "ko" ? ["ko-KR", "en-US"] : ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func semanticExpectations(for surface: UISmokeSurface, size: UISmokeRenderSize) -> [String] {
        switch surface {
        case .firstRunSetup:
            return [
                AppL10n.string("Guided setup path"),
                AppL10n.string("Save PAT"),
                AppL10n.string("Advanced GitHub OAuth"),
                AppL10n.string("Technical readiness details")
            ]
        case .repositorySidebar:
            return []
        case .reviewInbox:
            return [
                AppL10n.string("Recents/Favorites")
            ]
        case .diffWorkspace:
            return [
                AppL10n.string("Changed Files"),
                "Sources/App.swift"
            ]
        case .reviewInspector:
            return [
                AppL10n.string("Review Inspector"),
                AppL10n.string("Submit Review")
            ]
        case .submitPreview:
            var expectations = [
                AppL10n.string("Refresh Safety"),
                AppL10n.string("Regenerate")
            ]
            if size.name == "desktop" {
                expectations.append(AppL10n.string("Last checked at %@ UTC.", "2026-05-03 03:09"))
            }
            return expectations
        case .commandPanel:
            return [
                AppL10n.string("Stale")
            ]
        case .settingsReadiness:
            return [
                AppL10n.string("Readiness")
            ]
        }
    }

    static func commandPanelInteractionReport() -> String {
        let actions = [
            ReviewCommandPanelAction(
                title: "Generate AI Review Draft",
                subtitle: "Create a draft.",
                systemImage: "sparkles",
                shortcut: "⇧⌘R",
                isEnabled: true,
                kind: .generateReview
            ),
            ReviewCommandPanelAction(
                title: "Submit Review",
                subtitle: "Generate a valid draft before submitting.",
                systemImage: "paperplane",
                shortcut: "⌘↩",
                isEnabled: false,
                kind: .submitReview
            ),
            ReviewCommandPanelAction(
                title: "Filter Stale",
                subtitle: "Show Stale inbox items.",
                systemImage: "exclamationmark.triangle",
                shortcut: nil,
                isEnabled: true,
                kind: .selectSection(.stale)
            )
        ]
        let filteredActions = ReviewCommandPanelPresentation.filteredActions(actions, query: "filter")
        let selectedID = ReviewCommandPanelPresentation.selectedActionID(
            currentSelectionID: nil,
            filteredActions: filteredActions
        )
        let performedAction = ReviewCommandPanelPresentation.actionToPerform(
            selectedActionID: selectedID,
            filteredActions: filteredActions
        )

        return [
            "interaction=command-panel:filtered=\(filteredActions.count)",
            "interaction=command-panel:selected=\(selectedID ?? "none")",
            "interaction=command-panel:return=\(performedAction?.id ?? "none")"
        ].joined(separator: "\n")
    }

    private static func assertions(for surface: UISmokeSurface) -> [String] {
        switch surface {
        case .firstRunSetup:
            return ["finish-setup", "guided-setup", "github-codex-privacy"]
        case .repositorySidebar:
            return ["repository-sidebar", "queue-control"]
        case .reviewInbox:
            return ["review-inbox", "pull-request-row"]
        case .diffWorkspace:
            return ["diff-workspace", "changed-files"]
        case .reviewInspector:
            return ["review-inspector", "submit-safety"]
        case .submitPreview:
            return ["submit-preview", "preflight-state", "last-checked", "refresh-action", "regenerate-action", "submit-disabled"]
        case .commandPanel:
            return ["command-panel", "shortcut-hints", "selected-row", "return-execution"]
        case .settingsReadiness:
            return ["settings-readiness", "pat-fallback"]
        }
    }

    @ViewBuilder
    private static func view(for surface: UISmokeSurface) -> some View {
        switch surface {
        case .firstRunSetup:
            ReviewInboxView(model: firstRunModel(), selectedSection: .needsSetup)
        case .repositorySidebar:
            ReviewInboxSidebarView(model: populatedModel(), selectedSection: .constant(.recents))
        case .reviewInbox:
            ReviewInboxView(model: populatedModel(), selectedSection: .recents)
        case .diffWorkspace:
            ReviewPaneView(model: populatedModel())
        case .reviewInspector:
            ReviewInspectorView(model: populatedModel())
        case .submitPreview:
            ReviewSubmissionPreviewSheet(
                preview: stalePreview(),
                eventDisplayName: "Comment",
                isRefreshingSafety: false,
                onCancel: {},
                onRefreshSafety: {},
                onRegenerate: {},
                onSubmit: {}
            )
        case .commandPanel:
            ReviewCommandPanelView(
                model: populatedModel(),
                selectedSection: .constant(.recents),
                isInspectorPresented: .constant(true),
                isPresented: .constant(true),
                initialQuery: AppL10n.string("Filter %@", AppL10n.string("Stale")),
                initialSelectedActionID: ReviewCommandPanelActionKind.selectSection(.stale).stableID,
                onDeferredSubmit: {}
            )
        case .settingsReadiness:
            SettingsView(model: firstRunModel())
        }
    }

    private static func firstRunModel() -> AppModel {
        AppModel(
            credentialStore: VersionedCredentialStore(tokenStore: InMemoryTokenStore()),
            reviewDraftStore: InMemoryReviewDraftStore(),
            userDefaults: UserDefaults(suiteName: "PRReviewDesk.UISmoke.\(UUID().uuidString)") ?? .standard
        )
    }

    private static func populatedModel() -> AppModel {
        let model = firstRunModel()
        let repository = sampleRepository()
        let pullRequest = samplePullRequest()

        model.hasToken = true
        model.credentialKindDescription = GitHubCredentialKind.personalAccessToken.displayName
        model.repositories = [repository]
        model.selectedRepository = repository
        model.pullRequests = [pullRequest]
        model.selectedPullRequest = pullRequest
        model.changedFiles = sampleFiles()
        model.selectedChangedFilePath = "Sources/App.swift"
        model.draft = sampleDraft()
        model.reviewBody = "Looks good overall.\n\nPlease address the inline comment before merging."
        model.preflightHeadSha = pullRequest.headSha
        model.isPrivacyDisclosureAcknowledged = true
        return model
    }

    private static func stalePreview() -> ReviewSubmissionPreview {
        ReviewSubmissionPreview.make(
            event: .comment,
            body: "Looks good overall.\n\nPlease address the inline comment before merging.",
            draft: sampleDraft(),
            safetyState: ReviewSubmissionSafetyState(
                reviewedHeadSha: "abc123def456",
                currentHeadSha: "fed654cba321",
                selectedInlineCommentCount: 1,
                invalidSelectedInlineComments: []
            ),
            safetyCheckedAt: Date(timeIntervalSince1970: 1_777_777_777)
        )
    }

    private static func sampleRepository() -> Repository {
        Repository(
            id: 1,
            owner: "developjik",
            name: "pr-review-desk",
            fullName: "developjik/pr-review-desk",
            isPrivate: false
        )
    }

    private static func samplePullRequest() -> PullRequest {
        PullRequest(
            id: 10,
            number: 74,
            title: "Add review submission preview polish",
            htmlURL: URL(string: "https://github.com/developjik/pr-review-desk/pull/74")!,
            author: "developjik",
            headSha: "abc123def456",
            updatedAt: "2026-05-23"
        )
    }

    private static func sampleFiles() -> [PullRequestFile] {
        [
            PullRequestFile(
                path: "Sources/App.swift",
                status: "modified",
                additions: 8,
                deletions: 2,
                patch: """
                @@ -1,2 +1,3 @@
                 import SwiftUI
                +import PRReviewDeskCore
                 struct AppView: View {}
                """
            ),
            PullRequestFile(
                path: "README.md",
                status: "modified",
                additions: 3,
                deletions: 0,
                patch: nil
            )
        ]
    }

    private static func sampleDraft() -> ReviewDraft {
        ReviewDraft(
            summary: "The change improves review submission safety.",
            risks: ["Verify the preview state before posting."],
            inlineComments: [
                InlineCommentDraft(
                    id: "smoke-comment",
                    path: "Sources/App.swift",
                    position: 2,
                    body: "Confirm this import is still needed after the final refactor.",
                    severity: .medium,
                    isSelected: true
                )
            ]
        )
    }
}

private enum UISmokeRenderError: Error {
    case bitmapUnavailable
    case pngUnavailable
    case missingSemanticContent(surface: String, size: String, missing: [String], recognized: [String])
}

private struct UISmokeRenderSize {
    let name: String
    let width: CGFloat
    let height: CGFloat

    static let desktop = UISmokeRenderSize(name: "desktop", width: 920, height: 700)
    static let compact = UISmokeRenderSize(name: "compact", width: 520, height: 700)
}
