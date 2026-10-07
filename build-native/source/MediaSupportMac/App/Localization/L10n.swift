import Foundation

/// Cổng localization duy nhất cho các chuỗi không được SwiftUI tự tra cứu.
/// Dùng chính câu tiếng Việt làm key để việc chuyển dần UI không làm đổi bố cục.
enum L10n {
    /// Locale used to present provider metadata such as language and country names.
    /// The app relaunches after changing `AppleLanguages`, so the bundle preference
    /// is the authoritative UI language and does not depend on the system locale.
    static var interfaceLocaleIdentifier: String {
        Bundle.main.preferredLocalizations.first
            ?? Bundle.main.developmentLocalization
            ?? Locale.current.identifier
    }

    static func string(_ key: String, fallback: String? = nil) -> String {
        Bundle.main.localizedString(
            forKey: key,
            value: fallback ?? key,
            table: "Localizable"
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = string(key)
        let specifiers = conversionSpecifiers(in: format)
        let safeArguments = arguments.enumerated().map { index, argument -> CVarArg in
            guard index < specifiers.count, specifiers[index] == "@" else { return argument }
            return objectSafe(argument)
        }
        return String(format: format, locale: Locale.current, arguments: safeArguments)
    }

    /// Foundation format strings use Objective-C varargs. A scalar accidentally paired
    /// with `%@` is otherwise interpreted as an object pointer and can crash the process.
    private static func objectSafe(_ argument: CVarArg) -> CVarArg {
        switch argument {
        case let value as Int: String(value)
        case let value as Int8: String(value)
        case let value as Int16: String(value)
        case let value as Int32: String(value)
        case let value as Int64: String(value)
        case let value as UInt: String(value)
        case let value as UInt8: String(value)
        case let value as UInt16: String(value)
        case let value as UInt32: String(value)
        case let value as UInt64: String(value)
        case let value as Float: String(value)
        case let value as Double: String(value)
        case let value as Bool: String(value)
        default: argument
        }
    }

    private static func conversionSpecifiers(in format: String) -> [Character] {
        let characters = Array(format)
        let conversions = Set("diuoxXfFeEgGaAcsp@".map { $0 })
        var result: [Character] = []
        var index = 0
        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }
            index += 1
            if index < characters.count, characters[index] == "%" {
                index += 1
                continue
            }
            while index < characters.count {
                let character = characters[index]
                if conversions.contains(character) {
                    result.append(character)
                    index += 1
                    break
                }
                index += 1
            }
        }
        return result
    }
}
