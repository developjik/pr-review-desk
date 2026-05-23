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
                    RepositoryLoadEmptyRow(model: model)
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

            Section(AppL10n.string("Drafts")) {
                QueueSummaryRow(model: model)
                ForEach(model.backgroundReviewQueue.items) { item in
                    QueueItemRow(model: model, item: item)
                }
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

struct QueueItemRow: View {
    @ObservedObject var model: AppModel
    let item: BackgroundReviewQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(item.pullRequest.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(item.pullRequest.title)
                    .lineLimit(2)
                Spacer()
                StatusBadge(
                    title: AppL10n.string(item.state.displayName),
                    systemImage: statusIcon,
                    tone: statusTone
                )
            }

            if let message = item.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if item.state == .failed || item.state == .stale {
                    Button {
                        model.retryBackgroundQueueItem(id: item.id)
                    } label: {
                        Label(AppL10n.string("Retry"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBackgroundReviewQueueRunning)
                    .accessibilityHint(AppL10n.string("Moves this draft back to the pending list."))
                    .smokeAccessibilityIdentifier("review-inbox.queue.retry", state: "enabled")
                }

                Button {
                    model.removeBackgroundQueueItem(id: item.id)
                } label: {
                    Label(AppL10n.string("Remove"), systemImage: "xmark.circle")
                }
                .disabled(item.state == .generating)
                .accessibilityHint(AppL10n.string("Removes this draft list item and its saved draft if one exists."))
                .smokeAccessibilityIdentifier(
                    "review-inbox.queue.remove",
                    state: item.state == .generating ? "disabled" : "enabled"
                )
            }
            .buttonStyle(.plain)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch item.state {
        case .queued:
            return "tray"
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
        switch item.state {
        case .queued:
            return .neutral
        case .generating:
            return .focus
        case .draftReady:
            return .success
        case .stale:
            return .warning
        case .failed:
            return .invalid
        case .submitted:
            return .info
        }
    }
}

private struct RepositoryLoadEmptyRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppL10n.string("No repositories loaded."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if model.hasToken {
                    Task {
                        await model.refreshRepositories()
                    }
                } else {
                    model.startOAuthDeviceSignIn()
                }
            } label: {
                Label(
                    model.hasToken ? AppL10n.string("Load repositories") : AppL10n.string("Sign in with GitHub"),
                    systemImage: model.hasToken ? "arrow.clockwise" : "person.crop.circle.badge.checkmark"
                )
            }
            .controlSize(.small)
            .disabled(model.isWorking || model.isOAuthSignInPending)
        }
        .padding(.vertical, 6)
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
                Text(AppL10n.string("%d draft queue items", model.backgroundReviewQueue.items.count))
                    .lineLimit(1)
                Text(summaryDetail)
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
                    model.isBackgroundReviewQueueRunning ? AppL10n.string("Stop creating drafts") : AppL10n.string("Create pending drafts"),
                    systemImage: model.isBackgroundReviewQueueRunning ? "xmark.circle" : "play.circle"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .disabled(!model.isBackgroundReviewQueueRunning && !model.backgroundReviewQueue.hasQueuedItems)
            .help(model.isBackgroundReviewQueueRunning ? AppL10n.string("Stop creating drafts") : AppL10n.string("Create pending drafts"))
            .confirmationDialog(
                AppL10n.string("Stop creating drafts?"),
                isPresented: $isCancelConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(AppL10n.string("Stop creating drafts"), role: .destructive) {
                    model.cancelBackgroundReviewQueue()
                }
                Button(AppL10n.string("Keep Creating"), role: .cancel) {}
            } message: {
                Text(AppL10n.string("Drafts that have not started will stay in the list."))
            }
        }
    }

    private var summaryDetail: String {
        if model.isBackgroundReviewQueueRunning {
            return AppL10n.string("Creating drafts")
        }

        let pending = model.backgroundReviewQueue.items.filter {
            $0.state == .queued || $0.state == .generating
        }.count
        let ready = model.backgroundReviewQueue.items.filter {
            $0.state == .draftReady || $0.state == .submitted
        }.count
        let needsAttention = model.backgroundReviewQueue.items.filter {
            $0.state == .failed || $0.state == .stale
        }.count

        return AppL10n.string("Pending %d, ready %d, needs attention %d", pending, ready, needsAttention)
    }
}
