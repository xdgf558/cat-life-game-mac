import Foundation
import CatGameCore

enum GameMusicTrack: String, CaseIterable {
    case cover, home, night, sleep, work, town, hospital, shop, promenade, upstairs
    var fileName: String { "bgm-\(rawValue)" }
    var sceneKey: String { "audio.scene.\(rawValue)" }
    /// 2.20: the player-facing song name in the music picker.
    var nameKey: String { "audio.track.\(rawValue)" }
    /// Tracks the player can pick to play everywhere. The title screen keeps its own theme.
    static var pickable: [GameMusicTrack] { allCases.filter { $0 != .cover } }
    var title: String {
        switch self {
        case .cover: "Way Back Home"
        case .home: "Sunlit Little Home"
        case .night: "Lamp-lit Room"
        case .sleep: "Paws at Rest"
        case .work: "Little Steps to Payday"
        case .town: "Town Stroll"
        case .promenade: "Cat Town Promenade"
        case .upstairs: "Sunlit Upstairs"
        case .hospital: "Gentle Checkup"
        case .shop: "Bell Over the Door"
        }
    }
}

enum GameSoundEffect: String, CaseIterable {
    case tap, back, sheet, toggle, enter, purchase, place, feed, clean, play, pet, sleep, wake
    case coins, shield, claim, pin, knock, remind
    case softError = "soft-error"
    case shortGold = "short-gold"
    case workStart = "work-start"
    case workComplete = "work-complete"
    case levelUp = "level-up"
    case sickAlert = "sick-alert"
    case treatStart = "treat-start"
    case treatDone = "treat-done"
    case taskDone = "task-done"
    case dailyReset = "daily-reset"
    case catHappy = "cat-happy"
    case catHungry = "cat-hungry"
    case catCoax = "cat-coax"
    case catUnwell = "cat-unwell"
    case catSleepy = "cat-sleepy"
    case catPurr = "cat-purr"

    // Keep the existing actor's semantic call site while routing it to the cat bus.
    static let catMeow = GameSoundEffect.catHappy

    var isCatVoice: Bool {
        switch self {
        case .catHappy, .catHungry, .catCoax, .catUnwell, .catSleepy, .catPurr: true
        default: false
        }
    }
    var fileName: String { isCatVoice ? rawValue : "sfx-\(rawValue)" }
    var priority: Int {
        switch self {
        case .claim, .levelUp, .treatDone, .workComplete, .coins, .taskDone: 3
        case .catHappy, .catHungry, .catCoax, .catUnwell, .catSleepy, .catPurr: 2
        case .feed, .clean, .play, .pet, .sleep, .wake, .sickAlert, .treatStart, .shield: 1
        default: 0
        }
    }
    var ducksMusic: Bool {
        isCatVoice || [.claim, .levelUp, .treatDone, .workComplete].contains(self)
    }
    var successHaptic: Bool { self == .claim || self == .levelUp }
    var lightHaptic: Bool { [.pet, .treatDone, .workComplete].contains(self) }
}

/// 2.20: each cat has its own voice. The clips are the same six cat sounds replayed faster (a smaller,
/// higher cat) or slower (a bigger, lower one); `scripts/make_cat_voices.py` makes the files.
enum CatVoice: String, CaseIterable, Hashable {
    case tiny, bright, standard, warm, deep

    func fileName(for effect: GameSoundEffect) -> String {
        guard effect.isCatVoice, self != .standard else { return effect.fileName }
        return "\(effect.fileName)-\(rawValue)"
    }

    /// Breed sets the base voice, a kitten sounds a step higher, and each cat's id nudges it a step either
    /// way, so two cats of the same breed usually differ. The same cat always sounds the same.
    static func voice(for cat: CatState?, at date: Date) -> CatVoice {
        guard let cat else { return .standard }
        let base: Int = switch cat.appearance {
        case .cow, .siamese: 1
        case .orange: 2
        case .blue, .silver: 3
        }
        let kitten = cat.growthState?.stage(at: date) == .kitten ? -1 : 0
        let individual = Int(stableHash(cat.id) % 3) - 1
        return allCases[min(allCases.count - 1, max(0, base + kitten + individual))]
    }

    /// FNV-1a: Swift's `hashValue` changes every launch, a voice must not.
    static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }
}

/// Pure decisions are shared by playback and tests; AVAudioSession remains the sole runtime owner.
enum GameAudioPolicy {
    static let simultaneousEffects = 3
    static func isQuietHour(_ hour: Int) -> Bool { hour < 7 || hour >= 22 }

    static func track(_ requested: GameMusicTrack, settings: AudioSettings, hour: Int) -> GameMusicTrack {
        // A picked song plays everywhere except the title screen; an unknown name follows the scene.
        if requested != .cover, let choice = settings.musicChoice.flatMap(GameMusicTrack.init(rawValue:)),
           GameMusicTrack.pickable.contains(choice) { return choice }
        guard settings.sceneMusic else { return .home }
        return (requested == .home || requested == .upstairs) && settings.nightQuiet && isQuietHour(hour) ? .night : requested
    }

    static func musicVolume(settings: AudioSettings, hour: Int, ducked: Bool) -> Float {
        Float(settings.musicVolume * (settings.nightQuiet && isQuietHour(hour) ? 0.7 : 1) * (ducked ? 0.5 : 1))
    }

    static func effectVolume(_ effect: GameSoundEffect, settings: AudioSettings) -> Float {
        if effect.isCatVoice { return settings.catEnabled ? Float(settings.catVolume) : 0 }
        return settings.effectsEnabled ? Float(settings.effectsVolume) : 0
    }

    static func replacementIndex(for incoming: GameSoundEffect, active: [GameSoundEffect]) -> Int? {
        guard active.count >= simultaneousEffects,
              let lowest = active.indices.min(by: { active[$0].priority < active[$1].priority }),
              active[lowest].priority < incoming.priority else { return nil }
        return lowest
    }
}
