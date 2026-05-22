import Foundation
import AppKit
import SwiftUI
import PRReviewDeskCore

struct RecoverableErrorDetails: Identifiable, Equatable {
    let id = UUID()
    let operation: String
    let summary: String
    let details: String
    let recoverySuggestion: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tokenInput = ""
    @Published var hasToken = false
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var pullRequests: [PullRequest] = []
    @Published var selectedPullRequest: PullRequest?
    @Published var repositorySearchText = ""
    @Published var pullRequestSearchText = ""
    @Published var changedFiles: [PullRequestFile] = []
    @Published var selectedChangedFilePath: String?
    @Published var draft: ReviewDraft?
    @Published var reviewBody = ""
    @Published var selectedEvent: ReviewEvent = .comment
    @Published var statusMessage = "Enter a GitHub token or load one from Keychain."
    @Published var isWorking = false
    @Published var canCancelCurrentOperation = false
    @Published var preflightHeadSha: String?
    @Published var recoverableError: RecoverableErrorDetails?
    @Published var tokenValidationStatus = "Not validated."
    @Published var codexCLIStatus = "Not checked."
    @Published var codexLoginStatus = "Not checked."
    @Published var isSubmitConfirmationPresented = false
    @Published var isPrivacyDisclosureAcknowledged = false {
        didSet {
            userDefaults.set(isPrivacyDisclosureAcknowledged, forKey: Self.privacyDisclosureAcknowledgedKey)
        }
    }
    @Published var pendingPrivateRepositoryConsent: PrivateRepositoryConsentRequest?
    @Published private(set) var privateRepositoryConsentAcknowledgementCount = 0

    private static let privacyDisclosureAcknowledgedKey = "privacyDisclosureAcknowledged"
    private static let privateRepositoryConsentAcknowledgementsKey = "privateRepositoryConsentAcknowledgements"
    private let credentialStore: CredentialStore
    private let codexAgent: CodexReviewAgent
    private let userDefaults: UserDefaults
    private var githubClient: GitHubClient?
    private var reviewedHeadSha: String?
    private var currentOperationTask: Task<Void, Never>?
    private var privateRepositoryConsentAcknowledgements: Set<String> = []

    var selectedInlineCommentCount: Int {
        draft?.inlineComments.filter(\.isSelected).count ?? 0
    }

    var filteredRepositories: [Repository] {
        SearchFilter.repositories(repositories, matching: repositorySearchText)
    }

    var filteredPullRequests: [PullRequest] {
        SearchFilter.pullRequests(pullRequests, matching: pullRequestSearchText)
    }

    var reviewCoverageSummary: ReviewCoverageSummary {
        ReviewCoverageSummary(files: changedFiles)
    }

    var selectedChangedFile: PullRequestFile? {
        if let selectedChangedFilePath,
           let file = changedFiles.first(where: { $0.path == selectedChangedFilePath }) {
            return file
        }

        return changedFiles.first
    }

    var reviewedHeadShaForDisplay: String? {
        reviewedHeadSha
    }

    var submitSafetyState: ReviewSubmissionSafetyState {
        (try? ReviewSubmissionValidator.safetyState(
            reviewedHeadSha: reviewedHeadSha,
            currentHeadSha: preflightHeadSha ?? selectedPullRequest?.headSha,
            draft: draft,
            files: changedFiles
        )) ?? ReviewSubmissionSafetyState(
            reviewedHeadSha: reviewedHeadSha,
            currentHeadSha: preflightHeadSha ?? selectedPullRequest?.headSha,
            selectedInlineCommentCount: selectedInlineCommentCount,
            invalidSelectedInlineComments: []
        )
    }

    var commandAvailability: ReviewCommandAvailability {
        ReviewCommandAvailability(
            hasToken: hasToken,
            hasSelectedPullRequest: selectedPullRequest != nil,
            hasSubmittableDraft: hasSubmittableDraft,
            isWorking: isWorking
        )
    }

    var canRefreshActiveScope: Bool {
        commandAvailability.canRefreshActiveScope
    }

    var canGenerateReview: Bool {
        commandAvailability.canGenerateReview
    }

    var canSubmitReview: Bool {
        commandAvailability.canSubmitReview
    }

    var readinessChecklist: ReadinessChecklist {
        ReadinessChecklist(
            hasGitHubCredential: hasToken,
            tokenValidation: tokenValidationReadiness,
            codexCLI: codexCLIReadiness,
            codexLogin: codexLoginReadiness,
            isPrivacyDisclosureAcknowledged: isPrivacyDisclosureAcknowledged
        )
    }

    private var hasSubmittableDraft: Bool {
        draft != nil && submitSafetyState.canSubmit
    }

    var submitSafetyMessage: String {
        let state = submitSafetyState

        guard draft != nil else {
            return "Generate a review draft before submitting."
        }

        if state.isStale {
            return "Draft is stale. Regenerate before submitting."
        }

        if !state.invalidSelectedInlineComments.isEmpty {
            return "\(state.invalidSelectedInlineComments.count) selected inline comments target invalid diff positions."
        }

        return "Ready to submit."
    }

    init(
        credentialStore: CredentialStore = VersionedCredentialStore.keychainDefault(),
        codexAgent: CodexReviewAgent = CodexReviewAgent(),
        userDefaults: UserDefaults = .standard
    ) {
        self.credentialStore = credentialStore
        self.codexAgent = codexAgent
        self.userDefaults = userDefaults
        self.isPrivacyDisclosureAcknowledged = userDefaults.bool(forKey: Self.privacyDisclosureAcknowledgedKey)
        self.privateRepositoryConsentAcknowledgements = Set(
            userDefaults.stringArray(forKey: Self.privateRepositoryConsentAcknowledgementsKey) ?? []
        )
        self.privateRepositoryConsentAcknowledgementCount = privateRepositoryConsentAcknowledgements.count
    }

    func loadStoredToken() {
        do {
            guard let credential = try credentialStore.loadCredential(), !credential.accessToken.isEmpty else {
                hasToken = false
                return
            }
            configureGitHubClient()
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
            try credentialStore.saveCredential(.personalAccessToken(trimmed))
            configureGitHubClient()
            tokenInput = ""
            hasToken = true
            statusMessage = "GitHub token saved."
            await refreshRepositories()
        } catch {
            statusMessage = "Could not save token: \(error)"
        }
    }

    func deleteStoredToken() {
        do {
            try credentialStore.deleteCredential()
            githubClient = nil
            hasToken = false
            repositories = []
            pullRequests = []
            selectedRepository = nil
            selectedPullRequest = nil
            changedFiles = []
            draft = nil
            reviewBody = ""
            tokenValidationStatus = "No token saved."
            statusMessage = "GitHub token deleted."
        } catch {
            statusMessage = "Could not delete token: \(error)"
        }
    }

    func validateCurrentToken() async {
        guard let githubClient else {
            tokenValidationStatus = "Load or save a GitHub token first."
            return
        }

        await runWorking("Validating GitHub token...") {
            let validation = try await githubClient.validateToken()
            let scopes = validation.scopes.isEmpty ? "no scopes reported" : validation.scopes.joined(separator: ", ")
            tokenValidationStatus = "Valid for @\(validation.login). Scopes: \(scopes)."
        }
    }

    func refreshCodexCLIStatus() async {
        await runWorking("Checking Codex CLI...") {
            let runner = ProcessCommandRunner()
            let result = try await runner.run(
                executable: "which",
                arguments: ["codex"],
                standardInput: "",
                workingDirectory: nil,
                timeout: 2
            )

            if result.exitCode == 0 {
                codexCLIStatus = "Found at \(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))."
                let loginResult = try await runner.run(
                    executable: "codex",
                    arguments: ["login", "status"],
                    standardInput: "",
                    workingDirectory: nil,
                    timeout: 5
                )

                if loginResult.exitCode == 0 {
                    codexLoginStatus = loginResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    let details = SensitiveTextRedactor.redact(loginResult.standardError)
                    codexLoginStatus = details.isEmpty
                        ? "Not logged in. Run `codex login` in Terminal."
                        : "Not logged in. \(details)"
                }
            } else {
                codexCLIStatus = "Not found on PATH."
                codexLoginStatus = "Install or expose Codex CLI before checking login."
            }
        }
    }

    func refreshRepositories() async {
        guard let githubClient else {
            statusMessage = "Add a GitHub token first."
            return
        }

        let previousRepository = selectedRepository
        let previousPullRequest = selectedPullRequest

        await runWorking("Loading repositories...") {
            repositories = try await githubClient.listRepositories()
            selectedRepository = StableSelection.repository(
                afterRefresh: repositories,
                previousSelection: previousRepository
            )
            statusMessage = repositories.isEmpty ? "No repositories found." : "Loaded \(repositories.count) repositories."

            if let selectedRepository {
                if selectedRepository.id != previousRepository?.id {
                    clearPullRequestContext(clearPullRequests: true)
                }

                try await loadPullRequests(
                    repository: selectedRepository,
                    preserving: selectedRepository.id == previousRepository?.id ? previousPullRequest : nil
                )
            } else {
                clearPullRequestContext(clearPullRequests: true)
            }
        }
    }

    func refreshActiveScope() async {
        guard !isWorking else {
            return
        }

        if selectedPullRequest != nil {
            await refreshCurrentPullRequest()
        } else if let selectedRepository {
            await runWorking("Refreshing open pull requests...") {
                try await loadPullRequests(repository: selectedRepository)
            }
        } else {
            await refreshRepositories()
        }
    }

    func selectRepository(_ repository: Repository) async {
        selectedRepository = repository
        clearPullRequestContext(clearPullRequests: true)

        await runWorking("Loading open pull requests...") {
            try await loadPullRequests(repository: repository)
        }
    }

    func selectPullRequest(_ pullRequest: PullRequest) async {
        selectedPullRequest = pullRequest
        draft = nil
        reviewBody = ""
        reviewedHeadSha = nil
        selectedChangedFilePath = nil
        preflightHeadSha = pullRequest.headSha

        guard let selectedRepository, let githubClient else {
            return
        }

        await runWorking("Loading changed files...") {
            changedFiles = try await githubClient.pullRequestFiles(repository: selectedRepository, pullRequest: pullRequest)
            selectedChangedFilePath = changedFiles.first?.path
            statusMessage = "Loaded \(changedFiles.count) changed files. \(reviewCoverageSummary.statusMessage)"
        }
    }

    func startGenerateReview() {
        guard !isWorking else {
            return
        }

        if let consentRequest = privateRepositoryConsentRequestForSelectedRepository() {
            pendingPrivateRepositoryConsent = consentRequest
            statusMessage = "Private repository consent required before generating Codex review."
            return
        }

        enqueueGenerateReview()
    }

    private func enqueueGenerateReview() {
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

    func requestSubmitReview() {
        guard canSubmitReview else {
            return
        }

        if selectedEvent == .comment {
            Task { @MainActor in
                await submitReview()
            }
        } else {
            isSubmitConfirmationPresented = true
        }
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
                let previousSelectedFilePath = selectedChangedFilePath
                changedFiles = try await githubClient.pullRequestFiles(repository: selectedRepository, pullRequest: pullRequestForReview)
                selectedChangedFilePath = changedFiles.first(where: { $0.path == previousSelectedFilePath })?.path ?? changedFiles.first?.path
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
            preflightHeadSha = pullRequestForReview.headSha
            selectedEvent = .comment
            if let warningMessage = coverageSummary.warningMessage {
                statusMessage = "Generated review draft with \(generated.inlineComments.count) inline comments. \(warningMessage)"
            } else {
                statusMessage = "Generated review draft with \(generated.inlineComments.count) inline comments."
            }
        }
    }

    func refreshSubmitSafety() async {
        guard let selectedRepository, let selectedPullRequest, let githubClient else {
            statusMessage = "Select a pull request first."
            return
        }

        await runWorking("Refreshing submit safety...") {
            let previousSelectedFilePath = selectedChangedFilePath
            let currentPullRequest = try await githubClient.pullRequestDetails(
                repository: selectedRepository,
                number: selectedPullRequest.number
            )
            let currentFiles = try await githubClient.pullRequestFiles(
                repository: selectedRepository,
                pullRequest: currentPullRequest
            )

            self.selectedPullRequest = currentPullRequest
            changedFiles = currentFiles
            selectedChangedFilePath = changedFiles.first(where: { $0.path == previousSelectedFilePath })?.path ?? changedFiles.first?.path
            preflightHeadSha = currentPullRequest.headSha
            statusMessage = "Submit safety refreshed. \(submitSafetyMessage)"
        }
    }

    func submitReview() async {
        guard !isWorking else {
            return
        }

        isSubmitConfirmationPresented = false

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

    func isInlineCommentInvalid(_ comment: InlineCommentDraft) -> Bool {
        guard comment.isSelected else {
            return false
        }

        return submitSafetyState.invalidSelectedInlineComments.contains {
            $0.path == comment.path && $0.position == comment.position
        }
    }

    func dismissRecoverableError() {
        recoverableError = nil
    }

    func confirmPrivateRepositoryConsentAndGenerate() {
        guard let request = pendingPrivateRepositoryConsent else {
            return
        }

        privateRepositoryConsentAcknowledgements.insert(request.repositoryFullName)
        savePrivateRepositoryConsentAcknowledgements()
        pendingPrivateRepositoryConsent = nil
        statusMessage = "Private repository consent remembered for \(request.repositoryFullName)."
        enqueueGenerateReview()
    }

    func cancelPrivateRepositoryConsent() {
        pendingPrivateRepositoryConsent = nil
        statusMessage = "Private repository consent cancelled. Codex review was not generated."
    }

    func clearPrivateRepositoryConsentAcknowledgements() {
        privateRepositoryConsentAcknowledgements = []
        savePrivateRepositoryConsentAcknowledgements()
        statusMessage = "Cleared remembered private repository consent."
    }

    func acknowledgePrivacyDisclosure() {
        isPrivacyDisclosureAcknowledged = true
        statusMessage = "Privacy disclosure acknowledged."
    }

    func copyCodexLoginCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("codex login", forType: .string)
        statusMessage = "Copied codex login. Run it in Terminal, then check Codex readiness."
    }

    private func configureGitHubClient() {
        githubClient = GitHubClient(
            accessTokenProvider: CredentialStoreAccessTokenProvider(credentialStore: credentialStore)
        )
    }

    private func privateRepositoryConsentRequestForSelectedRepository() -> PrivateRepositoryConsentRequest? {
        guard let selectedRepository else {
            return nil
        }

        return PrivateRepositoryConsentPolicy.request(
            for: selectedRepository,
            acknowledgedRepositories: privateRepositoryConsentAcknowledgements
        )
    }

    private func savePrivateRepositoryConsentAcknowledgements() {
        userDefaults.set(
            Array(privateRepositoryConsentAcknowledgements).sorted(),
            forKey: Self.privateRepositoryConsentAcknowledgementsKey
        )
        privateRepositoryConsentAcknowledgementCount = privateRepositoryConsentAcknowledgements.count
    }

    private var tokenValidationReadiness: ReadinessProbeState {
        guard hasToken else {
            return .unknown("Load or save a GitHub token before validating scopes.")
        }

        if tokenValidationStatus.hasPrefix("Valid for @") {
            return .ready(tokenValidationStatus)
        }

        if tokenValidationStatus == "Not validated." {
            return .unknown("Validate the token to confirm login and scopes.")
        }

        return .needsAction(tokenValidationStatus)
    }

    private var codexCLIReadiness: ReadinessProbeState {
        if codexCLIStatus.hasPrefix("Found at ") {
            return .ready(codexCLIStatus)
        }

        if codexCLIStatus == "Not checked." {
            return .unknown("Check whether the Codex CLI is available on PATH.")
        }

        return .needsAction(codexCLIStatus)
    }

    private var codexLoginReadiness: ReadinessProbeState {
        if codexLoginStatus.hasPrefix("Logged in") {
            return .ready(codexLoginStatus)
        }

        if codexLoginStatus == "Not checked." {
            return .unknown("Check Codex login status. If needed, run `codex login` in Terminal.")
        }

        return .needsAction(codexLoginStatus)
    }

    private func loadPullRequests(
        repository: Repository,
        preserving previousPullRequest: PullRequest? = nil
    ) async throws {
        guard let githubClient else {
            return
        }

        pullRequests = try await githubClient.listOpenPullRequests(repository: repository)
        let preservedPullRequest = StableSelection.pullRequest(
            afterRefresh: pullRequests,
            previousSelection: previousPullRequest
        )
        if previousPullRequest != nil {
            if let preservedPullRequest {
                selectedPullRequest = preservedPullRequest
            } else {
                clearPullRequestContext(clearPullRequests: false)
            }
        }

        statusMessage = pullRequests.isEmpty ? "No open pull requests." : "Loaded \(pullRequests.count) open pull requests."
    }

    private func clearPullRequestContext(clearPullRequests: Bool) {
        if clearPullRequests {
            pullRequests = []
        }
        selectedPullRequest = nil
        changedFiles = []
        selectedChangedFilePath = nil
        draft = nil
        reviewBody = ""
        reviewedHeadSha = nil
        preflightHeadSha = nil
    }

    private func refreshCurrentPullRequest() async {
        guard let selectedRepository, let selectedPullRequest, let githubClient else {
            statusMessage = "Select a pull request first."
            return
        }

        await runWorking("Refreshing pull request...") {
            let previousSelectedFilePath = selectedChangedFilePath
            let currentPullRequest = try await githubClient.pullRequestDetails(
                repository: selectedRepository,
                number: selectedPullRequest.number
            )
            let currentFiles = try await githubClient.pullRequestFiles(
                repository: selectedRepository,
                pullRequest: currentPullRequest
            )

            self.selectedPullRequest = currentPullRequest
            changedFiles = currentFiles
            selectedChangedFilePath = changedFiles.first(where: { $0.path == previousSelectedFilePath })?.path ?? changedFiles.first?.path
            preflightHeadSha = currentPullRequest.headSha
            statusMessage = "Refreshed pull request and \(changedFiles.count) changed files. \(reviewCoverageSummary.statusMessage)"
        }
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
            let details = SensitiveTextRedactor.redact("\(error)")
            statusMessage = "Failed: \(shortOperationName(message))"
            recoverableError = RecoverableErrorDetails(
                operation: shortOperationName(message),
                summary: firstLine(details),
                details: details,
                recoverySuggestion: recoverySuggestion(for: error)
            )
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

    private func shortOperationName(_ message: String) -> String {
        message.replacingOccurrences(of: "...", with: "")
    }

    private func firstLine(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? text
    }

    private func recoverySuggestion(for error: Error) -> String {
        switch error {
        case CodexReviewError.cancelled:
            return "Start generation again when ready."
        case CodexReviewError.missingExecutable:
            return "Install or expose the Codex CLI on PATH, then retry generation."
        case CodexReviewError.timedOut:
            return "Reduce the PR size or retry generation."
        case ReviewSubmissionValidationError.staleHead:
            return "Refresh safety or regenerate the draft before submitting."
        case ReviewSubmissionValidationError.invalidInlineComments:
            return "Deselect invalid comments, refresh safety, or regenerate the draft."
        case GitHubError.requestFailed:
            return "Check GitHub access, token scopes, and the repository state, then retry."
        default:
            return "Check the details, adjust the input if needed, then retry."
        }
    }
}
