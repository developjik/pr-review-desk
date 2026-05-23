import Foundation
import Darwin

public struct CommandResult: Equatable, Hashable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum CommandRunError: Error, Equatable, CustomStringConvertible, Sendable {
    case timedOut(seconds: TimeInterval)
    case cancelled

    public var description: String {
        switch self {
        case let .timedOut(seconds):
            return "Command timed out after \(seconds) seconds"
        case .cancelled:
            return "Command was cancelled"
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL?,
        timeout: TimeInterval?
    ) async throws -> CommandResult
}

public enum CodexReviewError: Error, Equatable, CustomStringConvertible, Sendable {
    case processFailed(exitCode: Int32, standardError: String)
    case missingExecutable(String)
    case timedOut(seconds: TimeInterval)
    case cancelled
    case missingOutput(URL)
    case noReviewableFiles

    public var description: String {
        switch self {
        case let .processFailed(exitCode, standardError):
            return "Codex exited with \(exitCode): \(standardError)"
        case let .missingExecutable(executable):
            return "Codex executable not found: \(executable)"
        case let .timedOut(seconds):
            return "Codex timed out after \(seconds) seconds"
        case .cancelled:
            return "Codex review generation was cancelled"
        case let .missingOutput(url):
            return "Codex did not write expected output at \(url.path)"
        case .noReviewableFiles:
            return "The pull request has no reviewable changes"
        }
    }
}

public struct ProcessCommandRunner: CommandRunning, Sendable {
    private let temporaryDirectory: URL

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    public func run(
        executable: String,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL?,
        timeout: TimeInterval?
    ) async throws -> CommandResult {
        try Task.checkCancellation()

        let commandTemporaryDirectory = temporaryDirectory
            .appendingPathComponent("PRReviewDeskProcess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: commandTemporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: commandTemporaryDirectory)
        }

        let stdoutURL = commandTemporaryDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = commandTemporaryDirectory.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = workingDirectory

        let stdin = Pipe()
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        if let inputData = standardInput.data(using: .utf8) {
            stdin.fileHandleForWriting.write(inputData)
        }
        try? stdin.fileHandleForWriting.close()
        try await waitForExit(process: process, timeout: timeout)
        try? stdout.close()
        try? stderr.close()

        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
            standardError: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func waitForExit(process: Process, timeout: TimeInterval?) async throws {
        let start = Date()

        while process.isRunning {
            if Task.isCancelled {
                terminate(process)
                throw CommandRunError.cancelled
            }

            if let timeout, Date().timeIntervalSince(start) >= timeout {
                terminate(process)
                throw CommandRunError.timedOut(seconds: timeout)
            }

            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch is CancellationError {
                terminate(process)
                throw CommandRunError.cancelled
            }
        }
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}

public final class CodexReviewAgent: @unchecked Sendable {
    private let commandRunner: CommandRunning
    private let workingDirectory: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let generationTimeout: TimeInterval

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        workingDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default,
        generationTimeout: TimeInterval = 120
    ) {
        self.commandRunner = commandRunner
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.generationTimeout = generationTimeout
        decoder = JSONDecoder()
    }

    public func generateReview(
        repository: Repository,
        pullRequest: PullRequest,
        files: [PullRequestFile],
        context: PullRequestReviewContext = .empty
    ) async throws -> ReviewDraft {
        let prompt = try makePrompt(repository: repository, pullRequest: pullRequest, files: files, context: context)
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PRReviewDeskCodex-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        let schemaURL = tempDirectory.appendingPathComponent("review-schema.json")
        let outputURL = tempDirectory.appendingPathComponent("review-output.json")
        try reviewSchema.write(to: schemaURL, atomically: true, encoding: .utf8)

        let result: CommandResult
        do {
            result = try await commandRunner.run(
                executable: "codex",
                arguments: [
                    "exec",
                    "--ignore-user-config",
                    "--ignore-rules",
                    "--cd",
                    workingDirectory.path,
                    "--skip-git-repo-check",
                    "--sandbox",
                    "read-only",
                    "--ephemeral",
                    "-c",
                    "model_reasoning_effort=\"low\"",
                    "--output-schema",
                    schemaURL.path,
                    "--output-last-message",
                    outputURL.path,
                    "-"
                ],
                standardInput: prompt,
                workingDirectory: workingDirectory,
                timeout: generationTimeout
            )
        } catch let error as CommandRunError {
            throw codexError(from: error)
        } catch is CancellationError {
            throw CodexReviewError.cancelled
        }

        guard result.exitCode == 0 else {
            if isMissingExecutable(result, executable: "codex") {
                throw CodexReviewError.missingExecutable("codex")
            }
            throw CodexReviewError.processFailed(exitCode: result.exitCode, standardError: result.standardError)
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw CodexReviewError.missingOutput(outputURL)
        }

        let data = try Data(contentsOf: outputURL)
        return try decoder.decode(ReviewDraft.self, from: data)
    }

    public func makePrompt(
        repository: Repository,
        pullRequest: PullRequest,
        files: [PullRequestFile],
        context: PullRequestReviewContext = .empty
    ) throws -> String {
        let annotatedDiffs = try files.compactMap { file -> AnnotatedDiff? in
            guard file.reviewability == .includedPatch,
                  let patch = file.patch,
                  !patch.isEmpty
            else {
                return nil
            }
            return try DiffPositionMapper.annotate(path: file.path, patch: patch)
        }

        guard !annotatedDiffs.isEmpty else {
            throw CodexReviewError.noReviewableFiles
        }

        let filesText = annotatedDiffs.map { diff in
            """
            FILE: \(diff.path)
            \(diff.annotatedPatch)
            """
        }.joined(separator: "\n\n")

        return """
        You are reviewing a GitHub pull request for a personal developer workflow.
        Return only JSON that conforms to the provided schema.

        Repository: \(repository.fullName)
        Pull request: #\(pullRequest.number) \(pullRequest.title)
        Author: \(pullRequest.author)
        URL: \(pullRequest.htmlURL.absoluteString)
        Head SHA: \(pullRequest.headSha)

        \(makeContextText(context))

        Review goals:
        - Focus on correctness, regressions, security, data loss, and missing tests.
        - Do not comment on style unless it creates a real maintenance risk.
        - Prefer fewer, higher-confidence inline comments.
        - Inline comments must use the exact file path and `[pos N]` diff position shown below.
        - If no inline comment is warranted, return an empty inline_comments array.

        Changed files:

        \(filesText)
        """
    }

    private func makeContextText(_ context: PullRequestReviewContext) -> String {
        var lines = [
            "Additional pull request context:",
            "Context limits: PR body \(PromptContextLimits.bodyCharacters) characters, issue comments \(PromptContextLimits.issueCommentCount) x \(PromptContextLimits.commentCharacters) characters, review comments \(PromptContextLimits.reviewCommentCount) x \(PromptContextLimits.commentCharacters) characters, check runs \(PromptContextLimits.checkRunCount)."
        ]

        guard !context.isEmpty else {
            lines.append("No additional PR body, comments, or checks were provided.")
            return lines.joined(separator: "\n")
        }

        if let body = context.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            lines.append("")
            lines.append("PR body:")
            lines.append(truncatedContextText(body, limit: PromptContextLimits.bodyCharacters))
        }

        if !context.issueComments.isEmpty {
            lines.append("")
            lines.append("Existing issue comments:")
            for comment in context.issueComments.prefix(PromptContextLimits.issueCommentCount) {
                let createdAt = comment.createdAt.map { " at \($0)" } ?? ""
                lines.append("- @\(comment.author)\(createdAt): \(truncatedContextText(comment.body, limit: PromptContextLimits.commentCharacters))")
            }
            appendOmittedCount(
                total: context.issueComments.count,
                included: PromptContextLimits.issueCommentCount,
                itemDescription: "issue comments",
                to: &lines
            )
        }

        if !context.reviewComments.isEmpty {
            lines.append("")
            lines.append("Existing review comments:")
            for comment in context.reviewComments.prefix(PromptContextLimits.reviewCommentCount) {
                let position = comment.position.map { "[pos \($0)]" } ?? "[no position]"
                let createdAt = comment.createdAt.map { " at \($0)" } ?? ""
                lines.append("- @\(comment.author) on \(comment.path) \(position)\(createdAt): \(truncatedContextText(comment.body, limit: PromptContextLimits.commentCharacters))")
            }
            appendOmittedCount(
                total: context.reviewComments.count,
                included: PromptContextLimits.reviewCommentCount,
                itemDescription: "review comments",
                to: &lines
            )
        }

        if !context.checkRuns.isEmpty {
            lines.append("")
            lines.append("Check/status summary:")
            for checkRun in context.checkRuns.prefix(PromptContextLimits.checkRunCount) {
                let conclusion = checkRun.conclusion ?? "no conclusion"
                let details = checkRun.detailsURL.map { " (\($0.absoluteString))" } ?? ""
                lines.append("- \(checkRun.name): \(checkRun.status) / \(conclusion)\(details)")
            }
            appendOmittedCount(
                total: context.checkRuns.count,
                included: PromptContextLimits.checkRunCount,
                itemDescription: "check runs",
                to: &lines
            )
        }

        return lines.joined(separator: "\n")
    }

    private func truncatedContextText(_ text: String, limit: Int) -> String {
        let redacted = SensitiveTextRedactor.redact(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.count > limit else {
            return redacted
        }

        let endIndex = redacted.index(redacted.startIndex, offsetBy: limit)
        return String(redacted[..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines) + " ... [truncated]"
    }

    private func appendOmittedCount(
        total: Int,
        included: Int,
        itemDescription: String,
        to lines: inout [String]
    ) {
        guard total > included else {
            return
        }

        lines.append("- ... \(total - included) more \(itemDescription) omitted by context limit.")
    }

    private func codexError(from error: CommandRunError) -> CodexReviewError {
        switch error {
        case let .timedOut(seconds):
            return .timedOut(seconds: seconds)
        case .cancelled:
            return .cancelled
        }
    }

    private func isMissingExecutable(_ result: CommandResult, executable: String) -> Bool {
        guard result.exitCode == 127 else {
            return false
        }

        let message = result.standardError.lowercased()
        return message.contains(executable.lowercased())
            && (message.contains("no such file") || message.contains("not found"))
    }

    private let reviewSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["summary", "risks", "inline_comments"],
      "properties": {
        "summary": {
          "type": "string"
        },
        "risks": {
          "type": "array",
          "items": { "type": "string" }
        },
        "inline_comments": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["path", "position", "body", "severity"],
            "properties": {
              "path": { "type": "string" },
              "position": { "type": "integer", "minimum": 1 },
              "body": { "type": "string" },
              "severity": {
                "type": "string",
                "enum": ["low", "medium", "high"]
              }
            }
          }
        }
      }
    }
    """
}

private enum PromptContextLimits {
    static let bodyCharacters = 2_000
    static let commentCharacters = 800
    static let issueCommentCount = 6
    static let reviewCommentCount = 6
    static let checkRunCount = 10
}
