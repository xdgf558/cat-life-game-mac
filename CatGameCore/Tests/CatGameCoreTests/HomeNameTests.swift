import Foundation
import Testing
@testable import CatGameCore

@Suite("Custom home names and durable progress")
struct HomeNameTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func namesTrimOnlyOuterSpacesAndNeverTreatBlankInputAsReset() {
        #expect(HomeNameRules.maximumLength == 12)
        #expect(HomeNameRules.normalized("  小橘的家  ") == "小橘的家")
        #expect(HomeNameRules.normalized("\u{3000}\u{00A0}Sunny's Home\u{3000}") == "Sunny's Home")
        #expect(HomeNameRules.normalized("  Cat  Home  ") == "Cat  Home")
        #expect(HomeNameRules.normalized("小屋🐈‍⬛") == "小屋🐈‍⬛")
        for blank in ["", " ", "\u{3000}\u{00A0}"] {
            #expect(HomeNameRules.normalized(blank) == nil)
        }
        #expect(GameSnapshot.fresh(now: now).home.name == nil)
    }

    @Test func twelveVisibleCharactersIncludeWholeEmojiAndCombiningSequences() {
        let englandFlag = "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        for character in ["家", "A", "e\u{301}", "👨‍👩‍👧‍👦", "🐈‍⬛", "👩🏽‍💻", "🇸🇬", "✈️", englandFlag] {
            #expect(character.count == 1)
            let boundary = String(repeating: character, count: 12)
            #expect(HomeNameRules.normalized(boundary) == boundary)
            #expect(HomeNameRules.normalized(" " + boundary + " ") == boundary)
            #expect(HomeNameRules.normalized(boundary + character) == nil)
        }
    }

    @Test func originalNewlinesControlsAndIsolatedInvisibleModifiersAreRejected() {
        for invalid in ["\n小家", "小家\r\n", "\t小家", "小\t家", "小\u{0}家", "小\u{7F}家",
                        "小\u{85}家", "小\u{2028}家", "小\u{2029}家", "小\u{202E}家",
                        "小\u{200B}家", "小\u{2060}家", "\u{200D}", "\u{FE0F}", "\u{E0067}"] {
            #expect(HomeNameRules.normalized(invalid) == nil)
        }
    }

    @Test func missingNameInSchemaOnePreservesEveryOtherFieldAndDoesNotRewrite() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let expected = progressedSnapshot()
        try await repository.save(expected)
        var object = try object(in: Data(contentsOf: repository.saveURL))
        var home = try #require(object["home"] as? [String: Any])
        home.removeValue(forKey: "name")
        object["home"] = home
        let legacy = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try legacy.write(to: repository.saveURL)

        let reopened = FileSaveRepository(directory: folder)
        let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(600))
        #expect(loaded == expected)
        #expect(loaded.home.name == nil && loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(await reopened.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
    }

    @Test func invalidStoredNameFallsBackLocallyWithoutRecoveringAnOlderGame() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now))
        let expected = progressedSnapshot()
        try await repository.save(expected)
        let saved = try object(in: Data(contentsOf: repository.saveURL))
        for value: Any in ["", "   ", String(repeating: "家", count: 13), "小家\n", "\u{200B}", 17, NSNull()] {
            var modified = saved
            var home = try #require(modified["home"] as? [String: Any])
            home["name"] = value
            modified["home"] = home
            let bytes = try JSONSerialization.data(withJSONObject: modified, options: [.sortedKeys])
            try bytes.write(to: repository.saveURL)
            let reopened = FileSaveRepository(directory: folder)
            let loaded = try await reopened.loadOrCreate(now: now)
            #expect(loaded == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
            #expect(try Data(contentsOf: repository.saveURL) == bytes)
        }
        var modified = saved
        var home = try #require(modified["home"] as? [String: Any])
        home["name"] = "  小橘🐈‍⬛的家  "
        modified["home"] = home
        try JSONSerialization.data(withJSONObject: modified).write(to: repository.saveURL)
        var normalized = expected
        normalized.home.name = "小橘🐈‍⬛的家"
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == normalized)
    }

    @Test func customNameAndExplicitDefaultResetSurviveRealSaveAndColdReload() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var expected = progressedSnapshot()
        expected.home.furniture = []
        expected.home.name = "橘屋👨‍👩‍👧‍👦🐈‍⬛"
        try await FileSaveRepository(directory: folder).save(expected)
        let named = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(600))
        #expect(named == expected)
        #expect(named.settings.language == .traditionalChinese)
        #expect(named.home.furniture.isEmpty && named.inventory.furniture.count == 9)

        expected.home.name = nil
        try await FileSaveRepository(directory: folder).save(expected)
        let restored = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(restored == expected)
        #expect(restored.home.name == nil)
    }

    @Test func invalidOrUntrimmedRuntimeNameCannotOverwritePrimaryOrBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now))
        var valid = progressedSnapshot()
        valid.home.name = "茶香小屋🐈"
        try await repository.save(valid)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        for name in ["", " 小家", "小家 ", "小家\n", String(repeating: "家", count: 13), "\u{200D}"] {
            var invalid = valid
            invalid.home.name = name
            #expect(!invalid.isValid)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid) }
            #expect(try Data(contentsOf: repository.saveURL) == primary)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == valid)
    }

    private func progressedSnapshot() -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.settings.language = .traditionalChinese
        state.player.gold = 125
        state.player.completedWorkCount = 9
        state.player.activeWork = ActiveWork(id: "kept-work", startedAt: now,
                                             endsAt: now.addingTimeInterval(120), goldReward: 60)
        state.inventory.food = 11
        state.inventory.litter = 7
        state.inventory.toys = 5
        state.cats[0].name = "用户的小猫"
        state.cats.append(CatState(id: "kept-kitten", name: "小白", now: now))
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
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatHomeNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
