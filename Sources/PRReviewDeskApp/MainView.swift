import SwiftUI
import PRReviewDeskCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var isSubmitConfirmationPresented = false

    var body: some View {
        NavigationSplitView {
            repositorySidebar
        } content: {
            pullRequestList
        } detail: {
            reviewPane
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
    }

    private var repositorySidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            List(model.repositories, selection: repositorySelection) { repository in
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
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
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
            List(model.pullRequests, selection: pullRequestSelection) { pullRequest in
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
        .navigationSplitViewColumnWidth(min: 320, ideal: 380)
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
                draftEditor
            } else {
                ContentUnavailableView(
                    "No Pull Request Selected",
                    systemImage: "text.badge.plus",
                    description: Text("Choose a repository and open pull request.")
                )
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
        HStack(spacing: 10) {
            Button {
                model.startGenerateReview()
            } label: {
                Label("Generate Review", systemImage: "sparkles")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isWorking || model.selectedPullRequest == nil)

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
                submitReview()
            } label: {
                Label("Submit Review (\(model.selectedInlineCommentCount))", systemImage: "paperplane")
            }
            .disabled(model.isWorking || model.draft == nil)
            .confirmationDialog(
                "Submit \(model.selectedEvent.displayName) review?",
                isPresented: $isSubmitConfirmationPresented,
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
                        ForEach(draft.inlineComments) { comment in
                            inlineCommentRow(comment)
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

    private func inlineCommentRow(_ comment: InlineCommentDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
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

    private func submitReview() {
        if model.selectedEvent == .comment {
            Task {
                await model.submitReview()
            }
        } else {
            isSubmitConfirmationPresented = true
        }
    }
}
