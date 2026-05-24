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

private enum ProbeReadinessStatus: Equatable {
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
    @Published var oauthStatus = AppL10n.string("Not started.")
    @Published var oauthAuthorization: OAuthDeviceAuthorization?
    @Published var isOAuthSignInPending = false
    @Published var grantedGitHubScopes: [String] = []
    @Published var credentialKindDescription = AppL10n.string("None")
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
    @Published var statusMessage = AppL10n.string("Sign in with GitHub to load repositories.")
    @Published var isWorking = false
    @Published var canCancelCurrentOperation = false
    @Published var preflightHeadSha: String?
    @Published var submitSafetyLastCheckedAt: Date?
    @Published var recoverableError: RecoverableErrorDetails?
    @Published var tokenValidationStatus = AppL10n.string("Not validated.")
    @Published var codexCLIStatus = AppL10n.string("Not checked.")
    @Published var codexLoginStatus = AppL10n.string("Not checked.")
    @Published private var tokenValidationReadinessStatus: ProbeReadinessStatus = .unknown
    @Published private var codexCLIReadinessStatus: ProbeReadinessStatus = .unknown
    @Published private var codexLoginReadinessStatus: ProbeReadinessStatus = .unknown
    @Published var isSubmitConfirmationPresented = false
    @Published var backgroundReviewQueue = BackgroundReviewQueue()
    @Published private(set) var storedReviewDrafts: [StoredReviewDraft] = []
    @Published var isBackgroundReviewQueueRunning = false
    @Published var isPrivacyDisclosureAcknowledged = false {
        didSet {
            userDefaults.set(isPrivacyDisclosureAcknowledged, forKey: Self.privacyDisclosureAcknowledgedKey)
        }
    }
    @Published var pendingPrivateRepositoryConsent: PrivateRepositoryConsentRequest?
    @Published private(set) var privateRepositoryConsentAcknowledgementCount = 0
    @Published private(set) var generatedDraftPresentationRevision = 0

    private static let defaultGitHubOAuthClientID = "Ov23lil3NJWtY4l5QveY"
    private static let privacyDisclosureAcknowledgedKey = "privacyDisclosureAcknowledged"
    private static let privateRepositoryConsentAcknowledgementsKey = "privateRepositoryConsentAcknowledgements"
    private let credentialStore: CredentialStore
    private let oauthCredentialStore: any OAuthCredentialStoring
    private let storedCredentialLoader: (any StoredGitHubCredentialLoading)?
    private let credentialMetadataStore: (any OAuthCredentialStoring)?
    private let oauthDeviceFlowClient: GitHubOAuthDeviceFlowClient
    private let gitHubOAuthClientID: String
    private let codexAgent: CodexReviewAgent
    private let codexAuthenticationChecker: any CodexAuthenticationChecking
    private let reviewDraftStore: any ReviewDraftStore
    private let userDefaults: UserDefaults
    private var githubClient: GitHubClient?
    private var activeGitHubCredential: GitHubCredential?
    private var validatedGitHubLogin: String?
    private var reviewedHeadSha: String?
    private var currentOperationTask: Task<Void, Never>?
    private var backgroundQueueTask: Task<Void, Never>?
    private var oauthSignInTask: Task<Void, Never>?
    private var privateRepositoryConsentAcknowledgements: Set<String> = []
    private var pendingPrivateRepositoryConsentContinuation: PrivateRepositoryConsentContinuation?
    private var launchSessionRestoreGate = OneShotGate()
    private var launchCodexStatusGate = OneShotGate()

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
            safetyState: submitSafetyState,
            safetyCheckedAt: submitSafetyLastCheckedAt
        )
    }

    var commandAvailability: ReviewCommandAvailability {
        ReviewCommandAvailability(
            hasToken: hasToken,
            hasSelectedPullRequest: selectedPullRequest != nil,
            hasSubmittableDraft: hasSubmittableDraft,
            hasDraft: draft != nil,
            isWorking: isWorking,
            hasCancelableOperation: canCancelCurrentOperation,
            hasSelectedFile: selectedChangedFile != nil,
            hasFocusedInlineComment: focusedInlineCommentTarget != nil,
            supportsSelectedFileRegeneration: false,
            canCopyCodexLoginCommand: codexCLIReadinessStatus == .ready
        )
    }

    var isCodexCLIReadyForReviewSetup: Bool {
        codexCLIReadinessStatus == .ready
    }

    var isCodexReviewSetupReady: Bool {
        codexCLIReadinessStatus == .ready && codexLoginReadinessStatus == .ready
    }

    var needsCodexSignInAction: Bool {
        codexCLIReadinessStatus == .ready && codexLoginReadinessStatus != .ready
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
        rows.append(contentsOf: storedReviewDraftRows())

        var seenIDs = Set<String>()
        return rows.filter { row in
            seenIDs.insert(row.id).inserted
        }
    }

    func reviewInboxRows(for section: ReviewInboxSection) -> [PullRequestTriageRow] {
        guard section != .needsSetup else {
            return []
        }

        return reviewInboxRows.filter { $0.isVisible(in: section) }
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

    var canPreviewReviewSubmission: Bool {
        commandAvailability.canPreviewReviewSubmission
    }

    var canAddDraftForSelectedPullRequest: Bool {
        hasToken && selectedRepository != nil && selectedPullRequest != nil && selectedRepositoryAccessDecision.isAllowed
    }

    var canAddDraftsForSelectedRepository: Bool {
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
            return AppL10n.string("Finish the current operation before generating another draft.")
        }

        guard selectedPullRequest != nil else {
            return AppL10n.string("Select a pull request first.")
        }

        if let selectedRepositoryAccessMessage {
            return selectedRepositoryAccessMessage
        }

        if let blockingItem = readinessChecklist.items.first(where: { $0.state != .ready }) {
            return AppL10n.string(
                "%@: %@",
                AppL10n.string(blockingItem.title),
                AppL10n.string(blockingItem.detail)
            )
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

    var settingsGatePresentation: SettingsGatePresentation {
        SettingsGatePresentation.make(readinessChecklist: readinessChecklist)
    }

    func configureForUISmokeReadyState() {
        hasToken = true
        tokenValidationReadinessStatus = .ready
        codexCLIReadinessStatus = .ready
        codexLoginReadinessStatus = .ready
        tokenValidationStatus = AppL10n.string("Valid for @%@. Scopes: %@.", "developjik", scopeSummary(["repo"]))
        codexCLIStatus = AppL10n.string("Codex is ready for this app.")
        codexLoginStatus = AppL10n.string("Codex is signed in with ChatGPT.")
        isPrivacyDisclosureAcknowledged = true
    }

    private var hasSubmittableDraft: Bool {
        draft != nil && submitSafetyState.canSubmit
    }

    var submitSafetyMessage: String {
        let state = submitSafetyState

        guard draft != nil else {
            return AppL10n.string("Generate a review draft before submitting.")
        }

        if state.isStale {
            return AppL10n.string("PR changed after this draft. Regenerate before posting.")
        }

        if !state.invalidSelectedInlineComments.isEmpty {
            return AppL10n.string(
                "%d selected comments no longer match this PR.",
                state.invalidSelectedInlineComments.count
            )
        }

        return AppL10n.string("Ready to submit.")
    }

    init(
        credentialStore: (any CredentialStore)? = nil,
        oauthCredentialStore: (any OAuthCredentialStoring)? = nil,
        oauthDeviceFlowClient: GitHubOAuthDeviceFlowClient = GitHubOAuthDeviceFlowClient(),
        gitHubOAuthClientID: String = AppModel.defaultGitHubOAuthClientID,
        codexAgent: CodexReviewAgent = CodexReviewAgent(),
        codexAuthenticationChecker: any CodexAuthenticationChecking = CodexCLIAuthenticationChecker(),
        initialCodexAuthenticationState: CodexAuthenticationState? = nil,
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
        self.gitHubOAuthClientID = gitHubOAuthClientID
        self.codexAgent = codexAgent
        self.codexAuthenticationChecker = codexAuthenticationChecker
        self.reviewDraftStore = reviewDraftStore
        self.userDefaults = userDefaults
        self.isPrivacyDisclosureAcknowledged = userDefaults.bool(forKey: Self.privacyDisclosureAcknowledgedKey)
        self.privateRepositoryConsentAcknowledgements = Set(
            userDefaults.stringArray(forKey: Self.privateRepositoryConsentAcknowledgementsKey) ?? []
        )
        self.privateRepositoryConsentAcknowledgementCount = privateRepositoryConsentAcknowledgements.count
        reloadStoredReviewDrafts()
        if let initialCodexAuthenticationState {
            applyCodexAuthenticationState(initialCodexAuthenticationState, announceStatus: false)
        }
    }

    func loadStoredToken() {
        do {
            guard let credential = try credentialStore.loadCredential(), !credential.accessToken.isEmpty else {
                clearGitHubCredentialState(
                    tokenValidationStatus: AppL10n.string("No GitHub sign-in saved.")
                )
                return
            }

            guard case .oauthUserToken = credential else {
                try credentialStore.deleteCredential()
                clearGitHubCredentialState(
                    tokenValidationStatus: AppL10n.string("No GitHub sign-in saved."),
                    statusMessage: AppL10n.string("Unsupported saved GitHub credential removed. Sign in with GitHub.")
                )
                return
            }

            configureGitHubClient(credential: credential)
            applyStoredCredentialMetadata(fallbackCredential: credential)
            hasToken = true
            if let validatedGitHubLogin {
                statusMessage = AppL10n.string("Signed in as @%@. Loading repositories...", validatedGitHubLogin)
            } else {
                statusMessage = AppL10n.string("GitHub session restored. Validate access before generating reviews.")
            }
        } catch {
            let details = SensitiveTextRedactor.redact(String(describing: error))
            let summary = AppL10n.string("Could not restore saved GitHub session.")
            statusMessage = summary
            recoverableError = RecoverableErrorDetails(
                operation: AppL10n.string("Restore GitHub session"),
                summary: summary,
                details: details,
                recoverySuggestion: AppL10n.string("Unlock the saved Keychain item, retry restore, or sign in with GitHub again.")
            )
        }
    }

    func restoreGitHubSessionOnLaunchIfNeeded() async {
        guard launchSessionRestoreGate.consume() else {
            return
        }

        await restoreGitHubSession()
    }

    func retryGitHubSessionRestore() async {
        await restoreGitHubSession()
    }

    func refreshCodexStatusOnLaunchIfNeeded() async {
        guard launchCodexStatusGate.consume() else {
            return
        }

        await refreshCodexCLIStatus()
    }

    private func restoreGitHubSession() async {
        loadStoredToken()
        if hasToken {
            await refreshRepositories()
        }
    }

    func refreshLocalizedDefaults() {
        if let activeGitHubCredential {
            credentialKindDescription = AppL10n.string(GitHubCredentialKind(credential: activeGitHubCredential).displayName)
        } else {
            credentialKindDescription = relocalizedDefault(credentialKindDescription, key: "None")
        }
        statusMessage = relocalizedDefault(statusMessage, key: "Sign in with GitHub to load repositories.")
        if let validatedGitHubLogin, tokenValidationReadinessStatus == .ready {
            tokenValidationStatus = AppL10n.string(
                "Valid for @%@. Scopes: %@.",
                validatedGitHubLogin,
                scopeSummary(grantedGitHubScopes)
            )
        } else {
            tokenValidationStatus = relocalizedDefault(tokenValidationStatus, key: "Not validated.")
        }
        codexCLIStatus = relocalizedDefault(codexCLIStatus, key: "Not checked.")
        codexLoginStatus = relocalizedDefault(codexLoginStatus, key: "Not checked.")
        oauthStatus = relocalizedDefault(oauthStatus, key: "Not started.")
    }

    func deleteStoredToken() {
        do {
            try credentialStore.deleteCredential()
            clearGitHubCredentialState(
                tokenValidationStatus: AppL10n.string("No GitHub sign-in saved."),
                statusMessage: AppL10n.string("GitHub sign-in deleted.")
            )
        } catch {
            statusMessage = AppL10n.string("Could not delete token: %@", String(describing: error))
        }
    }

    func startOAuthDeviceSignIn() {
        guard !isOAuthSignInPending else {
            return
        }

        let clientID = gitHubOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            oauthStatus = AppL10n.string("GitHub OAuth client ID is not configured.")
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

        oauthStatus = AppL10n.string("Cancelling GitHub sign-in...")
        oauthSignInTask?.cancel()
    }

    func copyOAuthUserCode() {
        guard let userCode = oauthAuthorization?.userCode else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        oauthStatus = AppL10n.string("Copied GitHub device code.")
    }

    func validateCurrentToken() async {
        guard let githubClient else {
            tokenValidationStatus = AppL10n.string("Sign in with GitHub first.")
            tokenValidationReadinessStatus = .needsAction
            return
        }

        await runWorking(AppL10n.string("Checking GitHub sign-in...")) {
            let validation = try await githubClient.validateToken()
            grantedGitHubScopes = validation.scopes
            validatedGitHubLogin = validation.login
            if let credential = activeGitHubCredential {
                credentialKindDescription = AppL10n.string(GitHubCredentialKind(credential: credential).displayName)
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
                tokenValidationStatus = AppL10n.string("Valid for @%@. Scopes: %@. %@", validation.login, scopes, message)
                tokenValidationReadinessStatus = .needsAction
            } else {
                tokenValidationStatus = AppL10n.string("Valid for @%@. Scopes: %@.", validation.login, scopes)
                tokenValidationReadinessStatus = .ready
            }
        }
    }

    func refreshCodexCLIStatus() async {
        await runWorking(AppL10n.string("Checking Codex CLI...")) {
            let state = try await codexAuthenticationChecker.status()
            applyCodexAuthenticationState(state, announceStatus: true)
        }
    }

    func refreshRepositories() async {
        guard let githubClient else {
            statusMessage = AppL10n.string("Sign in with GitHub first.")
            return
        }

        let previousRepository = selectedRepository
        let previousPullRequest = selectedPullRequest

        await runWorking(AppL10n.string("Loading repositories...")) {
            repositories = try await githubClient.listRepositories()
            selectedRepository = StableSelection.repository(
                afterRefresh: repositories,
                previousSelection: previousRepository
            )
            statusMessage = repositories.isEmpty
                ? AppL10n.string("No repositories found.")
                : AppL10n.string("Loaded %d repositories.", repositories.count)

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
            await runWorking(AppL10n.string("Refreshing open pull requests...")) {
                try await loadPullRequests(repository: selectedRepository)
            }
        } else {
            await refreshRepositories()
        }
    }

    func selectRepository(_ repository: Repository) async {
        selectedRepository = repository
        clearPullRequestContext(clearPullRequests: true)

        await runWorking(AppL10n.string("Loading open pull requests...")) {
            try await loadPullRequests(repository: repository)
        }
    }

    func selectPullRequest(_ pullRequest: PullRequest) async {
        selectedPullRequest = pullRequest
        draft = nil
        reviewBody = ""
        reviewedHeadSha = nil
        submitSafetyLastCheckedAt = nil
        selectedChangedFilePath = nil
        focusedInlineCommentTarget = nil
        focusedDiffLineIndex = nil
        diffReviewFileState = DiffReviewFileState()
        preflightHeadSha = nil

        guard let selectedRepository, let githubClient else {
            return
        }

        await runWorking(AppL10n.string("Loading changed files...")) {
            let currentPullRequest = try await githubClient.pullRequestDetails(
                repository: selectedRepository,
                number: pullRequest.number
            )
            self.selectedPullRequest = currentPullRequest
            changedFiles = try await githubClient.pullRequestFiles(repository: selectedRepository, pullRequest: currentPullRequest)
            selectedChangedFilePath = changedFiles.first?.path
            preflightHeadSha = currentPullRequest.headSha
            submitSafetyLastCheckedAt = Date()
            statusMessage = AppL10n.string(
                "Loaded %d changed files. %@",
                changedFiles.count,
                localizedCoverageStatus(reviewCoverageSummary)
            )
            try restoreDraftIfAvailable(repository: selectedRepository, pullRequest: currentPullRequest)
        }
    }

    func clearSelectedPullRequestForVisibleFilter(hasVisibleRows: Bool) {
        guard selectedPullRequest != nil else {
            return
        }

        clearPullRequestContext(clearPullRequests: false)
        statusMessage = AppL10n.string(
            ReviewInboxFilterPresentation.selectionClearedStatus(
                hasVisibleRows: hasVisibleRows,
                hasActiveSearch: !pullRequestSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        )
    }

    func startGenerateReview() {
        guard canGenerateReview else {
            statusMessage = aiReviewDraftDisabledReason ?? AppL10n.string("Finish setup before generating an AI review draft.")
            return
        }

        if let selectedRepository,
           denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: AppL10n.string("Generate review")) {
            return
        }

        if let consentRequest = privateRepositoryConsentRequestForSelectedRepository() {
            pendingPrivateRepositoryConsentContinuation = .generateCurrentReview
            pendingPrivateRepositoryConsent = consentRequest
            statusMessage = AppL10n.string("Private repository consent required before generating Codex review.")
            return
        }

        enqueueGenerateReview()
    }

    func addSelectedPullRequestDraft() {
        guard hasToken && selectedRepository != nil && selectedPullRequest != nil else {
            statusMessage = AppL10n.string("Select a pull request before adding a draft.")
            return
        }

        if let selectedRepository,
           denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: AppL10n.string("Add pull request draft")) {
            return
        }

        if let consentRequest = privateRepositoryConsentRequestForSelectedRepository() {
            pendingPrivateRepositoryConsentContinuation = .enqueueSelectedPullRequest
            pendingPrivateRepositoryConsent = consentRequest
            statusMessage = AppL10n.string("Private repository consent required before creating saved drafts.")
            return
        }

        enqueueSelectedPullRequestForBackgroundReview()
    }

    func addSelectedRepositoryDrafts() {
        guard hasToken && selectedRepository != nil && !pullRequests.isEmpty else {
            statusMessage = AppL10n.string("Select a repository with open pull requests before adding drafts.")
            return
        }

        if let selectedRepository,
           denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: AppL10n.string("Add repository drafts")) {
            return
        }

        if let consentRequest = privateRepositoryConsentRequestForSelectedRepository() {
            pendingPrivateRepositoryConsentContinuation = .enqueueSelectedRepository
            pendingPrivateRepositoryConsent = consentRequest
            statusMessage = AppL10n.string("Private repository consent required before creating saved drafts.")
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
        statusMessage = AppL10n.string("Cancelling current operation...")
        currentOperationTask?.cancel()
    }

    func startBackgroundReviewQueue() {
        guard !isBackgroundReviewQueueRunning else {
            return
        }

        guard backgroundReviewQueue.hasQueuedItems else {
            statusMessage = AppL10n.string("No drafts are waiting to be created.")
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

        statusMessage = AppL10n.string("Stopping draft creation...")
        backgroundQueueTask?.cancel()
    }

    func removeBackgroundQueueItem(id: String) {
        guard let item = backgroundReviewQueue.items.first(where: { $0.id == id }) else {
            return
        }

        backgroundReviewQueue.remove(id: id)
        deleteStoredDraftsIfNeeded(for: item)
        statusMessage = AppL10n.string(
            "Removed draft list item for %@#%d.",
            item.repository.fullName,
            item.pullRequest.number
        )
    }

    func retryBackgroundQueueItem(id: String) {
        backgroundReviewQueue.markQueued(id: id)
        startBackgroundReviewQueue()
    }

    func requestSubmitReview() {
        guard canPreviewReviewSubmission else {
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
            statusMessage = AppL10n.string("Select a pull request first.")
            return
        }

        let didRefresh = await runWorking(AppL10n.string("Checking PR before posting...")) {
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
            submitSafetyLastCheckedAt = Date()
            markSavedDraftStaleIfNeeded(repository: selectedRepository, pullRequest: currentPullRequest)
        }
        guard didRefresh else {
            return
        }

        if ReviewSubmissionConfirmationPolicy.requiresConfirmation(for: selectedEvent) {
            isSubmitConfirmationPresented = true
            statusMessage = canSubmitReview
                ? AppL10n.string("Pre-submit check complete. Review the preview before posting.")
                : submitSafetyMessage
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
            statusMessage = AppL10n.string("Select a pull request first.")
            return
        }

        if denyIfRepositoryAccessInsufficient(for: selectedRepository, operation: AppL10n.string("Generate review")) {
            return
        }

        await runWorking(AppL10n.string("Generating Codex review draft..."), isCancellable: true) {
            guard try await requireCodexChatGPTLogin(operation: AppL10n.string("Generate review")) else {
                return
            }

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
            submitSafetyLastCheckedAt = Date()
            selectedEvent = .comment
            draft = generated
            reviewBody = composeReviewBody(from: generated)
            persistCurrentDraftIfPossible()
            generatedDraftPresentationRevision += 1
            if coverageSummary.warningMessage != nil {
                statusMessage = AppL10n.string(
                    "Generated review draft with %d inline comments. %@",
                    generated.inlineComments.count,
                    localizedCoverageStatus(coverageSummary)
                )
            } else {
                statusMessage = AppL10n.string(
                    "Generated review draft with %d inline comments.",
                    generated.inlineComments.count
                )
            }
        }
    }

    func refreshSubmitSafety() async {
        guard !isWorking else {
            return
        }
        guard let selectedRepository, let selectedPullRequest, let githubClient else {
            statusMessage = AppL10n.string("Select a pull request first.")
            return
        }

        await runWorking(AppL10n.string("Checking PR before posting...")) {
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
            submitSafetyLastCheckedAt = Date()
            markSavedDraftStaleIfNeeded(repository: selectedRepository, pullRequest: currentPullRequest)
            statusMessage = AppL10n.string("Pre-submit check complete. %@", submitSafetyMessage)
        }
    }

    func submitReview() async {
        guard !isWorking else {
            return
        }

        isSubmitConfirmationPresented = false

        guard let selectedRepository, let selectedPullRequest, let draft, let githubClient else {
            statusMessage = AppL10n.string("Generate a review draft before submitting.")
            return
        }

        guard let reviewedHeadSha else {
            statusMessage = AppL10n.string("Generate a fresh review draft before submitting.")
            return
        }

        await runWorking(AppL10n.string("Submitting review to GitHub...")) {
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
            statusMessage = AppL10n.string("Submitted %@ review to GitHub.", selectedEvent.localizedDisplayName)
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

    func deselectInlineComment(path: String, position: Int) {
        guard let index = draft?.inlineComments.firstIndex(where: {
            $0.path == path && $0.position == position
        }) else {
            return
        }

        draft?.inlineComments[index].isSelected = false
        persistCurrentDraftIfPossible()
        statusMessage = AppL10n.string("Deselected %@ comment spot %d.", path, position)
    }

    func revealInlineComment(path: String, position: Int) {
        guard let comment = draft?.inlineComments.first(where: {
            $0.path == path && $0.position == position
        }) else {
            selectedChangedFilePath = path
            statusMessage = AppL10n.string("Selected %@.", path)
            return
        }

        focusInlineComment(comment)
        if submitSafetyState.invalidSelectedInlineComments.contains(where: {
            $0.path == path && $0.position == position
        }) {
            statusMessage = AppL10n.string("Opened this comment in the inspector. Its original diff spot may no longer exist.")
        }
    }

    func focusInlineComment(_ comment: InlineCommentDraft) {
        selectedChangedFilePath = comment.path
        focusedInlineCommentTarget = InlineCommentFocusTarget(
            commentID: comment.id,
            path: comment.path,
            position: comment.position
        )
        focusedDiffLineIndex = nil
        statusMessage = AppL10n.string("Focused %@ comment in the diff and inspector.", comment.path)
    }

    func revealFocusedInlineComment() {
        guard let target = focusedInlineCommentTarget else {
            statusMessage = AppL10n.string("No inline comment is focused.")
            return
        }

        selectedChangedFilePath = target.path
        statusMessage = AppL10n.string("Revealed %@ comment in the diff.", target.path)
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
            statusMessage = AppL10n.string("No inline comments to navigate.")
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
            storedReviewDrafts.removeAll { $0.key == key }
        }

        draft = nil
        reviewBody = ""
        reviewedHeadSha = nil
        submitSafetyLastCheckedAt = nil
        focusedInlineCommentTarget = nil
        focusedDiffLineIndex = nil
        selectedEvent = .comment
        statusMessage = AppL10n.string("Discarded review draft.")
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
        statusMessage = AppL10n.string("Private repository consent remembered for %@.", request.repositoryFullName)

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
        statusMessage = AppL10n.string("Private repository consent cancelled. Codex review was not generated.")
    }

    func clearPrivateRepositoryConsentAcknowledgements() {
        privateRepositoryConsentAcknowledgements = []
        savePrivateRepositoryConsentAcknowledgements()
        statusMessage = AppL10n.string("Cleared remembered private repository consent.")
    }

    func acknowledgePrivacyDisclosure() {
        isPrivacyDisclosureAcknowledged = true
        statusMessage = AppL10n.string("Privacy disclosure acknowledged.")
    }

    func copyCodexLoginCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("codex login", forType: .string)
        statusMessage = AppL10n.string("Copied the Codex sign-in step. Paste it in Terminal, finish Codex sign-in, then return and check again.")
    }

    func copyHomebrewCodexInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install codex", forType: .string)
        statusMessage = AppL10n.string("Copied Codex Homebrew install command. Paste it in Terminal, wait for install to finish, then check Codex again.")
    }

    func copyNPMCodexInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("npm install -g @openai/codex", forType: .string)
        statusMessage = AppL10n.string("Copied Codex npm install command. Paste it in Terminal, wait for install to finish, then check Codex again.")
    }

    func openTerminalForCodexLogin() {
        copyCodexLoginCommand()

        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            statusMessage = AppL10n.string("Copied the Codex sign-in step, but Terminal could not be opened.")
            return
        }

        NSWorkspace.shared.open(terminalURL)
        statusMessage = AppL10n.string("Opened Terminal and copied the Codex sign-in step. Paste it, finish Codex sign-in, then return and check again.")
    }

    func openSelectedPullRequestInBrowser() {
        guard let selectedPullRequest else {
            statusMessage = AppL10n.string("Select a pull request first.")
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

        return AppL10n.string(
            "%@ %@",
            AppL10n.string(reason),
            AppL10n.string(decision.recoverySuggestion)
        )
    }

    private func repositoryAccessDecision(for repository: Repository) -> GitHubRepositoryAccessDecision {
        GitHubRepositoryAccessPolicy.reviewAccess(for: repository, scopes: grantedGitHubScopes)
    }

    private func denyIfRepositoryAccessInsufficient(for repository: Repository, operation: String) -> Bool {
        let decision = repositoryAccessDecision(for: repository)
        guard let reason = decision.reason else {
            return false
        }
        let localizedReason = AppL10n.string(reason)
        let localizedRecoverySuggestion = AppL10n.string(decision.recoverySuggestion)

        statusMessage = localizedReason
        recoverableError = RecoverableErrorDetails(
            operation: operation,
            summary: localizedReason,
            details: "\(localizedReason)\n\(localizedRecoverySuggestion)",
            recoverySuggestion: localizedRecoverySuggestion
        )
        return true
    }

    private func scopeSummary(_ scopes: [String]) -> String {
        scopes.isEmpty ? AppL10n.string("no scopes reported") : scopes.joined(separator: ", ")
    }

    private func localizedCoverageStatus(_ summary: ReviewCoverageSummary) -> String {
        if summary.reviewableFileCount == 0 {
            return AppL10n.string("No changed files have reviewable changes for Codex.")
        }

        if summary.omittedFileCount > 0 {
            return AppL10n.string(
                "%d of %d changed files do not have reviewable changes and will not be sent to Codex.",
                summary.omittedFileCount,
                summary.totalFileCount
            )
        }

        return AppL10n.string(
            "All %d changed files have reviewable changes for Codex.",
            summary.totalFileCount
        )
    }

    private func applyStoredCredentialMetadata(fallbackCredential: GitHubCredential) {
        guard let storedCredential = try? storedCredentialLoader?.loadStoredCredential() else {
            grantedGitHubScopes = []
            validatedGitHubLogin = nil
            credentialKindDescription = AppL10n.string(GitHubCredentialKind(credential: fallbackCredential).displayName)
            tokenValidationReadinessStatus = .unknown
            return
        }

        grantedGitHubScopes = storedCredential.scopes
        credentialKindDescription = AppL10n.string(storedCredential.kind.displayName)
        if let login = storedCredential.login {
            validatedGitHubLogin = login
            tokenValidationStatus = AppL10n.string("Valid for @%@. Scopes: %@.", login, scopeSummary(storedCredential.scopes))
            tokenValidationReadinessStatus = .ready
        } else {
            validatedGitHubLogin = nil
            tokenValidationReadinessStatus = .unknown
        }
    }

    private func clearGitHubCredentialState(
        tokenValidationStatus: String,
        statusMessage: String? = nil
    ) {
        githubClient = nil
        activeGitHubCredential = nil
        validatedGitHubLogin = nil
        hasToken = false
        repositories = []
        pullRequests = []
        selectedRepository = nil
        selectedPullRequest = nil
        changedFiles = []
        draft = nil
        reviewBody = ""
        grantedGitHubScopes = []
        credentialKindDescription = AppL10n.string("None")
        self.tokenValidationStatus = tokenValidationStatus
        tokenValidationReadinessStatus = .unknown
        if let statusMessage {
            self.statusMessage = statusMessage
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
        oauthStatus = AppL10n.string("Starting GitHub sign-in...")
        defer {
            isOAuthSignInPending = false
        }

        do {
            let authorization = try await oauthDeviceFlowClient.startDeviceFlow(
                clientID: clientID,
                scopes: ["repo"]
            )
            oauthAuthorization = authorization
            oauthStatus = AppL10n.string("Pending GitHub authorization. Enter code %@.", authorization.userCode)
            NSWorkspace.shared.open(authorization.verificationURI)

            let completion = try await oauthDeviceFlowClient.pollUntilAuthorized(
                authorization: authorization,
                clientID: clientID,
                credentialStore: oauthCredentialStore
            )

            switch completion {
            case let .success(token):
                configureGitHubClient(credential: .oauthUserToken(token.accessToken))
                grantedGitHubScopes = token.scopes
                validatedGitHubLogin = nil
                credentialKindDescription = AppL10n.string(GitHubCredentialKind.oauthUserToken.displayName)
                tokenValidationStatus = AppL10n.string("GitHub signed in. Checking access...")
                tokenValidationReadinessStatus = .unknown
                hasToken = true
                oauthStatus = AppL10n.string("Authorized with GitHub.")
                statusMessage = AppL10n.string("GitHub signed in. Checking repository access...")
                await validateCurrentToken()
                await refreshRepositories()
            case .expiredToken:
                oauthStatus = AppL10n.string("GitHub sign-in code expired. Start again.")
            case .accessDenied:
                oauthStatus = AppL10n.string("GitHub sign-in was denied.")
            case .cancelled:
                oauthStatus = AppL10n.string("GitHub sign-in cancelled.")
            }
        } catch {
            let details = SensitiveTextRedactor.redact("\(error)")
            oauthStatus = AppL10n.string("GitHub sign-in failed: %@", firstLine(details))
            recoverableError = RecoverableErrorDetails(
                operation: AppL10n.string("GitHub sign-in"),
                summary: firstLine(details),
                details: details,
                recoverySuggestion: AppL10n.string("Check the OAuth App client ID and network access, then start sign-in again.")
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
        statusMessage = AppL10n.string("Added #%d to draft creation.", selectedPullRequest.number)
        startBackgroundReviewQueue()
    }

    private func enqueueSelectedRepositoryForBackgroundReview() {
        guard let selectedRepository else {
            return
        }

        guard !pullRequests.isEmpty else {
            statusMessage = AppL10n.string("No open pull requests to add.")
            return
        }

        for pullRequest in pullRequests {
            backgroundReviewQueue.enqueue(repository: selectedRepository, pullRequest: pullRequest)
        }
        statusMessage = AppL10n.string("Added %d pull requests to draft creation.", pullRequests.count)
        startBackgroundReviewQueue()
    }

    private func processBackgroundReviewQueue() async {
        guard let githubClient else {
            statusMessage = AppL10n.string("Sign in with GitHub first.")
            return
        }

        isBackgroundReviewQueueRunning = true
        defer {
            isBackgroundReviewQueueRunning = false
        }

        while let item = backgroundReviewQueue.nextQueuedItem {
            if Task.isCancelled {
                statusMessage = AppL10n.string("Draft creation stopped.")
                return
            }

            let accessDecision = repositoryAccessDecision(for: item.repository)
            if !accessDecision.isAllowed {
                let summary = accessDecision.reason.map { AppL10n.string($0) } ?? AppL10n.string("GitHub OAuth scope required.")
                let recoverySuggestion = AppL10n.string(accessDecision.recoverySuggestion)
                backgroundReviewQueue.markFailed(id: item.id, message: summary)
                recoverableError = RecoverableErrorDetails(
                    operation: AppL10n.string("Create draft for #%d", item.pullRequest.number),
                    summary: summary,
                    details: "\(summary)\n\(recoverySuggestion)",
                    recoverySuggestion: recoverySuggestion
                )
                statusMessage = AppL10n.string("Draft creation blocked for #%d.", item.pullRequest.number)
                continue
            }

            if let consentRequest = PrivateRepositoryConsentPolicy.request(
                for: item.repository,
                acknowledgedRepositories: privateRepositoryConsentAcknowledgements
            ) {
                backgroundReviewQueue.markQueued(id: item.id, message: AppL10n.string("Private repository consent required."))
                pendingPrivateRepositoryConsentContinuation = .runBackgroundQueue
                pendingPrivateRepositoryConsent = consentRequest
                statusMessage = AppL10n.string("Private repository consent required before creating saved drafts.")
                return
            }

            do {
                try Task.checkCancellation()
                let codexAuthState = try await codexAuthenticationChecker.status()
                applyCodexAuthenticationState(codexAuthState, announceStatus: false)
                guard codexAuthState.isReadyForChatGPTSubscription else {
                    let summary = codexAuthenticationBlockedSummary(for: codexAuthState)
                    let recoverySuggestion = codexAuthenticationRecoverySuggestion(for: codexAuthState)
                    backgroundReviewQueue.markFailed(id: item.id, message: summary)
                    recoverableError = RecoverableErrorDetails(
                        operation: AppL10n.string("Create draft for #%d", item.pullRequest.number),
                        summary: summary,
                        details: "\(summary)\n\(recoverySuggestion)",
                        recoverySuggestion: recoverySuggestion
                    )
                    statusMessage = AppL10n.string("Draft creation blocked for #%d.", item.pullRequest.number)
                    continue
                }

                backgroundReviewQueue.markGenerating(id: item.id)
                statusMessage = AppL10n.string(
                    "Creating draft for %@#%d...",
                    item.repository.fullName,
                    item.pullRequest.number
                )
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
                    savedAt: Date(),
                    repositoryIsPrivate: item.repository.isPrivate
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

                statusMessage = AppL10n.string(
                    "Draft ready for %@#%d. Review and submit manually.",
                    item.repository.fullName,
                    currentPullRequest.number
                )
            } catch is CancellationError {
                backgroundReviewQueue.markQueued(id: item.id, message: AppL10n.string("Cancelled before generation finished."))
                statusMessage = AppL10n.string("Draft creation stopped.")
                return
            } catch {
                let details = SensitiveTextRedactor.redact("\(error)")
                backgroundReviewQueue.markFailed(id: item.id, message: firstLine(details))
                recoverableError = RecoverableErrorDetails(
                    operation: AppL10n.string("Create draft for #%d", item.pullRequest.number),
                    summary: firstLine(details),
                    details: details,
                    recoverySuggestion: recoverySuggestion(for: error)
                )
                statusMessage = AppL10n.string("Draft creation failed for #%d.", item.pullRequest.number)
            }
        }

        statusMessage = AppL10n.string("Draft creation finished.")
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
        submitSafetyLastCheckedAt = Date()
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
            if let queuedDraft = backgroundReviewQueue.items.first(where: {
                $0.repository.fullName == repository.fullName && $0.pullRequest.number == pullRequest.number
            })?.draft {
                return queuedDraft
            }

            return storedDraftForTriageRow(repository: repository, pullRequest: pullRequest)?.draft
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

        if let queuedHeadSha = backgroundReviewQueue.items.first(where: {
            $0.repository.fullName == repository.fullName && $0.pullRequest.number == pullRequest.number
        })?.reviewedHeadSha {
            return queuedHeadSha
        }

        return storedDraftForTriageRow(repository: repository, pullRequest: pullRequest)?.key.headSha
    }

    private func storedDraftForTriageRow(repository: Repository, pullRequest: PullRequest) -> StoredReviewDraft? {
        storedReviewDrafts.first {
            $0.key.repositoryFullName == repository.fullName
                && $0.key.pullRequestNumber == pullRequest.number
        }
    }

    private func storedReviewDraftRows() -> [PullRequestTriageRow] {
        storedReviewDrafts.compactMap { storedDraft in
            guard let repository = repository(for: storedDraft) else {
                return nil
            }
            let pullRequest = pullRequest(for: storedDraft)

            return PullRequestTriageRow(
                repository: repository,
                pullRequest: pullRequest,
                draft: storedDraft.draft,
                reviewedHeadSha: storedDraft.key.headSha
            )
        }
    }

    private func repository(for storedDraft: StoredReviewDraft) -> Repository? {
        let repositoryFullName = storedDraft.key.repositoryFullName
        if let repository = repositories.first(where: { $0.fullName == repositoryFullName }) {
            return repository
        }

        let parts = repositoryFullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return nil
        }

        return Repository(
            id: stableRepositoryID(for: repositoryFullName),
            owner: parts[0],
            name: parts[1],
            fullName: repositoryFullName,
            isPrivate: storedDraft.repositoryIsPrivate ?? true
        )
    }

    private func pullRequest(for storedDraft: StoredReviewDraft) -> PullRequest {
        if storedDraft.key.repositoryFullName == selectedRepository?.fullName,
           let pullRequest = pullRequests.first(where: { $0.number == storedDraft.key.pullRequestNumber }) {
            return pullRequest
        }

        return PullRequest(
            id: stablePullRequestID(for: storedDraft.key),
            number: storedDraft.key.pullRequestNumber,
            title: AppL10n.string("Saved review draft for #%d", storedDraft.key.pullRequestNumber),
            htmlURL: URL(string: "https://github.com/\(storedDraft.key.repositoryFullName)/pull/\(storedDraft.key.pullRequestNumber)")!,
            author: AppL10n.string("Saved draft"),
            headSha: "unverified-\(storedDraft.key.headSha)",
            updatedAt: nil
        )
    }

    private func stableRepositoryID(for fullName: String) -> Int {
        abs(fullName.unicodeScalars.reduce(17) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        })
    }

    private func stablePullRequestID(for key: ReviewDraftKey) -> Int {
        stableRepositoryID(for: "\(key.repositoryFullName)#\(key.pullRequestNumber)#\(key.headSha)")
    }

    private func markSavedDraftStaleIfNeeded(repository: Repository, pullRequest: PullRequest) {
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

    private func deleteStoredDraftsIfNeeded(for item: BackgroundReviewQueueItem) {
        let matchingKeys = Set(
            ((try? reviewDraftStore.loadAllDrafts()) ?? storedReviewDrafts)
                .map(\.key)
                .filter {
                    $0.repositoryFullName == item.repository.fullName
                        && $0.pullRequestNumber == item.pullRequest.number
                }
        )

        for key in matchingKeys {
            try? reviewDraftStore.deleteDraft(key: key)
        }

        storedReviewDrafts.removeAll {
            $0.key.repositoryFullName == item.repository.fullName
                && $0.key.pullRequestNumber == item.pullRequest.number
        }

        if currentDraftKey.map({
            $0.repositoryFullName == item.repository.fullName
                && $0.pullRequestNumber == item.pullRequest.number
        }) == true {
            draft = nil
            reviewBody = ""
            self.reviewedHeadSha = nil
            submitSafetyLastCheckedAt = nil
            focusedInlineCommentTarget = nil
            focusedDiffLineIndex = nil
            selectedEvent = .comment
        }
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
        submitSafetyLastCheckedAt = Date()
        draft = storedDraft.draft
        reviewBody = storedDraft.reviewBody
        selectedEvent = storedDraft.selectedEvent

        if storedDraft.key.headSha == pullRequest.headSha {
            statusMessage = AppL10n.string("Restored saved review draft.")
        } else {
            statusMessage = AppL10n.string(
                "Restored stale review draft from %@; regenerate before submitting.",
                String(storedDraft.key.headSha.prefix(8))
            )
        }
        markSavedDraftStaleIfNeeded(repository: repository, pullRequest: pullRequest)
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
            savedAt: Date(),
            repositoryIsPrivate: selectedRepository?.isPrivate
        )
        guard (try? reviewDraftStore.saveDraft(storedDraft)) != nil else {
            return
        }
        replaceStoredReviewDraft(storedDraft)
    }

    private func reloadStoredReviewDrafts() {
        storedReviewDrafts = (try? reviewDraftStore.loadAllDrafts()) ?? []
    }

    private func replaceStoredReviewDraft(_ storedDraft: StoredReviewDraft) {
        storedReviewDrafts.removeAll { $0.key == storedDraft.key }
        storedReviewDrafts.append(storedDraft)
        storedReviewDrafts.sort { $0.savedAt > $1.savedAt }
    }

    private var tokenValidationReadiness: ReadinessProbeState {
        guard hasToken else {
            return .unknown(AppL10n.string("Sign in with GitHub before validating scopes."))
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
            return .unknown(AppL10n.string("Validate the token to confirm login and scopes."))
        }
    }

    private var codexCLIReadiness: ReadinessProbeState {
        switch codexCLIReadinessStatus {
        case .ready:
            return .ready(codexCLIStatus)
        case .needsAction:
            return .needsAction(codexCLIStatus)
        case .unknown:
            return .unknown(AppL10n.string("Check whether Codex is installed and ready for this app."))
        }
    }

    private var codexLoginReadiness: ReadinessProbeState {
        switch codexLoginReadinessStatus {
        case .ready:
            return .ready(codexLoginStatus)
        case .needsAction:
            return .needsAction(codexLoginStatus)
        case .unknown:
            return .unknown(AppL10n.string("Check Codex sign-in status. If needed, finish the Codex sign-in step."))
        }
    }

    private func applyCodexAuthenticationState(_ state: CodexAuthenticationState, announceStatus: Bool) {
        switch state {
        case let .unknown(message):
            codexCLIStatus = AppL10n.string(message)
            codexLoginStatus = AppL10n.string("Check Codex sign-in status. If needed, finish the Codex sign-in step.")
            codexCLIReadinessStatus = .unknown
            codexLoginReadinessStatus = .unknown
            if announceStatus {
                statusMessage = AppL10n.string(message)
            }
        case let .missingCLI(message):
            codexCLIStatus = AppL10n.string(message)
            codexLoginStatus = AppL10n.string("Install Codex before checking Codex sign-in.")
            codexCLIReadinessStatus = .needsAction
            codexLoginReadinessStatus = .needsAction
            if announceStatus {
                statusMessage = AppL10n.string("Codex is not installed or this app cannot find it.")
            }
        case let .notLoggedIn(executablePath, message):
            codexCLIStatus = AppL10n.string("Found at %@.", executablePath)
            codexLoginStatus = AppL10n.string(message)
            codexCLIReadinessStatus = .ready
            codexLoginReadinessStatus = .needsAction
            if announceStatus {
                statusMessage = AppL10n.string("Codex is available. Codex sign-in needs action.")
            }
        case let .unsupportedLogin(executablePath, _, message):
            codexCLIStatus = AppL10n.string("Found at %@.", executablePath)
            codexLoginStatus = AppL10n.string(message)
            codexCLIReadinessStatus = .ready
            codexLoginReadinessStatus = .needsAction
            if announceStatus {
                statusMessage = AppL10n.string("Codex login must use ChatGPT.")
            }
        case let .ready(executablePath, _, message):
            codexCLIStatus = AppL10n.string("Found at %@.", executablePath)
            codexLoginStatus = AppL10n.string(message)
            codexCLIReadinessStatus = .ready
            codexLoginReadinessStatus = .ready
            if announceStatus {
                statusMessage = AppL10n.string("Codex CLI ready for ChatGPT.")
            }
        }
    }

    private func requireCodexChatGPTLogin(operation: String) async throws -> Bool {
        let state = try await codexAuthenticationChecker.status()
        applyCodexAuthenticationState(state, announceStatus: false)

        guard state.isReadyForChatGPTSubscription else {
            let summary = codexAuthenticationBlockedSummary(for: state)
            let recoverySuggestion = codexAuthenticationRecoverySuggestion(for: state)
            recoverableError = RecoverableErrorDetails(
                operation: operation,
                summary: summary,
                details: "\(summary)\n\(recoverySuggestion)",
                recoverySuggestion: recoverySuggestion
            )
            statusMessage = summary
            return false
        }

        return true
    }

    private func codexAuthenticationBlockedSummary(for state: CodexAuthenticationState) -> String {
        switch state {
        case .missingCLI:
            return AppL10n.string("Codex is not installed or this app cannot find it.")
        case .notLoggedIn:
            return AppL10n.string("Finish Codex sign-in before generating an AI review draft.")
        case .unsupportedLogin:
            return AppL10n.string("Codex login must use ChatGPT.")
        case .unknown:
            return AppL10n.string("Codex login method could not be verified. Sign in to Codex with ChatGPT.")
        case .ready:
            return AppL10n.string("Codex CLI ready for ChatGPT.")
        }
    }

    private func codexAuthenticationRecoverySuggestion(for state: CodexAuthenticationState) -> String {
        switch state {
        case .missingCLI:
            return AppL10n.string("Install Codex, then retry generation.")
        case .notLoggedIn,
             .unsupportedLogin,
             .unknown,
             .ready:
            return AppL10n.string("Run `codex login` in Terminal, finish Codex sign-in, then check Codex readiness.")
        }
    }

    private func relocalizedDefault(_ currentValue: String, key: String) -> String {
        let knownLocalizedValues = AppLanguage.allCases
            .filter { $0.localizationIdentifier != nil }
            .map { AppL10n.string(key, language: $0) }

        guard knownLocalizedValues.contains(currentValue) || currentValue == key else {
            return currentValue
        }

        return AppL10n.string(key)
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

        statusMessage = pullRequests.isEmpty
            ? AppL10n.string("No open pull requests.")
            : AppL10n.string("Loaded %d open pull requests.", pullRequests.count)
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
        submitSafetyLastCheckedAt = nil
    }

    private func selectChangedFile(offset: Int) {
        guard !changedFiles.isEmpty else {
            statusMessage = AppL10n.string("No changed files to navigate.")
            return
        }

        let currentIndex = selectedChangedFilePath.flatMap { path in
            changedFiles.firstIndex { $0.path == path }
        } ?? (offset > 0 ? -1 : changedFiles.count)
        let nextIndex = (currentIndex + offset + changedFiles.count) % changedFiles.count
        selectedChangedFilePath = changedFiles[nextIndex].path
        focusedInlineCommentTarget = nil
        focusedDiffLineIndex = nil
        statusMessage = AppL10n.string("Selected %@.", changedFiles[nextIndex].path)
    }

    private func focusHunk(offset: Int) {
        guard let selectedChangedFile else {
            statusMessage = AppL10n.string("Select a changed file first.")
            return
        }

        let annotatedDiff: AnnotatedDiff
        switch selectedChangedFile.reviewability {
        case .includedPatch:
            guard let patch = selectedChangedFile.patch,
                  let diff = try? DiffPositionMapper.annotate(path: selectedChangedFile.path, patch: patch)
            else {
                statusMessage = AppL10n.string("No change blocks are available for this file.")
                return
            }
            annotatedDiff = diff
        case .omitted:
            statusMessage = AppL10n.string("No change blocks are available for omitted files.")
            return
        }

        let hunkLineIndexes = annotatedDiff.lines
            .filter { $0.kind == .hunk }
            .map(\.index)
        guard !hunkLineIndexes.isEmpty else {
            statusMessage = AppL10n.string("No change blocks are available for this file.")
            return
        }

        let currentIndex = focusedDiffLineIndex.flatMap { lineIndex in
            hunkLineIndexes.firstIndex(of: lineIndex)
        } ?? (offset > 0 ? -1 : hunkLineIndexes.count)
        let nextIndex = (currentIndex + offset + hunkLineIndexes.count) % hunkLineIndexes.count
        focusedInlineCommentTarget = nil
        focusedDiffLineIndex = hunkLineIndexes[nextIndex]
        statusMessage = AppL10n.string(
            "Focused change block %d of %d.",
            nextIndex + 1,
            hunkLineIndexes.count
        )
    }

    private func refreshCurrentPullRequest() async {
        guard let selectedRepository, let selectedPullRequest, let githubClient else {
            statusMessage = AppL10n.string("Select a pull request first.")
            return
        }

        await runWorking(AppL10n.string("Refreshing pull request...")) {
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
            submitSafetyLastCheckedAt = Date()
            markSavedDraftStaleIfNeeded(repository: selectedRepository, pullRequest: currentPullRequest)
            statusMessage = AppL10n.string(
                "Refreshed pull request and %d changed files. %@",
                changedFiles.count,
                localizedCoverageStatus(reviewCoverageSummary)
            )
        }
    }

    @discardableResult
    private func runWorking(_ message: String, isCancellable: Bool = false, operation: () async throws -> Void) async -> Bool {
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
            return true
        } catch is CancellationError {
            statusMessage = AppL10n.string("Operation cancelled.")
            return false
        } catch {
            let details = SensitiveTextRedactor.redact("\(error)")
            statusMessage = AppL10n.string("Failed: %@", shortOperationName(message))
            recoverableError = RecoverableErrorDetails(
                operation: shortOperationName(message),
                summary: firstLine(details),
                details: details,
                recoverySuggestion: recoverySuggestion(for: error)
            )
            return false
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
            return AppL10n.string("Start generation again when ready.")
        case CodexReviewError.missingExecutable:
            return AppL10n.string("Install Codex, then retry generation.")
        case CodexReviewError.timedOut:
            return AppL10n.string("Reduce the PR size or retry generation.")
        case ReviewSubmissionValidationError.staleHead:
            return AppL10n.string("Check the PR again or regenerate the draft before posting.")
        case ReviewSubmissionValidationError.invalidInlineComments:
            return AppL10n.string("Deselect comments that no longer match, check again, or regenerate the draft.")
        case GitHubError.requestFailed:
            if !selectedRepositoryAccessDecision.isAllowed {
                return AppL10n.string(selectedRepositoryAccessDecision.recoverySuggestion)
            }
            return AppL10n.string("Check GitHub access, token scopes, and the repository state, then retry.")
        default:
            return AppL10n.string("Check the details, adjust the input if needed, then retry.")
        }
    }
}
