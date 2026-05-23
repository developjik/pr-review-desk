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

private enum ProbeReadinessStatus {
    case ready
    case needsAction
    case unknown

    var checklistState: ReadinessChecklistItemState {
        switch self {
        case .ready:
            return .ready
        case .needsAction:
            return .needsAction
        case .unknown:
            return .unknown
        }
    }
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
    @Published var credentialKindDescription = "None"
    @Published var hasToken = false
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var pullRequests: [PullRequest] = []
    @Published var selectedPullRequest: PullRequest?
    @Published var repositorySearchText = ""
    @Published var pullRequestSearchText = ""
    @Published var changedFiles: [PullRequestFile] = []
    @Published var selectedChangedFilePath: String?
    @Published var diffReviewFileState = DiffReviewFileState()
    @Published var diffDisplayMode: DiffDisplayMode = .unified
    @Published var showsWhitespaceInDiff = false
    @Published var focusedInlineCommentTarget: InlineCommentFocusTarget?
    @Published var focusedDiffLineIndex: Int?
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
    @Published private var tokenValidationReadinessStatus: ProbeReadinessStatus = .unknown
    @Published private var codexCLIReadinessStatus: ProbeReadinessStatus = .unknown
    @Published private var codexLoginReadinessStatus: ProbeReadinessStatus = .unknown
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
    @Published private(set) var generatedDraftPresentationRevision = 0

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
    private var activeGitHubCredential: GitHubCredential?
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
        do {
            return try ReviewSubmissionValidator.safetyState(
                reviewedHeadSha: reviewedHeadSha,
                currentHeadSha: preflightHeadSha ?? selectedPullRequest?.headSha,
                draft: draft,
                files: changedFiles
            )
        } catch {
            return ReviewSubmissionSafetyState(
                reviewedHeadSha: reviewedHeadSha,
                currentHeadSha: preflightHeadSha ?? selectedPullRequest?.headSha,
                selectedInlineCommentCount: selectedInlineCommentCount,
                invalidSelectedInlineComments: [],
                couldValidateDiffPositions: false
            )
        }
    }

    var submissionPreview: ReviewSubmissionPreview? {
        guard let draft else {
            return nil
        }

        return ReviewSubmissionPreview.make(
            event: selectedEvent,
            body: reviewBody,
            draft: draft,
            safetyState: submitSafetyState
        )
    }

    var commandAvailability: ReviewCommandAvailability {
        ReviewCommandAvailability(
            hasToken: hasToken,
            hasSelectedPullRequest: selectedPullRequest != nil,
            hasSubmittableDraft: hasSubmittableDraft,
            isWorking: isWorking,
            hasSelectedFile: selectedChangedFile != nil,
            hasFocusedInlineComment: focusedInlineCommentTarget != nil,
            supportsSelectedFileRegeneration: false
        )
    }

    var reviewInboxRows: [PullRequestTriageRow] {
        var rows = backgroundReviewQueue.items.map { item in
            PullRequestTriageRow(
                repository: item.repository,
                pullRequest: item.pullRequest,
                files: filesForTriageRow(repository: item.repository, pullRequest: item.pullRequest),
                draft: item.draft,
                queueState: item.state,
                reviewedHeadSha: item.reviewedHeadSha
            )
        }

        if let selectedRepository {
            rows.append(contentsOf: filteredPullRequests.map { pullRequest in
                PullRequestTriageRow(
                    repository: selectedRepository,
                    pullRequest: pullRequest,
                    files: filesForTriageRow(repository: selectedRepository, pullRequest: pullRequest),
                    draft: draftForTriageRow(repository: selectedRepository, pullRequest: pullRequest),
                    queueState: queueStateForTriageRow(repository: selectedRepository, pullRequest: pullRequest),
                    reviewedHeadSha: reviewedHeadShaForTriageRow(repository: selectedRepository, pullRequest: pullRequest)
                )
            })
        }

        var seenIDs = Set<String>()
        return rows.filter { row in
            seenIDs.insert(row.id).inserted
        }
    }

    func reviewInboxRows(for section: ReviewInboxSection) -> [PullRequestTriageRow] {
        guard section != .needsSetup else {
            return []
        }

        return reviewInboxRows.filter { $0.section == section }
    }

    func reviewInboxCount(for section: ReviewInboxSection) -> Int {
        if section == .needsSetup {
            return readinessChecklist.isReady ? 0 : 1
        }

        return reviewInboxRows(for: section).count
    }

    var canRefreshActiveScope: Bool {
        commandAvailability.canRefreshActiveScope
    }

    var canGenerateReview: Bool {
        commandAvailability.canGenerateReview
            && selectedRepositoryAccessDecision.isAllowed
            && readinessChecklist.isReady
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

    var aiReviewDraftActionPresentation: AIReviewDraftActionPresentation {
        AIReviewDraftActionPresentation(
            hasDraft: draft != nil,
            isEnabled: canGenerateReview,
            disabledReason: aiReviewDraftDisabledReason
        )
    }

    var aiReviewDraftDisabledReason: String? {
        if isWorking {
            return "Finish the current operation before generating another draft."
        }

        guard selectedPullRequest != nil else {
            return "Select a pull request first."
        }

        if let selectedRepositoryAccessMessage {
            return selectedRepositoryAccessMessage
        }

        if let blockingItem = readinessChecklist.items.first(where: { $0.state != .ready }) {
            return "\(blockingItem.title): \(blockingItem.detail)"
        }

        return nil
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
                activeGitHubCredential = nil
                hasToken = false
                grantedGitHubScopes = []
                credentialKindDescription = "None"
                tokenValidationStatus = "No token saved."
                tokenValidationReadinessStatus = .unknown
                return
            }
            configureGitHubClient(credential: credential)
            tokenInput = ""
            applyStoredCredentialMetadata(fallbackCredential: credential)
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
            let credential = GitHubCredential.personalAccessToken(trimmed)
            try credentialStore.saveCredential(credential)
            configureGitHubClient(credential: credential)
            tokenInput = ""
            grantedGitHubScopes = []
            credentialKindDescription = GitHubCredentialKind.personalAccessToken.displayName
            tokenValidationStatus = "Not validated."
            tokenValidationReadinessStatus = .unknown
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
            activeGitHubCredential = nil
            hasToken = false
            repositories = []
            pullRequests = []
            selectedRepository = nil
            selectedPullRequest = nil
            changedFiles = []
            draft = nil
            reviewBody = ""
            grantedGitHubScopes = []
            credentialKindDescription = "None"
            tokenValidationStatus = "No token saved."
            tokenValidationReadinessStatus = .unknown
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
            tokenValidationReadinessStatus = .needsAction
            return
        }

        await runWorking("Validating GitHub token...") {
            let validation = try await githubClient.validateToken()
            grantedGitHubScopes = validation.scopes
            if let credential = activeGitHubCredential {
                credentialKindDescription = GitHubCredentialKind(credential: credential).displayName
                if let credentialMetadataStore {
                    try credentialMetadataStore.saveCredential(
                        credential,
                        metadata: GitHubCredentialMetadata(
                            login: validation.login,
                            scopes: validation.scopes,
                            tokenType: "Bearer"
                        )
                    )
                }
            }

            let scopes = scopeSummary(validation.scopes)
            if let message = selectedRepositoryAccessMessage {
                tokenValidationStatus = "Valid for @\(validation.login). Scopes: \(scopes). \(message)"
                tokenValidationReadinessStatus = .needsAction
            } else {
                tokenValidationStatus = "Valid for @\(validation.login). Scopes: \(scopes)."
                tokenValidationReadinessStatus = .ready
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
                codexCLIReadinessStatus = .ready
                let loginResult = try await runner.run(
                    executable: "codex",
                    arguments: ["login", "status"],
                    standardInput: "",
                    workingDirectory: nil,
                    timeout: 5
                )

                if loginResult.exitCode == 0 {
                    codexLoginStatus = loginResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    codexLoginReadinessStatus = .ready
                    statusMessage = "Codex CLI ready."
                } else {
                    let details = SensitiveTextRedactor.redact(loginResult.standardError)
                    codexLoginStatus = details.isEmpty
                        ? "Not logged in. Run `codex login` in Terminal."
                        : "Not logged in. \(details)"
                    codexLoginReadinessStatus = .needsAction
                    statusMessage = "Codex CLI found. Codex login needs action."
                }
            } else {
                codexCLIStatus = "Not found on PATH."
                codexLoginStatus = "Install or expose Codex CLI before checking login."
                codexCLIReadinessStatus = .needsAction
                codexLoginReadinessStatus = .needsAction
                statusMessage = "Codex CLI not found on PATH."
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
        focusedDiffLineIndex = nil
        diffReviewFileState = DiffReviewFileState()
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

    func clearSelectedPullRequestForVisibleFilter(hasVisibleRows: Bool) {
        guard selectedPullRequest != nil else {
            return
        }

        clearPullRequestContext(clearPullRequests: false)
        statusMessage = ReviewInboxFilterPresentation.selectionClearedStatus(hasVisibleRows: hasVisibleRows)
    }

    func startGenerateReview() {
        guard canGenerateReview else {
            statusMessage = aiReviewDraftDisabledReason ?? "Finish setup before generating an AI review draft."
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

        if githubClient != nil {
            Task { @MainActor in
                await refreshSubmitSafetyForPreview()
            }
            return
        }

        if ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: selectedEvent) {
            isSubmitConfirmationPresented = true
        }
    }

    private func refreshSubmitSafetyForPreview() async {
        guard !isWorking else {
            return
        }
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
        }

        guard canSubmitReview else {
            statusMessage = submitSafetyMessage
            return
        }

        if ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: selectedEvent) {
            isSubmitConfirmationPresented = true
            statusMessage = "Submit safety refreshed. Review the preview before posting."
        }
    }

    func selectTriageRow(_ row: PullRequestTriageRow) async {
        let repository = repositories.first { $0.fullName == row.repositoryFullName } ?? row.repository
        if selectedRepository?.id != repository.id {
            await selectRepository(repository)
        }

        let pullRequest = pullRequests.first { $0.number == row.number } ?? row.pullRequest
        await selectPullRequest(pullRequest)
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
            generatedDraftPresentationRevision += 1
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
        focusedDiffLineIndex = nil
        statusMessage = "Focused \(comment.path) at diff position \(comment.position)."
    }

    func revealFocusedInlineComment() {
        guard let target = focusedInlineCommentTarget else {
            statusMessage = "No inline comment is focused."
            return
        }

        selectedChangedFilePath = target.path
        statusMessage = "Revealed \(target.path) at diff position \(target.position)."
    }

    func focusNextInlineComment() {
        focusInlineComment(offset: 1)
    }

    func focusPreviousInlineComment() {
        focusInlineComment(offset: -1)
    }

    func selectNextChangedFile() {
        selectChangedFile(offset: 1)
    }

    func selectPreviousChangedFile() {
        selectChangedFile(offset: -1)
    }

    func focusNextHunk() {
        focusHunk(offset: 1)
    }

    func focusPreviousHunk() {
        focusHunk(offset: -1)
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

    private func focusInlineComment(offset: Int) {
        let comments = (draft?.inlineComments ?? [])
            .sorted {
                if $0.path == $1.path {
                    return $0.position < $1.position
                }

                return $0.path < $1.path
            }

        guard !comments.isEmpty else {
            statusMessage = "No inline comments to navigate."
            return
        }

        let currentIndex = focusedInlineCommentTarget.flatMap { target in
            comments.firstIndex { $0.id == target.commentID }
        } ?? (offset > 0 ? -1 : comments.count)

        let nextIndex = (currentIndex + offset + comments.count) % comments.count
        focusInlineComment(comments[nextIndex])
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
        focusedDiffLineIndex = nil
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

    func openSelectedPullRequestInBrowser() {
        guard let selectedPullRequest else {
            statusMessage = "Select a pull request first."
            return
        }

        NSWorkspace.shared.open(selectedPullRequest.htmlURL)
    }

    func toggleViewed(path: String) {
        diffReviewFileState.toggleViewed(path: path)
    }

    func toggleCollapsed(path: String) {
        diffReviewFileState.toggleCollapsed(path: path)
    }

    func markViewed(path: String, isViewed: Bool) {
        diffReviewFileState.markViewed(path: path, isViewed: isViewed)
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

    private func applyStoredCredentialMetadata(fallbackCredential: GitHubCredential) {
        guard let storedCredential = try? storedCredentialLoader?.loadStoredCredential() else {
            grantedGitHubScopes = []
            credentialKindDescription = GitHubCredentialKind(credential: fallbackCredential).displayName
            tokenValidationReadinessStatus = .unknown
            return
        }

        grantedGitHubScopes = storedCredential.scopes
        credentialKindDescription = storedCredential.kind.displayName
        if let login = storedCredential.login {
            tokenValidationStatus = "Valid for @\(login). Scopes: \(scopeSummary(storedCredential.scopes))."
            tokenValidationReadinessStatus = .ready
        } else {
            tokenValidationReadinessStatus = .unknown
        }
    }

    private func configureGitHubClient(credential: GitHubCredential) {
        activeGitHubCredential = credential
        githubClient = GitHubClient(
            accessTokenProvider: StaticAccessTokenProvider(credential: credential)
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
                configureGitHubClient(credential: .oauthUserToken(token.accessToken))
                tokenInput = ""
                grantedGitHubScopes = token.scopes
                credentialKindDescription = GitHubCredentialKind.oauthUserToken.displayName
                tokenValidationStatus = "OAuth token saved. Validate to confirm login. Scopes: \(scopeSummary(token.scopes))."
                tokenValidationReadinessStatus = .unknown
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
        focusedDiffLineIndex = nil
        reviewedHeadSha = pullRequest.headSha
        preflightHeadSha = pullRequest.headSha
        selectedEvent = .comment
        self.draft = draft
        self.reviewBody = reviewBody
        persistCurrentDraftIfPossible()
    }

    private func filesForTriageRow(repository: Repository, pullRequest: PullRequest) -> [PullRequestFile] {
        guard isCurrentSelection(repository: repository, pullRequest: pullRequest) else {
            return []
        }

        return changedFiles
    }

    private func draftForTriageRow(repository: Repository, pullRequest: PullRequest) -> ReviewDraft? {
        guard isCurrentSelection(repository: repository, pullRequest: pullRequest) else {
            return backgroundReviewQueue.items.first {
                $0.repository.fullName == repository.fullName && $0.pullRequest.number == pullRequest.number
            }?.draft
        }

        return draft
    }

    private func queueStateForTriageRow(
        repository: Repository,
        pullRequest: PullRequest
    ) -> BackgroundReviewQueueItemState? {
        backgroundReviewQueue.items.first {
            $0.repository.fullName == repository.fullName && $0.pullRequest.number == pullRequest.number
        }?.state
    }

    private func reviewedHeadShaForTriageRow(repository: Repository, pullRequest: PullRequest) -> String? {
        if isCurrentSelection(repository: repository, pullRequest: pullRequest) {
            return reviewedHeadSha
        }

        return backgroundReviewQueue.items.first {
            $0.repository.fullName == repository.fullName && $0.pullRequest.number == pullRequest.number
        }?.reviewedHeadSha
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
        focusedDiffLineIndex = nil
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

        switch tokenValidationReadinessStatus {
        case .ready:
            return .ready(tokenValidationStatus)
        case .needsAction:
            return .needsAction(tokenValidationStatus)
        case .unknown:
            return .unknown("Validate the token to confirm login and scopes.")
        }
    }

    private var codexCLIReadiness: ReadinessProbeState {
        switch codexCLIReadinessStatus {
        case .ready:
            return .ready(codexCLIStatus)
        case .needsAction:
            return .needsAction(codexCLIStatus)
        case .unknown:
            return .unknown("Check whether the Codex CLI is available on PATH.")
        }
    }

    private var codexLoginReadiness: ReadinessProbeState {
        switch codexLoginReadinessStatus {
        case .ready:
            return .ready(codexLoginStatus)
        case .needsAction:
            return .needsAction(codexLoginStatus)
        case .unknown:
            return .unknown("Check Codex login status. If needed, run `codex login` in Terminal.")
        }
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
        focusedDiffLineIndex = nil
        preflightHeadSha = nil
    }

    private func selectChangedFile(offset: Int) {
        guard !changedFiles.isEmpty else {
            statusMessage = "No changed files to navigate."
            return
        }

        let currentIndex = selectedChangedFilePath.flatMap { path in
            changedFiles.firstIndex { $0.path == path }
        } ?? (offset > 0 ? -1 : changedFiles.count)
        let nextIndex = (currentIndex + offset + changedFiles.count) % changedFiles.count
        selectedChangedFilePath = changedFiles[nextIndex].path
        focusedInlineCommentTarget = nil
        focusedDiffLineIndex = nil
        statusMessage = "Selected \(changedFiles[nextIndex].path)."
    }

    private func focusHunk(offset: Int) {
        guard let selectedChangedFile else {
            statusMessage = "Select a changed file first."
            return
        }

        let annotatedDiff: AnnotatedDiff
        switch selectedChangedFile.reviewability {
        case .includedPatch:
            guard let patch = selectedChangedFile.patch,
                  let diff = try? DiffPositionMapper.annotate(path: selectedChangedFile.path, patch: patch)
            else {
                statusMessage = "No hunk anchors are available for this file."
                return
            }
            annotatedDiff = diff
        case .omitted:
            statusMessage = "No hunk anchors are available for omitted files."
            return
        }

        let hunkLineIndexes = annotatedDiff.lines
            .filter { $0.kind == .hunk }
            .map(\.index)
        guard !hunkLineIndexes.isEmpty else {
            statusMessage = "No hunk anchors are available for this file."
            return
        }

        let currentIndex = focusedDiffLineIndex.flatMap { lineIndex in
            hunkLineIndexes.firstIndex(of: lineIndex)
        } ?? (offset > 0 ? -1 : hunkLineIndexes.count)
        let nextIndex = (currentIndex + offset + hunkLineIndexes.count) % hunkLineIndexes.count
        focusedInlineCommentTarget = nil
        focusedDiffLineIndex = hunkLineIndexes[nextIndex]
        statusMessage = "Focused hunk \(nextIndex + 1) of \(hunkLineIndexes.count)."
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
