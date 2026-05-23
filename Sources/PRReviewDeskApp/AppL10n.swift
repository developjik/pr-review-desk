import Foundation
import SwiftUI

enum AppL10n {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        string(key, arguments: arguments)
    }

    static func string(_ key: String, arguments: [CVarArg]) -> String {
        let format = String(localized: String.LocalizationValue(key), bundle: .module)
        guard !arguments.isEmpty else {
            return format
        }

        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> Text {
        Text(string(key, arguments: arguments))
    }
}
