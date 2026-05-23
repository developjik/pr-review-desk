import Foundation

public struct OneShotGate: Equatable, Hashable, Sendable {
    public private(set) var hasConsumed = false

    public init() {}

    public mutating func consume() -> Bool {
        guard !hasConsumed else {
            return false
        }

        hasConsumed = true
        return true
    }

    public mutating func reset() {
        hasConsumed = false
    }
}
