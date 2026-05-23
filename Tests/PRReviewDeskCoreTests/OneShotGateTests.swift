import Foundation
import PRReviewDeskCore

enum OneShotGateTests {
    static func run() throws {
        try testOneShotGateAllowsOnlyFirstAttemptUntilReset()
    }

    private static func testOneShotGateAllowsOnlyFirstAttemptUntilReset() throws {
        var gate = OneShotGate()

        try expectTrue(gate.consume())
        try expectTrue(!gate.consume())

        gate.reset()
        try expectTrue(gate.consume())
        try expectTrue(!gate.consume())
    }
}
