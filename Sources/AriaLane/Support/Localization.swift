import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    enum Resolved: String {
        case simplifiedChinese = "zh-Hans"
        case english = "en"

        var metalinkRegionPreference: String {
            switch self {
            case .simplifiedChinese:
                return "CN"
            case .english:
                return "US"
            }
        }

        var metalinkLanguagePreference: String {
            switch self {
            case .simplifiedChinese:
                return "zh-CN"
            case .english:
                return "en-US"
            }
        }
    }

    static let preferenceKey = "appLanguage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            L10n.string("跟随系统")
        case .simplifiedChinese:
            L10n.string("简体中文")
        case .english:
            "English"
        }
    }

    var detail: String {
        switch self {
        case .system:
            L10n.string("中文系统显示中文；英文及其他系统显示英文。")
        case .simplifiedChinese:
            L10n.string("始终显示简体中文。")
        case .english:
            L10n.string("始终显示英文。")
        }
    }

    var resolved: Resolved {
        Self.resolve(self, preferredLanguages: Locale.preferredLanguages)
    }

    static func resolve(
        _ selection: AppLanguage,
        preferredLanguages: [String]
    ) -> Resolved {
        switch selection {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .system:
            guard let preferredLanguage = preferredLanguages.first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            else {
                return .english
            }
            return preferredLanguage.hasPrefix("zh")
                ? .simplifiedChinese
                : .english
        }
    }
}

enum L10n {
    struct Phrase: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        var key: String
        var arguments: [String]

        init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        struct StringInterpolation: StringInterpolationProtocol {
            var key: String
            var arguments: [String]

            init(literalCapacity: Int, interpolationCount: Int) {
                key = ""
                key.reserveCapacity(literalCapacity + interpolationCount * 3)
                arguments = []
                arguments.reserveCapacity(interpolationCount)
            }

            mutating func appendLiteral(_ literal: String) {
                key.append(literal)
            }

            mutating func appendInterpolation<Value>(_ value: Value) {
                key.append("{\(arguments.count)}")
                arguments.append(String(describing: value))
            }
        }
    }

    static var selectedLanguage: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        return AppLanguage(rawValue: stored ?? "") ?? .system
    }

    static var resolvedLanguage: AppLanguage.Resolved {
        selectedLanguage.resolved
    }

    static func string(_ phrase: Phrase) -> String {
        let template = localizedTemplate(for: phrase.key)
        return interpolate(template, arguments: phrase.arguments)
    }

    private static func localizedTemplate(for key: String) -> String {
        guard resolvedLanguage == .english,
              let localizationPath = Bundle.main.path(
                forResource: AppLanguage.Resolved.english.rawValue,
                ofType: "lproj"
              ),
              let localizationBundle = Bundle(path: localizationPath)
        else {
            return key
        }

        return localizationBundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }

    private static func interpolate(
        _ template: String,
        arguments: [String]
    ) -> String {
        guard !arguments.isEmpty else { return template }

        var output = ""
        var cursor = template.startIndex

        while cursor < template.endIndex {
            guard template[cursor] == "{",
                  let closingBrace = template[cursor...].firstIndex(of: "}")
            else {
                output.append(template[cursor])
                cursor = template.index(after: cursor)
                continue
            }

            let numberStart = template.index(after: cursor)
            let numberText = template[numberStart..<closingBrace]
            if let index = Int(numberText), arguments.indices.contains(index) {
                output.append(arguments[index])
                cursor = template.index(after: closingBrace)
            } else {
                output.append(template[cursor])
                cursor = template.index(after: cursor)
            }
        }

        return output
    }
}
