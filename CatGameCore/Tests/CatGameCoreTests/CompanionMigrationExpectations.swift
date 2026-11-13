import Foundation
@testable import CatGameCore

/// Expected new v14 fields only; every pre-existing snapshot field remains available for whole-value equality.
func expectedCompanionMigration(_ original: GameSnapshot) -> GameSnapshot {
    var expected = original
    for index in expected.cats.indices {
        expected.cats[index].habits.restLocations = expectedRestReferences(home: expected.home, inventory: expected.inventory)
        expected.cats[index].habits.pinnedMemory = nil
        expected.cats[index].habits.pinnedHintCollapsed = false
        expected.cats[index].habits.responseFinishIndex = 0
        expected.cats[index].habits.legacyRestSessionID = expected.cats[index].activeRest?.id
    }
    return expected
}

func expectedRestReferences(home: HomeState, inventory: InventoryState) -> [String: CatRestLocationRecord] {
    var records: [String: CatRestLocationRecord] = [:]
    for placement in home.furniture {
        guard let item = inventory.furniture.first(where: { $0.id == placement.itemID }),
              item.kind == .catBed || item.kind == .floorCushion else { continue }
        records[placement.itemID] = CatRestLocationRecord(reference: CatRestObservation(
            floor: placement.floor, position: placement.position), visited: false)
    }
    return records
}
