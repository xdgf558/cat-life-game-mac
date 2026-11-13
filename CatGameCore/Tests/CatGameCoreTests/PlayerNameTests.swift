import Foundation
import Testing
@testable import CatGameCore

@Suite("Player names and non-destructive profile migration")
struct PlayerNameTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func namesTrimSpacesAndCountVisibleGraphemeBoundaries() {
        #expect(PlayerNameRules.maximumLength == 12)
        #expect(PlayerNameRules.normalized("  小橘  ") == "小橘")
        #expect(PlayerNameRules.normalized("\u{3000}\u{00A0}Oliver Cat\u{3000}") == "Oliver Cat")
        #expect(PlayerNameRules.normalized("  Nora  Cat  ") == "Nora  Cat")
        for character in ["橘", "A", "é", "e\u{301}", "👨‍👩‍👧‍👦", "🐈‍⬛", "👍🏽", "🇸🇬"] {
            #expect(PlayerNameRules.normalized(character) == character)
            let boundary = String(repeating: character, count: 12)
            #expect(PlayerNameRules.normalized(" " + boundary + " ") == boundary)
            #expect(PlayerNameRules.normalized(boundary + character) == nil)
        }
    }

    @Test func controlsAndInvisibleNamesAreRejectedWithoutTrimmingThemAway() {
        for invalid in ["", "   ", "\u{3000}", "\nCat", "Cat\n", "Cat\t", "C\u{0}at",
                        "C\u{7F}at", "C\u{2028}at", "C\u{2029}at", "C\u{200B}at",
                        "C\u{2060}at", "C\u{202E}at", "\u{200D}", " \u{200D} ",
                        "\u{FE0F}", "\u{E0100}", "\u{E0061}"] {
            #expect(PlayerNameRules.normalized(invalid) == nil)
        }
    }

    @Test func invisibleLettersAndMarksAreRejectedAloneOrWithinVisibleNames() {
        for codePoint: UInt32 in [0x034F, 0x115F, 0x1160, 0x3164, 0xFFA0, 0x17B4, 0x17B5, 0x2800] {
            let invisible = String(UnicodeScalar(codePoint)!)
            for name in [invisible, " " + invisible + " ", "小" + invisible + "橘",
                         invisible + "Nora", "Cat" + invisible] {
                #expect(PlayerNameRules.normalized(name) == nil)
            }
        }
        // Visible emoji and ideographic variations may legitimately include
        // default-ignorable scalars; their attached modifiers remain supported.
        for visible in ["👨‍👩‍👧‍👦", "🐈‍⬛", "❤️", "\u{908A}\u{E0100}",
                        "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"] {
            #expect(PlayerNameRules.normalized(visible) == visible)
        }
    }

    @Test func preNameProfileLoadsWithoutRewritingOrLosingAnyProgress() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now))
        let expected = progressedSnapshot()
        try await repository.save(expected)
        let legacy = try replacingName(in: Data(contentsOf: repository.saveURL), with: nil)
        try legacy.write(to: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)

        let reopened = FileSaveRepository(directory: folder)
        let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(600))
        #expect(loaded == expected)
        #expect(loaded.player.profile.name == nil && loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(await reopened.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
    }

    @Test func malformedNameFallsBackAloneWithoutRestoringAnOlderBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now))
        var original = progressedSnapshot()
        original.player.profile.name = "Clover"
        try await repository.save(original)
        let saved = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        var expected = original
        expected.player.profile.name = nil

        for malformed: Any in [NSNull(), 17, false, ["name"], ["unexpected": "name"],
                               "", "  ", String(repeating: "橘", count: 13), "Cat\n", "\u{200B}",
                               "\u{034F}", "小\u{115F}橘", "\u{3164}", "Cat\u{FFA0}", "\u{2800}"] {
            let bytes = try replacingName(in: saved, with: malformed)
            try bytes.write(to: repository.saveURL)
            let reopened = FileSaveRepository(directory: folder)
            let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(600))
            #expect(loaded == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
            #expect(try Data(contentsOf: repository.saveURL) == bytes)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(!files.contains { $0.lastPathComponent.hasPrefix("unreadable-save-") })
    }

    @Test func validSavedNamesNormalizeWithoutRewritingTheSaveOnRead() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = progressedSnapshot()
        try await repository.save(original)
        let saved = try Data(contentsOf: repository.saveURL)
        for (raw, normalized) in [("  小橘  ", "小橘"), ("\u{3000}Nora Cat\u{3000}", "Nora Cat"),
                                  ("  👨‍👩‍👧‍👦  ", "👨‍👩‍👧‍👦")] {
            let bytes = try replacingName(in: saved, with: raw)
            try bytes.write(to: repository.saveURL)
            var expected = original
            expected.player.profile.name = normalized
            let reopened = FileSaveRepository(directory: folder)
            #expect(try await reopened.loadOrCreate(now: now) == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
            #expect(try Data(contentsOf: repository.saveURL) == bytes)
        }
    }

    @Test func renameAndDefaultResetPersistWithoutChangingWorkEquipmentOrOtherState() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = progressedSnapshot()
        #expect(original.player.activeWork != nil && original.player.activeWork?.quote != nil)
        try await FileSaveRepository(directory: folder).save(original)

        for name: String? in ["小橘", "Oliver Cat", "🐈‍⬛", nil] {
            var changed = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
            changed.player.profile.name = name
            #expect(changed.isValid)
            try await FileSaveRepository(directory: folder).save(changed)
            let loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(600))
            var expected = original
            expected.player.profile.name = name
            #expect(loaded == expected)
            #expect(loaded.player.activeWork == original.player.activeWork)
            #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("cat-life-native-v1.json"))) as? [String: Any])
            let player = try #require(object["player"] as? [String: Any])
            let profile = try #require(player["profile"] as? [String: Any])
            #expect(profile["name"] as? String == name)
        }
    }

    @Test func invalidRuntimeNamesCannotOverwritePrimaryOrBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now))
        var valid = progressedSnapshot()
        valid.player.profile.name = "Clover"
        try await repository.save(valid)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)

        for invalid in ["", "  ", " untrimmed ", "Cat\n", "\u{200B}", "\u{200D}",
                        "\u{034F}", "小\u{115F}橘", "\u{3164}", "Cat\u{FFA0}", "\u{2800}",
                        String(repeating: "👨‍👩‍👧‍👦", count: 13)] {
            var changed = valid
            changed.player.profile.name = invalid
            #expect(!changed.isValid)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(changed) }
            #expect(try Data(contentsOf: repository.saveURL) == primary)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    private func progressedSnapshot() -> GameSnapshot {
        var value = GameSnapshot.fresh(now: now)
        value.player.gold = 918
        value.player.level = 4
        value.player.exp = 39
        value.player.completedWorkCount = 27
        value.player.profile.avatarID = "female_forest"
        value.inventory.food = 11
        value.inventory.litter = 7
        value.inventory.toys = 18
        value.home.name = "Quiet home"
        value.home.furniture = []
        value.settings.language = .traditionalChinese
        value.settings.audio = AudioSettings(musicEnabled: false, effectsVolume: 0.4)
        value.cats.append(CatState(id: "generated-cat", name: "Clover", now: now))
        _ = GameEngine.equipStarterSet(&value, now: now)
        _ = GameEngine.startWork(&value, jobID: "job_petshop", now: now)
        return value
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CatPlayerNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func replacingName(in data: Data, with name: Any?) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var player = try #require(object["player"] as? [String: Any])
        var profile = try #require(player["profile"] as? [String: Any])
        if let name { profile["name"] = name } else { profile.removeValue(forKey: "name") }
        player["profile"] = profile
        object["player"] = player
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
