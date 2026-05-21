import Foundation

public struct Repository: Codable, Equatable, Identifiable, Hashable {
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

public struct PullRequest: Codable, Equatable, Identifiable, Hashable {
    public let id: Int
    public let number: Int
    public let title: String
    public let htmlURL: URL
    public let author: String
    public let headSha: String

    public init(id: Int, number: Int, title: String, htmlURL: URL, author: String, headSha: String) {
        self.id = id
        self.number = number
        self.title = title
        self.htmlURL = htmlURL
        self.author = author
        self.headSha = headSha
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
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
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        author = try userContainer.decode(String.self, forKey: .login)
        headSha = try headContainer.decode(String.self, forKey: .sha)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(title, forKey: .title)
        try container.encode(htmlURL, forKey: .htmlURL)
        var userContainer = container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
        try userContainer.encode(author, forKey: .login)
        var headContainer = container.nestedContainer(keyedBy: HeadKeys.self, forKey: .head)
        try headContainer.encode(headSha, forKey: .sha)
    }
}

public struct PullRequestFile: Codable, Equatable, Identifiable, Hashable {
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
}

public enum ReviewEvent: String, Codable, CaseIterable, Equatable, Hashable, Identifiable {
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

public enum CommentSeverity: String, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case low
    case medium
    case high

    public var id: String { rawValue }
}

public struct InlineCommentDraft: Codable, Equatable, Identifiable, Hashable {
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
}

public struct ReviewDraft: Codable, Equatable, Hashable {
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

public struct ReviewSubmission: Equatable, Hashable {
    public var event: ReviewEvent
    public var body: String
    public var comments: [InlineCommentDraft]

    public init(event: ReviewEvent, body: String, comments: [InlineCommentDraft]) {
        self.event = event
        self.body = body
        self.comments = comments
    }
}
