import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #file,
    line: UInt = #line
) throws {
    guard actual == expected else {
        throw TestFailure(message: "\(file):\(line): expected \(expected), got \(actual)")
    }
}

func expectTrue(
    _ condition: Bool,
    file: StaticString = #file,
    line: UInt = #line
) throws {
    guard condition else {
        throw TestFailure(message: "\(file):\(line): expected condition to be true")
    }
}

func unwrap<T>(
    _ value: T?,
    file: StaticString = #file,
    line: UInt = #line
) throws -> T {
    guard let value else {
        throw TestFailure(message: "\(file):\(line): expected non-nil value")
    }
    return value
}
