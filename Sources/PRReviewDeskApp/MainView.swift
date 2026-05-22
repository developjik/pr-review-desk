import SwiftUI
import PRReviewDeskCore

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HSplitView {
            repositorySidebar
                .frame(minWidth: 260, idealWidth: 300)
            pullRequestList
                .frame(minWidth: 320, idealWidth: 380)
            reviewPane
                .frame(minWidth: 520)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let recoverableError = model.recoverableError {
                    recoverableErrorPanel(recoverableError)
                }
                statusBar
            }
        }
        .sheet(item: $model.pendingPrivateRepositoryConsent) { request in
            PrivateRepositoryConsentSheet(
                request: request,
                onCancel: {
                    model.cancelPrivateRepositoryConsent()
                },
                onAcknowledge: {
                    model.confirmPrivateRepositoryConsentAndGenerate()
                }
            )
        }
    }

    private var repositorySidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReadinessChecklistView(model: model)
            Divider()
            tokenSection
            Divider()
            HStack {
                Text("Repositories")
                    .font(.headline)
                Spacer()
                Button {
                    Task {
                        await model.refreshRepositories()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh repositories")
                .disabled(model.isWorking || !model.hasToken)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search repositories", text: $model.repositorySearchText)
                    .textFieldStyle(.roundedBorder)
            }
            List(model.filteredRepositories, selection: repositorySelection) { repository in
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.name)
                        .font(.body)
                    Text(repository.owner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(repository)
            }
        }
        .padding()
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub")
                .font(.headline)
            SecureField("Personal access token", text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    Task {
                        await model.saveTokenAndRefresh()
                    }
                } label: {
                    Label("Save", systemImage: "key")
                }
                .disabled(model.isWorking)

                Button {
                    model.loadStoredToken()
                    Task {
                        await model.refreshRepositories()
                    }
                } label: {
                    Label("Load", systemImage: "lock.open")
                }
                .disabled(model.isWorking)
            }
            Text(model.hasToken ? "Token available" : "No token loaded")
                .font(.caption)
                .foregroundStyle(model.hasToken ? .green : .secondary)
        }
    }

    private var pullRequestList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.selectedRepository?.fullName ?? "Select a repository")
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search pull requests", text: $model.pullRequestSearchText)
                    .textFieldStyle(.roundedBorder)
            }
            List(model.filteredPullRequests, selection: pullRequestSelection) { pullRequest in
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(pullRequest.number) \(pullRequest.title)")
                        .font(.body)
                        .lineLimit(2)
                    Text(pullRequest.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(pullRequest)
            }
        }
        .padding()
    }

    private var reviewPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pullRequest = model.selectedPullRequest {
                pullRequestHeader(pullRequest)
                Divider()
                if !model.changedFiles.isEmpty {
                    reviewCoverageBanner(model.reviewCoverageSummary)
                }
                reviewControls
                reviewWorkspace
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ReadinessChecklistView(model: model)
                        .frame(maxWidth: 520, alignment: .leading)

                    ContentUnavailableView(
                        "No Pull Request Selected",
                        systemImage: "text.badge.plus",
                        description: Text("Choose a repository and open pull request.")
                    )
                }
            }
        }
        .padding()
    }

    private func reviewCoverageBanner(_ summary: ReviewCoverageSummary) -> some View {
        let hasOmittedFiles = summary.omittedFileCount > 0

        return VStack(alignment: .leading, spacing: 6) {
            Label(
                hasOmittedFiles ? "Partial Codex coverage" : "Full Codex coverage",
                systemImage: hasOmittedFiles ? "exclamationmark.triangle" : "checkmark.circle"
            )
            .font(.headline)
            .foregroundStyle(hasOmittedFiles ? .orange : .green)

            Text("\(summary.reviewableFileCount) of \(summary.totalFileCount) changed files have reviewable patches.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasOmittedFiles {
                Text("\(summary.omittedFileCount) files, +\(summary.omittedAdditions) -\(summary.omittedDeletions), will not be sent to Codex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.background)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasOmittedFiles ? .orange.opacity(0.45) : .green.opacity(0.35))
        }
    }

    @ViewBuilder
    private var reviewWorkspace: some View {
        if model.changedFiles.isEmpty {
            draftEditor
        } else {
            HSplitView {
                changedFilesPane
                    .frame(minWidth: 240, idealWidth: 280)
                selectedFileDetail
                    .frame(minWidth: 360, idealWidth: 520)
                draftEditor
                    .frame(minWidth: 360)
            }
        }
    }

    private var changedFilesPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Changed Files")
                .font(.headline)
            List(model.changedFiles, selection: changedFileSelection) { file in
                changedFileRow(file)
                    .tag(file.path)
            }
        }
    }

    private func changedFileRow(_ file: PullRequestFile) -> some View {
        let inlineCommentCount = model.inlineCommentCount(for: file)
        let inlineCommentCountColor: Color = inlineCommentCount.selected == inlineCommentCount.total ? .secondary : .orange

        return VStack(alignment: .leading, spacing: 4) {
            Text(file.path)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(file.status)
                Text("+\(file.additions)")
                    .foregroundStyle(.green)
                Text("-\(file.deletions)")
                    .foregroundStyle(.red)
                if case let .omitted(reason) = file.reviewability {
                    Label(reason.displayName, systemImage: "exclamationmark.triangle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .help(reason.displayName)
                }
                if inlineCommentCount.total > 0 {
                    Label(inlineCommentCount.displayText, systemImage: "text.bubble")
                        .foregroundStyle(inlineCommentCountColor)
                        .help("\(inlineCommentCount.selected) selected of \(inlineCommentCount.total) inline comments")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var selectedFileDetail: some View {
        if let file = model.selectedChangedFile {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
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

                let annotatedDiff = annotatedDiff(for: file)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(annotatedDiff.lines) { line in
                                diffLineView(line, isHighlighted: isFocusedDiffLine(line, in: file))
                                    .id(diffLineScrollID(line))
                            }
                        }
                        .padding(8)
                    }
                    .onAppear {
                        scrollToFocusedDiffPosition(proxy: proxy, file: file)
                    }
                    .onChange(of: model.focusedInlineCommentTarget) { _, _ in
                        scrollToFocusedDiffPosition(proxy: proxy, file: file)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }

                let comments = commentsForFile(file)
                if !comments.isEmpty {
                    Text("Inline Comments")
                        .font(.headline)
                    ForEach(comments) { comment in
                        inlineCommentReferenceRow(comment)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc.text",
                description: Text("Select a changed file.")
            )
        }
    }

    private func pullRequestHeader(_ pullRequest: PullRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(pullRequest.number) \(pullRequest.title)")
                .font(.title3)
                .fontWeight(.semibold)
            HStack(spacing: 12) {
                Text(pullRequest.author)
                Text(pullRequest.headSha.prefix(8))
                Link("Open on GitHub", destination: pullRequest.htmlURL)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.startGenerateReview()
                } label: {
                    Label("Generate Review", systemImage: "sparkles")
                }
                .disabled(!model.canGenerateReview)

                if model.canCancelCurrentOperation {
                    Button {
                        model.cancelCurrentOperation()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .keyboardShortcut(".", modifiers: [.command])
                }

                Picker("Review event", selection: $model.selectedEvent) {
                    ForEach(ReviewEvent.allCases) { event in
                        Text(event.displayName).tag(event)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)

                Button {
                    model.requestSubmitReview()
                } label: {
                    Label("Submit Review (\(model.selectedInlineCommentCount))", systemImage: "paperplane")
                }
                .disabled(!model.canSubmitReview)
                .confirmationDialog(
                    "Submit \(model.selectedEvent.displayName) review?",
                    isPresented: $model.isSubmitConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Submit \(model.selectedEvent.displayName) Review") {
                        Task {
                            await model.submitReview()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will post a \(model.selectedEvent.displayName) review with \(model.selectedInlineCommentCount) selected inline comments to GitHub.")
                }
            }

            if model.draft != nil {
                submitSafetyPanel
            }
        }
    }

    private var submitSafetyPanel: some View {
        let state = model.submitSafetyState

        return HStack(spacing: 14) {
            Label(model.submitSafetyMessage, systemImage: state.canSubmit ? "checkmark.shield" : "exclamationmark.triangle")
                .foregroundStyle(state.canSubmit ? .green : .orange)

            Text("Event \(model.selectedEvent.displayName)")
            Text("Selected \(state.selectedInlineCommentCount)")
            Text("Invalid \(state.invalidSelectedInlineComments.count)")
                .foregroundStyle(state.invalidSelectedInlineComments.isEmpty ? Color.secondary : Color.red)
            Text("Reviewed \(shortSha(state.reviewedHeadSha))")
            Text("Current \(shortSha(state.currentHeadSha))")

            Spacer()

            if state.isStale {
                Button {
                    model.startGenerateReview()
                } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!model.canGenerateReview)
            }

            Button {
                Task {
                    await model.refreshSubmitSafety()
                }
            } label: {
                Label("Refresh Safety", systemImage: "shield.lefthalf.filled")
            }
            .disabled(model.isWorking)
        }
        .font(.caption)
        .padding(8)
        .background(.background)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(state.canSubmit ? .green.opacity(0.35) : .orange.opacity(0.45))
        }
    }

    private var draftEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review Body")
                .font(.headline)
            TextEditor(text: $model.reviewBody)
                .font(.body)
                .frame(minHeight: 130)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }

            Text("Inline Comments")
                .font(.headline)
            if let draft = model.draft, !draft.inlineComments.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(commentsGroupedByPath(draft.inlineComments), id: \.path) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.path)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                ForEach(group.comments) { comment in
                                    inlineCommentRow(comment, isInvalid: model.isInlineCommentInvalid(comment))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("No inline comments generated yet.")
                    .foregroundStyle(.secondary)
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

    private func diffLineView(_ line: AnnotatedDiffLine, isHighlighted: Bool) -> some View {
        Text(line.text.isEmpty ? " " : line.text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay(alignment: .leading) {
                if isHighlighted {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }
    }

    private func isFocusedDiffLine(_ line: AnnotatedDiffLine, in file: PullRequestFile) -> Bool {
        guard let target = model.focusedInlineCommentTarget else {
            return false
        }

        return target.path == file.path && line.position == target.position
    }

    private func diffLineScrollID(_ line: AnnotatedDiffLine) -> String {
        if let position = line.position {
            return "position-\(position)"
        }

        return "line-\(line.index)"
    }

    private func scrollToFocusedDiffPosition(proxy: ScrollViewProxy, file: PullRequestFile) {
        guard let target = model.focusedInlineCommentTarget, target.path == file.path else {
            return
        }

        proxy.scrollTo("position-\(target.position)", anchor: .center)
    }

    private func commentsForFile(_ file: PullRequestFile) -> [InlineCommentDraft] {
        (model.draft?.inlineComments ?? [])
            .filter { $0.path == file.path }
            .sorted { $0.position < $1.position }
    }

    private func commentsGroupedByPath(_ comments: [InlineCommentDraft]) -> [(path: String, comments: [InlineCommentDraft])] {
        Dictionary(grouping: comments, by: \.path)
            .map { path, comments in
                (
                    path: path,
                    comments: comments.sorted { $0.position < $1.position }
                )
            }
            .sorted { $0.path < $1.path }
    }

    private func inlineCommentRow(_ comment: InlineCommentDraft, isInvalid: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { comment.isSelected },
                    set: { model.setInlineCommentSelection(id: comment.id, isSelected: $0) }
                )) {
                    HStack {
                        Text(comment.path)
                            .fontWeight(.medium)
                        Text("pos \(comment.position)")
                            .foregroundStyle(.secondary)
                        Text(comment.severity.rawValue)
                            .foregroundStyle(severityColor(comment.severity))
                    }
                }

                Spacer()

                Button {
                    model.focusInlineComment(comment)
                } label: {
                    Image(systemName: "scope")
                }
                .help("Reveal in diff")
            }
            if isInvalid {
                Text("Invalid selected target. Refresh safety or regenerate before submitting.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextEditor(text: Binding(
                get: { comment.body },
                set: { model.setInlineCommentBody(id: comment.id, body: $0) }
            ))
            .frame(minHeight: 76)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary)
            }
        }
        .padding(10)
        .background(.background)
        .overlay {
            if isInvalid {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.red.opacity(0.7))
            } else if model.isFocusedInlineComment(comment) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.7))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
        }
    }

    private func inlineCommentReferenceRow(_ comment: InlineCommentDraft) -> some View {
        Button {
            model.focusInlineComment(comment)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("pos \(comment.position)")
                        .fontWeight(.medium)
                    Text(comment.severity.rawValue)
                        .foregroundStyle(severityColor(comment.severity))
                    if !comment.isSelected {
                        Text("not selected")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)

                Text(comment.body)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(model.isFocusedInlineComment(comment) ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(model.isFocusedInlineComment(comment) ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25))
            }
        }
        .buttonStyle(.plain)
        .help("Reveal inline comment target in diff")
    }

    private var statusBar: some View {
        HStack {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.statusMessage)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func recoverableErrorPanel(_ error: RecoverableErrorDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(error.operation, systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button {
                    model.dismissRecoverableError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Dismiss error")
            }

            Text(error.summary)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(error.details)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(error.recoverySuggestion)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.orange.opacity(0.35))
                .frame(height: 1)
        }
    }

    private var repositorySelection: Binding<Repository?> {
        Binding(
            get: { model.selectedRepository },
            set: { repository in
                guard let repository else {
                    return
                }
                Task {
                    await model.selectRepository(repository)
                }
            }
        )
    }

    private var pullRequestSelection: Binding<PullRequest?> {
        Binding(
            get: { model.selectedPullRequest },
            set: { pullRequest in
                guard let pullRequest else {
                    return
                }
                Task {
                    await model.selectPullRequest(pullRequest)
                }
            }
        )
    }

    private var changedFileSelection: Binding<String?> {
        Binding(
            get: { model.selectedChangedFilePath },
            set: { path in
                model.selectedChangedFilePath = path
            }
        )
    }

    private func shortSha(_ sha: String?) -> String {
        guard let sha else {
            return "-"
        }

        return String(sha.prefix(8))
    }

    private func severityColor(_ severity: CommentSeverity) -> Color {
        switch severity {
        case .low:
            return .secondary
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

}
