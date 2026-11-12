import Foundation
import Testing
@testable import CatGameCore

@Suite("Cat adoption and independent companions")
struct CatAdoptionTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    @Test func legacySaveKeepsAllProgressAndSelectsItsFirstCat() throws {
        var original = eligibleSnapshot()
        original.cats[0].customName = "团子"
        original.inventory.food = 11
        original.settings.language = .traditionalChinese
        original.player.profile.avatarID = "female_forest"
        _ = GameEngine.startWork(&original, now: now)
        _ = GameEngine.startCatRest(&original, catID: CatCatalog.initialCatID,
            furnitureID: "catBed", sessionID: "legacy-rest", now: now)
        var object = try json(original)
        object["schemaVersion"] = 1
        object.removeValue(forKey: "activeCatID")
        var cats = try #require(object["cats"] as? [[String: Any]])
        for index in cats.indices { cats[index].removeValue(forKey: "appearance") }
        object["cats"] = cats
        let decoded = try decode(object)
        #expect(decoded == expectedCompanionMigration(original))
        #expect(decoded.activeCatID == CatCatalog.initialCatID)
        #expect(decoded.activeCat?.appearance == .orange)
        #expect(decoded.schemaVersion == GameSnapshot.currentSchemaVersion)
    }

    @Test func malformedSelectionRepairsOnlySelectionWithoutRecoveringOlderSave() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(GameSnapshot.fresh(now: now), now: now)
        var expected = eligibleSnapshot()
        #expect(GameEngine.adoptCat(&expected, catID: CatCatalog.cowCatID, now: now).succeeded)
        expected.cats[1].customName = "Milk🐾"
        try await repository.save(expected, now: now)
        let saved = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        for malformed: Any in ["missing-cat", "", 17, false, ["cat_002"], NSNull()] {
            var object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            object["activeCatID"] = malformed
            let bytes = try JSONSerialization.data(withJSONObject: object)
            try bytes.write(to: repository.saveURL)
            let reopened = FileSaveRepository(directory: folder)
            #expect(try await reopened.loadOrCreate(now: now) == expected)
            #expect(await reopened.lastLoadDisposition == .loaded)
            #expect(try Data(contentsOf: repository.saveURL) == bytes)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    @Test func adoptionChecksEachRequirementBeforeChargingAndNeverDuplicates() throws {
        let offer = try #require(CatCatalog.adoptionOffer(catID: CatCatalog.cowCatID))
        #expect(offer.price == 300 && offer.requiredPlayerLevel == 2 && offer.requiredRoomLevel == 2)
        for (level, room, gold, failure, amount) in [
            (1, 1, 900, ActionFailure.catPlayerLevelRequired, 2),
            (2, 1, 900, .catRoomLevelRequired, 2),
            (2, 2, 299, .shopGoldRequired, 300)
        ] {
            var state = eligibleSnapshot()
            state.player.level = level
            state.home.roomLevel = room
            state.player.gold = gold
            let original = state
            let result = GameEngine.adoptCat(&state, catID: offer.id, now: now)
            #expect(result.failure == failure && result.amount == amount)
            #expect(state == original)
        }
        var state = eligibleSnapshot()
        let original = state
        #expect(GameEngine.adoptCat(&state, catID: "missing", now: now).failure == .catAdoptionMissing)
        #expect(state == original)
        let adopted = GameEngine.adoptCat(&state, catID: offer.id, now: now)
        #expect(adopted.succeeded && adopted.amount == offer.price && adopted.kind == .purchase)
        #expect(state.cats.count == 2 && state.player.gold == original.player.gold - offer.price)
        #expect(state.cats[0] == original.cats[0] && state.activeCatID == original.activeCatID)
        #expect(state.home == original.home && state.inventory == original.inventory)
        #expect(state.cats[1].name == "牛奶" && state.cats[1].appearance == .cow)
        let once = state
        #expect(GameEngine.adoptCat(&state, catID: offer.id, now: now).failure == .catAlreadyOwned)
        #expect(state == once)
    }

    @Test func adoptionSynchronizesWorkAndDatesNewCatAtEffectiveTime() {
        var state = eligibleSnapshot()
        state.player.level = 1
        state.player.exp = WorkCatalog.requiredExperience(forLevel: 1) - 1
        state.player.gold = 300
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let finishedAt = state.player.activeWork!.endsAt
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.cowCatID, now: finishedAt).succeeded)
        #expect(state.player.level == 2 && state.player.activeWork == nil)
        #expect(state.cats[1].decayTracker == CatDecayTracker(now: finishedAt))
        #expect(state.cats[1].satiety == 70)

        var rollbackClock = eligibleSnapshot()
        rollbackClock.meta.lastSyncAt = now.addingTimeInterval(100)
        #expect(GameEngine.adoptCat(&rollbackClock, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(rollbackClock.cats[1].decayTracker == CatDecayTracker(now: now.addingTimeInterval(100)))
    }

    @Test func failedAdoptionRetainsOnlyIndependentElapsedProgress() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        let result = GameEngine.adoptCat(&state, catID: CatCatalog.cowCatID, now: now.addingTimeInterval(720))
        #expect(result.failure == .catPlayerLevelRequired)
        #expect(state.player.gold == original.player.gold && state.cats.count == 1)
        #expect(state.cats[0].satiety == original.cats[0].satiety - 1)
        #expect(state.meta.lastSyncAt == now.addingTimeInterval(720))
    }

    @Test func companionSelectionPersistsAlongWithBothNamesAndAppearances() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = adoptedSnapshot()
        state.cats[0].customName = "小太阳"
        state.cats[1].customName = "Milk🐾"
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(state.activeCat?.id == CatCatalog.cowCatID && state.activeCat?.appearance == .cow)
        try await FileSaveRepository(directory: folder).save(state, now: now)
        let reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(reopened == state)
        #expect(reopened.activeCat?.customName == "Milk🐾")
        #expect(reopened.cats[0].customName == "小太阳")
        #expect(reopened.cats.map(\.appearance) == [.orange, .cow])
    }

    @Test func invalidOrRepeatedCompanionSelectionDoesNotAlterCareOrMoney() {
        var state = adoptedSnapshot()
        #expect(GameEngine.startCatRest(&state, catID: CatCatalog.initialCatID,
            furnitureID: "catBed", sessionID: "same-cat", now: now).succeeded)
        let resting = state
        #expect(GameEngine.selectCompanion(&state, catID: "missing", now: now).failure == .careCatMissing)
        #expect(state == resting)
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.initialCatID, now: now).succeeded)
        #expect(state == resting)
        var invalid = state
        invalid.activeCatID = "not-owned"
        #expect(!invalid.isValid)
        let before = invalid
        #expect(GameEngine.selectCompanion(&invalid, catID: CatCatalog.initialCatID, now: now).failure == .gameInvalidState)
        #expect(invalid == before)
    }

    @Test func switchingSettlesActualRestTimeAndRejectsStaleArrivalAndExit() throws {
        var state = adoptedSnapshot()
        state.cats[0].energy = 20
        state.cats[1].energy = 30
        #expect(GameEngine.startCatRest(&state, catID: CatCatalog.initialCatID,
            furnitureID: "catBed", sessionID: "orange-rest", now: now).succeeded)
        let reward = try #require(state.cats[0].activeRest?.energyReward)
        let switchedAt = now.addingTimeInterval(6)
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.cowCatID, now: switchedAt).succeeded)
        #expect(state.cats[0].activeRest == nil && state.cats[0].energy == 20 + reward / 2)
        #expect(state.cats[1].energy == 30)
        #expect(GameEngine.startCatRest(&state, catID: CatCatalog.initialCatID,
            furnitureID: "catBed", sessionID: "late-arrival", now: switchedAt).succeeded)
        #expect(state.cats[0].activeRest == nil)
        #expect(GameEngine.startCatRest(&state, catID: CatCatalog.cowCatID,
            furnitureID: "floorCushion", sessionID: "cow-rest", now: switchedAt).succeeded)
        #expect(GameEngine.endCatRest(&state, catID: CatCatalog.initialCatID,
            sessionID: "orange-rest", now: switchedAt).succeeded)
        #expect(state.cats[1].activeRest?.id == "cow-rest")
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(30))
        #expect(state.cats[0].energy == 20 + reward / 2)
        #expect(state.cats[1].energy == 30 + reward)
        #expect(state.cats.allSatisfy { $0.activeRest == nil })
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.initialCatID,
            now: now.addingTimeInterval(30)).succeeded)
        _ = GameEngine.startCatRest(&state, catID: CatCatalog.initialCatID,
            furnitureID: "catBed", sessionID: "orange-rest", now: now.addingTimeInterval(30))
        #expect(state.cats[0].activeRest == nil)
    }

    @Test func allCatsDecayIndependentlyAndCareChangesOnlyItsTarget() {
        var state = adoptedSnapshot()
        state.inventory.toys = 3
        _ = GameEngine.selectCompanion(&state, catID: CatCatalog.cowCatID, now: now)
        let elapsed = now.addingTimeInterval(720)
        _ = GameEngine.synchronize(&state, now: elapsed)
        #expect(state.cats[0].satiety == 34 && state.cats[1].satiety == 69)
        let orange = state.cats[0]
        #expect(GameEngine.feed(&state, catID: state.activeCatID, now: elapsed).succeeded)
        #expect(GameEngine.clean(&state, catID: state.activeCatID, now: elapsed).succeeded)
        #expect(GameEngine.play(&state, catID: state.activeCatID, now: elapsed).succeeded)
        #expect(state.cats[0] == orange)
        #expect(state.cats[1].satiety == 94 && state.cats[1].cleanliness == 100)
        #expect(state.cats[1].intimacy == 22 && state.cats[1].energy == 73)
        let cow = state.cats[1]
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.initialCatID, now: elapsed).succeeded)
        #expect(GameEngine.feed(&state, catID: state.activeCatID, now: elapsed).succeeded)
        #expect(state.cats[1] == cow && state.cats[0].satiety == 59)
    }

    private func eligibleSnapshot() -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 2
        state.player.gold = 900
        state.home.roomLevel = 2
        return state
    }

    private func adoptedSnapshot() -> GameSnapshot {
        var state = eligibleSnapshot()
        _ = GameEngine.adoptCat(&state, catID: CatCatalog.cowCatID, now: now)
        return state
    }

    private func json(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CatAdoptionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
