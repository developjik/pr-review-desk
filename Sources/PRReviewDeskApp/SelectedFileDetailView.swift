import SwiftUI
import PRReviewDeskCore

struct SelectedFileDetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let file = model.selectedChangedFile {
            VStack(alignment: .leading, spacing: 10) {
                header(for: file)

                if model.diffReviewFileState.isCollapsed(file.path) {
                    ContentUnavailableView {
                        Label(AppL10n.string("File Collapsed"), systemImage: "chevron.right")
                    } description: {
                        Text(AppL10n.string("Expand the file to review this diff."))
                    } actions: {
                        Button {
                            model.toggleCollapsed(path: file.path)
                        } label: {
                            Label(AppL10n.string("Expand File"), systemImage: "chevron.down")
                        }
                    }
                } else {
                    let annotatedDiff = annotatedDiff(for: file)
                    DiffViewer(
                        annotatedDiff: annotatedDiff,
                        inlineComments: commentsForFile(file),
                        displayMode: model.diffDisplayMode,
                        showsWhitespace: model.showsWhitespaceInDiff,
                        isFocused: { line in isFocusedDiffLine(line, in: file) },
                        scrollTargetPosition: scrollTargetPosition(for: file),
                        scrollTargetLineIndex: scrollTargetLineIndex(for: file),
                        onSelectInlineComment: { comment in
                            model.focusInlineComment(comment)
                        }
                    )
                }
            }
        } else {
            ContentUnavailableView(
                AppL10n.string("No File Selected"),
                systemImage: "doc.text",
                description: Text(AppL10n.string("Select a changed file."))
            )
        }
    }

    private func header(for file: PullRequestFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.path)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(file.status)  +\(file.additions)  -\(file.deletions)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let reviewedHeadSha = model.reviewedHeadShaForDisplay {
                    Text("Draft \(reviewedHeadSha.prefix(8))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No draft SHA")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Picker(AppL10n.string("Diff mode"), selection: $model.diffDisplayMode) {
                    ForEach(DiffDisplayMode.allCases) { mode in
                        Text(AppL10n.string(mode.displayName)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)

                Toggle(isOn: $model.showsWhitespaceInDiff) {
                    Label(AppL10n.string("Whitespace"), systemImage: "paragraphsign")
                }
                .labelStyle(.iconOnly)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(AppL10n.string("Whitespace"))
                .accessibilityLabel(AppL10n.string("Whitespace"))

                Button {
                    model.toggleViewed(path: file.path)
                } label: {
                    Label(
                        model.diffReviewFileState.isViewed(file.path) ? AppL10n.string("Mark Unviewed") : AppL10n.string("Mark Viewed"),
                        systemImage: model.diffReviewFileState.isViewed(file.path) ? "circle" : "checkmark.circle"
                    )
                }
                .controlSize(.small)

                Button {
                    model.toggleCollapsed(path: file.path)
                } label: {
                    Label(
                        model.diffReviewFileState.isCollapsed(file.path) ? AppL10n.string("Expand File") : AppL10n.string("Collapse File"),
                        systemImage: model.diffReviewFileState.isCollapsed(file.path) ? "chevron.down" : "chevron.right"
                    )
                }
                .controlSize(.small)

                Spacer()
            }
        }
    }

    private func annotatedDiff(for file: PullRequestFile) -> AnnotatedDiff {
        switch file.reviewability {
        case .includedPatch:
            guard let patch = file.patch else {
                return AnnotatedDiff(path: file.path, annotatedPatch: "", positionsByNewLine: [:])
            }
            do {
                return try DiffPositionMapper.annotate(path: file.path, patch: patch)
            } catch {
                return AnnotatedDiff(path: file.path, annotatedPatch: patch, positionsByNewLine: [:])
            }
        case let .omitted(reason):
            return AnnotatedDiff(
                path: file.path,
                annotatedPatch: "\(reason.displayName). This file was not sent to Codex because GitHub did not provide reviewable patch content.",
                positionsByNewLine: [:]
            )
        }
    }

    private func isFocusedDiffLine(_ line: AnnotatedDiffLine, in file: PullRequestFile) -> Bool {
        guard let target = model.focusedInlineCommentTarget else {
            return model.focusedDiffLineIndex == line.index
        }

        return target.path == file.path && line.position == target.position
    }

    private func scrollTargetPosition(for file: PullRequestFile) -> Int? {
        guard let target = model.focusedInlineCommentTarget, target.path == file.path else {
            return nil
        }

        return target.position
    }

    private func scrollTargetLineIndex(for file: PullRequestFile) -> Int? {
        guard model.focusedInlineCommentTarget == nil else {
            return nil
        }

        return model.focusedDiffLineIndex
    }

    private func commentsForFile(_ file: PullRequestFile) -> [InlineCommentDraft] {
        (model.draft?.inlineComments ?? [])
            .filter { $0.path == file.path }
            .sorted { $0.position < $1.position }
    }
}
