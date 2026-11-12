public enum PlayerNameRules {
    public static let maximumLength = HomeNameRules.maximumLength

    /// Share trimming and grapheme counting with home names, then reject
    /// invisible fillers even when their Unicode category is a letter or mark.
    public static func normalized(_ raw: String) -> String? {
        guard let value = HomeNameRules.normalized(raw) else { return nil }
        for scalar in value.unicodeScalars {
            // Braille blank is not default-ignorable, but draws no visible dots.
            guard scalar.value != 0x2800 else { return nil }
            guard scalar.properties.isDefaultIgnorableCodePoint else { continue }
            switch scalar.value {
            case 0x200D, 0xFE00...0xFE0F, 0xE0100...0xE01EF, 0xE0020...0xE007F:
                // HomeNameRules already requires a visible base for these
                // joiners, variation selectors and emoji tag sequences.
                continue
            default:
                return nil
            }
        }
        return value
    }
}
