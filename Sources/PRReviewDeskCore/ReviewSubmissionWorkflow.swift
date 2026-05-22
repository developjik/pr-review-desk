import Foundation

public protocol PullRequestReviewSubmitting: Sendable {
    func pullRequestDetails(repository: Repository, number: Int) async throws -> PullRequest

    func pullRequestFiles(repository: Repository, pullRequest: PullRequest) async throws -> [PullRequestFile]

    func submitReview(
        repository: Repository,
        pullRequest: PullRequest,
        submission: ReviewSubmission
    ) async throws
}

extension GitHubClient: PullRequestReviewSubmitting {}

public struct ReviewSubmissionWorkflow: Sendable {
    private let api: any PullRequestReviewSubmitting

    public init(api: any PullRequestReviewSubmitting) {
        self.api = api
    }

    public func submitReview(
        repository: Repository,
        pullRequest: PullRequest,
        reviewedHeadSha: String,
        draft: ReviewDraft,
        body: String,
        event: ReviewEvent
    ) async throws {
        let currentPullRequest = try await api.pullRequestDetails(
            repository: repository,
            number: pullRequest.number
        )
        let currentFiles = try await api.pullRequestFiles(
            repository: repository,
            pullRequest: currentPullRequest
        )
        try ReviewSubmissionValidator.validate(
            reviewedHeadSha: reviewedHeadSha,
            currentHeadSha: currentPullRequest.headSha,
            draft: draft,
            files: currentFiles
        )

        let submission = ReviewSubmission(
            event: event,
            body: body,
            commitID: reviewedHeadSha,
            comments: draft.inlineComments
        )
        try await api.submitReview(
            repository: repository,
            pullRequest: pullRequest,
            submission: submission
        )
    }
}
