import Foundation
import PRReviewDeskCore

enum CodexReviewAgentTests {
    static func run() async throws {
        try await testGenerateReviewRunsCodexExecWithSchemaAndAnnotatedPatch()
        try await testGenerateReviewPassesDefaultTimeoutToRunner()
        try await testGenerateReviewMapsMissingCodexExecutable()
        try await testGenerateReviewMapsCommandTimeout()
        try await testGenerateReviewMapsCommandCancellation()
        try testMakePromptOmitsFilesWithoutReviewablePatches()
        try testReviewDraftDecodesCodexOutputWithoutLocalFields()
        try await testProcessCommandRunnerReturnsWhenChildKeepsStdoutOpen()
        try await testProcessCommandRunnerCleansTemporaryDirectoryAfterFailedCommand()
        try await testProcessCommandRunnerTimesOutAndCleansTemporaryDirectory()
        try await testProcessCommandRunnerCancelsAndCleansTemporaryDirectory()
    }

    private static func testGenerateReviewRunsCodexExecWithSchemaAndAnnotatedPatch() async throws {
        let runner = FakeCommandRunner(outputJSON: """
        {
          "summary": "Review summary",
          "risks": ["Risk one"],
          "inline_comments": [
            {
              "path": "Sources/App.swift",
              "position": 2,
              "body": "Please tighten this branch.",
              "severity": "high"
            }
          ]
        }
        """)
        let agent = CodexReviewAgent(commandRunner: runner, workingDirectory: URL(fileURLWithPath: "/tmp/review-desk"))
        let repository = Repository(id: 1, owner: "developjik", name: "desk", fullName: "developjik/desk", isPrivate: false)
        let pullRequest = PullRequest(
            id: 2,
            number: 5,
            title: "Improve review flow",
            htmlURL: URL(string: "https://github.com/developjik/desk/pull/5")!,
            author: "contributor",
            headSha: "abc123"
        )
        let files = [
            PullRequestFile(
                path: "Sources/App.swift",
                status: "modified",
                additions: 1,
                deletions: 0,
                patch: """
                @@ -1,1 +1,2 @@
                 let old = true
                +let new = true
                """
            )
        ]

        let draft = try await agent.generateReview(repository: repository, pullRequest: pullRequest, files: files)

        try expectEqual(draft.summary, "Review summary")
        try expectEqual(draft.risks, ["Risk one"])
        try expectEqual(draft.inlineComments.count, 1)
        try expectEqual(draft.inlineComments[0].isSelected, true)
        try expectEqual(runner.executable, "codex")
        try expectTrue(runner.arguments.contains("exec"))
        try expectTrue(runner.arguments.contains("--ignore-user-config"))
        try expectTrue(runner.arguments.contains("--ignore-rules"))
        try expectTrue(runner.arguments.contains("--cd"))
        try expectTrue(runner.arguments.contains("/tmp/review-desk"))
        try expectTrue(runner.arguments.contains("model_reasoning_effort=\"low\""))
        try expectTrue(runner.arguments.contains("--sandbox"))
        try expectTrue(runner.arguments.contains("read-only"))
        try expectTrue(runner.arguments.contains("--output-schema"))
        try expectTrue(runner.arguments.contains("--output-last-message"))
        try expectTrue(runner.standardInput.contains("Improve review flow"))
        try expectTrue(runner.standardInput.contains("[pos 2] +let new = true"))
    }

    private static func testGenerateReviewPassesDefaultTimeoutToRunner() async throws {
        let runner = FakeCommandRunner(outputJSON: minimalReviewJSON)
        let agent = CodexReviewAgent(commandRunner: runner, workingDirectory: URL(fileURLWithPath: "/tmp/review-desk"))

        _ = try await agent.generateReview(repository: repository, pullRequest: pullRequest, files: reviewableFiles)

        try expectEqual(runner.timeout, 120)
    }

    private static func testGenerateReviewMapsMissingCodexExecutable() async throws {
        let runner = FakeCommandRunner(
            result: CommandResult(
                exitCode: 127,
                standardOutput: "",
                standardError: "env: codex: No such file or directory"
            )
        )
        let agent = CodexReviewAgent(commandRunner: runner, workingDirectory: URL(fileURLWithPath: "/tmp/review-desk"))

        do {
            _ = try await agent.generateReview(repository: repository, pullRequest: pullRequest, files: reviewableFiles)
            throw TestFailure(message: "Expected missing codex executable error")
        } catch let error as CodexReviewError {
            try expectEqual(error, .missingExecutable("codex"))
        }
    }

    private static func testGenerateReviewMapsCommandTimeout() async throws {
        let runner = FakeCommandRunner(error: CommandRunError.timedOut(seconds: 1))
        let agent = CodexReviewAgent(commandRunner: runner, workingDirectory: URL(fileURLWithPath: "/tmp/review-desk"))

        do {
            _ = try await agent.generateReview(repository: repository, pullRequest: pullRequest, files: reviewableFiles)
            throw TestFailure(message: "Expected timeout error")
        } catch let error as CodexReviewError {
            try expectEqual(error, .timedOut(seconds: 1))
        }
    }

    private static func testGenerateReviewMapsCommandCancellation() async throws {
        let runner = FakeCommandRunner(error: CommandRunError.cancelled)
        let agent = CodexReviewAgent(commandRunner: runner, workingDirectory: URL(fileURLWithPath: "/tmp/review-desk"))

        do {
            _ = try await agent.generateReview(repository: repository, pullRequest: pullRequest, files: reviewableFiles)
            throw TestFailure(message: "Expected cancellation error")
        } catch let error as CodexReviewError {
            try expectEqual(error, .cancelled)
        }
    }

    private static func testMakePromptOmitsFilesWithoutReviewablePatches() throws {
        let agent = CodexReviewAgent(commandRunner: FakeCommandRunner(outputJSON: minimalReviewJSON))
        let files = reviewableFiles + [
            PullRequestFile(
                path: "Assets/logo.png",
                status: "modified",
                additions: 12,
                deletions: 0,
                patch: nil
            )
        ]

        let prompt = try agent.makePrompt(repository: repository, pullRequest: pullRequest, files: files)

        try expectTrue(prompt.contains("Sources/App.swift"))
        try expectTrue(!prompt.contains("Assets/logo.png"))
    }

    private static func testReviewDraftDecodesCodexOutputWithoutLocalFields() throws {
        let json = """
        {
          "summary": "Summary",
          "risks": [],
          "inline_comments": [
            {
              "path": "Sources/App.swift",
              "position": 4,
              "body": "Comment",
              "severity": "medium"
            }
          ]
        }
        """.data(using: .utf8)!

        let draft = try JSONDecoder().decode(ReviewDraft.self, from: json)

        try expectEqual(draft.inlineComments.count, 1)
        try expectEqual(draft.inlineComments[0].path, "Sources/App.swift")
        try expectEqual(draft.inlineComments[0].position, 4)
        try expectTrue(draft.inlineComments[0].isSelected)
        try expectTrue(!draft.inlineComments[0].id.isEmpty)
    }

    private static func testProcessCommandRunnerReturnsWhenChildKeepsStdoutOpen() async throws {
        let runner = ProcessCommandRunner()
        let start = Date()

        let result = try await runner.run(
            executable: "sh",
            arguments: ["-c", "sleep 3 & printf done"],
            standardInput: "",
            workingDirectory: nil,
            timeout: 5
        )

        let elapsed = Date().timeIntervalSince(start)
        try expectEqual(result.exitCode, 0)
        try expectEqual(result.standardOutput, "done")
        try expectTrue(elapsed < 1.5)
    }

    private static func testProcessCommandRunnerCleansTemporaryDirectoryAfterFailedCommand() async throws {
        let tempRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let runner = ProcessCommandRunner(temporaryDirectory: tempRoot)

        let result = try await runner.run(
            executable: "sh",
            arguments: ["-c", "printf failure >&2; exit 3"],
            standardInput: "",
            workingDirectory: nil,
            timeout: 5
        )

        try expectEqual(result.exitCode, 3)
        try expectEqual(result.standardError, "failure")
        try expectEqual(try FileManager.default.contentsOfDirectory(atPath: tempRoot.path), [])
    }

    private static func testProcessCommandRunnerTimesOutAndCleansTemporaryDirectory() async throws {
        let tempRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let runner = ProcessCommandRunner(temporaryDirectory: tempRoot)
        let start = Date()

        do {
            _ = try await runner.run(
                executable: "sleep",
                arguments: ["5"],
                standardInput: "",
                workingDirectory: nil,
                timeout: 0.2
            )
            throw TestFailure(message: "Expected timeout")
        } catch let error as CommandRunError {
            try expectEqual(error, .timedOut(seconds: 0.2))
        }

        try expectTrue(Date().timeIntervalSince(start) < 2)
        try expectEqual(try FileManager.default.contentsOfDirectory(atPath: tempRoot.path), [])
    }

    private static func testProcessCommandRunnerCancelsAndCleansTemporaryDirectory() async throws {
        let tempRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let runner = ProcessCommandRunner(temporaryDirectory: tempRoot)
        let task = Task {
            try await runner.run(
                executable: "sleep",
                arguments: ["5"],
                standardInput: "",
                workingDirectory: nil,
                timeout: 5
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure(message: "Expected cancellation")
        } catch let error as CommandRunError {
            try expectEqual(error, .cancelled)
        }

        try expectEqual(try FileManager.default.contentsOfDirectory(atPath: tempRoot.path), [])
    }
}

private final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    private let outputJSON: String?
    private let result: CommandResult
    private let error: Error?
    private(set) var executable = ""
    private(set) var arguments: [String] = []
    private(set) var standardInput = ""
    private(set) var timeout: TimeInterval?

    init(outputJSON: String) {
        self.outputJSON = outputJSON
        result = CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        error = nil
    }

    init(result: CommandResult) {
        outputJSON = nil
        self.result = result
        error = nil
    }

    init(error: Error) {
        outputJSON = nil
        result = CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        self.error = error
    }

    func run(
        executable: String,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL?,
        timeout: TimeInterval?
    ) async throws -> CommandResult {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput
        self.timeout = timeout

        if let error {
            throw error
        }

        if let outputJSON, let outputFlagIndex = arguments.firstIndex(of: "--output-last-message") {
            let outputPath = arguments[arguments.index(after: outputFlagIndex)]
            try outputJSON.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        }

        return result
    }
}

private let minimalReviewJSON = """
{
  "summary": "Review summary",
  "risks": [],
  "inline_comments": []
}
"""

private let repository = Repository(id: 1, owner: "developjik", name: "desk", fullName: "developjik/desk", isPrivate: false)

private let pullRequest = PullRequest(
    id: 2,
    number: 5,
    title: "Improve review flow",
    htmlURL: URL(string: "https://github.com/developjik/desk/pull/5")!,
    author: "contributor",
    headSha: "abc123"
)

private let reviewableFiles = [
    PullRequestFile(
        path: "Sources/App.swift",
        status: "modified",
        additions: 1,
        deletions: 0,
        patch: """
        @@ -1,1 +1,2 @@
         let old = true
        +let new = true
        """
    )
]

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PRReviewDeskCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
