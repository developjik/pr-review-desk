import Foundation
import PRReviewDeskCore

enum CodexReviewAgentTests {
    static func run() async throws {
        try await testGenerateReviewRunsCodexExecWithSchemaAndAnnotatedPatch()
        try testReviewDraftDecodesCodexOutputWithoutLocalFields()
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
        try expectTrue(runner.arguments.contains("--sandbox"))
        try expectTrue(runner.arguments.contains("read-only"))
        try expectTrue(runner.arguments.contains("--output-schema"))
        try expectTrue(runner.arguments.contains("--output-last-message"))
        try expectTrue(runner.standardInput.contains("Improve review flow"))
        try expectTrue(runner.standardInput.contains("[pos 2] +let new = true"))
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
}

private final class FakeCommandRunner: CommandRunning {
    private let outputJSON: String
    private(set) var executable = ""
    private(set) var arguments: [String] = []
    private(set) var standardInput = ""

    init(outputJSON: String) {
        self.outputJSON = outputJSON
    }

    func run(
        executable: String,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL?
    ) async throws -> CommandResult {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput

        if let outputFlagIndex = arguments.firstIndex(of: "--output-last-message") {
            let outputPath = arguments[arguments.index(after: outputFlagIndex)]
            try outputJSON.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        }

        return CommandResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}
