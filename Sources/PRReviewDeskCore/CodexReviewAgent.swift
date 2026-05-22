import Foundation

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

public protocol CommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL?
    ) async throws -> CommandResult
}

public enum CodexReviewError: Error, Equatable, CustomStringConvertible, Sendable {
    case processFailed(exitCode: Int32, standardError: String)
    case missingOutput(URL)
    case noReviewableFiles

    public var description: String {
        switch self {
        case let .processFailed(exitCode, standardError):
            return "Codex exited with \(exitCode): \(standardError)"
        case let .missingOutput(url):
            return "Codex did not write expected output at \(url.path)"
        case .noReviewableFiles:
            return "The pull request has no reviewable patch content"
        }
    }
}

public struct ProcessCommandRunner: CommandRunning, Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL?
    ) async throws -> CommandResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRReviewDeskProcess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = workingDirectory

        let stdin = Pipe()
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        if let inputData = standardInput.data(using: .utf8) {
            stdin.fileHandleForWriting.write(inputData)
        }
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
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
}

public final class CodexReviewAgent: @unchecked Sendable {
    private let commandRunner: CommandRunning
    private let workingDirectory: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) {
        self.commandRunner = commandRunner
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        decoder = JSONDecoder()
    }

    public func generateReview(
        repository: Repository,
        pullRequest: PullRequest,
        files: [PullRequestFile]
    ) async throws -> ReviewDraft {
        let prompt = try makePrompt(repository: repository, pullRequest: pullRequest, files: files)
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PRReviewDeskCodex-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        let schemaURL = tempDirectory.appendingPathComponent("review-schema.json")
        let outputURL = tempDirectory.appendingPathComponent("review-output.json")
        try reviewSchema.write(to: schemaURL, atomically: true, encoding: .utf8)

        let result = try await commandRunner.run(
            executable: "codex",
            arguments: [
                "exec",
                "--skip-git-repo-check",
                "--sandbox",
                "read-only",
                "--ephemeral",
                "--output-schema",
                schemaURL.path,
                "--output-last-message",
                outputURL.path,
                "-"
            ],
            standardInput: prompt,
            workingDirectory: workingDirectory
        )

        guard result.exitCode == 0 else {
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
        files: [PullRequestFile]
    ) throws -> String {
        let annotatedDiffs = try files.compactMap { file -> AnnotatedDiff? in
            guard let patch = file.patch, !patch.isEmpty else {
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
