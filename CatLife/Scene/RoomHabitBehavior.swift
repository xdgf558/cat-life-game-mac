import Foundation
import CoreGraphics
import CatGameCore

struct RoomHabitOpening: Sendable {
    let catID: String
    let floor: HomeFloor
    let preference: CatRestPreference
    let cornerID: String?
    let kindRoll: Double
    let instanceRoll: Double
}

/// Preference chooses a kind first, so buying extra cushions cannot dilute the bed preference.
enum RoomHabitBehavior {
    static func restingFurniture(placements: [FurniturePlacement], items: [FurnitureItem],
                                 floor: HomeFloor, preference: CatRestPreference?, cornerID: String?,
                                 kindRoll: Double, instanceRoll: Double) -> FurniturePlacement? {
        let candidates = placements.filter { placement in
            placement.floor == floor && items.contains { $0.id == placement.itemID && CatRestPreference(kind: $0.kind) != nil }
        }
        guard let preference else {
            return weighted(candidates.sorted { $0.itemID < $1.itemID }, roll: instanceRoll,
                            weight: { $0.itemID == cornerID ? 3 : 1 })
        }
        let kinds = CatRestPreference.allCases.filter { kind in
            candidates.contains { placement in items.contains { $0.id == placement.itemID && $0.kind == kind.furnitureKind } }
        }
        let cornerKind = candidates.first { $0.itemID == cornerID }.flatMap { placement in
            items.first { $0.id == placement.itemID }.flatMap { CatRestPreference(kind: $0.kind) }
        }
        guard let kind = weighted(kinds, roll: kindRoll, weight: { $0 == preference || $0 == cornerKind ? 3 : 1 }) else { return nil }
        let instances = candidates.filter { placement in
            items.contains { $0.id == placement.itemID && $0.kind == kind.furnitureKind }
        }.sorted { $0.itemID < $1.itemID }
        return weighted(instances, roll: instanceRoll, weight: { $0.itemID == cornerID ? 3 : 1 })
    }

    static func openingRequest(cat: CatState, floor: HomeFloor, roll: Double,
                               kindRoll: Double, instanceRoll: Double) -> RoomHabitOpening? {
        guard roll.isFinite, roll >= 0, roll < 0.5, canUseOpening(cat),
              let preference = CatHabitCatalog.definition(for: cat.id)?.rest else { return nil }
        return .init(catID: cat.id, floor: floor, preference: preference, cornerID: cat.habits.cornerFurnitureID,
                     kindRoll: kindRoll, instanceRoll: instanceRoll)
    }

    static func canUseOpening(_ cat: CatState) -> Bool {
        cat.activeRest == nil && cat.energy >= 40
            && (cat.habits.restConfirmed || cat.habits.cornerFurnitureID != nil)
            && CatNeed.current(satiety: cat.satiety, cleanliness: cat.cleanliness, mood: cat.mood,
                               hasFood: true, isIll: cat.healthState?.illness != nil) == nil
            && CatHabitCatalog.definition(for: cat.id) != nil
    }

    /// Called by the existing layout worker before other cats are placed, never by a frame callback.
    static func openingPoint(_ opening: RoomHabitOpening, world: RoomFurnitureWorld,
                             origin: CGPoint, navigation: RoomNavigation) -> CGPoint? {
        let eligible = world.placements.filter { placement in
            placement.floor == opening.floor && world.items.contains {
                $0.id == placement.itemID && ($0.kind == opening.preference.furnitureKind || $0.id == opening.cornerID)
                    && CatRestPreference(kind: $0.kind) != nil
            }
        }
        guard let first = restingFurniture(placements: eligible, items: world.items, floor: opening.floor,
            preference: opening.preference, cornerID: opening.cornerID,
            kindRoll: opening.kindRoll, instanceRoll: opening.instanceRoll) else { return nil }
        let ordered = [first] + eligible.filter { $0.itemID != first.itemID }.sorted { $0.itemID < $1.itemID }
        let floor = world.roomFloor
        for destination in ordered {
            guard !Task<Never, Never>.isCancelled else { return nil }
            guard let visit = world.restVisit(to: destination.itemID, from: origin),
                  let point = navigation.nearestWalkable(to: visit.plan.stage),
                  hypot(point.x - visit.plan.stage.x, point.y - visit.plan.stage.y) <= world.catWidth * 0.4,
                  navigation.isWalkable(point), navigation.route(from: origin, to: point) != nil,
                  floor.feedingPlan(from: point, bowlAt: world.bowlPosition, navigator: navigation, firstReachable: true) != nil
            else { continue }
            return point
        }
        return nil
    }

    private static func weighted<Value>(_ values: [Value], roll: Double, weight: (Value) -> Int) -> Value? {
        guard !values.isEmpty, roll.isFinite else { return nil }
        let total = values.reduce(0) { $0 + weight($1) }
        let target = min(Double(total).nextDown, max(0, roll * Double(total)))
        var end = 0
        for value in values {
            end += weight(value)
            if target < Double(end) { return value }
        }
        return values.last
    }
}
