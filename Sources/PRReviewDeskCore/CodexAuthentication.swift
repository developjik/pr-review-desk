import Foundation

public enum CodexLoginMethod: Equatable, Hashable, Sendable {
    case chatGPT
    case apiKey
    case accessToken
    case unknown
}

public enum CodexAuthenticationState: Equatable, Hashable, Sendable {
    case unknown(message: String)
    case missingCLI(message: String)
    case notLoggedIn(executablePath: String, message: String)
    case unsupportedLogin(executablePath: String, method: CodexLoginMethod, message: String)
    case ready(executablePath: String, method: CodexLoginMethod, message: String)

    public var isReadyForChatGPTSubscription: Bool {
        if case let .ready(_, method, _) = self {
            return method == .chatGPT
        }

        return false
    }

    public var message: String {
        switch self {
        case let .unknown(message),
             let .missingCLI(message),
             let .notLoggedIn(_, message),
             let .unsupportedLogin(_, _, message),
             let .ready(_, _, message):
            return message
        }
    }

    public var executablePath: String? {
        switch self {
        case .unknown,
             .missingCLI:
            return nil
        case let .notLoggedIn(executablePath, _),
             let .unsupportedLogin(executablePath, _, _),
             let .ready(executablePath, _, _):
            return executablePath
        }
    }
}

public protocol CodexAuthenticationChecking: Sendable {
    func status() async throws -> CodexAuthenticationState
}

public struct CodexCLIAuthenticationChecker: CodexAuthenticationChecking, Sendable {
    private let commandRunner: any CommandRunning
    private let fallbackExecutablePaths: [String]
    private let isExecutableFile: @Sendable (String) -> Bool

    public init(
        commandRunner: any CommandRunning = ProcessCommandRunner(),
        fallbackExecutablePaths: [String] = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ],
        isExecutableFile: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.commandRunner = commandRunner
        self.fallbackExecutablePaths = fallbackExecutablePaths
        self.isExecutableFile = isExecutableFile
    }

    public func status() async throws -> CodexAuthenticationState {
        guard let executablePath = try await codexExecutablePath() else {
            return .missingCLI(message: "Codex is not installed or this app cannot find it. Install the Codex command-line helper with Homebrew or npm, then check again.")
        }

        let loginResult = try await commandRunner.run(
            executable: executablePath,
            arguments: ["login", "status"],
            standardInput: "",
            workingDirectory: nil,
            timeout: 5
        )

        guard loginResult.exitCode == 0 else {
            return .notLoggedIn(
                executablePath: executablePath,
                message: notLoggedInMessage(from: loginResult)
            )
        }

        return readyOrUnsupportedState(
            executablePath: executablePath,
            output: loginStatusOutput(from: loginResult)
        )
    }

    private func codexExecutablePath() async throws -> String? {
        let whichResult = try await commandRunner.run(
            executable: "which",
            arguments: ["codex"],
            standardInput: "",
            workingDirectory: nil,
            timeout: 2
        )

        if whichResult.exitCode == 0 {
            return sanitizedOneLine(whichResult.standardOutput)
        }

        for path in fallbackExecutablePaths where isExecutableFile(path) {
            return path
        }

        return nil
    }

    private func readyOrUnsupportedState(executablePath: String, output: String) -> CodexAuthenticationState {
        let message = sanitizedStatusLine(from: output)
        let normalized = SensitiveTextRedactor.redact(output).lowercased()

        if normalized.contains("logged in using chatgpt")
            || normalized.contains("logged in with chatgpt") {
            return .ready(executablePath: executablePath, method: .chatGPT, message: message)
        }

        if normalized.contains("api key") || normalized.contains("api-key") || normalized.contains("apikey") {
            return .unsupportedLogin(
                executablePath: executablePath,
                method: .apiKey,
                message: "OpenAI API-key login is not supported. Sign in to Codex with ChatGPT."
            )
        }

        if normalized.contains("access token") || normalized.contains("access-token") {
            return .unsupportedLogin(
                executablePath: executablePath,
                method: .accessToken,
                message: "Codex access-token login is not supported. Sign in to Codex with ChatGPT."
            )
        }

        return .unsupportedLogin(
            executablePath: executablePath,
            method: .unknown,
            message: "Codex login method could not be verified. Sign in to Codex with ChatGPT."
        )
    }

    private func loginStatusOutput(from result: CommandResult) -> String {
        [result.standardOutput, result.standardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func sanitizedStatusLine(from text: String) -> String {
        let lines = SensitiveTextRedactor.redact(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        return lines.first { $0.localizedCaseInsensitiveContains("chatgpt") }
            ?? lines.first
            ?? ""
    }

    private func notLoggedInMessage(from result: CommandResult) -> String {
        let detail = sanitizedOneLine(result.standardError.isEmpty ? result.standardOutput : result.standardError)
        guard !detail.isEmpty,
              !detail.localizedCaseInsensitiveContains("not logged in") else {
            return "Not logged in. Run `codex login`."
        }

        return "Not logged in. \(detail)"
    }

    private func sanitizedOneLine(_ text: String) -> String {
        SensitiveTextRedactor.redact(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
    }
}
