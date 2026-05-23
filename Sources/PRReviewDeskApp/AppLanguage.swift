import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "language"

    case system
    case english = "en"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return AppL10n.string("System")
        case .english:
            return AppL10n.string("English")
        case .korean:
            return AppL10n.string("Korean")
        }
    }

    var localizationIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .korean:
            return "ko"
        }
    }

    static func preferred(from rawValue: String?) -> AppLanguage {
        guard let rawValue,
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }

        return language
    }
}
