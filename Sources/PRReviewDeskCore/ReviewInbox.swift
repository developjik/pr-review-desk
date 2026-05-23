import Foundation

public enum ReviewInboxSection: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case draftReady
    case stale
    case running
    case needsSetup
    case submitted
    case recents

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .draftReady:
            return "Draft Ready"
        case .stale:
            return "Stale"
        case .running:
            return "Running"
        case .needsSetup:
            return "Needs Setup"
        case .submitted:
            return "Submitted"
        case .recents:
            return "Recents/Favorites"
        }
    }

    public var systemImage: String {
        switch self {
        case .draftReady:
            return "doc.text"
        case .stale:
            return "exclamationmark.triangle"
        case .running:
            return "sparkles"
        case .needsSetup:
            return "wrench.and.screwdriver"
        case .submitted:
            return "paperplane"
        case .recents:
            return "clock"
        }
    }

    public static func classify(queueItem: BackgroundReviewQueueItem) -> ReviewInboxSection {
        switch queueItem.state {
        case .draftReady:
            return .draftReady
        case .stale, .failed:
            return .stale
        case .queued, .generating:
            return .running
        case .submitted:
            return .submitted
        }
    }
}

public enum PullRequestDraftStatus: String, Codable, Equatable, Hashable, Sendable {
    case notGenerated
    case queued
    case generating
    case draftReady
    case stale
    case failed
    case submitted

    public init(queueState: BackgroundReviewQueueItemState?, hasDraft: Bool, reviewedHeadSha: String?, currentHeadSha: String) {
        switch queueState {
        case .queued:
            self = .queued
        case .generating:
            self = .generating
        case .draftReady:
            self = reviewedHeadSha == currentHeadSha ? .draftReady : .stale
        case .stale:
            self = .stale
        case .failed:
            self = .failed
        case .submitted:
            self = .submitted
        case .none:
            if hasDraft {
                self = reviewedHeadSha == nil || reviewedHeadSha == currentHeadSha ? .draftReady : .stale
            } else {
                self = .notGenerated
            }
        }
    }

    public var displayName: String {
        switch self {
        case .notGenerated:
            return "No draft"
        case .queued:
            return "Queued"
        case .generating:
            return "Generating"
        case .draftReady:
            return "Draft ready"
        case .stale:
            return "Stale"
        case .failed:
            return "Failed"
        case .submitted:
            return "Submitted"
        }
    }
}

public struct PullRequestTriageRow: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let repository: Repository
    public let repositoryFullName: String
    public let repositoryIsPrivate: Bool
    public let pullRequest: PullRequest
    public let fileCount: Int
    public let additions: Int
    public let deletions: Int
    public let draftStatus: PullRequestDraftStatus
    public let hasCoverageWarning: Bool
    public let topSeverity: CommentSeverity?

    public var number: Int { pullRequest.number }
    public var title: String { pullRequest.title }
    public var author: String { pullRequest.author }
    public var htmlURL: URL { pullRequest.htmlURL }

    public var section: ReviewInboxSection {
        switch draftStatus {
        case .draftReady:
            return .draftReady
        case .stale, .failed:
            return .stale
        case .queued, .generating:
            return .running
        case .submitted:
            return .submitted
        case .notGenerated:
            return .recents
        }
    }

    public init(
        repository: Repository,
        pullRequest: PullRequest,
        files: [PullRequestFile] = [],
        draft: ReviewDraft? = nil,
        queueState: BackgroundReviewQueueItemState? = nil,
        reviewedHeadSha: String? = nil
    ) {
        self.id = "\(repository.fullName)#\(pullRequest.number)"
        self.repository = repository
        self.repositoryFullName = repository.fullName
        self.repositoryIsPrivate = repository.isPrivate
        self.pullRequest = pullRequest
        self.fileCount = files.count
        self.additions = files.reduce(0) { $0 + $1.additions }
        self.deletions = files.reduce(0) { $0 + $1.deletions }
        self.draftStatus = PullRequestDraftStatus(
            queueState: queueState,
            hasDraft: draft != nil,
            reviewedHeadSha: reviewedHeadSha,
            currentHeadSha: pullRequest.headSha
        )
        self.hasCoverageWarning = ReviewCoverageSummary(files: files).omittedFileCount > 0
        self.topSeverity = draft?.inlineComments.map(\.severity).max { lhs, rhs in
            lhs.reviewPriority < rhs.reviewPriority
        }
    }
}

public struct DiffReviewFileState: Codable, Equatable, Hashable, Sendable {
    private var viewedFilePaths: Set<String>
    private var collapsedFilePaths: Set<String>

    public init(viewedFilePaths: Set<String> = [], collapsedFilePaths: Set<String> = []) {
        self.viewedFilePaths = viewedFilePaths
        self.collapsedFilePaths = collapsedFilePaths
    }

    public func isViewed(_ path: String) -> Bool {
        viewedFilePaths.contains(path)
    }

    public func isCollapsed(_ path: String) -> Bool {
        collapsedFilePaths.contains(path)
    }

    public mutating func markViewed(path: String, isViewed: Bool = true) {
        if isViewed {
            viewedFilePaths.insert(path)
        } else {
            viewedFilePaths.remove(path)
        }
    }

    public mutating func toggleViewed(path: String) {
        markViewed(path: path, isViewed: !isViewed(path))
    }

    public mutating func markCollapsed(path: String, isCollapsed: Bool = true) {
        if isCollapsed {
            collapsedFilePaths.insert(path)
        } else {
            collapsedFilePaths.remove(path)
        }
    }

    public mutating func toggleCollapsed(path: String) {
        markCollapsed(path: path, isCollapsed: !isCollapsed(path))
    }
}

private extension CommentSeverity {
    var reviewPriority: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        }
    }
}
