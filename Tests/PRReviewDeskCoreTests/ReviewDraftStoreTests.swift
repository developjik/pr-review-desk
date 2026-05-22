import Foundation
import PRReviewDeskCore

enum ReviewDraftStoreTests {
    static func run() throws {
        try testInMemoryStoreRoundTripsDraftByKey()
        try testInMemoryStoreFindsLatestDraftForPullRequest()
    }

    private static func testInMemoryStoreRoundTripsDraftByKey() throws {
        let store = InMemoryReviewDraftStore()
        let key = ReviewDraftKey(repositoryFullName: "developjik/desk", pullRequestNumber: 12, headSha: "abc")
        let draft = ReviewDraft(
            summary: "Looks good",
            risks: ["Risk"],
            inlineComments: [
                InlineCommentDraft(id: "a", path: "Sources/App.swift", position: 2, body: "Edited", severity: .high, isSelected: false)
            ]
        )
        let stored = StoredReviewDraft(
            key: key,
            draft: draft,
            reviewBody: "Edited body",
            selectedEvent: .requestChanges,
            savedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try store.saveDraft(stored)

        try expectEqual(try store.loadDraft(key: key), stored)
    }

    private static func testInMemoryStoreFindsLatestDraftForPullRequest() throws {
        let store = InMemoryReviewDraftStore()
        let older = StoredReviewDraft(
            key: ReviewDraftKey(repositoryFullName: "developjik/desk", pullRequestNumber: 12, headSha: "old"),
            draft: ReviewDraft(summary: "Old", risks: [], inlineComments: []),
            reviewBody: "Old body",
            selectedEvent: .comment,
            savedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = StoredReviewDraft(
            key: ReviewDraftKey(repositoryFullName: "developjik/desk", pullRequestNumber: 12, headSha: "new"),
            draft: ReviewDraft(summary: "New", risks: [], inlineComments: []),
            reviewBody: "New body",
            selectedEvent: .approve,
            savedAt: Date(timeIntervalSince1970: 200)
        )

        try store.saveDraft(older)
        try store.saveDraft(newer)

        try expectEqual(
            try store.loadLatestDraft(repositoryFullName: "developjik/desk", pullRequestNumber: 12),
            newer
        )
        try expectEqual(
            try store.loadLatestDraft(repositoryFullName: "developjik/desk", pullRequestNumber: 13),
            nil
        )
    }
}
