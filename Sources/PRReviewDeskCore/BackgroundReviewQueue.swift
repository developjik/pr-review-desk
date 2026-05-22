import Foundation

public enum BackgroundReviewQueueItemState: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case queued
    case generating
    case draftReady
    case stale
    case failed
    case submitted

    public var displayName: String {
        switch self {
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

public struct BackgroundReviewQueueItem: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id: String
    public var repository: Repository
    public var pullRequest: PullRequest
    public var state: BackgroundReviewQueueItemState
    public var draft: ReviewDraft?
    public var reviewBody: String?
    public var reviewedHeadSha: String?
    public var message: String?

    public init(
        repository: Repository,
        pullRequest: PullRequest,
        state: BackgroundReviewQueueItemState = .queued,
        draft: ReviewDraft? = nil,
        reviewBody: String? = nil,
        reviewedHeadSha: String? = nil,
        message: String? = nil
    ) {
        self.id = Self.id(repositoryFullName: repository.fullName, pullRequestNumber: pullRequest.number)
        self.repository = repository
        self.pullRequest = pullRequest
        self.state = state
        self.draft = draft
        self.reviewBody = reviewBody
        self.reviewedHeadSha = reviewedHeadSha
        self.message = message
    }

    public static func id(repositoryFullName: String, pullRequestNumber: Int) -> String {
        "\(repositoryFullName)#\(pullRequestNumber)"
    }
}

public struct BackgroundReviewQueue: Codable, Equatable, Hashable, Sendable {
    public private(set) var items: [BackgroundReviewQueueItem]

    public init(items: [BackgroundReviewQueueItem] = []) {
        self.items = items
    }

    public var nextQueuedItem: BackgroundReviewQueueItem? {
        items.first { $0.state == .queued }
    }

    public var hasQueuedItems: Bool {
        nextQueuedItem != nil
    }

    @discardableResult
    public mutating func enqueue(repository: Repository, pullRequest: PullRequest) -> BackgroundReviewQueueItem {
        let item = BackgroundReviewQueueItem(repository: repository, pullRequest: pullRequest)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        return item
    }

    public mutating func markQueued(id: String, message: String? = nil) {
        update(id: id) { item in
            item.state = .queued
            item.message = message
        }
    }

    public mutating func markGenerating(id: String) {
        update(id: id) { item in
            item.state = .generating
            item.message = nil
        }
    }

    public mutating func markDraftReady(
        id: String,
        pullRequest: PullRequest,
        draft: ReviewDraft,
        reviewBody: String,
        reviewedHeadSha: String
    ) {
        update(id: id) { item in
            item.pullRequest = pullRequest
            item.state = .draftReady
            item.draft = draft
            item.reviewBody = reviewBody
            item.reviewedHeadSha = reviewedHeadSha
            item.message = nil
        }
    }

    public mutating func markStale(id: String, currentHeadSha: String) {
        update(id: id) { item in
            item.state = .stale
            item.message = "Current head is \(String(currentHeadSha.prefix(8)))."
        }
    }

    public mutating func markFailed(id: String, message: String) {
        update(id: id) { item in
            item.state = .failed
            item.message = message
        }
    }

    public mutating func markSubmitted(repositoryFullName: String, pullRequestNumber: Int) {
        let id = BackgroundReviewQueueItem.id(
            repositoryFullName: repositoryFullName,
            pullRequestNumber: pullRequestNumber
        )
        update(id: id) { item in
            item.state = .submitted
            item.message = nil
        }
    }

    public mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    private mutating func update(id: String, _ mutation: (inout BackgroundReviewQueueItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutation(&items[index])
    }
}
