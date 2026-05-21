import Foundation
import PRReviewDeskCore

enum DiffPositionMapperTests {
    static func run() throws {
        try testSingleHunkMapsNewLinesToGitHubPositions()
        try testMultipleHunksContinuePositionsWithinFile()
    }

    private static func testSingleHunkMapsNewLinesToGitHubPositions() throws {
        let patch = """
        @@ -1,3 +1,4 @@
         context
        -old
        +new
         more
        +added
        """

        let annotated = try DiffPositionMapper.annotate(path: "Sources/App.swift", patch: patch)

        try expectEqual(annotated.position(forNewLine: 1), 1)
        try expectEqual(annotated.position(forNewLine: 2), 3)
        try expectEqual(annotated.position(forNewLine: 3), 4)
        try expectEqual(annotated.position(forNewLine: 4), 5)
        try expectTrue(annotated.annotatedPatch.contains("[pos 3] +new"))
    }

    private static func testMultipleHunksContinuePositionsWithinFile() throws {
        let patch = """
        @@ -1,2 +10,2 @@
         a
        +b
        @@ -20,1 +30,2 @@
        -c
        +d
         e
        """

        let annotated = try DiffPositionMapper.annotate(path: "Sources/App.swift", patch: patch)

        try expectEqual(annotated.position(forNewLine: 10), 1)
        try expectEqual(annotated.position(forNewLine: 11), 2)
        try expectEqual(annotated.position(forNewLine: 30), 4)
        try expectEqual(annotated.position(forNewLine: 31), 5)
        try expectEqual(annotated.position(forNewLine: 20), nil)
    }
}
