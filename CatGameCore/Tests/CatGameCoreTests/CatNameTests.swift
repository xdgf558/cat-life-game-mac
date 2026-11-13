import Foundation
import Testing
@testable import CatGameCore

@Suite("Individual cat names and compatible saves")
struct CatNameTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func namesUseVisibleGraphemeLimitsAndRejectInvisibleInput() {
        #expect(CatNameRules.maximumLength == 12)
        #expect(CatNameRules.normalized("  小橘  ") == "小橘")
        #expect(CatNameRules.normalized("\u{3000}Oliver Cat\u{3000}") == "Oliver Cat")
        for character in ["橘", "A", "e\u{301}", "🐈‍⬛", "👨‍👩‍👧‍👦"] {
            let boundary = String(repeating: character, count: 12)
            #expect(CatNameRules.normalized(boundary) == boundary)
            #expect(CatNameRules.normalized(boundary + character) == nil)
        }
        for invalid in ["", "   ", "Cat\n", "C\tat", "\u{200B}", "\u{200D}", "\u{FE0F}",
                        "小\u{034F}橘", "\u{115F}", "\u{3164}", "\u{FFA0}", "\u{2800}"] {
            #expect(CatNameRules.normalized(invalid) == nil)
        }
    }

    @Test func oldCatsWithoutOverridesLoadWithoutRewritingAnyProgress() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now), now: now)
        let expected = progressedSnapshot()
        try await repository.save(expected, now: now)
        let legacy = try replacingName(in: Data(contentsOf: repository.saveURL), with: nil)
        try legacy.write(to: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        let reopened = FileSaveRepository(directory: folder)
        #expect(try await reopened.loadOrCreate(now: now.addingTimeInterval(600)) == expected)
        #expect(await reopened.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(expected.cats.allSatisfy { $0.customName == nil })
    }

    @Test func malformedOverrideRecoversOnlyThatFieldAndNeverAnOlderBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now), now: now)
        var original = progressedSnapshot()
        original.cats[0].customName = "团子"
        original.cats[1].customName = "Clover"
        try await repository.save(original, now: now)
        let saved = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        var expected = original
        expected.cats[0].customName = nil
        for malformed: Any in [NSNull(), 17, false, ["cat"], ["unexpected": "name"], "", "  ",
                               "Cat\n", "\u{200B}", "\u{3164}", String(repeating: "橘", count: 13)] {
            let bytes = try replacingName(in: saved, with: malformed)
            try bytes.write(to: repository.saveURL)
            let reopened = FileSaveRepository(directory: folder)
            #expect(try await reopened.loadOrCreate(now: now) == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
            #expect(try Data(contentsOf: repository.saveURL) == bytes)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    @Test func savedOverridesNormalizeWhileExplicitDefaultNameRemainsAnOverride() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = progressedSnapshot()
        try await repository.save(original, now: now)
        let saved = try Data(contentsOf: repository.saveURL)
        for (raw, normalized) in [("  小橘  ", "小橘"), ("\u{3000}Oliver Cat\u{3000}", "Oliver Cat"),
                                  ("  🐈‍⬛  ", "🐈‍⬛")] {
            let bytes = try replacingName(in: saved, with: raw)
            try bytes.write(to: repository.saveURL)
            let loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
            var expected = original
            expected.cats[0].customName = normalized
            #expect(loaded == expected)
            #expect(loaded.cats[0].name == "小橘")
            #expect(try Data(contentsOf: repository.saveURL) == bytes)
        }
    }

    @Test func independentNamesAndDefaultResetRoundTripWithWorkAndRestUntouched() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = progressedSnapshot()
        #expect(original.player.activeWork?.quote != nil && original.cats[0].activeRest != nil)
        var expected = original
        for (id, name) in [("cat_001", Optional("小橘")), ("generated-cat", Optional("Nora🐾")),
                           ("cat_001", nil), ("generated-cat", nil)] {
            let index = try #require(expected.cats.firstIndex { $0.id == id })
            expected.cats[index].customName = name
            try await FileSaveRepository(directory: folder).save(expected, now: now)
            let loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(600))
            #expect(loaded == expected)
            #expect(loaded.player == original.player && loaded.inventory == original.inventory)
            #expect(loaded.cats[0].activeRest == original.cats[0].activeRest)
            #expect(loaded.cats.map(\.name) == original.cats.map(\.name))
            #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        }
        #expect(expected == original)
    }

    @Test func invalidRuntimeOverridesCannotOverwritePrimaryOrBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now), now: now)
        let original = progressedSnapshot()
        try await repository.save(original, now: now)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        for invalid in ["", "  ", " untrimmed ", "Cat\n", "\u{200B}", "\u{3164}", String(repeating: "🐈‍⬛", count: 13)] {
            var candidate = original
            candidate.cats[1].customName = invalid
            #expect(!candidate.isValid)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) {
                try await repository.save(candidate, now: now)
            }
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
        value.settings.language = .traditionalChinese
        value.cats[0].energy = 40
        value.cats.append(CatState(id: "generated-cat", name: "Mochi", mood: 42, isPregnant: true, now: now,
            growthState: .init(recordedSince: now, adoptedAt: now, initialAgeDays: 365, sex: .female)))
        _ = GameEngine.equipStarterSet(&value, now: now)
        _ = GameEngine.startWork(&value, jobID: "job_petshop", now: now)
        _ = GameEngine.startCatRest(&value, catID: "cat_001", furnitureID: "catBed", sessionID: "cat-name-rest", now: now)
        return value
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CatNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func replacingName(in data: Data, with name: Any?) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var cats = try #require(object["cats"] as? [[String: Any]])
        if let name { cats[0]["customName"] = name } else { cats[0].removeValue(forKey: "customName") }
        object["cats"] = cats
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
