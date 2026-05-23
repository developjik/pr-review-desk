import Foundation
import SwiftUI

enum AppL10n {
    private static let languageOverride: String? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--ui-smoke-language"),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }

        return arguments[arguments.index(after: index)]
    }()

    static var languageIdentifier: String {
        languageOverride ?? "system"
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        string(key, arguments: arguments)
    }

    static func string(_ key: String, arguments: [CVarArg]) -> String {
        let format: String
        if let languageOverride,
           let languageBundlePath = Bundle.module.path(forResource: languageOverride, ofType: "lproj"),
           let languageBundle = Bundle(path: languageBundlePath) {
            format = languageBundle.localizedString(forKey: key, value: nil, table: nil)
        } else {
            format = String(localized: String.LocalizationValue(key), bundle: .module)
        }
        guard !arguments.isEmpty else {
            return format
        }

        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> Text {
        Text(string(key, arguments: arguments))
    }
}
