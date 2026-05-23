import SwiftUI
import PRReviewDeskCore

struct ReviewInboxView: View {
    @ObservedObject var model: AppModel
    let selectedSection: ReviewInboxSection
    @State private var selectedRowID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if selectedSection == .needsSetup && !model.readinessChecklist.isReady {
                FirstRunSetupView(model: model)
            } else if rows.isEmpty {
                emptyState
            } else {
                List(rows, selection: $selectedRowID) { row in
                    PullRequestTriageRowView(
                        row: row,
                        isSelected: isSelected(row)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRowID = row.id
                    }
                    .tag(row.id)
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, CGFloat(ReviewWorkspaceLayoutPolicy.primaryColumnTopContentInset))
        .navigationTitle("")
        .onAppear {
            syncSelectedRowIDFromModel()
        }
        .onChange(of: selectedRowID) { _, newValue in
            selectVisibleRow(with: newValue)
        }
        .onChange(of: model.selectedRepository?.id) { _, _ in
            syncSelectedRowIDFromModel()
        }
        .onChange(of: model.selectedPullRequest?.id) { _, _ in
            syncSelectedRowIDFromModel()
        }
        .onChange(of: selectedSection) { _, _ in
            Task {
                await syncSelectionToVisibleRows()
            }
        }
        .onChange(of: model.pullRequestSearchText) { _, _ in
            Task {
                await syncSelectionToVisibleRows()
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            Task {
                await syncSelectionToVisibleRows()
            }
        }
    }

    private var rows: [PullRequestTriageRow] {
        model.reviewInboxRows(for: selectedSection)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(AppL10n.string(selectedSection.displayName), systemImage: selectedSection.systemImage)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if let selectedRepository = model.selectedRepository {
                    StatusBadge(title: selectedRepository.fullName, systemImage: "line.3.horizontal.decrease.circle", tone: .neutral)
                }
            }

            HStack(spacing: 8) {
                Text(AppL10n.string(ReviewInboxFilterPresentation.pullRequestCountLocalizationKey(for: rows.count), rows.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if model.canWatchSelectedRepository {
                    Button {
                        model.startWatchingSelectedRepository()
                    } label: {
                        Label(AppL10n.string("Watch all"), systemImage: "eye")
                    }
                    .controlSize(.small)
                    .help(AppL10n.string("Watch all open pull requests in this repository"))
                }
            }

            if let activeSearchSummary {
                HStack(spacing: 8) {
                    StatusBadge(title: activeSearchSummary, systemImage: "magnifyingglass", tone: .info)
                        .lineLimit(1)

                    Button {
                        clearPullRequestSearch()
                    } label: {
                        Label(AppL10n.string("Clear search"), systemImage: "xmark.circle")
                    }
                    .controlSize(.small)

                    Spacer()
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                AppL10n.string(selectedSection.displayName),
                systemImage: selectedSection.systemImage,
                description: Text(emptyDescription)
            )

            if hasActiveSearch {
                Button {
                    clearPullRequestSearch()
                } label: {
                    Label(AppL10n.string("Clear search"), systemImage: "xmark.circle")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        let trimmedQuery = model.pullRequestSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            if model.selectedRepository != nil {
                return AppL10n.string(
                    "Search \"%@\" is hiding pull requests in this repository. Clear search to show saved drafts and open PRs again.",
                    trimmedQuery
                )
            }

            return AppL10n.string(
                "Search \"%@\" is hiding pull requests in the current scope. Clear search to show saved drafts and open PRs again.",
                trimmedQuery
            )
        }

        return AppL10n.string(ReviewInboxFilterPresentation.emptyDescription(
            section: selectedSection,
            query: model.pullRequestSearchText,
            hasSelectedRepository: model.selectedRepository != nil
        ))
    }

    private var hasActiveSearch: Bool {
        !model.pullRequestSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeSearchSummary: String? {
        let trimmedQuery = model.pullRequestSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        return AppL10n.string("Search \"%@\" - %d visible", trimmedQuery, rows.count)
    }

    private func clearPullRequestSearch() {
        model.pullRequestSearchText = ""
    }

    private func isSelected(_ row: PullRequestTriageRow) -> Bool {
        selectedRowID == row.id
            || (
                model.selectedRepository?.id == row.repository.id
                    && model.selectedPullRequest?.id == row.pullRequest.id
            )
    }

    private func selectVisibleRow(with rowID: String?) {
        guard let rowID,
              let row = rows.first(where: { $0.id == rowID }),
              !(model.selectedRepository?.id == row.repository.id && model.selectedPullRequest?.id == row.pullRequest.id) else {
            return
        }

        Task {
            await model.selectTriageRow(row)
        }
    }

    private func syncSelectedRowIDFromModel() {
        if let modelSelectedRowID = rows.first(where: isModelSelected)?.id {
            if selectedRowID != modelSelectedRowID {
                selectedRowID = modelSelectedRowID
            }
            return
        }

        if let selectedRowID,
           rows.contains(where: { $0.id == selectedRowID }) {
            return
        }

        selectedRowID = nil
    }

    private func isModelSelected(_ row: PullRequestTriageRow) -> Bool {
        model.selectedRepository?.id == row.repository.id
            && model.selectedPullRequest?.id == row.pullRequest.id
    }

    private func syncSelectionToVisibleRows() async {
        let visiblePullRequests = rows.map(\.pullRequest)
        guard model.selectedPullRequest != nil else {
            if let selectedRowID,
               !rows.contains(where: { $0.id == selectedRowID }) {
                self.selectedRowID = nil
            }
            return
        }

        guard let visibleSelection = StableSelection.visiblePullRequest(
            in: visiblePullRequests,
            previousSelection: model.selectedPullRequest
        ) else {
            let hadLocalSelection = selectedRowID != nil
            selectedRowID = nil
            if ReviewInboxFilterPresentation.shouldClearHiddenSelection(
                query: model.pullRequestSearchText,
                hasLocalSelection: hadLocalSelection
            ) {
                model.clearSelectedPullRequestForVisibleFilter(hasVisibleRows: !rows.isEmpty)
            }
            return
        }

        guard let row = rows.first(where: { $0.pullRequest.id == visibleSelection.id }) else {
            return
        }

        if selectedRowID != row.id {
            selectedRowID = row.id
        }
    }
}

private struct PullRequestTriageRowView: View {
    let row: PullRequestTriageRow
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("#\(row.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(row.title)
                        .lineLimit(ReviewWorkspaceLayoutPolicy.pullRequestTitleLineLimit)
                        .fontWeight(isSelected ? .semibold : .regular)
                }

                HStack(spacing: 8) {
                    Label(row.author, systemImage: "person")
                    Label(row.repositoryFullName, systemImage: row.repositoryIsPrivate ? "lock" : "book.closed")
                    if let updatedAt = row.pullRequest.updatedAt {
                        Label(updatedAt, systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(ReviewWorkspaceLayoutPolicy.pullRequestMetadataLineLimit)

                HStack(spacing: 8) {
                    Label("\(row.fileCount)", systemImage: "doc.on.doc")
                    Text("+\(row.additions)")
                        .foregroundStyle(AppTheme.foreground(.addition))
                    Text("-\(row.deletions)")
                        .foregroundStyle(AppTheme.foreground(.deletion))
                    StatusBadge(title: AppL10n.string(row.draftStatus.displayName), systemImage: statusIcon, tone: statusTone)
                    if row.hasCoverageWarning {
                        StatusBadge(title: AppL10n.string("Coverage warning"), systemImage: "exclamationmark.triangle", tone: .warning)
                    }
                    if row.repositoryIsPrivate {
                        StatusBadge(title: AppL10n.string("Private"), systemImage: "lock", tone: .neutral)
                    }
                    if let topSeverity = row.topSeverity {
                        StatusBadge(
                            title: topSeverity.localizedDisplayName,
                            systemImage: "exclamationmark.bubble",
                            tone: ReviewViewSupport.severityTone(topSeverity)
                        )
                    }
                }
                .font(.caption)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AppTheme.background(.focus) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppL10n.string(
            "Pull request #%d, %@, %@",
            row.number,
            row.title,
            AppL10n.string(row.draftStatus.displayName)
        ))
        .accessibilityValue(AppL10n.string(isSelected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .smokeAccessibilityIdentifier("review-inbox.pull-request.\(row.number)", state: isSelected ? "selected" : "unselected")
    }

    private var statusIcon: String {
        switch row.draftStatus {
        case .notGenerated:
            return "circle"
        case .queued:
            return "clock"
        case .generating:
            return "sparkles"
        case .draftReady:
            return "doc.text"
        case .stale:
            return "exclamationmark.triangle"
        case .failed:
            return "xmark.octagon"
        case .submitted:
            return "paperplane"
        }
    }

    private var statusTone: AppStatusTone {
        switch row.draftStatus {
        case .notGenerated:
            return .neutral
        case .queued, .generating:
            return .focus
        case .draftReady:
            return .success
        case .stale:
            return .warning
        case .failed:
            return .error
        case .submitted:
            return .info
        }
    }
}

private struct FirstRunSetupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(AppL10n.string("Finish setup"), systemImage: "checklist")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(AppL10n.string("Connect GitHub, confirm Codex CLI and ChatGPT login, and acknowledge privacy before generating reviews."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                guidedSetupPath

                DisclosureGroup(AppL10n.string("Technical readiness details")) {
                    ReadinessChecklistView(model: model, mode: .detailed)
                }

                SettingsLink {
                    Label(AppL10n.string("Open Settings"), systemImage: "gear")
                }
            }
            .padding()
            .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var guidedSetupSteps: [FirstRunSetupStep] {
        let checklist = model.readinessChecklist
        let gitHubReady = checklist.items
            .filter { $0.id == .githubCredential || $0.id == .githubTokenValidation }
            .allSatisfy { $0.state == .ready }
        let codexCLIReady = checklist.items
            .first { $0.id == .codexCLI }?
            .state == .ready
        let codexLoginReady = checklist.items
            .first { $0.id == .codexLogin }?
            .state == .ready

        return FirstRunSetupPresentation.steps(
            hasGitHubCredential: model.hasToken,
            isGitHubReady: gitHubReady,
            isCodexCLIReady: codexCLIReady,
            isCodexChatGPTLoginReady: codexLoginReady,
            isPrivacyAcknowledged: model.isPrivacyDisclosureAcknowledged
        )
    }

    private var guidedSetupPath: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppL10n.string("Guided setup path"), systemImage: "1.circle")
                .font(.headline)

            ForEach(Array(guidedSetupSteps.enumerated()), id: \.element.id) { enumeratedStep in
                guidedSetupRow(index: enumeratedStep.offset, step: enumeratedStep.element)
            }
        }
        .padding(10)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border(.info))
        }
    }

    private func guidedSetupRow(index: Int, step: FirstRunSetupStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.state == .complete ? "checkmark.circle.fill" : "\(index + 1).circle")
                .foregroundStyle(step.state == .complete ? AppTheme.foreground(.success) : AppTheme.foreground(.focus))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppL10n.string(step.title))
                    .fontWeight(.medium)
                Text(AppL10n.string(step.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                guidedSetupAction(for: step)
            }
        }
    }

    @ViewBuilder
    private func guidedSetupAction(for step: FirstRunSetupStep) -> some View {
        if step.state == .complete {
            StatusBadge(title: AppL10n.string("Complete"), systemImage: "checkmark.circle", tone: .success)
        } else {
            switch step.id {
            case "github":
                GitHubCredentialSetupControls(model: model)
            case "codex":
                Button {
                    Task {
                        await model.refreshCodexCLIStatus()
                    }
                } label: {
                    Label(AppL10n.string(step.actionTitle), systemImage: "terminal")
                }
                .controlSize(.small)
                .disabled(model.isWorking)
                .smokeAccessibilityIdentifier("first-run.codex.check")
            case "codexLogin":
                Button {
                    model.copyCodexLoginCommand()
                } label: {
                    Label(AppL10n.string(step.actionTitle), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(model.isWorking)
                .smokeAccessibilityIdentifier("first-run.codex-login.copy")
            case "privacy":
                Button {
                    model.acknowledgePrivacyDisclosure()
                } label: {
                    Label(AppL10n.string(step.actionTitle), systemImage: "hand.raised")
                }
                .controlSize(.small)
                .disabled(model.isWorking)
                .smokeAccessibilityIdentifier("first-run.privacy.acknowledge")
            default:
                EmptyView()
            }
        }
    }
}

private struct GitHubCredentialSetupControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.hasToken {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await model.validateCurrentToken()
                        }
                    } label: {
                        Label(AppL10n.string("Validate GitHub"), systemImage: "checkmark.seal")
                    }
                    .disabled(model.isWorking)
                    .smokeAccessibilityIdentifier("first-run.github.validate")

                    Button {
                        model.loadStoredToken()
                        Task {
                            await model.refreshRepositories()
                        }
                    } label: {
                        Label(AppL10n.string("Reload credential"), systemImage: "lock.open")
                    }
                    .disabled(model.isWorking)
                    .smokeAccessibilityIdentifier("first-run.github.reload")
                }
                .controlSize(.small)

                Text(AppL10n.string(model.tokenValidationStatus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(AppL10n.string("Sign in with GitHub OAuth to authorize repository review access."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        model.startOAuthDeviceSignIn()
                    } label: {
                        Label(AppL10n.string("Sign in with GitHub"), systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(model.isOAuthSignInPending)
                    .smokeAccessibilityIdentifier("first-run.github.oauth")

                    if model.isOAuthSignInPending {
                        Button {
                            model.cancelOAuthDeviceSignIn()
                        } label: {
                            Label(AppL10n.string("Cancel"), systemImage: "xmark.circle")
                        }
                    }

                    if let authorization = model.oauthAuthorization {
                        Button {
                            model.copyOAuthUserCode()
                        } label: {
                            Label(AppL10n.string("Copy Code"), systemImage: "doc.on.doc")
                        }

                        Link(AppL10n.string("Open GitHub"), destination: authorization.verificationURI)
                    }
                }
                .controlSize(.small)

                if let authorization = model.oauthAuthorization {
                    Text(AppL10n.string("Device code"))
                        + Text(" \(authorization.userCode)")
                        .font(.system(.caption, design: .monospaced))
                }

                Text(AppL10n.string(model.oauthStatus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
