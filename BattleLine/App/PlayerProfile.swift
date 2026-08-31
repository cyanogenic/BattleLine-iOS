import Foundation
import Observation

enum NicknameRules {
    static let maximumCharacters = 20
    // Bound unusually large grapheme clusters as well as visible character count.
    static let maximumUTF8Bytes = 1_024

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
    }

    static func validationMessage(for value: String) -> String? {
        let nickname = normalized(value)
        guard !nickname.isEmpty else { return "请输入昵称，不能只包含空格。" }
        guard nickname.utf8.count <= maximumUTF8Bytes else {
            return "昵称包含过多组合字符，请简化后重试。"
        }
        guard nickname.count <= maximumCharacters else {
            return "昵称最多支持 \(maximumCharacters) 个字符。"
        }
        var hasVisibleCharacter = false
        for scalar in value.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned:
                return "昵称不能包含换行或控制字符。"
            case .format:
                // Preserve emoji joiners and subdivision-flag tag sequences, but
                // reject bidi overrides and other invisible formatting controls.
                guard scalar.value == 0x200C || scalar.value == 0x200D
                    || (0xE0020...0xE007F).contains(scalar.value) else {
                    return "昵称不能包含隐藏的格式控制字符。"
                }
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter, .decimalNumber, .letterNumber,
                 .otherNumber, .connectorPunctuation, .dashPunctuation,
                 .openPunctuation, .closePunctuation, .initialPunctuation,
                 .finalPunctuation, .otherPunctuation, .mathSymbol,
                 .currencySymbol, .modifierSymbol, .otherSymbol:
                // Some Unicode letters are invisible fillers; a blank braille
                // cell also must not satisfy the nonblank-name requirement.
                if !scalar.properties.isDefaultIgnorableCodePoint && scalar.value != 0x2800 {
                    hasVisibleCharacter = true
                }
            default:
                break
            }
        }
        return hasVisibleCharacter ? nil : "昵称至少需要一个可见字符。"
    }
}

@MainActor
@Observable
final class PlayerProfile {
    static let nicknameKey = "playerNickname"
    private(set) var nickname: String
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Self.nicknameKey) as? String ?? ""
        nickname = NicknameRules.validationMessage(for: saved) == nil
            ? NicknameRules.normalized(saved) : ""
    }

    @discardableResult
    func saveNickname(_ value: String) -> Bool {
        guard NicknameRules.validationMessage(for: value) == nil else { return false }
        let normalized = NicknameRules.normalized(value)
        defaults.set(normalized, forKey: Self.nicknameKey)
        nickname = normalized
        return true
    }
}
