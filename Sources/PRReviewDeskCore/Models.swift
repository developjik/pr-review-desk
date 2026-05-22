import Foundation

public struct Repository: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let owner: String
    public let name: String
    public let fullName: String
    public let isPrivate: Bool

    public init(id: Int, owner: String, name: String, fullName: String, isPrivate: Bool) {
        self.id = id
        self.owner = owner
        self.name = name
        self.fullName = fullName
        self.isPrivate = isPrivate
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case owner
    }

    private enum OwnerKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ownerContainer = try container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner)

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fullName = try container.decode(String.self, forKey: .fullName)
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
        owner = try ownerContainer.decode(String.self, forKey: .login)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(isPrivate, forKey: .isPrivate)
        var ownerContainer = container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner)
        try ownerContainer.encode(owner, forKey: .login)
    }
}

public struct PullRequest: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let htmlURL: URL
    public let author: String
    public let headSha: String

    public init(id: Int, number: Int, title: String, body: String? = nil, htmlURL: URL, author: String, headSha: String) {
        self.id = id
        self.number = number
        self.title = title
        self.body = body
        self.htmlURL = htmlURL
        self.author = author
        self.headSha = headSha
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case body
        case htmlURL = "html_url"
        case user
        case head
    }

    private enum UserKeys: String, CodingKey {
        case login
    }

    private enum HeadKeys: String, CodingKey {
        case sha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userContainer = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        let headContainer = try container.nestedContainer(keyedBy: HeadKeys.self, forKey: .head)

        id = try container.decode(Int.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        author = try userContainer.decode(String.self, forKey: .login)
        headSha = try headContainer.decode(String.self, forKey: .sha)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(htmlURL, forKey: .htmlURL)
        var userContainer = container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        try userContainer.encode(author, forKey: .login)
        var headContainer = container.nestedContainer(keyedBy: HeadKeys.self, forKey: .head)
        try headContainer.encode(headSha, forKey: .sha)
    }
}

public struct PullRequestConversationComment: Codable, Equatable, Hashable, Sendable {
    public let author: String
    public let body: String
    public let createdAt: String?

    public init(author: String, body: String, createdAt: String?) {
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case user
        case body
        case createdAt = "created_at"
    }

    private enum UserKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userContainer = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)

        author = try userContainer.decode(String.self, forKey: .login)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var userContainer = container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        try userContainer.encode(author, forKey: .login)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

public struct PullRequestReviewCommentContext: Codable, Equatable, Hashable, Sendable {
    public let author: String
    public let path: String
    public let position: Int?
    public let body: String
    public let createdAt: String?

    public init(author: String, path: String, position: Int?, body: String, createdAt: String?) {
        self.author = author
        self.path = path
        self.position = position
        self.body = body
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case user
        case path
        case position
        case body
        case createdAt = "created_at"
    }

    private enum UserKeys: String, CodingKey {
        case login
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userContainer = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)

        author = try userContainer.decode(String.self, forKey: .login)
        path = try container.decode(String.self, forKey: .path)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var userContainer = container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        try userContainer.encode(author, forKey: .login)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

public struct PullRequestCheckRunContext: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let detailsURL: URL?

    public init(name: String, status: String, conclusion: String?, detailsURL: URL?) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.detailsURL = detailsURL
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case status
        case conclusion
        case detailsURL = "details_url"
    }
}

public struct PullRequestReviewContext: Equatable, Hashable, Sendable {
    public static let empty = PullRequestReviewContext(
        body: nil,
        issueComments: [],
        reviewComments: [],
        checkRuns: []
    )

    public let body: String?
    public let issueComments: [PullRequestConversationComment]
    public let reviewComments: [PullRequestReviewCommentContext]
    public let checkRuns: [PullRequestCheckRunContext]

    public init(
        body: String?,
        issueComments: [PullRequestConversationComment],
        reviewComments: [PullRequestReviewCommentContext],
        checkRuns: [PullRequestCheckRunContext]
    ) {
        self.body = body
        self.issueComments = issueComments
        self.reviewComments = reviewComments
        self.checkRuns = checkRuns
    }

    public var isEmpty: Bool {
        body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            && issueComments.isEmpty
            && reviewComments.isEmpty
            && checkRuns.isEmpty
    }
}

public struct PullRequestFile: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let status: String
    public let additions: Int
    public let deletions: Int
    public let patch: String?

    public init(path: String, status: String, additions: Int, deletions: Int, patch: String?) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }

    private enum CodingKeys: String, CodingKey {
        case path = "filename"
        case status
        case additions
        case deletions
        case patch
    }

    public var reviewability: PullRequestFileReviewability {
        guard let patch, !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if additions == 0 && deletions == 0 {
                return .omitted(reason: .metadataOnly)
            }
            return .omitted(reason: .patchUnavailable)
        }

        return .includedPatch
    }
}

public enum PullRequestFileReviewability: Equatable, Hashable, Sendable {
    case includedPatch
    case omitted(reason: PullRequestFileOmissionReason)
}

public enum PullRequestFileOmissionReason: String, Codable, Equatable, Hashable, Sendable {
    case patchUnavailable
    case metadataOnly

    public var displayName: String {
        switch self {
        case .patchUnavailable:
            return "Patch unavailable from GitHub"
        case .metadataOnly:
            return "Metadata-only change"
        }
    }
}

public struct ReviewCoverageSummary: Equatable, Sendable {
    public let files: [PullRequestFile]

    public init(files: [PullRequestFile]) {
        self.files = files
    }

    public var totalFileCount: Int {
        files.count
    }

    public var reviewableFiles: [PullRequestFile] {
        files.filter { $0.reviewability == .includedPatch }
    }

    public var omittedFiles: [PullRequestFile] {
        files.filter { file in
            if case .omitted = file.reviewability {
                return true
            }
            return false
        }
    }

    public var reviewableFileCount: Int {
        reviewableFiles.count
    }

    public var omittedFileCount: Int {
        omittedFiles.count
    }

    public var omittedAdditions: Int {
        omittedFiles.reduce(0) { $0 + $1.additions }
    }

    public var omittedDeletions: Int {
        omittedFiles.reduce(0) { $0 + $1.deletions }
    }

    public var warningMessage: String? {
        guard omittedFileCount > 0 else {
            return nil
        }

        return "\(omittedFileCount) of \(totalFileCount) changed files do not have reviewable patches and will not be sent to Codex."
    }

    public var generationBlockReason: String? {
        guard reviewableFileCount == 0 else {
            return nil
        }

        return "No changed files have reviewable patches for Codex."
    }

    public var statusMessage: String {
        if let generationBlockReason {
            return generationBlockReason
        }

        if let warningMessage {
            return warningMessage
        }

        return "All \(totalFileCount) changed files have reviewable patches for Codex."
    }
}

public enum SensitiveTextRedactor {
    public static func redact(_ text: String) -> String {
        var redacted = replaceMatches(
            in: text,
            pattern: #"(?i)Authorization\s*:\s*(Bearer|Token|Basic)\s+[A-Za-z0-9._\-+/=]+"#,
            replacement: "Authorization: [REDACTED]"
        )

        let tokenPatterns = [
            #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b"#,
            #"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#,
            #"\bsk-proj-[A-Za-z0-9_\-]{20,}\b"#,
            #"\bsk-[A-Za-z0-9_\-]{20,}\b"#
        ]

        for pattern in tokenPatterns {
            redacted = replaceMatches(
                in: redacted,
                pattern: pattern,
                replacement: "[REDACTED_TOKEN]"
            )
        }

        return redacted
    }

    private static func replaceMatches(in text: String, pattern: String, replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
    }
}

public enum ReviewEvent: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .comment:
            return "Comment"
        case .approve:
            return "Approve"
        case .requestChanges:
            return "Request changes"
        }
    }
}

public enum CommentSeverity: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }
}

public struct InlineCommentDraft: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var path: String
    public var position: Int
    public var body: String
    public var severity: CommentSeverity
    public var isSelected: Bool

    public init(
        id: String = UUID().uuidString,
        path: String,
        position: Int,
        body: String,
        severity: CommentSeverity,
        isSelected: Bool = true
    ) {
        self.id = id
        self.path = path
        self.position = position
        self.body = body
        self.severity = severity
        self.isSelected = isSelected
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case position
        case body
        case severity
        case isSelected = "is_selected"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        path = try container.decode(String.self, forKey: .path)
        position = try container.decode(Int.self, forKey: .position)
        body = try container.decode(String.self, forKey: .body)
        severity = try container.decode(CommentSeverity.self, forKey: .severity)
        isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(position, forKey: .position)
        try container.encode(body, forKey: .body)
        try container.encode(severity, forKey: .severity)
        try container.encode(isSelected, forKey: .isSelected)
    }
}

public struct ReviewDraft: Codable, Equatable, Hashable, Sendable {
    public var summary: String
    public var risks: [String]
    public var inlineComments: [InlineCommentDraft]

    public init(summary: String, risks: [String], inlineComments: [InlineCommentDraft]) {
        self.summary = summary
        self.risks = risks
        self.inlineComments = inlineComments
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case risks
        case inlineComments = "inline_comments"
    }
}

public struct ReviewSubmission: Equatable, Hashable, Sendable {
    public var event: ReviewEvent
    public var body: String
    public var commitID: String
    public var comments: [InlineCommentDraft]

    public init(event: ReviewEvent, body: String, commitID: String, comments: [InlineCommentDraft]) {
        self.event = event
        self.body = body
        self.commitID = commitID
        self.comments = comments
    }
}
