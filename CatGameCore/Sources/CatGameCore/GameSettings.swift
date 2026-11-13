import Foundation

public enum GameLanguage: String, Codable, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    /// Resolve the first supported system preference. An explicit Chinese
    /// script takes precedence over its region (for example, zh-Hans-TW).
    public static func preferred(in preferredLanguages: [String]) -> GameLanguage {
        for language in preferredLanguages {
            let components = language.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")
                .lowercased().split(separator: "-")
            guard let base = components.first else { continue }
            if base == "en" { return .english }
            guard base == "zh" else { continue }
            if components.contains("hant") { return .traditionalChinese }
            if components.contains("hans") { return .simplifiedChinese }
            if components.contains(where: { ["tw", "hk", "mo"].contains($0) }) {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }
        return .simplifiedChinese
    }
}

/// Optional presentation preferences must not invalidate earned game progress.
/// Volume setters keep runtime edits as safe to encode as decoded preferences.
public struct AudioSettings: Codable, Equatable, Sendable {
    public static let defaultMusicVolume = 0.35
    public static let defaultEffectsVolume = 0.65

    public var musicEnabled: Bool
    public var effectsEnabled: Bool
    public var catEnabled: Bool
    public var sceneMusic: Bool
    public var nightQuiet: Bool
    public var haptics: Bool
    private var storedMusicVolume: Double
    private var storedEffectsVolume: Double
    private var storedCatVolume: Double

    public var musicVolume: Double {
        get { storedMusicVolume }
        set { storedMusicVolume = Self.normalized(newValue, fallback: Self.defaultMusicVolume) }
    }

    public var effectsVolume: Double {
        get { storedEffectsVolume }
        set { storedEffectsVolume = Self.normalized(newValue, fallback: Self.defaultEffectsVolume) }
    }

    public var catVolume: Double {
        get { storedCatVolume }
        set { storedCatVolume = Self.normalized(newValue, fallback: Self.defaultEffectsVolume) }
    }

    public init(musicEnabled: Bool = true, effectsEnabled: Bool = true,
                musicVolume: Double = Self.defaultMusicVolume,
                effectsVolume: Double = Self.defaultEffectsVolume,
                catEnabled: Bool? = nil, catVolume: Double? = nil,
                sceneMusic: Bool = true, nightQuiet: Bool = true, haptics: Bool = true) {
        self.musicEnabled = musicEnabled
        self.effectsEnabled = effectsEnabled
        self.catEnabled = catEnabled ?? effectsEnabled
        self.sceneMusic = sceneMusic
        self.nightQuiet = nightQuiet
        self.haptics = haptics
        storedMusicVolume = Self.normalized(musicVolume, fallback: Self.defaultMusicVolume)
        storedEffectsVolume = Self.normalized(effectsVolume, fallback: Self.defaultEffectsVolume)
        storedCatVolume = Self.normalized(catVolume ?? effectsVolume, fallback: Self.defaultEffectsVolume)
    }

    private enum CodingKeys: String, CodingKey {
        case musicEnabled, effectsEnabled, musicVolume, effectsVolume, catEnabled, catVolume, sceneMusic, nightQuiet, haptics
    }

    public init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(musicEnabled: (try? values.decode(Bool.self, forKey: .musicEnabled)) ?? true,
                  effectsEnabled: (try? values.decode(Bool.self, forKey: .effectsEnabled)) ?? true,
                  musicVolume: (try? values.decode(Double.self, forKey: .musicVolume)) ?? Self.defaultMusicVolume,
                  effectsVolume: (try? values.decode(Double.self, forKey: .effectsVolume)) ?? Self.defaultEffectsVolume,
                  catEnabled: try? values.decode(Bool.self, forKey: .catEnabled),
                  catVolume: try? values.decode(Double.self, forKey: .catVolume),
                  sceneMusic: (try? values.decode(Bool.self, forKey: .sceneMusic)) ?? true,
                  nightQuiet: (try? values.decode(Bool.self, forKey: .nightQuiet)) ?? true,
                  haptics: (try? values.decode(Bool.self, forKey: .haptics)) ?? true)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(musicEnabled, forKey: .musicEnabled)
        try values.encode(effectsEnabled, forKey: .effectsEnabled)
        try values.encode(musicVolume, forKey: .musicVolume)
        try values.encode(effectsVolume, forKey: .effectsVolume)
        try values.encode(catEnabled, forKey: .catEnabled)
        try values.encode(catVolume, forKey: .catVolume)
        try values.encode(sceneMusic, forKey: .sceneMusic)
        try values.encode(nightQuiet, forKey: .nightQuiet)
        try values.encode(haptics, forKey: .haptics)
    }

    private static func normalized(_ volume: Double, fallback: Double) -> Double {
        volume.isFinite ? min(1, max(0, volume)) : fallback
    }
}

public struct GameSettings: Codable, Equatable, Sendable {
    /// nil follows the system preference; a selected language stays in this save.
    public var language: GameLanguage?
    public var audio: AudioSettings

    public init(language: GameLanguage? = nil, audio: AudioSettings = AudioSettings()) {
        self.language = language
        self.audio = audio
    }

    private enum CodingKeys: String, CodingKey { case language, audio }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // An unsupported preference must not discard an otherwise valid game.
        language = (try? values.decode(String.self, forKey: .language))
            .flatMap(GameLanguage.init(rawValue:))
        audio = (try? values.decode(AudioSettings.self, forKey: .audio)) ?? AudioSettings()
    }
}
