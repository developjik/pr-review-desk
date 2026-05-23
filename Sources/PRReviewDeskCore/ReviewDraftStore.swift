import Foundation

public struct ReviewDraftKey: Codable, Equatable, Hashable, Sendable {
    public let repositoryFullName: String
    public let pullRequestNumber: Int
    public let headSha: String

    public init(repositoryFullName: String, pullRequestNumber: Int, headSha: String) {
        self.repositoryFullName = repositoryFullName
        self.pullRequestNumber = pullRequestNumber
        self.headSha = headSha
    }
}

public struct StoredReviewDraft: Codable, Equatable, Hashable, Sendable {
    public let key: ReviewDraftKey
    public var draft: ReviewDraft
    public var reviewBody: String
    public var selectedEvent: ReviewEvent
    public var savedAt: Date
    public var repositoryIsPrivate: Bool?

    public init(
        key: ReviewDraftKey,
        draft: ReviewDraft,
        reviewBody: String,
        selectedEvent: ReviewEvent,
        savedAt: Date,
        repositoryIsPrivate: Bool? = nil
    ) {
        self.key = key
        self.draft = draft
        self.reviewBody = reviewBody
        self.selectedEvent = selectedEvent
        self.savedAt = savedAt
        self.repositoryIsPrivate = repositoryIsPrivate
    }
}

public protocol ReviewDraftStore: Sendable {
    func loadDraft(key: ReviewDraftKey) throws -> StoredReviewDraft?
    func loadLatestDraft(repositoryFullName: String, pullRequestNumber: Int) throws -> StoredReviewDraft?
    func loadAllDrafts() throws -> [StoredReviewDraft]
    func saveDraft(_ draft: StoredReviewDraft) throws
    func deleteDraft(key: ReviewDraftKey) throws
}

public final class InMemoryReviewDraftStore: ReviewDraftStore, @unchecked Sendable {
    private var drafts: [ReviewDraftKey: StoredReviewDraft] = [:]

    public init() {}

    public func loadDraft(key: ReviewDraftKey) throws -> StoredReviewDraft? {
        drafts[key]
    }

    public func loadLatestDraft(
        repositoryFullName: String,
        pullRequestNumber: Int
    ) throws -> StoredReviewDraft? {
        drafts.values
            .filter {
                $0.key.repositoryFullName == repositoryFullName
                    && $0.key.pullRequestNumber == pullRequestNumber
            }
            .sorted { $0.savedAt > $1.savedAt }
            .first
    }

    public func loadAllDrafts() throws -> [StoredReviewDraft] {
        drafts.values.sorted { $0.savedAt > $1.savedAt }
    }

    public func saveDraft(_ draft: StoredReviewDraft) throws {
        drafts[draft.key] = draft
    }

    public func deleteDraft(key: ReviewDraftKey) throws {
        drafts[key] = nil
    }
}

public struct FileReviewDraftStore: ReviewDraftStore, @unchecked Sendable {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public static func appDefault(fileManager: FileManager = .default) -> FileReviewDraftStore {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.homeDirectoryForCurrentUser
        return FileReviewDraftStore(
            directoryURL: baseURL
                .appendingPathComponent("PRReviewDesk", isDirectory: true)
                .appendingPathComponent("ReviewDrafts", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func loadDraft(key: ReviewDraftKey) throws -> StoredReviewDraft? {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(StoredReviewDraft.self, from: data)
    }

    public func loadLatestDraft(
        repositoryFullName: String,
        pullRequestNumber: Int
    ) throws -> StoredReviewDraft? {
        try loadAllDrafts()
        .filter {
            $0.key.repositoryFullName == repositoryFullName
                && $0.key.pullRequestNumber == pullRequestNumber
        }
        .first
    }

    public func loadAllDrafts() throws -> [StoredReviewDraft] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url -> StoredReviewDraft? in
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(StoredReviewDraft.self, from: data)
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    public func saveDraft(_ draft: StoredReviewDraft) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(draft)
        try data.write(to: fileURL(for: draft.key), options: .atomic)
    }

    public func deleteDraft(key: ReviewDraftKey) throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    private func fileURL(for key: ReviewDraftKey) -> URL {
        directoryURL.appendingPathComponent(Self.fileName(for: key), isDirectory: false)
    }

    private static func fileName(for key: ReviewDraftKey) -> String {
        "\(key.repositoryFullName)-\(key.pullRequestNumber)-\(key.headSha)"
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
            .map(String.init)
            .joined() + ".json"
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
