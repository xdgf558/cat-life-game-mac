import XCTest
import CatGameCore
@testable import CatLifeMac

/// 2.20: a picked song plays everywhere but the title screen, and every cat keeps one voice.
final class MacAudioChoiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    func testPickedSongPlaysEverywhereButTheTitle() {
        var settings = AudioSettings()
        XCTAssertEqual(GameAudioPolicy.track(.work, settings: settings, hour: 12), .work)
        settings.musicChoice = GameMusicTrack.promenade.rawValue
        for scene in [GameMusicTrack.home, .work, .shop, .hospital, .sleep] {
            XCTAssertEqual(GameAudioPolicy.track(scene, settings: settings, hour: 23), .promenade)
        }
        XCTAssertEqual(GameAudioPolicy.track(.cover, settings: settings, hour: 12), .cover)
        settings.musicChoice = "not-a-song"
        XCTAssertEqual(GameAudioPolicy.track(.work, settings: settings, hour: 12), .work)
        settings.musicChoice = GameMusicTrack.cover.rawValue
        XCTAssertEqual(GameAudioPolicy.track(.work, settings: settings, hour: 12), .work)
        XCTAssertFalse(GameMusicTrack.pickable.contains(.cover))
    }

    func testEachCatKeepsOneVoiceAndKittensSoundHigher() {
        var adult = CatState(id: "cat_042", name: "Mochi", now: now, appearance: .blue,
                             growthState: CatGrowthState(recordedSince: now, adoptedAt: now, initialAgeDays: 400, sex: .female))
        let voice = CatVoice.voice(for: adult, at: now)
        XCTAssertEqual(CatVoice.voice(for: adult, at: now), voice)
        XCTAssertEqual(CatVoice.stableHash("cat_042"), CatVoice.stableHash("cat_042"))
        adult.growthState = CatGrowthState(recordedSince: now, adoptedAt: now, initialAgeDays: 10, sex: .female)
        let kitten = CatVoice.voice(for: adult, at: now)
        XCTAssertLessThanOrEqual(CatVoice.allCases.firstIndex(of: kitten)!, CatVoice.allCases.firstIndex(of: voice)!)
        XCTAssertEqual(CatVoice.voice(for: nil, at: now), .standard)
    }

    func testVoiceFilesExistForEveryCatSound() {
        for effect in GameSoundEffect.allCases where effect.isCatVoice {
            XCTAssertEqual(CatVoice.standard.fileName(for: effect), effect.fileName)
            for voice in CatVoice.allCases {
                XCTAssertNotNil(Bundle.main.url(forResource: voice.fileName(for: effect), withExtension: "caf", subdirectory: "Audio"),
                                voice.fileName(for: effect))
            }
        }
        XCTAssertEqual(CatVoice.tiny.fileName(for: .coins), GameSoundEffect.coins.fileName)
    }
}
