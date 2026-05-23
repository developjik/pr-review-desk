import SwiftUI
import PRReviewDeskCore

struct DiffViewer: View {
    let annotatedDiff: AnnotatedDiff
    let inlineComments: [InlineCommentDraft]
    let displayMode: DiffDisplayMode
    let showsWhitespace: Bool
    let isFocused: (AnnotatedDiffLine) -> Bool
    let scrollTargetPosition: Int?
    let scrollTargetLineIndex: Int?
    let onSelectInlineComment: (InlineCommentDraft) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(annotatedDiff.lines) { line in
                        DiffLineView(
                            line: line,
                            comments: commentsByPosition[line.position ?? -1] ?? [],
                            displayMode: displayMode,
                            showsWhitespace: showsWhitespace,
                            isHighlighted: isFocused(line),
                            onSelectInlineComment: onSelectInlineComment
                        )
                        .id(diffLineScrollID(line))
                    }
                }
                .padding(8)
            }
            .onAppear {
                scrollToFocusedDiffPosition(proxy: proxy)
            }
            .onChange(of: scrollTargetPosition) { _, _ in
                scrollToFocusedDiffPosition(proxy: proxy)
            }
            .onChange(of: scrollTargetLineIndex) { _, _ in
                scrollToFocusedDiffPosition(proxy: proxy)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary)
        }
    }

    private var commentsByPosition: [Int: [InlineCommentDraft]] {
        Dictionary(grouping: inlineComments, by: \.position)
    }

    private func scrollToFocusedDiffPosition(proxy: ScrollViewProxy) {
        if let scrollTargetLineIndex {
            proxy.scrollTo("line-\(scrollTargetLineIndex)", anchor: .center)
            return
        }

        guard let scrollTargetPosition else {
            return
        }

        proxy.scrollTo("position-\(scrollTargetPosition)", anchor: .center)
    }

    private func diffLineScrollID(_ line: AnnotatedDiffLine) -> String {
        if let position = line.position {
            return "position-\(position)"
        }

        return "line-\(line.index)"
    }
}

private struct DiffLineView: View {
    let line: AnnotatedDiffLine
    let comments: [InlineCommentDraft]
    let displayMode: DiffDisplayMode
    let showsWhitespace: Bool
    let isHighlighted: Bool
    let onSelectInlineComment: (InlineCommentDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 0) {
                gutterText(line.oldLine.map(String.init) ?? "")
                gutterText(line.newLine.map(String.init) ?? "")
                gutterText(line.position.map { "p\($0)" } ?? "", width: 46)

                switch displayMode {
                case .unified:
                    codeText(displayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .split:
                    HStack(spacing: 0) {
                        codeText(splitLeftText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        codeText(splitRightText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(comments) { comment in
                        Button {
                            onSelectInlineComment(comment)
                        } label: {
                            Label(comment.body, systemImage: "text.bubble")
                                .font(.caption)
                                .foregroundStyle(AppTheme.foreground(ReviewViewSupport.severityTone(comment.severity)))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 92)
                .padding(.trailing, 8)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 1)
        .background(lineBackground)
        .overlay(alignment: .leading) {
            if isHighlighted {
                Rectangle()
                    .fill(AppTheme.foreground(.focus))
                    .frame(width: 3)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func gutterText(_ text: String, width: CGFloat = 34) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: width, alignment: .trailing)
            .padding(.trailing, 4)
            .textSelection(.enabled)
    }

    private func codeText(_ text: String) -> some View {
        Text(renderWhitespace(text).isEmpty ? " " : renderWhitespace(text))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .foregroundStyle(AppTheme.diffForeground(for: line.kind))
            .padding(.horizontal, 6)
    }

    private var lineBackground: Color {
        if isHighlighted {
            return AppTheme.background(.focus)
        }

        return AppTheme.diffBackground(for: line.kind)
    }

    private var displayText: String {
        guard line.text.hasPrefix("[pos "),
              let closingRange = line.text.range(of: "] ")
        else {
            return line.text
        }

        return String(line.text[closingRange.upperBound...])
    }

    private var splitLeftText: String {
        switch line.kind {
        case .deletion, .context:
            return displayText
        case .addition:
            return ""
        case .hunk, .metadata, .omitted:
            return displayText
        }
    }

    private var splitRightText: String {
        switch line.kind {
        case .addition, .context:
            return displayText
        case .deletion:
            return ""
        case .hunk, .metadata, .omitted:
            return displayText
        }
    }

    private func renderWhitespace(_ text: String) -> String {
        guard showsWhitespace else {
            return text
        }

        return text
            .replacingOccurrences(of: "\t", with: "→\t")
            .replacingOccurrences(of: " ", with: "·")
    }

    private var accessibilityLabel: String {
        var parts = [line.kind.rawValue]
        if let oldLine = line.oldLine {
            parts.append("old line \(oldLine)")
        }
        if let newLine = line.newLine {
            parts.append("new line \(newLine)")
        }
        if let position = line.position {
            parts.append("position \(position)")
        }
        parts.append(line.text)
        return parts.joined(separator: ", ")
    }
}
