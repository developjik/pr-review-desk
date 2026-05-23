import Foundation

public struct InvalidInlineComment: Equatable, Hashable, Sendable {
    public let path: String
    public let position: Int

    public init(path: String, position: Int) {
        self.path = path
        self.position = position
    }
}

public struct ReviewSubmissionSafetyState: Equatable, Hashable, Sendable {
    public let reviewedHeadSha: String?
    public let currentHeadSha: String?
    public let selectedInlineCommentCount: Int
    public let invalidSelectedInlineComments: [InvalidInlineComment]
    public let couldValidateDiffPositions: Bool

    public init(
        reviewedHeadSha: String?,
        currentHeadSha: String?,
        selectedInlineCommentCount: Int,
        invalidSelectedInlineComments: [InvalidInlineComment],
        couldValidateDiffPositions: Bool = true
    ) {
        self.reviewedHeadSha = reviewedHeadSha
        self.currentHeadSha = currentHeadSha
        self.selectedInlineCommentCount = selectedInlineCommentCount
        self.invalidSelectedInlineComments = invalidSelectedInlineComments
        self.couldValidateDiffPositions = couldValidateDiffPositions
    }

    public var isStale: Bool {
        guard let reviewedHeadSha, let currentHeadSha else {
            return false
        }

        return reviewedHeadSha != currentHeadSha
    }

    public var canSubmit: Bool {
        reviewedHeadSha != nil
            && currentHeadSha != nil
            && !isStale
            && couldValidateDiffPositions
            && invalidSelectedInlineComments.isEmpty
    }
}

public enum ReviewSubmissionValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    case staleHead(reviewed: String, current: String)
    case invalidInlineComments([InvalidInlineComment])

    public var description: String {
        switch self {
        case let .staleHead(reviewed, current):
            return "Pull request changed after review generation. Reviewed \(reviewed), current \(current)."
        case let .invalidInlineComments(comments):
            let locations = comments.map { "\($0.path):pos \($0.position)" }.joined(separator: ", ")
            return "Review contains inline comments outside the current diff: \(locations)"
        }
    }
}

public enum ReviewSubmissionValidator {
    public static func validate(
        reviewedHeadSha: String,
        currentHeadSha: String,
        draft: ReviewDraft,
        files: [PullRequestFile]
    ) throws {
        let state = try safetyState(
            reviewedHeadSha: reviewedHeadSha,
            currentHeadSha: currentHeadSha,
            draft: draft,
            files: files
        )

        guard !state.isStale else {
            throw ReviewSubmissionValidationError.staleHead(reviewed: reviewedHeadSha, current: currentHeadSha)
        }

        if !state.invalidSelectedInlineComments.isEmpty {
            throw ReviewSubmissionValidationError.invalidInlineComments(state.invalidSelectedInlineComments)
        }
    }

    public static func safetyState(
        reviewedHeadSha: String?,
        currentHeadSha: String?,
        draft: ReviewDraft?,
        files: [PullRequestFile]
    ) throws -> ReviewSubmissionSafetyState {
        let validPositionsByPath = try files.reduce(into: [String: Set<Int>]()) { result, file in
            guard let patch = file.patch, !patch.isEmpty else {
                return
            }
            result[file.path] = try diffPositions(in: patch)
        }

        let selectedComments = draft?.inlineComments.filter(\.isSelected) ?? []
        let invalidComments = selectedComments
            .filter { comment in
                !(validPositionsByPath[comment.path]?.contains(comment.position) ?? false)
            }
            .map { comment in
                InvalidInlineComment(path: comment.path, position: comment.position)
            }

        return ReviewSubmissionSafetyState(
            reviewedHeadSha: reviewedHeadSha,
            currentHeadSha: currentHeadSha,
            selectedInlineCommentCount: selectedComments.count,
            invalidSelectedInlineComments: invalidComments
        )
    }

    private static func diffPositions(in patch: String) throws -> Set<Int> {
        var hasSeenHunk = false
        var position = 0
        var positions = Set<Int>()

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                _ = try DiffPositionMapper.annotate(path: "", patch: line)
                hasSeenHunk = true
                continue
            }

            guard hasSeenHunk, !line.hasPrefix("\\") else {
                continue
            }

            position += 1
            positions.insert(position)
        }

        return positions
    }
}
