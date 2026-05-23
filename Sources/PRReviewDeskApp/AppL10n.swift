import Foundation
import SwiftUI

enum AppL10n {
    private static let languageOverride = commandLineArgument(after: "--ui-smoke-language")
    private static let smokeLanguagePreference = commandLineArgument(after: "--ui-smoke-language-preference")

    static var languageIdentifier: String {
        activeLanguage.rawValue
    }

    static var usesSmokeLanguagePreference: Bool {
        languageOverride == nil && smokeLanguagePreference != nil
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        string(key, arguments: arguments)
    }

    static func string(_ key: String, arguments: [CVarArg]) -> String {
        let format = localizedFormat(key, language: activeLanguage)
        guard !arguments.isEmpty else {
            return format
        }

        return String(format: format, locale: formatLocale, arguments: arguments)
    }

    static func string(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        let format = localizedFormat(key, language: language)
        guard !arguments.isEmpty else {
            return format
        }

        let locale = language.localizationIdentifier.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> Text {
        Text(string(key, arguments: arguments))
    }

    private static var activeLanguage: AppLanguage {
        if let languageOverride {
            return AppLanguage.preferred(from: languageOverride)
        }

        if let smokeLanguagePreference {
            return AppLanguage.preferred(from: smokeLanguagePreference)
        }

        return AppLanguage.preferred(
            from: UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        )
    }

    private static var formatLocale: Locale {
        guard let localizationIdentifier = activeLanguage.localizationIdentifier else {
            return .current
        }

        return Locale(identifier: localizationIdentifier)
    }

    private static func commandLineArgument(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return arguments[valueIndex]
    }

    private static func localizedFormat(_ key: String, language: AppLanguage) -> String {
        if let localizationIdentifier = language.localizationIdentifier,
           let languageBundlePath = Bundle.module.path(forResource: localizationIdentifier, ofType: "lproj"),
           let languageBundle = Bundle(path: languageBundlePath) {
            return languageBundle.localizedString(forKey: key, value: nil, table: nil)
        }

        return String(localized: String.LocalizationValue(key), bundle: .module)
    }
}
