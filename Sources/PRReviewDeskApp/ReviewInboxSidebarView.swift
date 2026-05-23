import SwiftUI
import PRReviewDeskCore

struct ReviewInboxSidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedSection: ReviewInboxSection
    @SceneStorage("sidebar.repositoriesExpanded.v4") private var isRepositoriesExpanded = ReviewWorkspaceLayoutPolicy.defaultRepositoriesExpanded

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: CGFloat(ReviewWorkspaceLayoutPolicy.sidebarTopContentInset))

            if !model.readinessChecklist.isReady {
                readinessPanel
            }

            sidebarList
        }
    }

    private var sidebarList: some View {
        List(selection: selectedSectionListBinding) {
            Section(AppL10n.string("Review Inbox")) {
                ForEach(ReviewInboxSection.allCases) { section in
                    InboxSectionRow(
                        section: section,
                        count: model.reviewInboxCount(for: section)
                    )
                    .tag(section)
                }
            }

            Section(AppL10n.string("Repositories")) {
                if model.repositories.isEmpty {
                    Text(AppL10n.string("No repositories loaded."))
                        .foregroundStyle(.secondary)
                } else {
                    if let selectedRepository = model.selectedRepository {
                        RepositoryFilterRow(repository: selectedRepository, isSelected: true)
                    }

                    Button {
                        isRepositoriesExpanded.toggle()
                    } label: {
                        Label(
                            isRepositoriesExpanded ? AppL10n.string("Hide repositories") : AppL10n.string("Show repositories"),
                            systemImage: isRepositoriesExpanded ? "chevron.up" : "chevron.down"
                        )
                    }

                    if isRepositoriesExpanded {
                        TextField(AppL10n.string("Search repositories"), text: $model.repositorySearchText)
                            .textFieldStyle(.roundedBorder)

                        if RepositorySearchPresentation.showsNoMatches(
                            totalRepositoryCount: model.repositories.count,
                            filteredRepositoryCount: model.filteredRepositories.count,
                            query: model.repositorySearchText
                        ) {
                            RepositorySearchEmptyRow(query: RepositorySearchPresentation.trimmedQuery(model.repositorySearchText)) {
                                model.repositorySearchText = ""
                            }
                        } else {
                            ForEach(model.filteredRepositories) { repository in
                                Button {
                                    Task {
                                        await model.selectRepository(repository)
                                    }
                                } label: {
                                    RepositoryFilterRow(
                                        repository: repository,
                                        isSelected: model.selectedRepository?.id == repository.id
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section(AppL10n.string("Queue")) {
                QueueSummaryRow(model: model)
            }
        }
        .listStyle(.sidebar)
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReadinessChecklistView(model: model, mode: .compact)
            SettingsLink {
                Label(AppL10n.string("Open Settings"), systemImage: "gear")
            }
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var selectedSectionListBinding: Binding<ReviewInboxSection?> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                if let newValue {
                    selectedSection = newValue
                }
            }
        )
    }
}

private struct InboxSectionRow: View {
    let section: ReviewInboxSection
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Label(AppL10n.string(section.displayName), systemImage: section.systemImage)
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .accessibilityLabel(AppL10n.string("%@, %d", AppL10n.string(section.displayName), count))
    }
}

private struct RepositoryFilterRow: View {
    let repository: Repository
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: repository.isPrivate ? "lock" : "book.closed")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .lineLimit(ReviewWorkspaceLayoutPolicy.repositoryOwnerLineLimit)
                Text(repository.owner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(ReviewWorkspaceLayoutPolicy.repositoryOwnerLineLimit)
            }
            Spacer()
            if isSelected {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppL10n.string(
            "%@, %@",
            repository.fullName,
            repository.isPrivate ? AppL10n.string("Private") : AppL10n.string("Public")
        ))
    }
}

private struct RepositorySearchEmptyRow: View {
    let query: String
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AppL10n.string("No matching repositories"), systemImage: "magnifyingglass")
                .font(.callout)
                .fontWeight(.medium)
            Text(AppL10n.string("No repositories match \"%@\".", query))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onClear()
            } label: {
                Label(AppL10n.string("Clear repository search"), systemImage: "xmark.circle")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

private struct QueueSummaryRow: View {
    @ObservedObject var model: AppModel
    @State private var isCancelConfirmationPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isBackgroundReviewQueueRunning ? "sparkles" : "tray")
                .foregroundStyle(model.isBackgroundReviewQueueRunning ? AppTheme.foreground(.focus) : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppL10n.string("%d queued items", model.backgroundReviewQueue.items.count))
                    .lineLimit(1)
                Text(model.isBackgroundReviewQueueRunning ? AppL10n.string("Running") : AppL10n.string("Idle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBackgroundReviewQueueRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                if model.isBackgroundReviewQueueRunning {
                    isCancelConfirmationPresented = true
                } else {
                    model.startBackgroundReviewQueue()
                }
            } label: {
                Label(
                    model.isBackgroundReviewQueueRunning ? AppL10n.string("Cancel background queue") : AppL10n.string("Run queued draft generation"),
                    systemImage: model.isBackgroundReviewQueueRunning ? "xmark.circle" : "play.circle"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .disabled(!model.isBackgroundReviewQueueRunning && !model.backgroundReviewQueue.hasQueuedItems)
            .help(model.isBackgroundReviewQueueRunning ? AppL10n.string("Cancel background queue") : AppL10n.string("Run queued draft generation"))
            .confirmationDialog(
                AppL10n.string("Cancel background queue?"),
                isPresented: $isCancelConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(AppL10n.string("Cancel background queue"), role: .destructive) {
                    model.cancelBackgroundReviewQueue()
                }
                Button(AppL10n.string("Keep Running"), role: .cancel) {}
            } message: {
                Text(AppL10n.string("Queued review drafts that have not started will remain in the queue."))
            }
        }
    }
}
