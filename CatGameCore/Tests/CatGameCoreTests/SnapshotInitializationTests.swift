import Foundation
import Testing
@testable import CatGameCore

@Suite("Snapshot construction preserves history and fresh games initialize real places")
struct SnapshotInitializationTests {
    private let now = Date(timeIntervalSince1970: 1_794_500_000)

    @Test func initializerPreservesSuppliedCatsWithoutAddingRestLocations() throws {
        let empty = CatState(id: CatCatalog.initialCatID, name: "小橘", now: now)
        var recorded = CatState(id: CatCatalog.cowCatID, name: "牛奶", now: now, appearance: .cow)
        recorded.habits.restLocations["catBed"] = .init(
            reference: .init(floor: .upper, position: .init(x: 0.3, y: 0.4)), visited: true)
        recorded.habits.restLocations["stored-cushion"] = .init(
            reference: .init(floor: .ground, position: .init(x: 0.6, y: 0.7)))
        let cats = [empty, recorded]
        let snapshot = GameSnapshot(player: PlayerState(staminaUpdatedAt: now), cats: cats,
            inventory: InventoryState(), home: HomeState(), meta: SaveMetadata(createdAt: now, lastSyncAt: now))

        #expect(snapshot.cats == cats)
        #expect(snapshot.cats[0].habits.restLocations.isEmpty)
        #expect(snapshot.cats[1].habits.restLocations["floorCushion"] == nil)
        #expect(snapshot.isValid)
        let loaded = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(loaded == snapshot, "Current-schema reload must preserve empty and partial histories without seeding them.")
    }

    @Test func freshGameSeedsOnlyCurrentRestPlacementsWithoutInventingVisitsOrMemories() throws {
        let snapshot = GameSnapshot.fresh(now: now)
        let cat = try #require(snapshot.activeCat)
        #expect(snapshot.isValid)
        #expect(Set(cat.habits.restLocations.keys) == Set(["catBed", "floorCushion"]))
        for itemID in ["catBed", "floorCushion"] {
            let placement = try #require(snapshot.home.furniture.first { $0.itemID == itemID })
            #expect(snapshot.inventory.furniture.contains { $0.id == itemID })
            #expect(cat.habits.restLocations[itemID] == CatRestLocationRecord(
                reference: .init(floor: placement.floor, position: placement.position)))
        }
        #expect(cat.habits.restClueSessionIDs.isEmpty && cat.habits.memories.isEmpty)
        #expect(cat.habits.lastRestObservation == nil && cat.habits.legacyRestSessionID == nil)
        #expect(cat.activeRest == nil)
    }
}
