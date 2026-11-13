import Foundation
import Testing
@testable import CatGameCore

@Suite("Language, audio preferences and save compatibility")
struct GameSettingsTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func systemPreferencesRespectOrderScriptAndChineseRegions() {
        for tag in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh_HK", "ZH-hant-HK", "zh-Hant-CN"] {
            #expect(GameLanguage.preferred(in: [tag]) == .traditionalChinese)
        }
        for tag in ["zh", "zh-Hans", "zh-CN", "zh-SG", "zh_Hans_CN", "zh-Hans-TW"] {
            #expect(GameLanguage.preferred(in: [tag]) == .simplifiedChinese)
        }
        for tag in ["en", "en-US", "en-GB", " EN_sg "] {
            #expect(GameLanguage.preferred(in: [tag]) == .english)
        }
        #expect(GameLanguage.preferred(in: ["fr-FR", "en-GB", "zh-Hant"]) == .english)
        #expect(GameLanguage.preferred(in: ["ja-JP", "zh-HK", "en"]) == .traditionalChinese)
        #expect(GameLanguage.preferred(in: ["zh-CN", "en"]) == .simplifiedChinese)
        #expect(GameLanguage.preferred(in: ["fr-FR", "ja-JP"]) == .simplifiedChinese)
        #expect(GameLanguage.preferred(in: []) == .simplifiedChinese)
    }

    @Test func languageDefaultsDoNotFreezeTheFirstSystemPreference() throws {
        let fresh = GameSnapshot.fresh(now: now)
        #expect(fresh.settings.language == nil)
        let data = try JSONEncoder().encode(fresh)
        let reloaded = try JSONDecoder().decode(GameSnapshot.self, from: data)
        #expect(reloaded.settings.language == nil)
        #expect(reloaded == fresh)
        #expect(GameLanguage.preferred(in: ["en-US"]) == .english)
        #expect(GameLanguage.preferred(in: ["zh-TW"]) == .traditionalChinese)
    }

    @Test func preSettingsSaveKeepsFurnitureCatsResourcesAndWorkWithoutRewrite() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let expected = progressedSnapshot()
        try await repository.save(expected)
        var object = try object(in: Data(contentsOf: repository.saveURL))
        object.removeValue(forKey: "settings")
        let legacy = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try legacy.write(to: repository.saveURL)

        let reopened = FileSaveRepository(directory: folder)
        let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(600))
        #expect(loaded == expected)
        #expect(loaded.settings.language == nil)
        #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(await reopened.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
    }

    @Test func earliestSaveMigratesBothSettingsAndFurnitureWithoutLosingProgress() throws {
        var expected = progressedSnapshot()
        expected.home.furniture = FurnitureCatalog.defaultPlacements
        var object = try object(in: JSONEncoder().encode(expected))
        object["schemaVersion"] = 14
        object.removeValue(forKey: "settings")
        for key in ["home", "inventory"] {
            var container = try #require(object[key] as? [String: Any])
            container.removeValue(forKey: "furniture")
            object[key] = container
        }
        let legacy = try snapshotFixtureData(object)
        let loaded = try JSONDecoder().decode(GameSnapshot.self, from: legacy)
        #expect(loaded == expected)
        #expect(loaded.settings.language == nil)
        #expect(loaded.inventory.furniture.count == 9 && loaded.home.furniture.count == 9)
    }

    @Test func unknownMissingOrMalformedLanguageDoesNotRecoverAnOlderBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        // A fallback to this valid but older save would lose the earned progress.
        try await repository.save(GameSnapshot.fresh(now: now))
        var selected = progressedSnapshot()
        selected.settings.language = .traditionalChinese
        try await repository.save(selected)
        let saved = try object(in: Data(contentsOf: repository.saveURL))
        var expected = selected
        expected.settings.language = nil

        for settings: [String: Any] in [[:], ["language": "future-language"],
                                        ["language": NSNull()], ["language": 17]] {
            var modified = saved
            modified["settings"] = settings
            let originalBytes = try JSONSerialization.data(withJSONObject: modified, options: [.sortedKeys])
            try originalBytes.write(to: repository.saveURL)
            let reopened = FileSaveRepository(directory: folder)
            let loaded = try await reopened.loadOrCreate(now: now)
            #expect(loaded == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
            #expect(try Data(contentsOf: repository.saveURL) == originalBytes)
        }
    }

    @Test func explicitLanguageSurvivesSaveAndNewRepositoryWithAllProgressIntact() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var expected = progressedSnapshot()
        // Deliberately store every item: saving settings must not repopulate []
        // or alter ownership, supplies, custom cat data or the bowl position.
        expected.home.furniture = []
        for language in GameLanguage.allCases {
            expected.settings.language = language
            try await FileSaveRepository(directory: folder).save(expected)
            let saved = try object(in: Data(contentsOf: folder.appendingPathComponent("cat-life-native-v1.json")))
            let settings = try #require(saved["settings"] as? [String: Any])
            #expect(settings["language"] as? String == language.rawValue)
            let reopened = FileSaveRepository(directory: folder)
            let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(600))
            #expect(loaded == expected)
            #expect(loaded.home.furniture.isEmpty && loaded.inventory.furniture.count == 9)
            #expect(await reopened.lastLoadDisposition == .loaded)
        }
    }

    @Test func preAudioSaveKeepsLanguageAndProgressWithoutRewritingTheFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var expected = progressedSnapshot()
        expected.settings.language = .traditionalChinese
        try await repository.save(expected)
        var saved = try object(in: Data(contentsOf: repository.saveURL))
        var settings = try #require(saved["settings"] as? [String: Any])
        settings.removeValue(forKey: "audio")
        saved["settings"] = settings
        let legacy = try JSONSerialization.data(withJSONObject: saved, options: [.sortedKeys])
        try legacy.write(to: repository.saveURL)

        let reopened = FileSaveRepository(directory: folder)
        let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(600))
        #expect(loaded == expected)
        #expect(loaded.settings.audio == AudioSettings())
        #expect(loaded.settings.language == .traditionalChinese)
        #expect(await reopened.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
    }

    @Test func partialAndMalformedAudioFieldsFallBackIndividually() throws {
        let fixtures: [([String: Any], AudioSettings)] = [
            (["musicEnabled": false, "musicVolume": 0],
             AudioSettings(musicEnabled: false, musicVolume: 0)),
            (["musicEnabled": "false", "effectsEnabled": false,
              "musicVolume": "0.8", "effectsVolume": 0],
             AudioSettings(effectsEnabled: false, effectsVolume: 0)),
            (["musicEnabled": NSNull(), "effectsEnabled": 1,
              "musicVolume": -8, "effectsVolume": 8],
             AudioSettings(musicVolume: 0, effectsVolume: 1)),
            (["musicEnabled": false, "effectsEnabled": false,
              "musicVolume": NSNull(), "effectsVolume": ["unsupported"]],
             AudioSettings(musicEnabled: false, effectsEnabled: false))
        ]
        for (audio, expected) in fixtures {
            let encoded = try JSONSerialization.data(withJSONObject: ["language": "en", "audio": audio])
            let settings = try JSONDecoder().decode(GameSettings.self, from: encoded)
            #expect(settings.language == .english)
            #expect(settings.audio == expected)
        }
    }

    @Test func malformedAudioContainerDoesNotRestoreAnOlderBackupOrEraseProgress() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now))
        var expected = progressedSnapshot()
        expected.settings.language = .english
        try await repository.save(expected)
        let saved = try object(in: Data(contentsOf: repository.saveURL))
        let backup = try Data(contentsOf: repository.backupURL)

        for audio: Any in [NSNull(), "future-audio-format", 17, [false, true]] {
            var modified = saved
            var settings = try #require(saved["settings"] as? [String: Any])
            settings["audio"] = audio
            modified["settings"] = settings
            let originalBytes = try JSONSerialization.data(withJSONObject: modified, options: [.sortedKeys])
            try originalBytes.write(to: repository.saveURL)
            let reopened = FileSaveRepository(directory: folder)
            let loaded = try await reopened.loadOrCreate(now: now)
            #expect(loaded == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
            #expect(try Data(contentsOf: repository.saveURL) == originalBytes)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    @Test func nonfiniteAndOutOfRangeRuntimeVolumesRemainSafeToEncode() throws {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            var audio = AudioSettings(musicVolume: invalid, effectsVolume: invalid)
            #expect(audio.musicVolume == 0.35 && audio.effectsVolume == 0.65)
            audio.musicVolume = 0
            audio.effectsVolume = 1
            audio[keyPath: \.musicVolume] = invalid
            audio[keyPath: \.effectsVolume] = invalid
            #expect(audio.musicVolume == 0.35 && audio.effectsVolume == 0.65)
            let data = try JSONEncoder().encode(audio)
            #expect(try JSONDecoder().decode(AudioSettings.self, from: data) == audio)
        }
        var audio = AudioSettings(musicVolume: -4, effectsVolume: 4)
        #expect(audio.musicVolume == 0 && audio.effectsVolume == 1)
        audio.musicVolume = 7
        audio.effectsVolume = -7
        #expect(audio.musicVolume == 1 && audio.effectsVolume == 0)
        let encoded = try object(in: JSONEncoder().encode(audio))
        #expect(Set(encoded.keys) == ["musicEnabled", "effectsEnabled", "musicVolume", "effectsVolume", "catEnabled", "catVolume", "sceneMusic", "nightQuiet", "haptics"])
    }

    @Test func legacyCatChannelInheritsMutedEffectsWithoutChangingExistingVolumes() throws {
        let legacy = Data(#"{"musicEnabled":false,"effectsEnabled":false,"musicVolume":0.2,"effectsVolume":0.4}"#.utf8)
        let audio = try JSONDecoder().decode(AudioSettings.self, from: legacy)
        #expect(!audio.catEnabled && audio.catVolume == 0.4)
        #expect(!audio.musicEnabled && !audio.effectsEnabled && audio.musicVolume == 0.2)
        #expect(audio.sceneMusic && audio.nightQuiet && audio.haptics)
        #expect(try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(audio)) == audio)
    }

    @Test func independentCatAndScenePreferencesRoundTripAndNormalizeSafely() throws {
        var audio = AudioSettings(effectsEnabled: false, effectsVolume: 0.4,
                                  catEnabled: true, catVolume: 0.8,
                                  sceneMusic: false, nightQuiet: false, haptics: false)
        #expect(audio.catEnabled && !audio.effectsEnabled)
        #expect(try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(audio)) == audio)
        audio.catVolume = .infinity
        #expect(audio.catVolume == AudioSettings.defaultEffectsVolume)
        audio.catVolume = -2
        #expect(audio.catVolume == 0)
        audio.catVolume = 3
        #expect(audio.catVolume == 1)
        let malformed = Data(#"{"effectsEnabled":false,"effectsVolume":0.4,"catEnabled":"true","catVolume":{},"sceneMusic":4,"nightQuiet":null,"haptics":"false"}"#.utf8)
        let fallback = try JSONDecoder().decode(AudioSettings.self, from: malformed)
        #expect(!fallback.catEnabled && fallback.catVolume == 0.4)
        #expect(fallback.sceneMusic && fallback.nightQuiet && fallback.haptics)
    }

    @Test func independentMuteAndZeroVolumePersistWithoutChangingOtherGameData() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var expected = progressedSnapshot()
        expected.settings.language = .traditionalChinese
        expected.home.name = "橘子的午后"
        expected.home.furniture = []
        expected.player.profile.avatarID = "female_forest"
        let preferences = [
            AudioSettings(musicEnabled: false, musicVolume: 0, effectsVolume: 0.27),
            AudioSettings(effectsEnabled: false, musicVolume: 0.42, effectsVolume: 0),
            AudioSettings(musicEnabled: false, effectsEnabled: false, musicVolume: 0, effectsVolume: 0)
        ]
        for audio in preferences {
            expected.settings.audio = audio
            let repository = FileSaveRepository(directory: folder)
            try await repository.save(expected)
            let saved = try object(in: Data(contentsOf: repository.saveURL))
            let settings = try #require(saved["settings"] as? [String: Any])
            let storedAudio = try #require(settings["audio"] as? [String: Any])
            #expect(saved["audio"] == nil)
            #expect(storedAudio["musicEnabled"] as? Bool == audio.musicEnabled)
            #expect(storedAudio["effectsEnabled"] as? Bool == audio.effectsEnabled)
            #expect(storedAudio["musicVolume"] as? Double == audio.musicVolume)
            #expect(storedAudio["effectsVolume"] as? Double == audio.effectsVolume)
            let reopened = FileSaveRepository(directory: folder)
            #expect(try await reopened.loadOrCreate(now: now.addingTimeInterval(600)) == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
        }
    }

    private func progressedSnapshot() -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.food = 11
        state.inventory.litter = 7
        state.inventory.toys = 5
        state.player.gold = 125
        state.player.completedWorkCount = 9
        state.player.activeWork = ActiveWork(id: "existing-work", startedAt: now,
                                             endsAt: now.addingTimeInterval(120), goldReward: 60)
        state.cats[0].name = "用户的小猫"
        state.cats[0].satiety = 63
        state.cats.append(CatState(id: "existing-kitten", name: "小白", now: now))
        state.home.bowlPosition = .init(x: 0.53, y: 0.68)
        state.home.comfortScore = 43
        state.home.furniture = [.init(itemID: "catBed", position: .init(x: 0.41, y: 0.64)),
                                .init(itemID: "plantSmall", position: .init(x: 0.8, y: 0.7))]
        return state
    }

    private func object(in data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func directory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
