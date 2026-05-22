import Foundation

public struct InvalidInlineComment: Equatable, Hashable, Sendable {
    public let path: String
    public let position: Int

    public init(path: String, position: Int) {
        self.path = path
        self.position = position
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
        guard reviewedHeadSha == currentHeadSha else {
            throw ReviewSubmissionValidationError.staleHead(reviewed: reviewedHeadSha, current: currentHeadSha)
        }

        let validPositionsByPath = try files.reduce(into: [String: Set<Int>]()) { result, file in
            guard let patch = file.patch, !patch.isEmpty else {
                return
            }
            result[file.path] = try diffPositions(in: patch)
        }

        let invalidComments = draft.inlineComments
            .filter(\.isSelected)
            .filter { comment in
                !(validPositionsByPath[comment.path]?.contains(comment.position) ?? false)
            }
            .map { comment in
                InvalidInlineComment(path: comment.path, position: comment.position)
            }

        if !invalidComments.isEmpty {
            throw ReviewSubmissionValidationError.invalidInlineComments(invalidComments)
        }
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
