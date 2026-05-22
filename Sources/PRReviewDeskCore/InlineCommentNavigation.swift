import Foundation

public struct InlineCommentFileCount: Equatable, Hashable, Sendable {
    public let selected: Int
    public let total: Int

    public init(selected: Int, total: Int) {
        self.selected = selected
        self.total = total
    }

    public var displayText: String {
        "\(selected)/\(total)"
    }

    public static func count(
        for path: String,
        comments: [InlineCommentDraft]
    ) -> InlineCommentFileCount {
        let fileComments = comments.filter { $0.path == path }
        return InlineCommentFileCount(
            selected: fileComments.filter(\.isSelected).count,
            total: fileComments.count
        )
    }
}
