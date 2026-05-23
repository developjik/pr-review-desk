import SwiftUI
import PRReviewDeskCore

struct ChangedFilesPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppL10n.string("Changed Files"))
                .font(.headline)
            List(model.changedFiles, selection: changedFileSelection) { file in
                ChangedFileRow(model: model, file: file)
                    .tag(file.path)
            }
        }
    }

    private var changedFileSelection: Binding<String?> {
        Binding(
            get: { model.selectedChangedFilePath },
            set: { path in
                model.selectedChangedFilePath = path
            }
        )
    }
}

private struct ChangedFileRow: View {
    @ObservedObject var model: AppModel
    let file: PullRequestFile

    var body: some View {
        let inlineCommentCount = model.inlineCommentCount(for: file)
        let inlineCommentTone: AppStatusTone = inlineCommentCount.selected == inlineCommentCount.total ? .neutral : .warning

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: model.diffReviewFileState.isCollapsed(file.path) ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(file.path)
                    .font(.body)
                    .lineLimit(2)
                    .strikethrough(model.diffReviewFileState.isViewed(file.path), color: .secondary)
            }
            HStack(spacing: 8) {
                Text(file.status)
                Text("+\(file.additions)")
                    .foregroundStyle(AppTheme.foreground(.addition))
                Text("-\(file.deletions)")
                    .foregroundStyle(AppTheme.foreground(.deletion))
                if model.diffReviewFileState.isViewed(file.path) {
                    Label(AppL10n.string("Viewed"), systemImage: "checkmark.circle")
                        .foregroundStyle(AppTheme.foreground(.success))
                }
                if case let .omitted(reason) = file.reviewability {
                    Label(reason.displayName, systemImage: "exclamationmark.triangle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(AppTheme.foreground(.omitted))
                        .help(reason.displayName)
                        .accessibilityLabel(reason.displayName)
                }
                if inlineCommentCount.total > 0 {
                    Label(inlineCommentCount.displayText, systemImage: "text.bubble")
                        .foregroundStyle(AppTheme.foreground(inlineCommentTone))
                        .help("\(inlineCommentCount.selected) selected of \(inlineCommentCount.total) inline comments")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button {
                model.toggleViewed(path: file.path)
            } label: {
                Label(
                    model.diffReviewFileState.isViewed(file.path) ? AppL10n.string("Mark Unviewed") : AppL10n.string("Mark Viewed"),
                    systemImage: model.diffReviewFileState.isViewed(file.path) ? "circle" : "checkmark.circle"
                )
            }
            Button {
                model.toggleCollapsed(path: file.path)
            } label: {
                Label(
                    model.diffReviewFileState.isCollapsed(file.path) ? AppL10n.string("Expand File") : AppL10n.string("Collapse File"),
                    systemImage: model.diffReviewFileState.isCollapsed(file.path) ? "chevron.down" : "chevron.right"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.path), \(file.status), \(file.additions) additions, \(file.deletions) deletions")
    }
}
