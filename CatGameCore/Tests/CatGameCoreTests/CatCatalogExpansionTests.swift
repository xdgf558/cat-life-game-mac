import Foundation
import Testing
@testable import CatGameCore

@Suite("Blue cat adoption and schema 6 compatibility")
struct CatCatalogExpansionTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    private func eligibleSnapshot() -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 4
        state.player.gold = 2_000
        state.home.roomLevel = 3
        return state
    }

    private func json(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    @Test func blueOfferKeepsStableIdentityAndChecksEachRequirementBeforeCharging() throws {
        let offer = try #require(CatCatalog.adoptionOffer(catID: CatCatalog.blueCatID))
        #expect(offer.id == "cat_003" && offer.name == "蓝影" && offer.appearance == .blue)
        #expect(offer.price == 600 && offer.requiredPlayerLevel == 4 && offer.requiredRoomLevel == 3)
        #expect(CatAppearance.allCases == [.orange, .cow, .blue, .siamese, .silver])
        #expect(Set(CatCatalog.adoptionOffers.map(\.id)).count == CatCatalog.adoptionOffers.count)
        for (level, room, gold, failure, amount) in [
            (3, 3, 2_000, ActionFailure.catPlayerLevelRequired, 4),
            (4, 2, 2_000, .catRoomLevelRequired, 3),
            (4, 3, 599, .shopGoldRequired, 600)
        ] {
            var state = eligibleSnapshot()
            state.player.level = level
            state.home.roomLevel = room
            state.player.gold = gold
            let original = state
            let outcome = GameEngine.adoptCat(&state, catID: offer.id, now: now)
            #expect(outcome.failure == failure && outcome.amount == amount)
            #expect(state == original)
        }
    }

    @Test func blueCanBeAdoptedWithoutCowAndChargesOnceWithoutChangingCompanion() {
        var state = eligibleSnapshot()
        state.player.gold = 600
        let original = state
        let outcome = GameEngine.adoptCat(&state, catID: CatCatalog.blueCatID, now: now)
        #expect(outcome.success == .catAdopted && outcome.amount == 600 && state.player.gold == 0)
        #expect(state.cats.map(\.id) == [CatCatalog.initialCatID, CatCatalog.blueCatID])
        #expect(state.activeCatID == original.activeCatID && state.cats[0] == original.cats[0])
        var expectedCat = CatState(id: CatCatalog.blueCatID, name: "蓝影", satiety: 70,
            cleanliness: 85, mood: 80, intimacy: 10, energy: 85, health: 100, now: now, appearance: .blue)
        expectedCat.habits.restLocations = expectedRestReferences(home: original.home, inventory: original.inventory)
        #expect(state.cats[1] == expectedCat)
        #expect(state.home == original.home && state.inventory == original.inventory && state.tasks == original.tasks)
        let once = state
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.blueCatID, now: now).failure == .catAlreadyOwned)
        #expect(state == once)
    }

    @Test func threeCatsKeepIndependentCareAndBlueHealthStartsAtEffectiveTime() throws {
        var state = eligibleSnapshot()
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.cowCatID, now: now).succeeded)
        let future = now.addingTimeInterval(100)
        #expect(GameEngine.synchronize(&state, now: future).succeeded)
        let otherCats = state.cats
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.blueCatID, now: now).succeeded)
        #expect(Array(state.cats.prefix(2)) == otherCats && state.activeCatID == CatCatalog.cowCatID)
        #expect(state.cats[2].healthState == CatHealthState(now: future))
        #expect(state.cats[2].decayTracker == CatDecayTracker(now: future))
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.blueCatID, now: future).succeeded)
        #expect(GameEngine.feed(&state, catID: CatCatalog.blueCatID, now: future).succeeded)
        #expect(GameEngine.clean(&state, catID: CatCatalog.blueCatID, now: future).succeeded)
        #expect(Array(state.cats.prefix(2)) == otherCats)
        #expect(state.cats[2].satiety == 95 && state.cats[2].cleanliness == 100)
        #expect(state.cats[2].healthState == CatHealthState(now: future))
        #expect(state.activeCat?.appearance == .blue && state.isValid)
    }

    @Test func schemaOneThroughFivePreserveExistingProgressAndClaimReceipts() throws {
        var original = eligibleSnapshot()
        #expect(GameEngine.adoptCat(&original, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(GameEngine.selectCompanion(&original, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(GameEngine.purchaseFurniture(&original, offerID: "potted_plant", now: now).succeeded)
        #expect(GameEngine.feed(&original, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(GameEngine.clean(&original, catID: CatCatalog.cowCatID, now: now).succeeded)
        for id in ["tutorial_feed", "tutorial_clean", "tutorial_furniture", "daily_feed", "daily_clean"] {
            #expect(GameEngine.claimTask(&original, id: id, expectedDayKey: original.tasks.dailyDayKey, now: now).succeeded)
        }
        original.player.completedWorkCount = 17
        original.player.profile.name = "Milo"
        original.player.profile.avatarID = "female_forest"
        original.cats[0].customName = "团子"
        original.cats[1].customName = "Milk🐾"
        original.cats[1].healthState?.illness = .cold
        original.cats[1].healthState?.riskPoints = CatHealthCatalog.illnessRiskThreshold
        original.home.name = "Quiet home"
        original.settings.language = .traditionalChinese
        original.settings.audio.musicVolume = 0.2
        #expect(GameEngine.startWork(&original, now: now).succeeded)
        #expect(GameEngine.startCatRest(&original, catID: CatCatalog.cowCatID,
            furnitureID: "catBed", sessionID: "migrating-rest", now: now).succeeded)
        for version in 1...5 {
            var object = try json(original)
            object["schemaVersion"] = version
            var loaded = try decode(object)
            let expected = expectedCompanionMigration(original)
            #expect(loaded == expected && loaded.schemaVersion == GameSnapshot.currentSchemaVersion && loaded.isValid)
            #expect(loaded.cats.map(\.appearance) == [.orange, .cow])
            #expect(GameEngine.claimTask(&loaded, id: "tutorial_furniture", now: now).failure == .taskAlreadyClaimed)
            #expect(GameEngine.claimTask(&loaded, id: "daily_clean", expectedDayKey: loaded.tasks.dailyDayKey,
                                         now: now).failure == .taskAlreadyClaimed)
            #expect(loaded == expected)
        }
    }

    @Test func schemaSixPersistsBlueNameSelectionHealthAndRestWithoutDowngradingHeader() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BlueCat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = eligibleSnapshot()
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.blueCatID, now: now).succeeded)
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.blueCatID, now: now).succeeded)
        state.cats[2].customName = "Moon🐾"
        state.cats[2].energy = 20
        state.cats[2].healthState?.riskPoints = 3
        #expect(GameEngine.startCatRest(&state, catID: CatCatalog.blueCatID,
            furnitureID: "catBed", sessionID: "blue-rest", now: now).succeeded)
        try await repository.save(state, now: now)
        let saved = try Data(contentsOf: repository.saveURL)
        let object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == GameSnapshot.currentSchemaVersion)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == state)
        var stale = state
        stale.schemaVersion = 5
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(5)) {
            try await repository.save(stale, now: now)
        }
        #expect(try Data(contentsOf: repository.saveURL) == saved)
    }

    @Test func futureAppearanceIsRejectedBySchemaBeforeDecodeAndCannotRestoreOlderBackup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatSchema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = eligibleSnapshot()
        try await repository.save(state, now: now)
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.blueCatID, now: now).succeeded)
        try await repository.save(state, now: now)
        let backup = try Data(contentsOf: repository.backupURL)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        let futureSchema = GameSnapshot.currentSchemaVersion + 1
        object["schemaVersion"] = futureSchema
        var cats = try #require(object["cats"] as? [[String: Any]])
        cats[1]["appearance"] = "future-appearance"
        object["cats"] = cats
        let futureSave = try JSONSerialization.data(withJSONObject: object)
        try futureSave.write(to: repository.saveURL)
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(futureSchema)) {
            try await repository.loadOrCreate(now: now)
        }
        #expect(try Data(contentsOf: repository.saveURL) == futureSave)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }
}
