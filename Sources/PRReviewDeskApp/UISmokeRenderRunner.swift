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
        if AppL10n.usesSmokeLanguagePreference {
            lines.append("ui_preference_language=\(AppL10n.languageIdentifier)")
            lines.append("preference_localized_sample=submit-preview-title:\(AppL10n.string("Submit Review Preview"))")
        }

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
        let bitmap = try renderedBitmap(for: view(for: surface), size: size)
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
            "semantic=\(surface.rawValue):\(size.name):ocr=\(recognizedText.count):matched=\(semanticExpectations.count)"
        ].joined(separator: "\n")
    }

    private static func renderedBitmap<Content: View>(
        for view: Content,
        size: UISmokeRenderSize
    ) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(
            rootView: AnyView(
                view
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            window.close()
            throw UISmokeRenderError.bitmapUnavailable
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        window.close()
        return bitmap
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
                AppL10n.string("Sign in with GitHub"),
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

    static func commandPanelKeyboardReport() -> String {
        let state = CommandPanelKeyboardSmokeState()
        let hostingView = NSHostingView(
            rootView: ReviewCommandPanelView(
                model: populatedModel(),
                selectedSection: Binding(
                    get: { state.selectedSection },
                    set: { state.selectedSection = $0 }
                ),
                isInspectorPresented: Binding(
                    get: { state.isInspectorPresented },
                    set: { state.isInspectorPresented = $0 }
                ),
                isPresented: Binding(
                    get: { state.isPresented },
                    set: { state.isPresented = $0 }
                ),
                initialQuery: AppL10n.string("Filter"),
                initialSelectedActionID: nil,
                onDeferredSubmit: {
                    state.deferredSubmitCount += 1
                }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        sendKey(to: window, keyCode: 125, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        sendKey(to: window, keyCode: 36, characters: "\r")
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        window.close()

        return [
            "interaction=command-panel-keyboard:selected-section=\(state.selectedSection.rawValue)",
            "interaction=command-panel-keyboard:is-presented=\(state.isPresented)",
            "interaction=command-panel-keyboard:deferred-submit=\(state.deferredSubmitCount)"
        ].joined(separator: "\n")
    }

    static func commandPanelSelectionVisualReport() -> String {
        do {
            let size = UISmokeRenderSize(name: "command-panel-selection", width: 520, height: 520)
            let bitmap = try renderedBitmap(for: view(for: .commandPanel), size: size)
            let metrics = selectedRowFocusMetrics(in: bitmap)
            guard metrics.focusPixels >= 600, metrics.maxRowPixels >= 180 else {
                return [
                    "visual_failed=command-panel:selected-row=select-section-stale",
                    "visual_failed=command-panel:focus-pixels=\(metrics.focusPixels):max-row=\(metrics.maxRowPixels)"
                ].joined(separator: "\n")
            }

            return "visual=command-panel:selected-row=select-section-stale:focus-pixels=\(metrics.focusPixels):max-row=\(metrics.maxRowPixels)"
        } catch {
            return "visual_failed=command-panel:selected-row=select-section-stale:error=\(error)"
        }
    }

    static func layoutContractReport() -> String {
        do {
            let reviewInboxBitmap = try renderedBitmap(
                for: ReviewInboxView(model: populatedModel(), selectedSection: .recents),
                size: .desktop
            )
            let reviewInboxTopY = firstNonBackgroundRow(in: reviewInboxBitmap)
            let reviewInboxMinimumY = Int(ReviewWorkspaceLayoutPolicy.primaryColumnTopContentInset)
            guard reviewInboxTopY >= reviewInboxMinimumY else {
                return "layout_failed=review-inbox:top-content-y=\(reviewInboxTopY):minimum=\(reviewInboxMinimumY)"
            }

            let sidebarBitmap = try renderedBitmap(
                for: ReviewInboxSidebarView(model: populatedModel(), selectedSection: .constant(.recents)),
                size: .desktop
            )
            let sidebarTopY = firstNonBackgroundRow(in: sidebarBitmap)
            let sidebarMinimumY = Int(ReviewWorkspaceLayoutPolicy.sidebarTopContentInset)
            guard sidebarTopY >= sidebarMinimumY else {
                return "layout_failed=repository-sidebar:top-content-y=\(sidebarTopY):minimum=\(sidebarMinimumY)"
            }

            return [
                "layout=review-inbox:top-content-y=\(reviewInboxTopY):minimum=\(reviewInboxMinimumY)",
                "layout=repository-sidebar:top-content-y=\(sidebarTopY):minimum=\(sidebarMinimumY)"
            ].joined(separator: "\n")
        } catch {
            return "layout_failed=review-inbox:error=\(error)"
        }
    }

    static func accessibilityReport() -> String {
        let firstRunNoTokenControls = renderedAccessibilityControls(
            for: ReviewInboxView(model: firstRunModel(), selectedSection: .needsSetup)
        )
        let firstRunLoadedTokenControls = renderedAccessibilityControls(
            for: ReviewInboxView(model: firstRunLoadedTokenModel(), selectedSection: .needsSetup)
        )
        let submitPreviewControls = renderedAccessibilityControls(
            for: ReviewSubmissionPreviewSheet(
                preview: stalePreview(),
                eventDisplayName: "Comment",
                isRefreshingSafety: false,
                onCancel: {},
                onRefreshSafety: {},
                onRegenerate: {},
                onSubmit: {}
            )
        )
        let commandPanelControls = renderedAccessibilityControls(
            for: ReviewCommandPanelView(
                model: populatedModel(),
                selectedSection: .constant(.recents),
                isInspectorPresented: .constant(true),
                isPresented: .constant(true),
                initialQuery: AppL10n.string("Filter %@", AppL10n.string("Stale")),
                initialSelectedActionID: ReviewCommandPanelActionKind.selectSection(.stale).stableID,
                onDeferredSubmit: {}
            )
        )
        let settingsLoadedTokenControls = renderedAccessibilityControls(
            for: SettingsView(model: settingsLoadedTokenModel())
        )
        let reviewInboxControls = renderedAccessibilityControls(
            for: ReviewInboxView(model: selectedRecentsModel(), selectedSection: .recents)
        )

        return [
            accessibilityLine(surface: "first-run-setup.no-token", controls: firstRunNoTokenControls),
            accessibilityLine(surface: "first-run-setup.loaded-token", controls: firstRunLoadedTokenControls),
            accessibilityLine(surface: "submit-preview", controls: submitPreviewControls),
            accessibilityLine(surface: "command-panel", controls: commandPanelControls),
            accessibilityLine(surface: "settings.loaded-token", controls: settingsLoadedTokenControls),
            accessibilityLine(surface: "review-inbox", controls: reviewInboxControls)
        ].joined(separator: "\n")
    }

    private static func sendKey(to window: NSWindow, keyCode: UInt16, characters: String) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            return
        }

        window.sendEvent(event)
    }

    private static func selectedRowFocusMetrics(in bitmap: NSBitmapImageRep) -> (focusPixels: Int, maxRowPixels: Int) {
        let minX = 24
        let maxX = max(minX, bitmap.pixelsWide - 24)
        let minY = 80
        let maxY = max(minY, bitmap.pixelsHigh - 120)
        var focusPixels = 0
        var maxRowPixels = 0

        for y in minY..<maxY {
            var rowPixels = 0
            for x in minX..<maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.9,
                      color.blueComponent > 0.72,
                      color.blueComponent > color.redComponent + 0.035,
                      color.blueComponent > color.greenComponent + 0.01
                else {
                    continue
                }

                rowPixels += 1
            }
            focusPixels += rowPixels
            maxRowPixels = max(maxRowPixels, rowPixels)
        }

        return (focusPixels, maxRowPixels)
    }

    private static func firstNonBackgroundRow(in bitmap: NSBitmapImageRep) -> Int {
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
            return 0
        }

        for y in 0..<bitmap.pixelsHigh {
            var nonBackgroundPixels = 0
            stride(from: 0, to: bitmap.pixelsWide, by: 4).forEach { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.85 else {
                    return
                }

                let distance = abs(color.redComponent - background.redComponent)
                    + abs(color.greenComponent - background.greenComponent)
                    + abs(color.blueComponent - background.blueComponent)
                if distance > 0.12 {
                    nonBackgroundPixels += 1
                }
            }

            if nonBackgroundPixels >= 6 {
                return y
            }
        }

        return bitmap.pixelsHigh
    }

    private static func renderedAccessibilityControls<Content: View>(
        for view: Content,
        size: UISmokeRenderSize = .desktop
    ) -> [UISmokeAccessibilityControl] {
        let state = UISmokeAccessibilityCaptureState()
        let hostingView = NSHostingView(
            rootView: AnyView(
                view
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .onPreferenceChange(UISmokeAccessibilityControlPreferenceKey.self) { controls in
                        state.controls = controls
                    }
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.close()

        return state.controls
    }

    private static func accessibilityLine(
        surface: String,
        controls: [UISmokeAccessibilityControl]
    ) -> String {
        let uniqueControls = Dictionary(grouping: controls, by: \.identifier)
            .compactMap { _, controls in controls.last }
            .sorted { lhs, rhs in lhs.identifier < rhs.identifier }
            .map(\.reportToken)

        return "accessibility=\(surface):rendered-controls=\(uniqueControls.joined(separator: ","))"
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

    private static func firstRunLoadedTokenModel() -> AppModel {
        let model = firstRunModel()
        model.hasToken = true
        model.credentialKindDescription = AppL10n.string(GitHubCredentialKind.oauthUserToken.displayName)
        model.tokenValidationStatus = AppL10n.string("GitHub credential is loaded. Validate scopes before generating reviews.")
        return model
    }

    private static func settingsLoadedTokenModel() -> AppModel {
        let model = firstRunLoadedTokenModel()
        model.grantedGitHubScopes = [
            "repo",
            "read:org",
            "workflow",
            "pull_requests:write"
        ]
        model.isPrivacyDisclosureAcknowledged = true
        return model
    }

    private static func populatedModel() -> AppModel {
        let model = firstRunModel()
        let repository = sampleRepository()
        let pullRequest = samplePullRequest()

        model.hasToken = true
        model.credentialKindDescription = AppL10n.string(GitHubCredentialKind.oauthUserToken.displayName)
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

    private static func selectedRecentsModel() -> AppModel {
        let model = firstRunModel()
        let repository = sampleRepository()
        let pullRequest = samplePullRequest()

        model.hasToken = true
        model.credentialKindDescription = AppL10n.string(GitHubCredentialKind.oauthUserToken.displayName)
        model.repositories = [repository]
        model.selectedRepository = repository
        model.pullRequests = [pullRequest]
        model.selectedPullRequest = pullRequest
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

@MainActor
private final class CommandPanelKeyboardSmokeState {
    var selectedSection = ReviewInboxSection.draftReady
    var isInspectorPresented = true
    var isPresented = true
    var deferredSubmitCount = 0
}

@MainActor
private final class UISmokeAccessibilityCaptureState {
    var controls: [UISmokeAccessibilityControl] = []
}

private struct UISmokeRenderSize {
    let name: String
    let width: CGFloat
    let height: CGFloat

    static let desktop = UISmokeRenderSize(name: "desktop", width: 920, height: 700)
    static let compact = UISmokeRenderSize(name: "compact", width: 520, height: 700)
}
