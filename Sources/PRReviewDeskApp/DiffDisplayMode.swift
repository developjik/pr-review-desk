import Foundation

enum DiffDisplayMode: String, CaseIterable, Identifiable {
    case unified
    case split

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unified:
            return "Unified"
        case .split:
            return "Split"
        }
    }
}
