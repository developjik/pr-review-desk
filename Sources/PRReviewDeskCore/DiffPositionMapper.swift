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

public enum AnnotatedDiffLineKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case hunk
    case addition
    case deletion
    case context
    case metadata
    case omitted
}

public struct AnnotatedDiffLine: Identifiable, Equatable, Hashable, Sendable {
    public var id: Int { index }

    public let index: Int
    public let position: Int?
    public let oldLine: Int?
    public let newLine: Int?
    public let text: String
    public let kind: AnnotatedDiffLineKind

    public init(
        index: Int,
        position: Int?,
        oldLine: Int? = nil,
        newLine: Int? = nil,
        text: String,
        kind: AnnotatedDiffLineKind = .metadata
    ) {
        self.index = index
        self.position = position
        self.oldLine = oldLine
        self.newLine = newLine
        self.text = text
        self.kind = kind
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
                let text = String(line)
                return AnnotatedDiffLine(
                    index: index,
                    position: nil,
                    oldLine: nil,
                    newLine: nil,
                    text: text,
                    kind: text.hasSuffix("was not sent to Codex because GitHub did not provide reviewable patch content.")
                        ? .omitted
                        : .metadata
                )
            }
    }

    public func position(forNewLine line: Int) -> Int? {
        positionsByNewLine[line]
    }
}

public enum DiffPositionMapper {
    public static func annotate(path: String, patch: String) throws -> AnnotatedDiff {
        var currentOldLine: Int?
        var currentNewLine: Int?
        var position = 0
        var positionsByNewLine: [Int: Int] = [:]
        var annotatedLines: [String] = []
        var diffLines: [AnnotatedDiffLine] = []

        func appendLine(
            _ text: String,
            position: Int? = nil,
            oldLine: Int? = nil,
            newLine: Int? = nil,
            kind: AnnotatedDiffLineKind = .metadata
        ) {
            annotatedLines.append(text)
            diffLines.append(
                AnnotatedDiffLine(
                    index: diffLines.count,
                    position: position,
                    oldLine: oldLine,
                    newLine: newLine,
                    text: text,
                    kind: kind
                )
            )
        }

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                currentOldLine = try parseStart(from: line, marker: "-")
                currentNewLine = try parseStart(from: line, marker: "+")
                appendLine(line, kind: .hunk)
                continue
            }

            guard let oldLine = currentOldLine, let newLine = currentNewLine else {
                appendLine(line)
                continue
            }

            if line.hasPrefix("\\") {
                appendLine(line)
                continue
            }

            position += 1
            let lineKind = lineKind(forPatchLine: line)
            let annotatedOldLine = lineKind == .addition ? nil : oldLine
            let annotatedNewLine = lineKind == .deletion ? nil : newLine

            appendLine(
                "[pos \(position)] \(line)",
                position: position,
                oldLine: annotatedOldLine,
                newLine: annotatedNewLine,
                kind: lineKind
            )

            if line.hasPrefix("-") {
                currentOldLine = oldLine + 1
                continue
            }

            positionsByNewLine[newLine] = position
            currentNewLine = newLine + 1
            if !line.hasPrefix("+") {
                currentOldLine = oldLine + 1
            }
        }

        return AnnotatedDiff(
            path: path,
            annotatedPatch: annotatedLines.joined(separator: "\n"),
            positionsByNewLine: positionsByNewLine,
            lines: diffLines
        )
    }

    private static func lineKind(forPatchLine line: String) -> AnnotatedDiffLineKind {
        if line.hasPrefix("+") {
            return .addition
        }

        if line.hasPrefix("-") {
            return .deletion
        }

        if line.hasPrefix(" ") {
            return .context
        }

        return .metadata
    }

    private static func parseStart(from hunkHeader: String, marker: String) throws -> Int {
        guard let markerRange = hunkHeader.range(of: marker) else {
            throw DiffPositionError.invalidHunkHeader(hunkHeader)
        }

        let afterMarker = hunkHeader[markerRange.upperBound...]
        let digits = afterMarker.prefix { character in
            character >= "0" && character <= "9"
        }

        guard let value = Int(digits) else {
            throw DiffPositionError.invalidHunkHeader(hunkHeader)
        }

        return value
    }
}
