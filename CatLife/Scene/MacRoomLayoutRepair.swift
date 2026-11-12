#if os(macOS)
import Foundation
import CoreGraphics
import CatGameCore

/// Fixed architecture uses the display grid, while physics stays in legacy world coordinates.
enum MacRoomReservations {
    static func projection(transform: RoomArtworkTransform) -> MacRoomProjection? {
        let floor = RoomFloor(sceneSize: transform.sceneSize, artworkSize: transform.artworkSize,
                              catWidth: 1, bowlSize: .zero)
        return MacRoomProjection(legacyFloor: floor.polygon, worldSize: transform.sceneSize, angle: .front)
    }
    static func stairObstacle(transform: RoomArtworkTransform) -> CGRect? {
        projection(transform: transform).map { MacRoomProjection.bounds($0.logicalBoundary(of: MacRoomProjection.stairCells)) }
    }
    static func intersects(_ rectangle: CGRect, projection: MacRoomProjection) -> Bool {
        [MacRoomProjection.doorClearanceCells, MacRoomProjection.stairCells].contains {
            overlaps(rectangle, polygon: projection.logicalBoundary(of: $0))
        }
    }
    private static func overlaps(_ rect: CGRect, polygon: [CGPoint]) -> Bool {
        let path = CGMutablePath(); path.addLines(between: polygon); path.closeSubpath()
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        if corners.contains(where: { path.contains($0) }) || polygon.contains(where: { rect.contains($0) }) { return true }
        func crossing(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
            let u = CGPoint(x: b.x - a.x, y: b.y - a.y), v = CGPoint(x: d.x - c.x, y: d.y - c.y)
            let denominator = u.x * v.y - u.y * v.x
            guard abs(denominator) > 0.000_001 else { return false }
            let delta = CGPoint(x: c.x - a.x, y: c.y - a.y)
            let t = (delta.x * v.y - delta.y * v.x) / denominator
            let s = (delta.x * u.y - delta.y * u.x) / denominator
            return t >= 0 && t <= 1 && s >= 0 && s <= 1
        }
        return polygon.indices.contains { i in corners.indices.contains { j in
            crossing(polygon[i], polygon[(i + 1) % polygon.count], corners[j], corners[(j + 1) % 4])
        } }
    }
}

/// A worker proposes both floors together; the Store commits the complete candidate atomically.
enum MacRoomLayoutRepair {
    struct Plan: Sendable {
        let placements: [FurniturePlacement]
        let bowlPositions: [HomeFloor: NormalizedPoint]
        let movedIDs: Set<String>
        let storedIDs: Set<String>
    }
    static func makeWorld(_ snapshot: GameSnapshot, floor: HomeFloor) -> RoomFurnitureWorld {
        let viewport = CGSize(width: 390, height: 600)
        let geometry = RoomWorldGeometry(viewportSize: viewport,
            worldScale: CGFloat(HomeCatalog.level(snapshot.home.roomLevel)?.worldScale ?? 1))
        let bowl = snapshot.home.bowlPosition(on: floor) ?? HomeState.defaultBowlPosition
        let width = min(viewport.width * 0.156, viewport.height * 0.185)
        return RoomFurnitureWorld(transform: .init(sceneSize: geometry.worldSize,
            artworkSize: CGSize(width: 1024, height: 1536), viewportSize: viewport),
            catWidth: min(viewport.width * 0.14, viewport.height * 0.172),
            // bowl-empty/full are both 1374×1145; keep pure worker geometry identical to their runtime aspect.
            bowlSize: CGSize(width: width, height: width * 5 / 6),
            bowlPosition: CGPoint(x: geometry.worldSize.width * bowl.x, y: geometry.worldSize.height * (1 - bowl.y)),
            items: snapshot.inventory.furniture, placements: snapshot.home.furniture.filter { $0.floor == floor })
    }
    static func plan(_ snapshot: GameSnapshot, isNewHome: Bool = false) -> Plan? {
        var placements = snapshot.home.furniture
        var bowls: [HomeFloor: NormalizedPoint] = [:]
        var moved = Set<String>(), stored = Set<String>()
        for floor in snapshot.home.availableFloors {
            guard !Task<Never, Never>.isCancelled else { return nil }
            var world = makeWorld(snapshot, floor: floor)
            let originalBowl = world.bowlPosition
            if isNewHome, floor == .ground { world = startingLayout(world) }
            guard let repaired = resolve(world) else { return nil }
            let byID = Dictionary(uniqueKeysWithValues: repaired.placements.map { ($0.itemID, $0) })
            for old in snapshot.home.furniture where old.floor == floor {
                if let next = byID[old.itemID] { if next != old { moved.insert(old.itemID) } }
                else { stored.insert(old.itemID) }
            }
            // Keep source ordering, including the other floor and every untouched placement.
            placements = placements.compactMap { $0.floor == floor ? byID[$0.itemID] : $0 }
            let size = world.transform.sceneSize
            bowls[floor] = repaired.bowlPosition == originalBowl ? snapshot.home.bowlPosition(on: floor)
                : .init(x: repaired.bowlPosition.x / size.width, y: 1 - repaired.bowlPosition.y / size.height)
        }
        return Plan(placements: placements, bowlPositions: bowls, movedIDs: moved, storedIDs: stored)
    }
    /// This seed is only used for an explicitly new home, never as a migration heuristic.
    static func startingLayout(_ world: RoomFurnitureWorld) -> RoomFurnitureWorld {
        guard let model = MacRoomReservations.projection(transform: world.transform) else { return world }
        let targets: [FurnitureKind: CGPoint] = [.catBed: .init(x: 2.2, y: 4.9), .cabinet: .init(x: 4.4, y: 6.4),
            .floorCushion: .init(x: 7.2, y: 3.3), .catTree: .init(x: 8.9, y: 4.2), .flowerStool: .init(x: 10.4, y: 2)]
        let grid = RoomArrangementGrid68(transform: world.transform)
        var wallProjection = RoomViewProjection(worldSize: world.transform.sceneSize, angle: .front)
        wallProjection.macRoom = model
        let placements = world.placements.map { placement -> FurniturePlacement in
            guard let item = world.item(placement.itemID) else { return placement }
            let cell = item.kind == .plant ? CGPoint(x: item.id == "plantSmall" ? 11.3 : 0.8,
                                                     y: item.id == "plantSmall" ? 0.9 : 6.3) : targets[item.kind]
            if FurnitureCatalog.metadata(for: item.kind).isWall {
                let x: CGFloat = item.kind == .wallFlower ? 4.4 : 8.6
                let point = wallProjection.unprojectWallPoint(model.wallPoint(x: x, height: 2.9))
                return .init(itemID: item.id, position: grid.normalized(world: point), floor: placement.floor)
            }
            guard let cell else { return placement }
            return .init(itemID: item.id, position: grid.normalized(world: model.logicalPoint(cell: cell)), floor: placement.floor)
        }
        return .init(transform: world.transform, catWidth: world.catWidth, bowlSize: world.bowlSize,
            bowlPosition: model.logicalPoint(cell: CGPoint(x: 1.4, y: 1.6)), items: world.items, placements: placements)
    }
    private static func safeCat(in world: RoomFurnitureWorld) -> CGPoint? {
        let navigation = world.roomFloor.navigator(bowlAt: world.bowlPosition)
        return navigation.walkablePoints.first { world.roomFloor.feedingPlan(from: $0,
            bowlAt: world.bowlPosition, navigator: navigation, firstReachable: true) != nil }
    }
    private static func valid(_ world: RoomFurnitureWorld, cat: CGPoint) -> Bool {
        guard RoomArrangementPlanning68.issue(id: nil, at: world.bowlPosition, world: world,
                                              preservingLegacyFootprints: true) == nil else { return false }
        let navigation = world.roomFloor.navigator(bowlAt: world.bowlPosition, precomputeGrid: false)
        guard navigation.isWalkable(cat), world.roomFloor.feedingPlan(from: cat, bowlAt: world.bowlPosition,
            navigator: navigation, firstReachable: true) != nil else { return false }
        for placement in world.placements {
            let point = world.transform.point(placement.position)
            guard RoomArrangementPlanning68.issue(id: placement.itemID, at: point, world: world,
                                                  preservingLegacyFootprints: true) == nil else { return false }
            if let item = world.item(placement.itemID), [.catBed, .floorCushion].contains(item.kind),
               world.restVisit(to: item.id, from: cat) == nil { return false }
        }
        return true
    }
    private static func resolve(_ original: RoomFurnitureWorld) -> RoomFurnitureWorld? {
        if let cat = safeCat(in: original), valid(original, cat: cat) { return original }
        // Keep valid originals first; only conflicting objects enter the nearest-position planner.
        var world = RoomFurnitureWorld(transform: original.transform, catWidth: original.catWidth,
            bowlSize: original.bowlSize, bowlPosition: original.bowlPosition, items: original.items, placements: [])
        let grid = RoomArrangementGrid68(transform: original.transform)
        guard let model = MacRoomReservations.projection(transform: original.transform) else { return nil }
        let requested = original.bowlPosition
        var bowlCandidates = [requested]
        bowlCandidates += (1..<24).flatMap { x in (1..<14).map { z in
            model.logicalPoint(cell: CGPoint(x: CGFloat(x) / 2, y: CGFloat(z) / 2))
        } }.sorted { hypot($0.x - requested.x, $0.y - requested.y) < hypot($1.x - requested.x, $1.y - requested.y) }
        var cat: CGPoint?
        for point in bowlCandidates {
            guard !Task<Never, Never>.isCancelled else { return nil }
            let candidate = RoomFurnitureWorld(transform: world.transform, catWidth: world.catWidth, bowlSize: world.bowlSize,
                bowlPosition: point, items: world.items, placements: [])
            guard RoomArrangementPlanning68.issue(id: nil, at: point, world: candidate, preservingLegacyFootprints: true) == nil,
                  let safe = safeCat(in: candidate) else { continue }
            world = candidate; cat = safe; break
        }
        guard var cat else { return nil }
        let originals = original.placements
        var pending: [FurniturePlacement] = []
        for placement in originals {
            let candidate = RoomFurnitureWorld(transform: world.transform, catWidth: world.catWidth, bowlSize: world.bowlSize,
                bowlPosition: world.bowlPosition, items: world.items, placements: world.placements + [placement])
            if let safe = safeCat(in: candidate), valid(candidate, cat: safe) { world = candidate; cat = safe }
            else { pending.append(placement) }
        }
        for placement in pending {
            guard !Task<Never, Never>.isCancelled else { return nil }
            let resolution = RoomArrangementPlanning68.resolve(id: placement.itemID,
                at: original.transform.point(placement.position), world: world, cat: cat, grid: grid,
                snap: true, findNearest: true, preservingLegacyFootprints: true, validatesAllRestPlaces: true,
                placementFloor: placement.floor)
            guard resolution.issue == nil else { continue } // Unplaceable objects stay owned in the backpack.
            world = resolution.world
            cat = resolution.catRoute.last ?? cat
        }
        guard valid(world, cat: cat) else { return nil }
        return world
    }
}
#endif
