import SwiftUI
import PRReviewDeskCore

struct ReviewPaneView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pullRequest = model.selectedPullRequest {
                AIReviewActionStripView(model: model, pullRequest: pullRequest)
                if !model.changedFiles.isEmpty {
                    ReviewCoverageBanner(summary: model.reviewCoverageSummary)
                }
                ReviewControlsView(model: model)
                Divider()
                reviewWorkspace
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ReadinessChecklistView(model: model, mode: .compact)
                        .frame(maxWidth: 520, alignment: .leading)

                    ContentUnavailableView(
                        AppL10n.string("No Pull Request Selected"),
                        systemImage: "text.badge.plus",
                        description: Text(AppL10n.string("Choose a repository and open pull request."))
                    )
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
        .padding(.top, 108)
    }

    @ViewBuilder
    private var reviewWorkspace: some View {
        if model.changedFiles.isEmpty {
            ContentUnavailableView(
                AppL10n.string("No Changed Files Loaded"),
                systemImage: "doc.text.magnifyingglass",
                description: Text(AppL10n.string("Refresh the pull request or generate a review to load changed files."))
            )
        } else {
            switch ReviewWorkspaceLayoutPolicy.fileNavigationStyle(fileCount: model.changedFiles.count) {
            case .inline:
                SelectedFileDetailView(model: model)
            case .sidebar:
                HSplitView {
                    ChangedFilesPane(model: model)
                        .frame(
                            minWidth: CGFloat(ReviewWorkspaceLayoutPolicy.changedFilesMinimumPaneWidth),
                            idealWidth: CGFloat(ReviewWorkspaceLayoutPolicy.changedFilesIdealPaneWidth)
                        )
                    SelectedFileDetailView(model: model)
                        .frame(
                            minWidth: CGFloat(ReviewWorkspaceLayoutPolicy.selectedFileMinimumPaneWidth),
                            idealWidth: CGFloat(ReviewWorkspaceLayoutPolicy.selectedFileIdealPaneWidth)
                        )
                }
            }
        }
    }
}

struct PullRequestHeaderView: View {
    let pullRequest: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(pullRequest.number) \(pullRequest.title)")
                .font(.title3)
                .fontWeight(.semibold)
            HStack(spacing: 12) {
                Text(pullRequest.author)
                Text(pullRequest.headSha.prefix(8))
                Link(AppL10n.string("Open on GitHub"), destination: pullRequest.htmlURL)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ReviewCoverageBanner: View {
    let summary: ReviewCoverageSummary

    var body: some View {
        let hasOmittedFiles = summary.omittedFileCount > 0

        VStack(alignment: .leading, spacing: 6) {
            Label(
                hasOmittedFiles ? AppL10n.string("Partial Codex coverage") : AppL10n.string("Full Codex coverage"),
                systemImage: hasOmittedFiles ? "exclamationmark.triangle" : "checkmark.circle"
            )
            .font(.headline)
            .foregroundStyle(hasOmittedFiles ? AppTheme.foreground(.warning) : AppTheme.foreground(.success))

            Text(AppL10n.string(
                "%d of %d changed files have reviewable patches.",
                summary.reviewableFileCount,
                summary.totalFileCount
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if hasOmittedFiles {
                Text(AppL10n.string(
                    "%d files, +%d -%d, will not be sent to Codex.",
                    summary.omittedFileCount,
                    summary.omittedAdditions,
                    summary.omittedDeletions
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(AppTheme.panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasOmittedFiles ? AppTheme.border(.warning) : AppTheme.border(.success))
        }
    }
}
