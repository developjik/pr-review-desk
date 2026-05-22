import Foundation

public enum DiffPositionError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidHunkHeader(String)

    public var description: String {
        switch self {
        case let .invalidHunkHeader(header):
            return "Invalid diff hunk header: \(header)"
        }
    }
}

public struct AnnotatedDiffLine: Identifiable, Equatable, Hashable, Sendable {
    public var id: Int { index }

    public let index: Int
    public let position: Int?
    public let text: String

    public init(index: Int, position: Int?, text: String) {
        self.index = index
        self.position = position
        self.text = text
    }
}

public struct AnnotatedDiff: Equatable, Hashable, Sendable {
    public let path: String
    public let annotatedPatch: String
    public let positionsByNewLine: [Int: Int]
    public let lines: [AnnotatedDiffLine]

    public init(
        path: String,
        annotatedPatch: String,
        positionsByNewLine: [Int: Int],
        lines: [AnnotatedDiffLine]? = nil
    ) {
        self.path = path
        self.annotatedPatch = annotatedPatch
        self.positionsByNewLine = positionsByNewLine
        self.lines = lines ?? annotatedPatch
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                AnnotatedDiffLine(index: index, position: nil, text: String(line))
            }
    }

    public func position(forNewLine line: Int) -> Int? {
        positionsByNewLine[line]
    }
}

public enum DiffPositionMapper {
    public static func annotate(path: String, patch: String) throws -> AnnotatedDiff {
        var currentNewLine: Int?
        var position = 0
        var positionsByNewLine: [Int: Int] = [:]
        var annotatedLines: [String] = []
        var diffLines: [AnnotatedDiffLine] = []

        func appendLine(_ text: String, position: Int? = nil) {
            annotatedLines.append(text)
            diffLines.append(
                AnnotatedDiffLine(index: diffLines.count, position: position, text: text)
            )
        }

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                currentNewLine = try parseNewStart(from: line)
                appendLine(line)
                continue
            }

            guard let newLine = currentNewLine else {
                appendLine(line)
                continue
            }

            if line.hasPrefix("\\") {
                appendLine(line)
                continue
            }

            position += 1
            appendLine("[pos \(position)] \(line)", position: position)

            if line.hasPrefix("-") {
                continue
            }

            positionsByNewLine[newLine] = position
            currentNewLine = newLine + 1
        }

        return AnnotatedDiff(
            path: path,
            annotatedPatch: annotatedLines.joined(separator: "\n"),
            positionsByNewLine: positionsByNewLine,
            lines: diffLines
        )
    }

    private static func parseNewStart(from hunkHeader: String) throws -> Int {
        guard let plusRange = hunkHeader.range(of: "+") else {
            throw DiffPositionError.invalidHunkHeader(hunkHeader)
        }

        let afterPlus = hunkHeader[plusRange.upperBound...]
        let digits = afterPlus.prefix { character in
            character >= "0" && character <= "9"
        }

        guard let value = Int(digits) else {
            throw DiffPositionError.invalidHunkHeader(hunkHeader)
        }

        return value
    }
}
