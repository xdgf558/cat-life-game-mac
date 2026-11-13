import Foundation

public enum HomeNameRules {
    public static let maximumLength = 12

    /// nil means invalid input, not a request to restore the default name.
    /// Count extended grapheme clusters so an emoji family is one character.
    public static func normalized(_ raw: String) -> String? {
        // Check the original text before trimming: a pasted trailing newline
        // or tab is invalid rather than silently becoming a different name.
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                return nil
            case .format:
                // ZWJ and emoji tag sequences belong to visible emoji. Other
                // format controls, including bidi and zero-width spaces, don't.
                guard scalar.value == 0x200D || (0xE0020...0xE007F).contains(scalar.value) else { return nil }
            default:
                break
            }
        }
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard (1...maximumLength).contains(value.count) else { return nil }
        for character in value {
            let scalars = character.unicodeScalars
            let hasInvisibleModifier = scalars.contains {
                $0.properties.generalCategory == .format
                    || (0xFE00...0xFE0F).contains($0.value)
                    || (0xE0100...0xE01EF).contains($0.value)
            }
            if hasInvisibleModifier {
                // An isolated ZWJ/variation selector must not produce a blank
                // name. Keep modifiers attached to an actual visible base.
                let hasBase = scalars.contains {
                    switch $0.properties.generalCategory {
                    case .format, .control, .nonspacingMark, .spacingMark, .enclosingMark:
                        return false
                    default:
                        return !CharacterSet.whitespaces.contains($0)
                    }
                }
                guard hasBase else { return nil }
            }
        }
        return value
    }
}
