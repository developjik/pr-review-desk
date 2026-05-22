import Foundation
import PRReviewDeskCore

enum ReviewSubmissionWorkflowTests {
    static func run() async throws {
        try await testRefetchesPullRequestAndSubmitsWithReviewedHeadCommitID()
        try await testRejectsStaleHeadBeforeSubmitting()
        try await testRejectsInlineCommentOutsideRefetchedDiffBeforeSubmitting()
    }

    private static func testRefetchesPullRequestAndSubmitsWithReviewedHeadCommitID() async throws {
        let api = FakeReviewSubmissionAPI(currentHeadSha: "reviewed-sha", currentFiles: testFiles)
        let workflow = ReviewSubmissionWorkflow(api: api)

        try await workflow.submitReview(
            repository: testRepository,
            pullRequest: testPullRequest(headSha: "old-list-sha"),
            reviewedHeadSha: "reviewed-sha",
            draft: testDraft(position: 2),
            body: "Please address the inline note.",
            event: .comment
        )

        try expectEqual(api.requestedPullRequestNumber, 7)
        try expectEqual(api.requestedFilesPullRequestNumber, 7)
        let submission = try unwrap(api.submittedReview)
        try expectEqual(submission.commitID, "reviewed-sha")
        try expectEqual(submission.event, .comment)
        try expectEqual(submission.body, "Please address the inline note.")
        try expectEqual(submission.comments.count, 1)
    }

    private static func testRejectsStaleHeadBeforeSubmitting() async throws {
        let api = FakeReviewSubmissionAPI(currentHeadSha: "new-sha", currentFiles: testFiles)
        let workflow = ReviewSubmissionWorkflow(api: api)

        do {
            try await workflow.submitReview(
                repository: testRepository,
                pullRequest: testPullRequest(headSha: "old-list-sha"),
                reviewedHeadSha: "reviewed-sha",
                draft: testDraft(position: 2),
                body: "Please address the inline note.",
                event: .comment
            )
            throw TestFailure(message: "expected stale head submission to fail")
        } catch let error as ReviewSubmissionValidationError {
            try expectEqual(error, .staleHead(reviewed: "reviewed-sha", current: "new-sha"))
        }

        try expectEqual(api.requestedPullRequestNumber, 7)
        try expectTrue(api.submittedReview == nil)
    }

    private static func testRejectsInlineCommentOutsideRefetchedDiffBeforeSubmitting() async throws {
        let api = FakeReviewSubmissionAPI(
            currentHeadSha: "reviewed-sha",
            currentFiles: [
                PullRequestFile(
                    path: "Sources/App.swift",
                    status: "modified",
                    additions: 1,
                    deletions: 0,
                    patch: """
                    @@ -1,1 +1,1 @@
                    +let new = true
                    """
                )
            ]
        )
        let workflow = ReviewSubmissionWorkflow(api: api)

        do {
            try await workflow.submitReview(
                repository: testRepository,
                pullRequest: testPullRequest(headSha: "old-list-sha"),
                reviewedHeadSha: "reviewed-sha",
                draft: testDraft(position: 2),
                body: "Please address the inline note.",
                event: .comment
            )
            throw TestFailure(message: "expected invalid inline comment submission to fail")
        } catch let error as ReviewSubmissionValidationError {
            try expectEqual(
                error,
                .invalidInlineComments([
                    InvalidInlineComment(path: "Sources/App.swift", position: 2)
                ])
            )
        }

        try expectEqual(api.requestedPullRequestNumber, 7)
        try expectEqual(api.requestedFilesPullRequestNumber, 7)
        try expectTrue(api.submittedReview == nil)
    }

    private static let testRepository = Repository(
        id: 1,
        owner: "developjik",
        name: "review-desk",
        fullName: "developjik/review-desk",
        isPrivate: false
    )

    private static func testPullRequest(headSha: String) -> PullRequest {
        PullRequest(
            id: 2,
            number: 7,
            title: "Safety gate",
            htmlURL: URL(string: "https://github.com/developjik/review-desk/pull/7")!,
            author: "developjik",
            headSha: headSha
        )
    }

    private static func testDraft(position: Int) -> ReviewDraft {
        ReviewDraft(
            summary: "Summary",
            risks: [],
            inlineComments: [
                InlineCommentDraft(
                    id: "comment-1",
                    path: "Sources/App.swift",
                    position: position,
                    body: "Inline note",
                    severity: .medium,
                    isSelected: true
                )
            ]
        )
    }

    private static let testFiles = [
        PullRequestFile(
            path: "Sources/App.swift",
            status: "modified",
            additions: 1,
            deletions: 0,
            patch: """
            @@ -1,1 +1,2 @@
             let old = true
            +let new = true
            """
        )
    ]
}

private final class FakeReviewSubmissionAPI: PullRequestReviewSubmitting, @unchecked Sendable {
    private let currentHeadSha: String
    private let currentFiles: [PullRequestFile]
    private(set) var requestedPullRequestNumber: Int?
    private(set) var requestedFilesPullRequestNumber: Int?
    private(set) var submittedReview: ReviewSubmission?

    init(currentHeadSha: String, currentFiles: [PullRequestFile]) {
        self.currentHeadSha = currentHeadSha
        self.currentFiles = currentFiles
    }

    func pullRequestDetails(repository: Repository, number: Int) async throws -> PullRequest {
        requestedPullRequestNumber = number
        return PullRequest(
            id: 2,
            number: number,
            title: "Safety gate",
            htmlURL: URL(string: "https://github.com/developjik/review-desk/pull/\(number)")!,
            author: "developjik",
            headSha: currentHeadSha
        )
    }

    func pullRequestFiles(repository: Repository, pullRequest: PullRequest) async throws -> [PullRequestFile] {
        requestedFilesPullRequestNumber = pullRequest.number
        return currentFiles
    }

    func submitReview(
        repository: Repository,
        pullRequest: PullRequest,
        submission: ReviewSubmission
    ) async throws {
        submittedReview = submission
    }
}
