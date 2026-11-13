import Foundation
import Testing
@testable import CatGameCore

@Suite("Full-height starter room compatibility")
struct StarterLayoutMigrationTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    private func legacyStarter() throws -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.home.furniture = FurnitureCatalog.legacyPlacementsV6
        let cushion = try #require(state.home.furniture.firstIndex { $0.itemID == "floorCushion" })
        state.home.furniture[cushion].position.x = 0.12
        return state
    }

    private func reload(_ state: GameSnapshot, schema: Int) throws -> GameSnapshot {
        var encoded = state
        encoded.schemaVersion = schema
        return try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(encoded))
    }

    @Test func frozenSchemaSixStarterPlacesCushionInsideFullHeightFloor() throws {
        var state = GameSnapshot.fresh(now: now)
        state.home.furniture = FurnitureCatalog.legacyPlacementsV6
        let cushion = try #require(state.home.furniture.first { $0.itemID == "floorCushion" })
        #expect(cushion.position == NormalizedPoint(x: 0.22, y: 0.7))
        #expect(state.isValid)
    }

    @Test func completeLegacyStarterMigratesOnlyCushionRegardlessOfOrder() throws {
        for version in 1...5 {
            for reversed in [false, true] {
                var original = try legacyStarter()
                original.home.roomLevel = 3
                original.home.name = "Saved home"
                original.player.gold = 723
                original.player.profile.name = "Milo"
                original.cats[0].customName = "豆豆"
                let item = try #require(original.inventory.furniture.firstIndex { $0.id == "floorCushion" })
                original.inventory.furniture[item].orientation = .left
                let catID = original.activeCatID
                try #require(original.isValid)
                try #require(GameEngine.startCatRest(&original, catID: catID,
                    furnitureID: "floorCushion", sessionID: "saved-cushion-rest", now: now).succeeded)
                try #require(original.cats[0].activeRest != nil)
                if reversed { original.home.furniture.reverse() }
                var expected = original
                let cushion = try #require(expected.home.furniture.firstIndex { $0.itemID == "floorCushion" })
                expected.home.furniture[cushion].position.x = 0.22
                expected = try expectedLegacyFootprintMigration(expectedCompanionMigration(expected))
                let loaded = try reload(original, schema: version)
                #expect(loaded == expected)
                #expect(loaded.isValid && loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
                #expect(loaded.home.furniture.map(\.itemID) == original.home.furniture.map(\.itemID))
                #expect(try reload(loaded, schema: 6) == loaded)
            }
        }
    }

    @Test func customizedStoredOrExpandedLayoutsNeverMoveOrRestoreAnyFurniture() throws {
        let original = try legacyStarter()
        var movedBed = original
        var movedBowl = original
        movedBowl.home.bowlPosition = .init(x: 0.22, y: 0.7)
        let bed = try #require(movedBed.home.furniture.firstIndex { $0.itemID == "catBed" })
        movedBed.home.furniture[bed].position.x += 0.001
        var movedCushion = original
        let cushion = try #require(movedCushion.home.furniture.firstIndex { $0.itemID == "floorCushion" })
        movedCushion.home.furniture[cushion].position.x = 0.121
        var storedCushion = original
        storedCushion.home.furniture.removeAll { $0.itemID == "floorCushion" }
        var storedOtherItem = original
        storedOtherItem.home.furniture.removeAll { $0.itemID == "wallCat" }
        var newlyPlaced = original
        newlyPlaced.home.roomLevel = 2
        newlyPlaced.inventory.furniture.append(.init(id: "custom-plant", kind: .plant))
        newlyPlaced.home.furniture.append(.init(itemID: "custom-plant", position: .init(x: 0.6, y: 0.8)))
        var emptyRoom = original
        emptyRoom.home.furniture = []
        for state in [movedBowl, movedBed, movedCushion, storedCushion, storedOtherItem, newlyPlaced, emptyRoom] {
            #expect(state.isValid)
            #expect(try reload(state, schema: 5) == expectedCompanionMigration(state))
        }
    }

    @Test func schemaSixDoesNotReapplyMigrationToAPlayerChosenOldPosition() throws {
        let original = try legacyStarter()
        #expect(try reload(original, schema: 6) == expectedCompanionMigration(original))
        var upgraded = try reload(original, schema: 5)
        let cushion = try #require(upgraded.home.furniture.firstIndex { $0.itemID == "floorCushion" })
        upgraded.home.furniture[cushion].position.x = 0.12
        #expect(try reload(upgraded, schema: 6) == expectedCompanionMigration(upgraded))
    }
}
