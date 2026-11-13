import Foundation
import Testing
@testable import CatGameCore

@Suite("Front-room starter layout migration preserves player arrangements")
struct FrontStarterLayoutMigrationTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    private func oldStarter() throws -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.home.furniture = FurnitureCatalog.legacyPlacementsV6
        state.home.roomLevel = 3
        state.home.name = "Saved home"
        state.player.level = 4
        state.player.gold = 987
        state.player.profile.name = "Milo"
        state.cats[0].customName = "豆豆"
        state.inventory.food = 8
        state.inventory.litter = 9
        state.inventory.toys = 6
        state.tasks.totalFeedCount = 5
        try #require(state.isValid)
        try #require(GameEngine.visitNeighbor(&state, neighborID: "neighbor_mira", now: now).succeeded)
        try #require(state.isValid)
        return state
    }

    private func reload(_ state: GameSnapshot, schema: Int = 12) throws -> GameSnapshot {
        var saved = state
        saved.schemaVersion = schema
        return try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(saved))
    }

    private func companionMigrated(_ state: GameSnapshot) -> GameSnapshot {
        var expected = state
        for index in expected.cats.indices {
            expected.cats[index].habits.restLocations = [:]
            expected.cats[index].habits.seedRestLocations(home: expected.home, inventory: expected.inventory)
            expected.cats[index].habits.legacyRestSessionID = expected.cats[index].activeRest?.id
        }
        return expected
    }

    private func reflowed(_ state: GameSnapshot) -> GameSnapshot {
        var expected = state
        let positions = Dictionary(uniqueKeysWithValues: FurnitureCatalog.frontPlacementsV13.map { ($0.itemID, $0.position) })
        for index in expected.home.furniture.indices {
            if let position = positions[expected.home.furniture[index].itemID] { expected.home.furniture[index].position = position }
        }
        return companionMigrated(expected)
    }

    @Test func untouchedV12StarterReflowsRegardlessOfOrderWithoutChangingProgressOrUnplacedPurchases() throws {
        for reversed in [false, true] {
            var original = try oldStarter()
            #expect(GameEngine.purchaseFurniture(&original, offerID: "potted_plant", now: now).succeeded)
            #expect(GameEngine.startWork(&original, now: now).succeeded)
            if reversed { original.home.furniture.reverse() }
            let loaded = try reload(original)
            #expect(loaded == reflowed(original))
            #expect(loaded.isValid && loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
            #expect(loaded.home.furniture.map(\.itemID) == original.home.furniture.map(\.itemID))
            #expect(loaded.inventory == original.inventory && loaded.player == original.player)
            #expect(loaded.cats == reflowed(original).cats && loaded.tasks == original.tasks && loaded.community == original.community)
            #expect(try reload(loaded, schema: 13) == loaded)
            #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: loaded, exportedAt: now), now: now).snapshot == loaded)
        }
    }

    @Test func customizedStoredMirroredExpandedAndUpstairsLayoutsRemainExactlyAsSaved() throws {
        let original = try oldStarter()
        var moved = original
        moved.home.furniture[0].position.x += 0.001
        var bowl = original
        bowl.home.bowlPosition.x += 0.001
        var mirrored = original
        mirrored.inventory.furniture[0].orientation = .left
        var differentKind = original
        differentKind.inventory.furniture[0].kind = .bookcase
        var stored = original
        stored.home.furniture.removeAll { $0.itemID == "plantSmall" }
        var placedExtra = original
        #expect(GameEngine.purchaseFurniture(&placedExtra, offerID: "potted_plant", now: now).succeeded)
        let extra = try #require(placedExtra.inventory.furniture.last)
        placedExtra.home.furniture.append(.init(itemID: extra.id, position: .init(x: 0.6, y: 0.8)))
        var upper = original
        upper.home = HomeState(furniture: original.home.furniture, name: original.home.name, roomLevel: 6)
        var upstairsItem = upper
        upstairsItem.home.furniture[0].floor = .upper
        for state in [moved, bowl, mirrored, differentKind, stored, placedExtra, upper, upstairsItem] {
            #expect(state.isValid)
            #expect(try reload(state) == expectedLegacyFootprintMigration(companionMigrated(state)))
        }
    }

    @Test func anyCatsActiveRestChosenCornerAndUndismissedObservationPreventReflow() throws {
        var starter = try oldStarter()
        #expect(GameEngine.adoptCat(&starter, catID: CatCatalog.cowCatID, now: now).succeeded)
        for index in starter.cats.indices {
            var resting = starter
            resting.activeCatID = resting.cats[index].id
            #expect(GameEngine.startCatRest(&resting, catID: resting.activeCatID, furnitureID: "catBed",
                                            sessionID: "rest-\(index)", now: now).succeeded)
            resting.activeCatID = starter.activeCatID
            #expect(try reload(resting) == companionMigrated(resting))

            var observed = starter
            observed.cats[index].habits.lastRestObservation = .init(id: "offer-\(index)", furnitureID: "catBed", kind: .bed,
                location: .init(floor: .ground, position: try #require(observed.home.furniture.first { $0.itemID == "catBed" }?.position)),
                completedAt: now, matched: index == 1)
            #expect(observed.isValid)
            #expect(try reload(observed) == companionMigrated(observed))

            var corner = observed
            #expect(CatHabitEngine.chooseCorner(&corner, catID: corner.cats[index].id,
                                                observationID: "offer-\(index)", now: now).succeeded)
            #expect(try reload(corner) == companionMigrated(corner))
        }
    }

    @Test func dismissedObservationKeepsItsHistoryWhileAllowingUntouchedStarterReflow() throws {
        var original = try oldStarter()
        original.cats[0].habits.lastRestObservation = .init(id: "dismissed-rest", furnitureID: "floorCushion", kind: .cushion,
            location: .init(floor: .ground, position: try #require(original.home.furniture.first { $0.itemID == "floorCushion" }?.position)),
            completedAt: now, matched: true)
        original.cats[0].habits.dismissedRestOfferID = "dismissed-rest"
        original.cats[0].habits.restClueSessionIDs = ["dismissed-rest"]
        let loaded = try reload(original)
        #expect(loaded == reflowed(original) && loaded.isValid)
        #expect(loaded.cats == reflowed(original).cats)
    }

    @Test func activePlaySessionAndItsUnspentTutorialKeepAllOldPlacementCoordinates() throws {
        var original = try oldStarter()
        #expect(CatHabitEngine.beginPlay(&original, catID: original.activeCatID, now: now).succeeded)
        #expect(original.catPlay.activeSession != nil)
        #expect(try reload(original) == companionMigrated(original))
    }

    @Test func schema13NeverReappliesReflowToAnOldLayoutThePlayerChoseAgain() throws {
        let oldChoice = try oldStarter()
        #expect(try reload(oldChoice, schema: 13) == companionMigrated(oldChoice))
        #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: oldChoice, exportedAt: now), now: now).snapshot == oldChoice)
    }

    @Test func frozenPreSixCushionMigrationChainsIntoFrontReflowOnlyForUntouchedRooms() throws {
        for schema in 1...5 {
            var original = try oldStarter()
            let cushion = try #require(original.home.furniture.firstIndex { $0.itemID == "floorCushion" })
            original.home.furniture[cushion].position.x = 0.12
            #expect(try reload(original, schema: schema) == reflowed(original))
        }
    }

    @Test func oldMissingFurnitureFallbackDoesNotBypassActiveRestProtection() throws {
        var original = try oldStarter()
        #expect(GameEngine.startCatRest(&original, catID: original.activeCatID, furnitureID: "catBed",
                                        sessionID: "missing-placement-rest", now: now).succeeded)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["schemaVersion"] = 12
        var home = try #require(object["home"] as? [String: Any])
        home.removeValue(forKey: "furniture")
        object["home"] = home
        let loaded = try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
        #expect(loaded == companionMigrated(original))
    }
}
