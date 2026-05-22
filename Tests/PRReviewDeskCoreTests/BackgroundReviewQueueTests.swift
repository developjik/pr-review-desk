import Foundation
import PRReviewDeskCore

enum BackgroundReviewQueueTests {
    static func run() throws {
        try testEnqueueDeduplicatesByRepositoryAndPullRequest()
        try testQueueTransitionsThroughDraftLifecycleStates()
        try testNextQueuedItemSkipsTerminalStates()
    }

    private static func testEnqueueDeduplicatesByRepositoryAndPullRequest() throws {
        var queue = BackgroundReviewQueue()

        let first = queue.enqueue(repository: repository, pullRequest: pullRequest(number: 12, headSha: "old"))
        let second = queue.enqueue(repository: repository, pullRequest: pullRequest(number: 12, headSha: "new"))

        try expectEqual(first.id, "developjik/desk#12")
        try expectEqual(second.id, "developjik/desk#12")
        try expectEqual(queue.items.count, 1)
        try expectEqual(queue.items[0].pullRequest.headSha, "new")
        try expectEqual(queue.items[0].state, .queued)
        try expectEqual(queue.nextQueuedItem?.id, "developjik/desk#12")
    }

    private static func testQueueTransitionsThroughDraftLifecycleStates() throws {
        var queue = BackgroundReviewQueue()
        let item = queue.enqueue(repository: repository, pullRequest: pullRequest(number: 12, headSha: "head-1"))
        let draft = ReviewDraft(summary: "Summary", risks: [], inlineComments: [])

        queue.markGenerating(id: item.id)
        try expectEqual(queue.items[0].state, .generating)
        try expectEqual(queue.nextQueuedItem, nil)

        queue.markDraftReady(
            id: item.id,
            pullRequest: pullRequest(number: 12, headSha: "head-1"),
            draft: draft,
            reviewBody: "Summary",
            reviewedHeadSha: "head-1"
        )
        try expectEqual(queue.items[0].state, .draftReady)
        try expectEqual(queue.items[0].draft, draft)
        try expectEqual(queue.items[0].reviewBody, "Summary")
        try expectEqual(queue.items[0].reviewedHeadSha, "head-1")

        queue.markStale(id: item.id, currentHeadSha: "head-2")
        try expectEqual(queue.items[0].state, .stale)
        try expectEqual(queue.items[0].message, "Current head is head-2.")

        queue.markSubmitted(repositoryFullName: "developjik/desk", pullRequestNumber: 12)
        try expectEqual(queue.items[0].state, .submitted)
    }

    private static func testNextQueuedItemSkipsTerminalStates() throws {
        var queue = BackgroundReviewQueue()
        let failed = queue.enqueue(repository: repository, pullRequest: pullRequest(number: 12, headSha: "head-1"))
        let ready = queue.enqueue(repository: repository, pullRequest: pullRequest(number: 13, headSha: "head-1"))
        let queued = queue.enqueue(repository: repository, pullRequest: pullRequest(number: 14, headSha: "head-1"))

        queue.markFailed(id: failed.id, message: "Codex timed out.")
        queue.markDraftReady(
            id: ready.id,
            pullRequest: pullRequest(number: 13, headSha: "head-1"),
            draft: ReviewDraft(summary: "Summary", risks: [], inlineComments: []),
            reviewBody: "Summary",
            reviewedHeadSha: "head-1"
        )

        try expectEqual(queue.nextQueuedItem?.id, queued.id)
    }
}

private let repository = Repository(
    id: 1,
    owner: "developjik",
    name: "desk",
    fullName: "developjik/desk",
    isPrivate: false
)

private func pullRequest(number: Int, headSha: String) -> PullRequest {
    PullRequest(
        id: number,
        number: number,
        title: "PR \(number)",
        htmlURL: URL(string: "https://github.com/developjik/desk/pull/\(number)")!,
        author: "contributor",
        headSha: headSha
    )
}
