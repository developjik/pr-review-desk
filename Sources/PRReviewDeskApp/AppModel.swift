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

struct InlineCommentFocusTarget: Equatable, Sendable {
    let commentID: String
    let path: String
    let position: Int
}

private enum PrivateRepositoryConsentContinuation {
    case generateCurrentReview
    case enqueueSelectedPullRequest
    case enqueueSelectedRepository
    case runBackgroundQueue
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tokenInput = ""
    @Published var oauthClientID = ""
    @Published var oauthStatus = "Not started."
    @Published var oauthAuthorization: OAuthDeviceAuthorization?
    @Published var isOAuthSignInPending = false
    @Published var grantedGitHubScopes: [String] = []
    @Published var hasToken = false
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var pullRequests: [PullRequest] = []
    @Published var selectedPullRequest: PullRequest?
    @Published var repositorySearchText = ""
    @Published var pullRequestSearchText = ""
    @Published var changedFiles: [PullRequestFile] = []
    @Published var selectedChangedFilePath: String?
    @Published var focusedInlineCommentTarget: InlineCommentFocusTarget?
    @Published var draft: ReviewDraft?
    @Published var reviewBody = "" {
        didSet {
            persistCurrentDraftIfPossible()
        }
    }
    @Published var selectedEvent: ReviewEvent = .comment {
        didSet {
            persistCurrentDraftIfPossible()
        }
    }
    @Published var statusMessage = "Enter a GitHub token or load one from Keychain."
    @Published var isWorking = false
    @Published var canCancelCurrentOperation = false
    @Published var preflightHeadSha: String?
    @Published var recoverableError: RecoverableErrorDetails?
    @Published var tokenValidationStatus = "Not validated."
    @Published var codexCLIStatus = "Not checked."
    @Published var codexLoginStatus = "Not checked."
    @Published var isSubmitConfirmationPresented = false
    @Published var backgroundReviewQueue = BackgroundReviewQueue()
    @Published var isBackgroundReviewQueueRunning = false
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
    private let oauthCredentialStore: any OAuthCredentialStoring
    private let storedCredentialLoader: (any StoredGitHubCredentialLoading)?
    private let credentialMetadataStore: (any OAuthCredentialStoring)?
    private let oauthDeviceFlowClient: GitHubOAuthDeviceFlowClient
    private let codexAgent: CodexReviewAgent
    private let reviewDraftStore: any ReviewDraftStore
    private let userDefaults: UserDefaults
    private var githubClient: GitHubClient?
    private var reviewedHeadSha: String?
    private var currentOperationTask: Task<Void, Never>?
    private var backgroundQueueTask: Task<Void, Never>?
    private var oauthSignInTask: Task<Void, Never>?
    private var privateRepositoryConsentAcknowledgements: Set<String> = []
    private var pendingPrivateRepositoryConsentContinuation: PrivateRepositoryConsentContinuation?

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
        commandAvailability.canGenerateReview && selectedRepositoryAccessDecision.isAllowed
    }

    var canSubmitReview: Bool {
        commandAvailability.canSubmitReview
    }

    var canWatchSelectedPullRequest: Bool {
        hasToken && selectedRepository != nil && selectedPullRequest != nil && selectedRepositoryAccessDecision.isAllowed
    }

    var canWatchSelectedRepository: Bool {
        hasToken && selectedRepository != nil && !pullRequests.isEmpty && selectedRepositoryAccessDecision.isAllowed
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
        credentialStore: (any CredentialStore)? = nil,
        oauthCredentialStore: (any OAuthCredentialStoring)? = nil,
        oauthDeviceFlowClient: GitHubOAuthDeviceFlowClient = GitHubOAuthDeviceFlowClient(),
        codexAgent: CodexReviewAgent = CodexReviewAgent(),
        reviewDraftStore: any ReviewDraftStore = FileReviewDraftStore.appDefault(),
        userDefaults: UserDefaults = .standard
    ) {
        let defaultCredentialStore = VersionedCredentialStore.keychainDefault()
        let resolvedCredentialStore = credentialStore ?? defaultCredentialStore
        let resolvedOAuthCredentialStore = oauthCredentialStore
            ?? (resolvedCredentialStore as? any OAuthCredentialStoring)
            ?? defaultCredentialStore
        self.credentialStore = resolvedCredentialStore
        self.oauthCredentialStore = resolvedOAuthCredentialStore
        self.storedCredentialLoader = (resolvedCredentialStore as? any StoredGitHubCredentialLoading)
            ?? (resolvedOAuthCredentialStore as? any StoredGitHubCredentialLoading)
        self.credentialMetadataStore = resolvedCredentialStore as? any OAuthCredentialStoring
        self.oauthDeviceFlowClient = oauthDeviceFlowClient
        self.codexAgent = codexAgent
        self.reviewDraftStore = reviewDraftStore
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
                grantedGitHubScopes = []
                tokenValidationStatus = "No token saved."
                return
            }
            configureGitHubClient()
            tokenInput = ""
            grantedGitHubScopes = loadStoredGitHubScopes()
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
            grantedGitHubScopes = []
            tokenValidationStatus = "Not validated."
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
            grantedGitHubScopes = []
            tokenValidationStatus = "No token saved."
            statusMessage = "GitHub token deleted."
        } catch {
            statusMessage = "Could not delete token: \(error)"
        }
    }

    func startOAuthDeviceSignIn() {
        guard !isOAuthSignInPending else {
            return
        }

        let clientID = oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            oauthStatus = "Enter an OAuth App client ID first."
            return
        }

        oauthSignInTask = Task { @MainActor [weak self] in
            await self?.runOAuthDeviceSignIn(clientID: clientID)
            self?.oauthSignInTask = nil
        }
    }

    func cancelOAuthDeviceSignIn() {
        guard isOAuthSignInPending else {
            return
        }

        oauthStatus = "Cancelling GitHub sign-in..."
        oauthSignInTask?.cancel()
    }

    func copyOAuthUserCode() {
        guard let userCode = oauthAuthorization?.userCode else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        oauthStatus = "Copied GitHub device code."
    }

    func validateCurrentToken() async {
        guard let githubClient else {
            tokenValidationStatus = "Load or save a GitHub token first."
            return
        }

        await runWorking("Validating GitHub token...") {
            let validation = try await githubClient.validateToken()
            grantedGitHubScopes = validation.scopes
            if let credential = try credentialStore.loadCredential(),
               let credentialMetadataStore {
                try credentialMetadataStore.saveCredential(
                    credential,
                    metadata: GitHubCredentialMetadata(
                        login: validation.login,
                        scopes: validation.scopes,
                        tokenType: "Bearer"
                    )
                )
            }

            let scopes = scopeSummary(validation.scopes)
            if let message = selectedRepositoryAccessMessage {
                tokenValidationStatus = "Valid for @\(validation.login). Scopes: \(scopes). \(message)"
            } else {
                tokenValidationStatus = "Valid for @\(validation.login). Scopes: \(scopes)."
            }
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
        focusedInlineCommentTarget = nil
        preflightHeadSha = pullRequest.headSha

        guard let selectedRepository, let githubClient else {
            return
        }

        await runWorking("Loading changed files...") {
            changedFiles = try await githubClient.pullRequestFiles(repository: selectedRepository, pullRequest: pullRequest)
            selectedChangedFilePath = changedFiles.first?.path
            statusMessage = "Loaded \(changedFiles.count) changed files. \(reviewCoverageSummary.statusMessage)"
            try restoreDraftIfAvailable(repository: selectedRepository, pullRequest: pullRequest)
        }
    }

    func startGenerateReview() {
        guard !isWorking else {
            return
        }

        if let selectedRepository,
           denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: "Generate review") {
            return
        }

        if let consentRequest = privateRepositoryConsentRequestForSelectedRepository() {
            pendingPrivateRepositoryConsentContinuation = .generateCurrentReview
            pendingPrivateRepositoryConsent = consentRequest
            statusMessage = "Private repository consent required before generating Codex review."
            return
        }

        enqueueGenerateReview()
    }

    func startWatchingSelectedPullRequest() {
        guard hasToken && selectedRepository != nil && selectedPullRequest != nil else {
            statusMessage = "Select a pull request to watch."
            return
        }

        if let selectedRepository,
           denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: "Watch pull request") {
            return
        }

        if let consentRequest = privateRepositoryConsentRequestForSelectedRepository() {
            pendingPrivateRepositoryConsentContinuation = .enqueueSelectedPullRequest
            pendingPrivateRepositoryConsent = consentRequest
            statusMessage = "Private repository consent required before queued Codex review generation."
            return
        }

        enqueueSelectedPullRequestForBackgroundReview()
    }

    func startWatchingSelectedRepository() {
        guard hasToken && selectedRepository != nil && !pullRequests.isEmpty else {
            statusMessage = "Select a repository with open pull requests to watch."
            return
        }

        if let selectedRepository,
           denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: "Watch repository") {
            return
        }

        if let consentRequest = privateRepositoryConsentRequestForSelectedRepository() {
            pendingPrivateRepositoryConsentContinuation = .enqueueSelectedRepository
            pendingPrivateRepositoryConsent = consentRequest
            statusMessage = "Private repository consent required before queued Codex review generation."
            return
        }

        enqueueSelectedRepositoryForBackgroundReview()
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

    func startBackgroundReviewQueue() {
        guard !isBackgroundReviewQueueRunning else {
            return
        }

        guard backgroundReviewQueue.hasQueuedItems else {
            statusMessage = "No queued background reviews."
            return
        }

        backgroundQueueTask = Task { @MainActor [weak self] in
            await self?.processBackgroundReviewQueue()
            self?.backgroundQueueTask = nil
        }
    }

    func cancelBackgroundReviewQueue() {
        guard isBackgroundReviewQueueRunning else {
            return
        }

        statusMessage = "Cancelling background review queue..."
        backgroundQueueTask?.cancel()
    }

    func removeBackgroundQueueItem(id: String) {
        backgroundReviewQueue.remove(id: id)
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

        if denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: "Generate review") {
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
            let reviewContext: PullRequestReviewContext
            if let githubClient {
                reviewContext = try await githubClient.pullRequestReviewContext(
                    repository: selectedRepository,
                    pullRequest: pullRequestForReview
                )
            } else {
                reviewContext = .empty
            }
            let coverageSummary = reviewCoverageSummary
            let generated = try await codexAgent.generateReview(
                repository: selectedRepository,
                pullRequest: pullRequestForReview,
                files: changedFiles,
                context: reviewContext
            )
            focusedInlineCommentTarget = nil
            reviewedHeadSha = pullRequestForReview.headSha
            preflightHeadSha = pullRequestForReview.headSha
            selectedEvent = .comment
            draft = generated
            reviewBody = composeReviewBody(from: generated)
            persistCurrentDraftIfPossible()
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
            markWatchedDraftStaleIfNeeded(repository: selectedRepository, pullRequest: currentPullRequest)
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
            backgroundReviewQueue.markSubmitted(
                repositoryFullName: selectedRepository.fullName,
                pullRequestNumber: selectedPullRequest.number
            )
            statusMessage = "Submitted \(selectedEvent.displayName) review to GitHub."
        }
    }

    func setInlineCommentSelection(id: String, isSelected: Bool) {
        guard let index = draft?.inlineComments.firstIndex(where: { $0.id == id }) else {
            return
        }
        draft?.inlineComments[index].isSelected = isSelected
        persistCurrentDraftIfPossible()
    }

    func setInlineCommentBody(id: String, body: String) {
        guard let index = draft?.inlineComments.firstIndex(where: { $0.id == id }) else {
            return
        }
        draft?.inlineComments[index].body = body
        persistCurrentDraftIfPossible()
    }

    func focusInlineComment(_ comment: InlineCommentDraft) {
        selectedChangedFilePath = comment.path
        focusedInlineCommentTarget = InlineCommentFocusTarget(
            commentID: comment.id,
            path: comment.path,
            position: comment.position
        )
        statusMessage = "Focused \(comment.path) at diff position \(comment.position)."
    }

    func isFocusedInlineComment(_ comment: InlineCommentDraft) -> Bool {
        focusedInlineCommentTarget?.commentID == comment.id
    }

    func inlineCommentCount(for file: PullRequestFile) -> InlineCommentFileCount {
        InlineCommentFileCount.count(for: file.path, comments: draft?.inlineComments ?? [])
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

    func discardCurrentDraft() {
        if let key = currentDraftKey {
            try? reviewDraftStore.deleteDraft(key: key)
        }

        draft = nil
        reviewBody = ""
        reviewedHeadSha = nil
        focusedInlineCommentTarget = nil
        selectedEvent = .comment
        statusMessage = "Discarded review draft."
    }

    func confirmPrivateRepositoryConsentAndGenerate() {
        guard let request = pendingPrivateRepositoryConsent else {
            return
        }

        let continuation = pendingPrivateRepositoryConsentContinuation ?? .generateCurrentReview
        privateRepositoryConsentAcknowledgements.insert(request.repositoryFullName)
        savePrivateRepositoryConsentAcknowledgements()
        pendingPrivateRepositoryConsent = nil
        pendingPrivateRepositoryConsentContinuation = nil
        statusMessage = "Private repository consent remembered for \(request.repositoryFullName)."

        switch continuation {
        case .generateCurrentReview:
            enqueueGenerateReview()
        case .enqueueSelectedPullRequest:
            enqueueSelectedPullRequestForBackgroundReview()
        case .enqueueSelectedRepository:
            enqueueSelectedRepositoryForBackgroundReview()
        case .runBackgroundQueue:
            startBackgroundReviewQueue()
        }
    }

    func cancelPrivateRepositoryConsent() {
        pendingPrivateRepositoryConsent = nil
        pendingPrivateRepositoryConsentContinuation = nil
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

    private var selectedRepositoryAccessDecision: GitHubRepositoryAccessDecision {
        guard let selectedRepository else {
            return .allowed
        }

        return repositoryAccessDecision(for: selectedRepository)
    }

    private var selectedRepositoryAccessMessage: String? {
        let decision = selectedRepositoryAccessDecision
        guard let reason = decision.reason else {
            return nil
        }

        return "\(reason) \(decision.recoverySuggestion)"
    }

    private func repositoryAccessDecision(for repository: Repository) -> GitHubRepositoryAccessDecision {
        GitHubRepositoryAccessPolicy.reviewAccess(for: repository, scopes: grantedGitHubScopes)
    }

    private func denyIfRepositoryAccessInsufficient(for repository: Repository, operation: String) -> Bool {
        let decision = repositoryAccessDecision(for: repository)
        guard let reason = decision.reason else {
            return false
        }

        statusMessage = reason
        recoverableError = RecoverableErrorDetails(
            operation: operation,
            summary: reason,
            details: "\(reason)\n\(decision.recoverySuggestion)",
            recoverySuggestion: decision.recoverySuggestion
        )
        return true
    }

    private func scopeSummary(_ scopes: [String]) -> String {
        scopes.isEmpty ? "no scopes reported" : scopes.joined(separator: ", ")
    }

    private func loadStoredGitHubScopes() -> [String] {
        guard let storedCredential = try? storedCredentialLoader?.loadStoredCredential() else {
            return []
        }

        return storedCredential.scopes
    }

    private func configureGitHubClient() {
        githubClient = GitHubClient(
            accessTokenProvider: CredentialStoreAccessTokenProvider(credentialStore: credentialStore)
        )
    }

    private func runOAuthDeviceSignIn(clientID: String) async {
        isOAuthSignInPending = true
        oauthAuthorization = nil
        oauthStatus = "Starting GitHub sign-in..."
        defer {
            isOAuthSignInPending = false
        }

        do {
            let authorization = try await oauthDeviceFlowClient.startDeviceFlow(
                clientID: clientID,
                scopes: ["repo"]
            )
            oauthAuthorization = authorization
            oauthStatus = "Pending GitHub authorization. Enter code \(authorization.userCode)."
            NSWorkspace.shared.open(authorization.verificationURI)

            let completion = try await oauthDeviceFlowClient.pollUntilAuthorized(
                authorization: authorization,
                clientID: clientID,
                credentialStore: oauthCredentialStore
            )

            switch completion {
            case let .success(token):
                configureGitHubClient()
                tokenInput = ""
                grantedGitHubScopes = token.scopes
                tokenValidationStatus = "OAuth token saved. Validate to confirm login. Scopes: \(scopeSummary(token.scopes))."
                hasToken = true
                oauthStatus = "Authorized with GitHub."
                statusMessage = "GitHub OAuth token saved."
                await refreshRepositories()
            case .expiredToken:
                oauthStatus = "GitHub sign-in code expired. Start again."
            case .accessDenied:
                oauthStatus = "GitHub sign-in was denied."
            case .cancelled:
                oauthStatus = "GitHub sign-in cancelled."
            }
        } catch {
            let details = SensitiveTextRedactor.redact("\(error)")
            oauthStatus = "GitHub sign-in failed: \(firstLine(details))"
            recoverableError = RecoverableErrorDetails(
                operation: "GitHub sign-in",
                summary: firstLine(details),
                details: details,
                recoverySuggestion: "Check the OAuth App client ID and network access, then start sign-in again."
            )
        }
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

    private func enqueueSelectedPullRequestForBackgroundReview() {
        guard let selectedRepository, let selectedPullRequest else {
            return
        }

        backgroundReviewQueue.enqueue(repository: selectedRepository, pullRequest: selectedPullRequest)
        statusMessage = "Queued #\(selectedPullRequest.number) for draft-only background review."
        startBackgroundReviewQueue()
    }

    private func enqueueSelectedRepositoryForBackgroundReview() {
        guard let selectedRepository else {
            return
        }

        guard !pullRequests.isEmpty else {
            statusMessage = "No open pull requests to watch."
            return
        }

        for pullRequest in pullRequests {
            backgroundReviewQueue.enqueue(repository: selectedRepository, pullRequest: pullRequest)
        }
        statusMessage = "Queued \(pullRequests.count) pull requests for draft-only background review."
        startBackgroundReviewQueue()
    }

    private func processBackgroundReviewQueue() async {
        guard let githubClient else {
            statusMessage = "Add a GitHub token first."
            return
        }

        isBackgroundReviewQueueRunning = true
        defer {
            isBackgroundReviewQueueRunning = false
        }

        while let item = backgroundReviewQueue.nextQueuedItem {
            if Task.isCancelled {
                statusMessage = "Background review queue cancelled."
                return
            }

            let accessDecision = repositoryAccessDecision(for: item.repository)
            if !accessDecision.isAllowed {
                let summary = accessDecision.reason ?? "GitHub OAuth scope required."
                backgroundReviewQueue.markFailed(id: item.id, message: summary)
                recoverableError = RecoverableErrorDetails(
                    operation: "Background review for #\(item.pullRequest.number)",
                    summary: summary,
                    details: "\(summary)\n\(accessDecision.recoverySuggestion)",
                    recoverySuggestion: accessDecision.recoverySuggestion
                )
                statusMessage = "Background review blocked for #\(item.pullRequest.number)."
                continue
            }

            if let consentRequest = PrivateRepositoryConsentPolicy.request(
                for: item.repository,
                acknowledgedRepositories: privateRepositoryConsentAcknowledgements
            ) {
                backgroundReviewQueue.markQueued(id: item.id, message: "Private repository consent required.")
                pendingPrivateRepositoryConsentContinuation = .runBackgroundQueue
                pendingPrivateRepositoryConsent = consentRequest
                statusMessage = "Private repository consent required before queued Codex review generation."
                return
            }

            backgroundReviewQueue.markGenerating(id: item.id)
            statusMessage = "Generating draft-only review for \(item.repository.fullName)#\(item.pullRequest.number)..."

            do {
                try Task.checkCancellation()
                let currentPullRequest = try await githubClient.pullRequestDetails(
                    repository: item.repository,
                    number: item.pullRequest.number
                )
                let files = try await githubClient.pullRequestFiles(
                    repository: item.repository,
                    pullRequest: currentPullRequest
                )
                let reviewContext = try await githubClient.pullRequestReviewContext(
                    repository: item.repository,
                    pullRequest: currentPullRequest
                )
                let generated = try await codexAgent.generateReview(
                    repository: item.repository,
                    pullRequest: currentPullRequest,
                    files: files,
                    context: reviewContext
                )
                let body = composeReviewBody(from: generated)
                let key = ReviewDraftKey(
                    repositoryFullName: item.repository.fullName,
                    pullRequestNumber: currentPullRequest.number,
                    headSha: currentPullRequest.headSha
                )
                try reviewDraftStore.saveDraft(StoredReviewDraft(
                    key: key,
                    draft: generated,
                    reviewBody: body,
                    selectedEvent: .comment,
                    savedAt: Date()
                ))

                backgroundReviewQueue.markDraftReady(
                    id: item.id,
                    pullRequest: currentPullRequest,
                    draft: generated,
                    reviewBody: body,
                    reviewedHeadSha: currentPullRequest.headSha
                )

                if isCurrentSelection(repository: item.repository, pullRequest: currentPullRequest) {
                    applyGeneratedDraftToCurrentSelection(
                        pullRequest: currentPullRequest,
                        files: files,
                        draft: generated,
                        reviewBody: body
                    )
                }

                statusMessage = "Draft ready for \(item.repository.fullName)#\(currentPullRequest.number). Review and submit manually."
            } catch is CancellationError {
                backgroundReviewQueue.markQueued(id: item.id, message: "Cancelled before generation finished.")
                statusMessage = "Background review queue cancelled."
                return
            } catch {
                let details = SensitiveTextRedactor.redact("\(error)")
                backgroundReviewQueue.markFailed(id: item.id, message: firstLine(details))
                recoverableError = RecoverableErrorDetails(
                    operation: "Background review for #\(item.pullRequest.number)",
                    summary: firstLine(details),
                    details: details,
                    recoverySuggestion: recoverySuggestion(for: error)
                )
                statusMessage = "Background review failed for #\(item.pullRequest.number)."
            }
        }

        statusMessage = "Background review queue finished."
    }

    private func isCurrentSelection(repository: Repository, pullRequest: PullRequest) -> Bool {
        selectedRepository?.fullName == repository.fullName
            && selectedPullRequest?.number == pullRequest.number
    }

    private func applyGeneratedDraftToCurrentSelection(
        pullRequest: PullRequest,
        files: [PullRequestFile],
        draft: ReviewDraft,
        reviewBody: String
    ) {
        let previousSelectedFilePath = selectedChangedFilePath
        selectedPullRequest = pullRequest
        changedFiles = files
        selectedChangedFilePath = changedFiles.first(where: { $0.path == previousSelectedFilePath })?.path ?? changedFiles.first?.path
        focusedInlineCommentTarget = nil
        reviewedHeadSha = pullRequest.headSha
        preflightHeadSha = pullRequest.headSha
        selectedEvent = .comment
        self.draft = draft
        self.reviewBody = reviewBody
        persistCurrentDraftIfPossible()
    }

    private func markWatchedDraftStaleIfNeeded(repository: Repository, pullRequest: PullRequest) {
        let id = BackgroundReviewQueueItem.id(
            repositoryFullName: repository.fullName,
            pullRequestNumber: pullRequest.number
        )
        guard let item = backgroundReviewQueue.items.first(where: { $0.id == id }),
              item.state == .draftReady,
              let reviewedHeadSha = item.reviewedHeadSha,
              reviewedHeadSha != pullRequest.headSha
        else {
            return
        }

        backgroundReviewQueue.markStale(id: id, currentHeadSha: pullRequest.headSha)
    }

    private var currentDraftKey: ReviewDraftKey? {
        guard let selectedRepository, let selectedPullRequest, let reviewedHeadSha else {
            return nil
        }

        return ReviewDraftKey(
            repositoryFullName: selectedRepository.fullName,
            pullRequestNumber: selectedPullRequest.number,
            headSha: reviewedHeadSha
        )
    }

    private func restoreDraftIfAvailable(repository: Repository, pullRequest: PullRequest) throws {
        guard let storedDraft = try reviewDraftStore.loadLatestDraft(
            repositoryFullName: repository.fullName,
            pullRequestNumber: pullRequest.number
        ) else {
            return
        }

        focusedInlineCommentTarget = nil
        reviewedHeadSha = storedDraft.key.headSha
        preflightHeadSha = pullRequest.headSha
        draft = storedDraft.draft
        reviewBody = storedDraft.reviewBody
        selectedEvent = storedDraft.selectedEvent

        if storedDraft.key.headSha == pullRequest.headSha {
            statusMessage = "Restored saved review draft."
        } else {
            statusMessage = "Restored stale review draft from \(storedDraft.key.headSha.prefix(8)); regenerate before submitting."
        }
        markWatchedDraftStaleIfNeeded(repository: repository, pullRequest: pullRequest)
    }

    private func persistCurrentDraftIfPossible() {
        guard let key = currentDraftKey, let draft else {
            return
        }

        let storedDraft = StoredReviewDraft(
            key: key,
            draft: draft,
            reviewBody: reviewBody,
            selectedEvent: selectedEvent,
            savedAt: Date()
        )
        try? reviewDraftStore.saveDraft(storedDraft)
    }

    private var tokenValidationReadiness: ReadinessProbeState {
        guard hasToken else {
            return .unknown("Load or save a GitHub token before validating scopes.")
        }

        if let message = selectedRepositoryAccessMessage {
            return .needsAction(message)
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
        focusedInlineCommentTarget = nil
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
            markWatchedDraftStaleIfNeeded(repository: selectedRepository, pullRequest: currentPullRequest)
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
            if !selectedRepositoryAccessDecision.isAllowed {
                return selectedRepositoryAccessDecision.recoverySuggestion
            }
            return "Check GitHub access, token scopes, and the repository state, then retry."
        default:
            return "Check the details, adjust the input if needed, then retry."
        }
    }
}
