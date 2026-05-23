import SwiftUI
import PRReviewDeskCore

struct ReviewInboxSidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedSection: ReviewInboxSection
    @SceneStorage("sidebar.repositoriesExpanded.v4") private var isRepositoriesExpanded = ReviewWorkspaceLayoutPolicy.defaultRepositoriesExpanded

    var body: some View {
        List {
            Section(AppL10n.string("Review Inbox")) {
                ForEach(ReviewInboxSection.allCases) { section in
                    InboxSectionRow(
                        section: section,
                        count: model.reviewInboxCount(for: section),
                        isSelected: selectedSection == section
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSection = section
                    }
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
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section(AppL10n.string("Queue")) {
                QueueSummaryRow(model: model)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            if !model.readinessChecklist.isReady {
                VStack(alignment: .leading, spacing: 8) {
                    ReadinessChecklistView(model: model, mode: .compact)
                    SettingsLink {
                        Label(AppL10n.string("Open Settings"), systemImage: "gear")
                    }
                    .controlSize(.small)
                }
                .padding()
                .background(.bar)
            }
        }
    }
}

private struct InboxSectionRow: View {
    let section: ReviewInboxSection
    let count: Int
    let isSelected: Bool

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
        .background(isSelected ? AppTheme.background(.focus) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("\(section.displayName), \(count)")
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
                    .lineLimit(1)
                Text(repository.owner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(repository.fullName), \(repository.isPrivate ? "private" : "public")")
    }
}

private struct QueueSummaryRow: View {
    @ObservedObject var model: AppModel

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
                    model.cancelBackgroundReviewQueue()
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
        }
        .accessibilityElement(children: .combine)
    }
}
