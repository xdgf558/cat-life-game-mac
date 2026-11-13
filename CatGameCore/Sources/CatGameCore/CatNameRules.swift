public enum CatNameRules {
    public static let maximumLength = PlayerNameRules.maximumLength

    public static func normalized(_ raw: String) -> String? {
        PlayerNameRules.normalized(raw)
    }
}
