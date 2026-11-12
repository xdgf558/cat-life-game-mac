#if os(macOS)
import Foundation
import CatGameCore

/// Mac geometry is adapted before publishing a loaded or imported timeline.
/// The repository remains responsible for the single atomic durable commit.
enum MacRoomSaveRepair {
    enum RepairError: Error { case unavailableLayout, invalidCandidate }

    static func prepare(_ original: GameSnapshot, now: Date, isNewHome: Bool = false) async throws -> GameSnapshot {
        try await Task.detached(priority: .userInitiated) {
            guard let plan = MacRoomLayoutRepair.plan(original, isNewHome: isNewHome) else { throw RepairError.unavailableLayout }
            return try applying(plan, to: original, now: now)
        }.value
    }

    static func applying(_ plan: MacRoomLayoutRepair.Plan, to original: GameSnapshot, now: Date) throws -> GameSnapshot {
        let previous = Dictionary(uniqueKeysWithValues: original.home.furniture.map { ($0.itemID, $0) })
        let proposedIDs = Set(plan.placements.map(\.itemID))
        guard proposedIDs.count == plan.placements.count,
              proposedIDs.isSubset(of: Set(previous.keys)),
              plan.placements.allSatisfy({ previous[$0.itemID]?.floor == $0.floor }),
              Set(plan.bowlPositions.keys) == Set(original.home.availableFloors) else { throw RepairError.invalidCandidate }
        let moved = plan.placements.filter { previous[$0.itemID] != $0 }
        let removed = Set(previous.keys).subtracting(proposedIDs)
        let bowlChanged = plan.bowlPositions.contains { original.home.bowlPosition(on: $0.key) != $0.value }
        guard !moved.isEmpty || !removed.isEmpty || bowlChanged else { return original }

        // Finish real elapsed care against the old layout before moving anything.
        var candidate = original
        guard GameEngine.synchronize(&candidate, now: now).succeeded else { throw RepairError.invalidCandidate }
        for cat in candidate.cats {
            if let rest = cat.activeRest {
                guard GameEngine.endCatRest(&candidate, catID: cat.id, sessionID: rest.id, now: now).succeeded
                else { throw RepairError.invalidCandidate }
            }
        }
        candidate.home.furniture = plan.placements
        candidate.inventory.furniture = candidate.inventory.furniture.map { item in
            removed.contains(item.id) ? item.applyingPlacement(from: previous[item.id], to: nil) : item
        }
        for (floor, point) in plan.bowlPositions { candidate.home.setBowlPosition(point, on: floor) }
        for index in candidate.cats.indices {
            for placement in moved {
                guard var known = candidate.cats[index].habits.restLocations[placement.itemID] else { continue }
                known.reference = .init(floor: placement.floor, position: placement.position)
                candidate.cats[index].habits.restLocations[placement.itemID] = known
            }
            if let corner = candidate.cats[index].habits.cornerFurnitureID, removed.contains(corner) {
                candidate.cats[index].habits.cornerFurnitureID = nil
            }
        }
        do { _ = try NativeSaveTransfer.encode(snapshot: candidate, exportedAt: now) }
        catch { throw RepairError.invalidCandidate }
        return candidate
    }
}
#endif
