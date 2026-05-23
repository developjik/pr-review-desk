import SwiftUI
import PRReviewDeskCore

struct ReviewInboxView: View {
    @ObservedObject var model: AppModel
    let selectedSection: ReviewInboxSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if selectedSection == .needsSetup && !model.readinessChecklist.isReady {
                FirstRunSetupView(model: model)
            } else if rows.isEmpty {
                ContentUnavailableView(
                    AppL10n.string(selectedSection.displayName),
                    systemImage: selectedSection.systemImage,
                    description: Text(emptyDescription)
                )
            } else {
                List(rows, selection: selectedRowIDBinding) { row in
                    PullRequestTriageRowView(
                        row: row,
                        isSelected: isSelected(row)
                    )
                    .tag(row.id)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(AppL10n.string(selectedSection.displayName))
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
                Text(AppL10n.string("%d pull requests", rows.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let activeSearchSummary {
                    StatusBadge(title: activeSearchSummary, systemImage: "magnifyingglass", tone: .info)
                }

                if model.canWatchSelectedRepository {
                    Button {
                        model.startWatchingSelectedRepository()
                    } label: {
                        Label(AppL10n.string("Watch all open pull requests in this repository"), systemImage: "eye")
                    }
                    .controlSize(.small)
                }

                Spacer()
            }
        }
        .padding()
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

    private var activeSearchSummary: String? {
        let trimmedQuery = model.pullRequestSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        return AppL10n.string("Search \"%@\" - %d visible", trimmedQuery, rows.count)
    }

    private func isSelected(_ row: PullRequestTriageRow) -> Bool {
        model.selectedRepository?.fullName == row.repositoryFullName
            && model.selectedPullRequest?.number == row.number
    }

    private var selectedRowIDBinding: Binding<String?> {
        Binding(
            get: {
                rows.first(where: isSelected)?.id
            },
            set: { newValue in
                guard let newValue,
                      let row = rows.first(where: { $0.id == newValue }) else {
                    return
                }

                Task {
                    await model.selectTriageRow(row)
                }
            }
        )
    }

    private func syncSelectionToVisibleRows() async {
        let visiblePullRequests = rows.map(\.pullRequest)
        guard let visibleSelection = StableSelection.visiblePullRequest(
            in: visiblePullRequests,
            previousSelection: model.selectedPullRequest
        ) else {
            model.clearSelectedPullRequestForVisibleFilter(hasVisibleRows: !rows.isEmpty)
            return
        }
        guard visibleSelection.id != model.selectedPullRequest?.id,
              let row = rows.first(where: { $0.pullRequest.id == visibleSelection.id }) else {
            return
        }

        await model.selectTriageRow(row)
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
        .background(isSelected ? AppTheme.background(.focus) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pull request #\(row.number), \(row.title), \(row.draftStatus.displayName)")
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

                Text(AppL10n.string("Connect GitHub, confirm Codex readiness, and acknowledge privacy before generating reviews."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Label(AppL10n.string("Recommended path"), systemImage: "1.circle")
                        .font(.headline)
                    Text(AppL10n.string("Use GitHub OAuth if you have an OAuth App client ID configured. For this personal-alpha build, the personal access token fallback is the fastest reliable path."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(AppTheme.panelBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border(.info))
                }

                ReadinessChecklistView(model: model, mode: .detailed)

                SettingsLink {
                    Label(AppL10n.string("Open Settings"), systemImage: "gear")
                }
            }
            .padding()
            .frame(maxWidth: 620, alignment: .leading)
        }
    }
}
