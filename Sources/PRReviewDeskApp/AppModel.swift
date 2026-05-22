import Foundation
import SwiftUI
import PRReviewDeskCore

@MainActor
final class AppModel: ObservableObject {
    @Published var tokenInput = ""
    @Published var hasToken = false
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var pullRequests: [PullRequest] = []
    @Published var selectedPullRequest: PullRequest?
    @Published var changedFiles: [PullRequestFile] = []
    @Published var draft: ReviewDraft?
    @Published var reviewBody = ""
    @Published var selectedEvent: ReviewEvent = .comment
    @Published var statusMessage = "Enter a GitHub token or load one from Keychain."
    @Published var isWorking = false
    @Published var canCancelCurrentOperation = false

    private let tokenStore: TokenStore
    private let codexAgent: CodexReviewAgent
    private var githubClient: GitHubClient?
    private var reviewedHeadSha: String?
    private var currentOperationTask: Task<Void, Never>?

    var selectedInlineCommentCount: Int {
        draft?.inlineComments.filter(\.isSelected).count ?? 0
    }

    var reviewCoverageSummary: ReviewCoverageSummary {
        ReviewCoverageSummary(files: changedFiles)
    }

    init(
        tokenStore: TokenStore = KeychainTokenStore(),
        codexAgent: CodexReviewAgent = CodexReviewAgent()
    ) {
        self.tokenStore = tokenStore
        self.codexAgent = codexAgent
    }

    func loadStoredToken() {
        do {
            guard let token = try tokenStore.loadToken(), !token.isEmpty else {
                hasToken = false
                return
            }
            configureGitHubClient(token: token)
            tokenInput = ""
            hasToken = true
            statusMessage = "GitHub token loaded from Keychain."
        } catch {
            statusMessage = "Could not load token: \(error)"
        }
    }

    func saveTokenAndRefresh() async {
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "GitHub token is empty."
            return
        }

        do {
            try tokenStore.saveToken(trimmed)
            configureGitHubClient(token: trimmed)
            tokenInput = ""
            hasToken = true
            statusMessage = "GitHub token saved."
            await refreshRepositories()
        } catch {
            statusMessage = "Could not save token: \(error)"
        }
    }

    func refreshRepositories() async {
        guard let githubClient else {
            statusMessage = "Add a GitHub token first."
            return
        }

        await runWorking("Loading repositories...") {
            repositories = try await githubClient.listRepositories()
            selectedRepository = repositories.first
            statusMessage = repositories.isEmpty ? "No repositories found." : "Loaded \(repositories.count) repositories."
            if let selectedRepository {
                try await loadPullRequests(repository: selectedRepository)
            }
        }
    }

    func selectRepository(_ repository: Repository) async {
        selectedRepository = repository
        selectedPullRequest = nil
        changedFiles = []
        draft = nil
        reviewBody = ""
        reviewedHeadSha = nil

        await runWorking("Loading open pull requests...") {
            try await loadPullRequests(repository: repository)
        }
    }

    func selectPullRequest(_ pullRequest: PullRequest) async {
        selectedPullRequest = pullRequest
        draft = nil
        reviewBody = ""
        reviewedHeadSha = nil

        guard let selectedRepository, let githubClient else {
            return
        }

        await runWorking("Loading changed files...") {
            changedFiles = try await githubClient.pullRequestFiles(repository: selectedRepository, pullRequest: pullRequest)
            statusMessage = "Loaded \(changedFiles.count) changed files. \(reviewCoverageSummary.statusMessage)"
        }
    }

    func startGenerateReview() {
        guard !isWorking else {
            return
        }

        currentOperationTask = Task { @MainActor [weak self] in
            await self?.generateReview()
            self?.currentOperationTask = nil
        }
    }

    func cancelCurrentOperation() {
        guard canCancelCurrentOperation else {
            return
        }
        statusMessage = "Cancelling current operation..."
        currentOperationTask?.cancel()
    }

    func generateReview() async {
        guard let selectedRepository, let selectedPullRequest else {
            statusMessage = "Select a pull request first."
            return
        }

        await runWorking("Generating Codex review draft...", isCancellable: true) {
            let pullRequestForReview: PullRequest
            if let githubClient {
                pullRequestForReview = try await githubClient.pullRequestDetails(
                    repository: selectedRepository,
                    number: selectedPullRequest.number
                )
                self.selectedPullRequest = pullRequestForReview
            } else {
                pullRequestForReview = selectedPullRequest
            }

            if let githubClient {
                changedFiles = try await githubClient.pullRequestFiles(repository: selectedRepository, pullRequest: pullRequestForReview)
            }
            let coverageSummary = reviewCoverageSummary
            let generated = try await codexAgent.generateReview(
                repository: selectedRepository,
                pullRequest: pullRequestForReview,
                files: changedFiles
            )
            draft = generated
            reviewBody = composeReviewBody(from: generated)
            reviewedHeadSha = pullRequestForReview.headSha
            selectedEvent = .comment
            if let warningMessage = coverageSummary.warningMessage {
                statusMessage = "Generated review draft with \(generated.inlineComments.count) inline comments. \(warningMessage)"
            } else {
                statusMessage = "Generated review draft with \(generated.inlineComments.count) inline comments."
            }
        }
    }

    func submitReview() async {
        guard !isWorking else {
            return
        }

        guard let selectedRepository, let selectedPullRequest, let draft, let githubClient else {
            statusMessage = "Generate a review draft before submitting."
            return
        }

        guard let reviewedHeadSha else {
            statusMessage = "Generate a fresh review draft before submitting."
            return
        }

        await runWorking("Submitting review to GitHub...") {
            try await ReviewSubmissionWorkflow(api: githubClient).submitReview(
                repository: selectedRepository,
                pullRequest: selectedPullRequest,
                reviewedHeadSha: reviewedHeadSha,
                draft: draft,
                body: reviewBody,
                event: selectedEvent
            )
            statusMessage = "Submitted \(selectedEvent.displayName) review to GitHub."
        }
    }

    func setInlineCommentSelection(id: String, isSelected: Bool) {
        guard let index = draft?.inlineComments.firstIndex(where: { $0.id == id }) else {
            return
        }
        draft?.inlineComments[index].isSelected = isSelected
    }

    func setInlineCommentBody(id: String, body: String) {
        guard let index = draft?.inlineComments.firstIndex(where: { $0.id == id }) else {
            return
        }
        draft?.inlineComments[index].body = body
    }

    private func configureGitHubClient(token: String) {
        githubClient = GitHubClient(token: token)
    }

    private func loadPullRequests(repository: Repository) async throws {
        guard let githubClient else {
            return
        }
        pullRequests = try await githubClient.listOpenPullRequests(repository: repository)
        statusMessage = pullRequests.isEmpty ? "No open pull requests." : "Loaded \(pullRequests.count) open pull requests."
    }

    private func runWorking(_ message: String, isCancellable: Bool = false, operation: () async throws -> Void) async {
        isWorking = true
        canCancelCurrentOperation = isCancellable
        statusMessage = message
        defer {
            isWorking = false
            canCancelCurrentOperation = false
        }

        do {
            try Task.checkCancellation()
            try await operation()
        } catch is CancellationError {
            statusMessage = "Operation cancelled."
        } catch {
            statusMessage = "\(error)"
        }
    }

    private func composeReviewBody(from draft: ReviewDraft) -> String {
        guard !draft.risks.isEmpty else {
            return draft.summary
        }

        let risks = draft.risks.map { "- \($0)" }.joined(separator: "\n")
        return """
        \(draft.summary)

        Risks:
        \(risks)
        """
    }
}
