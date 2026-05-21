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

public struct AnnotatedDiff: Equatable, Hashable, Sendable {
    public let path: String
    public let annotatedPatch: String
    public let positionsByNewLine: [Int: Int]

    public init(path: String, annotatedPatch: String, positionsByNewLine: [Int: Int]) {
        self.path = path
        self.annotatedPatch = annotatedPatch
        self.positionsByNewLine = positionsByNewLine
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

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                currentNewLine = try parseNewStart(from: line)
                annotatedLines.append(line)
                continue
            }

            guard let newLine = currentNewLine else {
                annotatedLines.append(line)
                continue
            }

            if line.hasPrefix("\\") {
                annotatedLines.append(line)
                continue
            }

            position += 1
            annotatedLines.append("[pos \(position)] \(line)")

            if line.hasPrefix("-") {
                continue
            }

            positionsByNewLine[newLine] = position
            currentNewLine = newLine + 1
        }

        return AnnotatedDiff(
            path: path,
            annotatedPatch: annotatedLines.joined(separator: "\n"),
            positionsByNewLine: positionsByNewLine
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
