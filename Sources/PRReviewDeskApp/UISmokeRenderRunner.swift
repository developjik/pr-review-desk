import AppKit
import SwiftUI
import PRReviewDeskCore

@MainActor
enum UISmokeRenderRunner {
    static func run() -> String {
        var lines = UISmokeManifest.current.renderedReport()
            .split(separator: "\n")
            .map(String.init)

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
        let size = NSSize(width: 920, height: 700)
        let hostingView = NSHostingView(
            rootView: AnyView(
                view(for: surface)
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
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

        return [
            "render=\(surface.rawValue):\(bitmap.pixelsWide)x\(bitmap.pixelsHigh):bytes=\(data.count):checksum=\(checksum)",
            "assert=\(surface.rawValue):\(assertions(for: surface).joined(separator: ","))"
        ].joined(separator: "\n")
    }

    private static func assertions(for surface: UISmokeSurface) -> [String] {
        switch surface {
        case .firstRunSetup:
            return ["finish-setup", "recommended-path"]
        case .repositorySidebar:
            return ["repository-sidebar", "queue-control"]
        case .reviewInbox:
            return ["review-inbox", "pull-request-row"]
        case .diffWorkspace:
            return ["diff-workspace", "changed-files"]
        case .reviewInspector:
            return ["review-inspector", "submit-safety"]
        case .submitPreview:
            return ["submit-preview", "preflight-state", "submit-enabled"]
        case .commandPanel:
            return ["command-panel", "shortcut-hints"]
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
                preview: readyPreview(),
                eventDisplayName: "Comment",
                onCancel: {},
                onSubmit: {}
            )
        case .commandPanel:
            ReviewCommandPanelView(
                model: populatedModel(),
                selectedSection: .constant(.recents),
                isInspectorPresented: .constant(true),
                isPresented: .constant(true),
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

    private static func readyPreview() -> ReviewSubmissionPreview {
        ReviewSubmissionPreview.make(
            event: .comment,
            body: "Looks good overall.\n\nPlease address the inline comment before merging.",
            draft: sampleDraft(),
            safetyState: ReviewSubmissionSafetyState(
                reviewedHeadSha: "abc123def456",
                currentHeadSha: "abc123def456",
                selectedInlineCommentCount: 1,
                invalidSelectedInlineComments: []
            )
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
}
