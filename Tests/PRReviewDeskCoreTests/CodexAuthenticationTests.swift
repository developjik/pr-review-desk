import Foundation
import PRReviewDeskCore

enum CodexAuthenticationTests {
    static func run() async throws {
        try await testChatGPTLoginIsReady()
        try await testAPIKeyLoginIsUnsupported()
        try await testAccessTokenLoginIsUnsupported()
        try await testUnknownSuccessfulLoginOutputIsUnsupported()
        try await testNonzeroLoginStatusRequiresLogin()
        try await testMissingCodexCLIRequiresInstall()
        try await testFallbackCodexPathWorksWhenAppPathIsMissingCodex()
        try await testLoginFailureDetailsAreRedacted()
    }

    private static func testChatGPTLoginIsReady() async throws {
        let checker = CodexCLIAuthenticationChecker(commandRunner: SequenceCommandRunner(results: [
            .success(CommandResult(exitCode: 0, standardOutput: "/opt/homebrew/bin/codex\n", standardError: "")),
            .success(CommandResult(exitCode: 0, standardOutput: "Logged in using ChatGPT\n", standardError: ""))
        ]))

        let state = try await checker.status()

        try expectEqual(
            state,
            .ready(
                executablePath: "/opt/homebrew/bin/codex",
                method: .chatGPT,
                message: "Logged in using ChatGPT"
            )
        )
        try expectTrue(state.isReadyForChatGPTSubscription)
    }

    private static func testAPIKeyLoginIsUnsupported() async throws {
        let checker = CodexCLIAuthenticationChecker(commandRunner: SequenceCommandRunner(results: [
            .success(CommandResult(exitCode: 0, standardOutput: "/usr/local/bin/codex\n", standardError: "")),
            .success(CommandResult(exitCode: 0, standardOutput: "Logged in using OpenAI API key\n", standardError: ""))
        ]))

        let state = try await checker.status()

        try expectEqual(
            state,
            .unsupportedLogin(
                executablePath: "/usr/local/bin/codex",
                method: .apiKey,
                message: "OpenAI API-key login is not supported. Sign in to Codex with ChatGPT."
            )
        )
        try expectTrue(!state.isReadyForChatGPTSubscription)
    }

    private static func testAccessTokenLoginIsUnsupported() async throws {
        let checker = CodexCLIAuthenticationChecker(commandRunner: SequenceCommandRunner(results: [
            .success(CommandResult(exitCode: 0, standardOutput: "/usr/local/bin/codex\n", standardError: "")),
            .success(CommandResult(exitCode: 0, standardOutput: "Logged in using access token\n", standardError: ""))
        ]))

        let state = try await checker.status()

        try expectEqual(
            state,
            .unsupportedLogin(
                executablePath: "/usr/local/bin/codex",
                method: .accessToken,
                message: "Codex access-token login is not supported. Sign in to Codex with ChatGPT."
            )
        )
        try expectTrue(!state.isReadyForChatGPTSubscription)
    }

    private static func testUnknownSuccessfulLoginOutputIsUnsupported() async throws {
        let checker = CodexCLIAuthenticationChecker(commandRunner: SequenceCommandRunner(results: [
            .success(CommandResult(exitCode: 0, standardOutput: "/opt/homebrew/bin/codex\n", standardError: "")),
            .success(CommandResult(exitCode: 0, standardOutput: "Authenticated\n", standardError: ""))
        ]))

        let state = try await checker.status()

        try expectEqual(
            state,
            .unsupportedLogin(
                executablePath: "/opt/homebrew/bin/codex",
                method: .unknown,
                message: "Codex login method could not be verified. Sign in to Codex with ChatGPT."
            )
        )
        try expectTrue(!state.isReadyForChatGPTSubscription)
    }

    private static func testNonzeroLoginStatusRequiresLogin() async throws {
        let checker = CodexCLIAuthenticationChecker(commandRunner: SequenceCommandRunner(results: [
            .success(CommandResult(exitCode: 0, standardOutput: "/opt/homebrew/bin/codex\n", standardError: "")),
            .success(CommandResult(exitCode: 1, standardOutput: "", standardError: "Not logged in\n"))
        ]))

        let state = try await checker.status()

        try expectEqual(
            state,
            .notLoggedIn(
                executablePath: "/opt/homebrew/bin/codex",
                message: "Not logged in. Run `codex login` and sign in with ChatGPT."
            )
        )
        try expectTrue(!state.isReadyForChatGPTSubscription)
    }

    private static func testMissingCodexCLIRequiresInstall() async throws {
        let checker = CodexCLIAuthenticationChecker(
            commandRunner: SequenceCommandRunner(results: [
                .success(CommandResult(exitCode: 1, standardOutput: "", standardError: "codex not found\n"))
            ]),
            fallbackExecutablePaths: [],
            isExecutableFile: { _ in false }
        )

        let state = try await checker.status()

        try expectEqual(
            state,
            .missingCLI(message: "Codex is not installed or this app cannot find it. Install the Codex command-line helper with Homebrew or npm, then check again.")
        )
        try expectTrue(!state.isReadyForChatGPTSubscription)
    }

    private static func testFallbackCodexPathWorksWhenAppPathIsMissingCodex() async throws {
        let checker = CodexCLIAuthenticationChecker(
            commandRunner: SequenceCommandRunner(results: [
                .success(CommandResult(exitCode: 1, standardOutput: "", standardError: "codex not found\n")),
                .success(CommandResult(exitCode: 0, standardOutput: "Logged in using ChatGPT\n", standardError: ""))
            ]),
            fallbackExecutablePaths: ["/opt/homebrew/bin/codex"],
            isExecutableFile: { $0 == "/opt/homebrew/bin/codex" }
        )

        let state = try await checker.status()

        try expectEqual(
            state,
            .ready(
                executablePath: "/opt/homebrew/bin/codex",
                method: .chatGPT,
                message: "Logged in using ChatGPT"
            )
        )
        try expectTrue(state.isReadyForChatGPTSubscription)
    }

    private static func testLoginFailureDetailsAreRedacted() async throws {
        let checker = CodexCLIAuthenticationChecker(commandRunner: SequenceCommandRunner(results: [
            .success(CommandResult(exitCode: 0, standardOutput: "/opt/homebrew/bin/codex\n", standardError: "")),
            .success(CommandResult(exitCode: 1, standardOutput: "", standardError: "token sk-proj-secret12345678901234567890 expired\n"))
        ]))

        let state = try await checker.status()

        guard case let .notLoggedIn(_, message) = state else {
            throw TestFailure(message: "Expected notLoggedIn, got \(state)")
        }
        try expectTrue(!message.contains("sk-proj-secret12345678901234567890"))
        try expectTrue(message.contains("[REDACTED_TOKEN]"))
    }
}

private final class SequenceCommandRunner: CommandRunning, @unchecked Sendable {
    private var results: [Result<CommandResult, Error>]
    private(set) var calls: [(executable: String, arguments: [String])] = []

    init(results: [Result<CommandResult, Error>]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        standardInput: String,
        workingDirectory: URL?,
        timeout: TimeInterval?
    ) async throws -> CommandResult {
        calls.append((executable: executable, arguments: arguments))
        guard !results.isEmpty else {
            throw TestFailure(message: "Unexpected command: \(executable) \(arguments.joined(separator: " "))")
        }

        switch results.removeFirst() {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }
}
