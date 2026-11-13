import Foundation
import CatGameCore

enum GameMusicTrack: String, CaseIterable {
    case cover, home, night, sleep, work, town, hospital, shop, promenade, upstairs
    var fileName: String { "bgm-\(rawValue)" }
    var sceneKey: String { "audio.scene.\(rawValue)" }
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

/// Pure decisions are shared by playback and tests; AVAudioSession remains the sole runtime owner.
enum GameAudioPolicy {
    static let simultaneousEffects = 3
    static func isQuietHour(_ hour: Int) -> Bool { hour < 7 || hour >= 22 }

    static func track(_ requested: GameMusicTrack, settings: AudioSettings, hour: Int) -> GameMusicTrack {
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
