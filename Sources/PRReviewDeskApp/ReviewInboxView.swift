import SwiftUI
import PRReviewDeskCore

struct ReviewInboxView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedSection: ReviewInboxSection
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
            Task {
                await syncSelectionToVisibleRows(reason: .contentChanged)
            }
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
                await syncSelectionToVisibleRows(reason: .userSelectedFilter)
            }
        }
        .onChange(of: model.pullRequestSearchText) { _, _ in
            Task {
                await syncSelectionToVisibleRows(reason: .userSelectedFilter)
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            Task {
                await syncSelectionToVisibleRows(reason: .contentChanged)
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

                if model.canAddDraftsForSelectedRepository {
                    Button {
                        model.addSelectedRepositoryDrafts()
                    } label: {
                        Label(AppL10n.string("Add drafts"), systemImage: "tray.full")
                    }
                    .controlSize(.small)
                    .help(AppL10n.string("Create drafts for all open pull requests in this repository."))
                    .smokeAccessibilityIdentifier("review-inbox.queue-repository")
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
        List {
            EmptyInboxFilterRowView(
                section: selectedSection,
                description: emptyDescription
            ) {
                if hasActiveSearch {
                    Button {
                        clearPullRequestSearch()
                    } label: {
                        Label(AppL10n.string("Clear search"), systemImage: "xmark.circle")
                    }
                } else {
                    emptyStateAction
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
            .smokeAccessibilityIdentifier("review-inbox.empty-placeholder")
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var emptyStateAction: some View {
        if (selectedSection == .draftReady || selectedSection == .running), model.canAddDraftsForSelectedRepository {
            Button {
                model.addSelectedRepositoryDrafts()
            } label: {
                Label(AppL10n.string("Add drafts for this repository"), systemImage: "tray.full")
            }
            .accessibilityHint(AppL10n.string("Creates saved drafts for the open PRs in the selected repository."))
            .smokeAccessibilityIdentifier("review-inbox.empty.queue-repository")
        } else if model.hasToken, model.canRefreshActiveScope {
            Button {
                Task {
                    await model.refreshActiveScope()
                }
            } label: {
                Label(
                    AppL10n.string(model.selectedRepository == nil ? "Load repositories" : "Refresh pull requests"),
                    systemImage: "arrow.clockwise"
                )
            }
            .accessibilityHint(AppL10n.string("Loads the latest repositories and PRs from GitHub."))
            .smokeAccessibilityIdentifier("review-inbox.empty.refresh")
        } else if !model.hasToken {
            Button {
                model.startOAuthDeviceSignIn()
            } label: {
                Label(AppL10n.string("Sign in with GitHub"), systemImage: "person.crop.circle.badge.checkmark")
            }
            .accessibilityHint(AppL10n.string("Opens GitHub sign-in and then checks repository access."))
            .smokeAccessibilityIdentifier("review-inbox.empty.github-sign-in")
        }
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

    private func syncSelectionToVisibleRows(reason: ReviewInboxSelectionReason) async {
        let selectedRow = model.reviewInboxRows.first(where: isModelSelected)
        let decision = ReviewInboxSelectionPolicy.decision(
            selectedRow: selectedRow,
            visibleRows: rows,
            selectedSection: selectedSection,
            reason: reason
        )

        switch decision {
        case let .keep(rowID):
            if selectedRowID != rowID {
                selectedRowID = rowID
            }
        case let .select(rowID):
            guard let row = rows.first(where: { $0.id == rowID }) else {
                return
            }
            if selectedRowID == rowID {
                await model.selectTriageRow(row)
            } else {
                selectedRowID = rowID
            }
        case let .moveSection(section, rowID):
            if selectedRowID != rowID {
                selectedRowID = rowID
            }
            if selectedSection != section {
                selectedSection = section
            }
        case .clear:
            let hadModelSelection = model.selectedPullRequest != nil
            selectedRowID = nil
            if hadModelSelection {
                model.clearSelectedPullRequestForVisibleFilter(hasVisibleRows: !rows.isEmpty)
            }
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
                    Label(AppL10n.string("%d files", row.fileCount), systemImage: "doc.on.doc")
                        .foregroundStyle(.secondary)
                    StatusBadge(title: AppL10n.string(row.draftStatus.displayName), systemImage: statusIcon, tone: statusTone)
                    if row.hasCoverageWarning {
                        StatusBadge(title: AppL10n.string("Coverage warning"), systemImage: "exclamationmark.triangle", tone: .warning)
                    }
                    if row.repositoryIsPrivate {
                        StatusBadge(title: AppL10n.string("Private"), systemImage: "lock", tone: .neutral)
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

private struct EmptyInboxFilterRowView<Action: View>: View {
    let section: ReviewInboxSection
    let description: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 6) {
                Text(AppL10n.string(section.displayName))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                action()
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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

                Text(AppL10n.string("Connect GitHub, confirm Codex, and acknowledge privacy before generating reviews."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                guidedSetupPath

                DisclosureGroup(AppL10n.string("Setup details")) {
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
        return FirstRunSetupPresentation.steps(
            hasGitHubCredential: model.hasToken,
            isGitHubReady: gitHubReady,
            isCodexCLIReady: model.isCodexCLIReadyForReviewSetup,
            isCodexChatGPTLoginReady: model.isCodexReviewSetupReady,
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
                if step.id == "privacy", step.state != .complete {
                    privacyDisclosureCallout
                }
                guidedSetupAction(for: step)
            }
        }
    }

    private var needsCodexInstallAction: Bool {
        !model.isCodexCLIReadyForReviewSetup
            && model.readinessChecklist.items.first { $0.id == .codexCLI }?.state == .needsAction
    }

    private var privacyDisclosureCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(AppL10n.string("Privacy disclosure"), systemImage: "hand.raised")
                .font(.caption)
                .fontWeight(.medium)
            Text(AppL10n.string("When you generate an AI review draft, pull request details and reviewable changes may be sent to Codex and OpenAI. Files without reviewable changes are not sent to Codex by this app."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppTheme.border(.warning))
                .frame(width: 2)
        }
        .smokeAccessibilityIdentifier("first-run.privacy.disclosure")
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await model.refreshCodexCLIStatus()
                            }
                        } label: {
                            Label(AppL10n.string(step.actionTitle), systemImage: "terminal")
                        }
                        .accessibilityHint(AppL10n.string("Checks whether AI review setup is ready on this Mac."))
                        .disabled(model.isWorking)
                        .smokeAccessibilityIdentifier("first-run.codex.check")

                        Link(
                            AppL10n.string("Open Codex help"),
                            destination: URL(string: "https://developers.openai.com/codex/quickstart?setup=cli")!
                        )
                        .accessibilityHint(AppL10n.string("Opens official Codex setup help in your browser."))
                        .smokeAccessibilityIdentifier("first-run.codex.help")
                    }

                    if needsCodexInstallAction {
                        DisclosureGroup(AppL10n.string("Advanced install options")) {
                            Text(AppL10n.string("Use these only if Codex help asks you to install the command-line helper."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                model.copyHomebrewCodexInstallCommand()
                            } label: {
                                Label(AppL10n.string("Copy Homebrew Install"), systemImage: "doc.on.doc")
                            }
                            .accessibilityHint(AppL10n.string("Copies the official Homebrew install command for Codex."))

                            Button {
                                model.copyNPMCodexInstallCommand()
                            } label: {
                                Label(AppL10n.string("Copy npm Install"), systemImage: "doc.on.doc")
                            }
                            .accessibilityHint(AppL10n.string("Copies the official npm install command for Codex."))
                        }
                        .font(.caption)
                        .controlSize(.small)
                    }

                    if model.needsCodexSignInAction {
                        DisclosureGroup(AppL10n.string("Manual sign-in options")) {
                            Button {
                                model.copyCodexLoginCommand()
                            } label: {
                                Label(AppL10n.string("Copy sign-in step"), systemImage: "doc.on.doc")
                            }
                            .accessibilityHint(AppL10n.string("Copies codex login so you can finish Codex sign-in."))
                            .disabled(model.isWorking)
                            .smokeAccessibilityIdentifier("first-run.codex.copy-login")

                            Button {
                                model.openTerminalForCodexLogin()
                            } label: {
                                Label(AppL10n.string("Open Terminal Sign-In Step"), systemImage: "terminal")
                            }
                            .accessibilityHint(AppL10n.string("Copies the Codex sign-in step, opens Terminal, and asks you to paste it."))
                            .disabled(model.isWorking)
                            .smokeAccessibilityIdentifier("first-run.codex.open-terminal-login")
                        }
                        .font(.caption)
                    }
                }
                .controlSize(.small)
            case "privacy":
                Button {
                    model.acknowledgePrivacyDisclosure()
                } label: {
                    Label(AppL10n.string(step.actionTitle), systemImage: "hand.raised")
                }
                .accessibilityHint(AppL10n.string("Marks the privacy disclosure as read so setup can continue."))
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
                        Label(AppL10n.string("Check GitHub Access"), systemImage: "checkmark.seal")
                    }
                    .accessibilityHint(AppL10n.string("Checks that GitHub can read repositories and reviews for this account."))
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
                    .accessibilityHint(AppL10n.string("Loads your saved GitHub sign-in from macOS and refreshes repositories."))
                    .disabled(model.isWorking)
                    .smokeAccessibilityIdentifier("first-run.github.reload")
                }
                .controlSize(.small)

                Text(AppL10n.string(model.tokenValidationStatus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(AppL10n.string("Sign in with GitHub to authorize repository review access."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        model.startOAuthDeviceSignIn()
                    } label: {
                        Label(AppL10n.string("Sign in with GitHub"), systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .accessibilityHint(AppL10n.string("Opens GitHub sign-in and then checks repository access."))
                    .disabled(model.isOAuthSignInPending)
                    .smokeAccessibilityIdentifier("first-run.github.oauth")

                    Button {
                        Task {
                            await model.retryGitHubSessionRestore()
                        }
                    } label: {
                        Label(AppL10n.string("Use saved sign-in"), systemImage: "lock.open")
                    }
                    .accessibilityHint(AppL10n.string("Uses a GitHub sign-in already saved on this Mac."))
                    .disabled(model.isWorking || model.isOAuthSignInPending)
                    .smokeAccessibilityIdentifier("first-run.github.restore")

                    if model.isOAuthSignInPending {
                        Button {
                            model.cancelOAuthDeviceSignIn()
                        } label: {
                            Label(AppL10n.string("Cancel"), systemImage: "xmark.circle")
                        }
                        .accessibilityHint(AppL10n.string("Cancels the current GitHub sign-in."))
                    }

                    if let authorization = model.oauthAuthorization {
                        Button {
                            model.copyOAuthUserCode()
                        } label: {
                            Label(AppL10n.string("Copy Code"), systemImage: "doc.on.doc")
                        }
                        .accessibilityHint(AppL10n.string("Copies the GitHub sign-in code to the clipboard."))

                        Link(AppL10n.string("Open GitHub"), destination: authorization.verificationURI)
                            .accessibilityHint(AppL10n.string("Opens GitHub so you can enter the copied sign-in code."))
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
