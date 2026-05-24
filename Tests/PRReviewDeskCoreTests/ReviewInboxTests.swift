import Foundation
import PRReviewDeskCore

enum ReviewInboxTests {
    static func run() throws {
        try testInboxSectionsClassifyQueuedReviews()
        try testTriageRowMetadataSummarizesFilesDraftAndSeverity()
        try testRecentsKeepsActionablePullRequestsVisible()
        try testInboxSelectionPolicySelectsFirstVisibleRowWhenNothingIsSelected()
        try testInboxSelectionPolicyMovesToSelectedRowsCurrentSection()
        try testInboxSelectionPolicyStaysOnUserSelectedEmptySection()
        try testInboxSelectionPolicyClearsHiddenSelectionWhenCurrentSectionIsEmpty()
        try testDiffReviewFileStateTracksViewedAndCollapsedFiles()
        try testCommandAvailabilityIncludesContextualActions()
    }

    private static func testInboxSectionsClassifyQueuedReviews() throws {
        let repository = sampleRepository(isPrivate: false)
        let draftReady = BackgroundReviewQueueItem(
            repository: repository,
            pullRequest: samplePullRequest(number: 1, headSha: "ready-sha"),
            state: .draftReady,
            draft: sampleDraft(),
            reviewedHeadSha: "ready-sha"
        )
        let stale = BackgroundReviewQueueItem(
            repository: repository,
            pullRequest: samplePullRequest(number: 2, headSha: "new-sha"),
            state: .stale,
            reviewedHeadSha: "old-sha"
        )
        let running = BackgroundReviewQueueItem(
            repository: repository,
            pullRequest: samplePullRequest(number: 3, headSha: "running-sha"),
            state: .generating
        )

        try expectEqual(ReviewInboxSection.classify(queueItem: draftReady), .draftReady)
        try expectEqual(ReviewInboxSection.classify(queueItem: stale), .stale)
        try expectEqual(ReviewInboxSection.classify(queueItem: running), .running)
    }

    private static func testTriageRowMetadataSummarizesFilesDraftAndSeverity() throws {
        let repository = sampleRepository(isPrivate: true)
        let pullRequest = samplePullRequest(number: 42, headSha: "abc123")
        let files = [
            PullRequestFile(path: "Sources/App.swift", status: "modified", additions: 10, deletions: 2, patch: "@@ -1 +1 @@"),
            PullRequestFile(path: "Assets/logo.png", status: "modified", additions: 5, deletions: 1, patch: nil)
        ]

        let row = PullRequestTriageRow(
            repository: repository,
            pullRequest: pullRequest,
            files: files,
            draft: sampleDraft(),
            queueState: .draftReady,
            reviewedHeadSha: "abc123"
        )

        try expectEqual(row.id, "developjik/desk#42")
        try expectEqual(row.author, "contributor")
        try expectEqual(row.fileCount, 2)
        try expectEqual(row.additions, 15)
        try expectEqual(row.deletions, 3)
        try expectEqual(row.draftStatus, .draftReady)
        try expectTrue(row.hasCoverageWarning)
        try expectTrue(row.repositoryIsPrivate)
        try expectEqual(row.topSeverity, .high)
        try expectEqual(row.section, .draftReady)
    }

    private static func testRecentsKeepsActionablePullRequestsVisible() throws {
        let repository = sampleRepository(isPrivate: false)
        let notGenerated = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 1, headSha: "fresh-sha")
        )
        let draftReady = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 2, headSha: "ready-sha"),
            draft: sampleDraft(),
            reviewedHeadSha: "ready-sha"
        )
        let stale = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 3, headSha: "new-sha"),
            draft: sampleDraft(),
            reviewedHeadSha: "old-sha"
        )
        let submitted = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 4, headSha: "submitted-sha"),
            draft: sampleDraft(),
            queueState: .submitted,
            reviewedHeadSha: "submitted-sha"
        )

        try expectTrue(notGenerated.isVisible(in: .recents))
        try expectTrue(draftReady.isVisible(in: .recents))
        try expectTrue(stale.isVisible(in: .recents))
        try expectEqual(submitted.isVisible(in: .recents), false)
        try expectTrue(draftReady.isVisible(in: .draftReady))
        try expectTrue(stale.isVisible(in: .stale))
    }

    private static func testInboxSelectionPolicySelectsFirstVisibleRowWhenNothingIsSelected() throws {
        let repository = sampleRepository(isPrivate: false)
        let first = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 11, headSha: "first-sha")
        )
        let second = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 12, headSha: "second-sha")
        )

        try expectEqual(
            ReviewInboxSelectionPolicy.decision(
                selectedRow: nil,
                visibleRows: [first, second],
                selectedSection: .recents
            ),
            .select(rowID: first.id)
        )
    }

    private static func testInboxSelectionPolicyMovesToSelectedRowsCurrentSection() throws {
        let repository = sampleRepository(isPrivate: false)
        let selected = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 21, headSha: "ready-sha"),
            draft: sampleDraft(),
            reviewedHeadSha: "ready-sha"
        )

        try expectEqual(
            ReviewInboxSelectionPolicy.decision(
                selectedRow: selected,
                visibleRows: [],
                selectedSection: .stale
            ),
            .moveSection(.draftReady, rowID: selected.id)
        )
    }

    private static func testInboxSelectionPolicyStaysOnUserSelectedEmptySection() throws {
        let repository = sampleRepository(isPrivate: false)
        let selected = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 22, headSha: "ready-sha"),
            draft: sampleDraft(),
            reviewedHeadSha: "ready-sha"
        )

        try expectEqual(
            ReviewInboxSelectionPolicy.decision(
                selectedRow: selected,
                visibleRows: [],
                selectedSection: .stale,
                reason: .userSelectedFilter
            ),
            .clear
        )
    }

    private static func testInboxSelectionPolicyClearsHiddenSelectionWhenCurrentSectionIsEmpty() throws {
        let repository = sampleRepository(isPrivate: false)
        let selected = PullRequestTriageRow(
            repository: repository,
            pullRequest: samplePullRequest(number: 31, headSha: "ready-sha"),
            draft: sampleDraft(),
            reviewedHeadSha: "ready-sha"
        )

        try expectEqual(
            ReviewInboxSelectionPolicy.decision(
                selectedRow: selected,
                visibleRows: [],
                selectedSection: .draftReady
            ),
            .clear
        )
    }

    private static func testDiffReviewFileStateTracksViewedAndCollapsedFiles() throws {
        var state = DiffReviewFileState()

        try expectEqual(state.isViewed("Sources/App.swift"), false)
        try expectEqual(state.isCollapsed("Sources/App.swift"), false)

        state.toggleViewed(path: "Sources/App.swift")
        state.toggleCollapsed(path: "Sources/App.swift")

        try expectTrue(state.isViewed("Sources/App.swift"))
        try expectTrue(state.isCollapsed("Sources/App.swift"))

        state.markViewed(path: "Sources/App.swift", isViewed: false)
        state.markCollapsed(path: "Sources/App.swift", isCollapsed: false)

        try expectEqual(state.isViewed("Sources/App.swift"), false)
        try expectEqual(state.isCollapsed("Sources/App.swift"), false)
    }

    private static func testCommandAvailabilityIncludesContextualActions() throws {
        let availability = ReviewCommandAvailability(
            hasToken: true,
            hasSelectedPullRequest: true,
            hasSubmittableDraft: true,
            isWorking: false,
            hasSelectedFile: true,
            hasFocusedInlineComment: true,
            supportsSelectedFileRegeneration: true
        )

        try expectTrue(availability.canOpenPullRequest)
        try expectTrue(availability.canRegenerateSelectedFile)
        try expectTrue(availability.canRevealInlineComment)
        try expectTrue(availability.canToggleInspector)
        try expectTrue(availability.canCopyCodexLoginCommand)
    }

    private static func sampleRepository(isPrivate: Bool) -> Repository {
        Repository(
            id: 100,
            owner: "developjik",
            name: "desk",
            fullName: "developjik/desk",
            isPrivate: isPrivate
        )
    }

    private static func samplePullRequest(number: Int, headSha: String) -> PullRequest {
        PullRequest(
            id: number,
            number: number,
            title: "Improve review flow",
            htmlURL: URL(string: "https://github.com/developjik/desk/pull/\(number)")!,
            author: "contributor",
            headSha: headSha
        )
    }

    private static func sampleDraft() -> ReviewDraft {
        ReviewDraft(
            summary: "Review summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(path: "Sources/App.swift", position: 2, body: "High concern", severity: .high),
                InlineCommentDraft(path: "Sources/App.swift", position: 4, body: "Low concern", severity: .low)
            ]
        )
    }
}
