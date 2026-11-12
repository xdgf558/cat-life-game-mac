import Foundation
import CoreGraphics
import CatGameCore

/// One floor-grid mapping for snapping, nudging, outlines and rendering.
struct RoomArrangementGrid68: Sendable {
    let transform: RoomArtworkTransform
    var origin: CGPoint { transform.point(.init(x: 0.5, y: 0.7)) }
    var unit: CGSize { CGSize(width: 128 * transform.visualScale, height: 64 * transform.visualScale) }

    func gridPoint(world: CGPoint) -> CGPoint {
        #if os(macOS)
        if let model = MacRoomReservations.projection(transform: transform) { return model.cellPoint(logical: world) }
        #endif
        return CGPoint(x: (world.x - origin.x) / unit.width, y: (world.y - origin.y) / unit.height)
    }
    func worldPoint(grid: CGPoint) -> CGPoint {
        #if os(macOS)
        if let model = MacRoomReservations.projection(transform: transform) { return model.logicalPoint(cell: grid) }
        #endif
        return CGPoint(x: origin.x + grid.x * unit.width, y: origin.y + grid.y * unit.height)
    }
    func snapped(_ world: CGPoint, enabled: Bool) -> CGPoint {
        let point = gridPoint(world: world), step: CGFloat = enabled ? 0.5 : 0.1
        return worldPoint(grid: CGPoint(x: (point.x / step).rounded() * step, y: (point.y / step).rounded() * step))
    }
    func normalized(world: CGPoint) -> NormalizedPoint {
        .init(x: 0.5 + (world.x - transform.sceneSize.width / 2) / (transform.artworkSize.width * transform.scale),
              y: 0.5 - (world.y - transform.sceneSize.height / 2) / (transform.artworkSize.height * transform.scale))
    }
    func nudged(_ point: CGPoint, dx: Int, dy: Int, step: Double,
                projection: RoomViewProjection, wall: Bool) -> CGPoint {
        let anchor = wall ? projection.wallPoint(point) : projection.project(point)
        func candidate(_ distance: CGFloat) -> CGPoint {
            let screen = CGPoint(x: anchor.x + CGFloat(dx) * distance, y: anchor.y - CGFloat(dy) * distance)
            return wall ? projection.unprojectWallPoint(screen) : projection.unproject(screen)
        }
        func length(_ distance: CGFloat) -> CGFloat {
            let target = candidate(distance)
            #if os(macOS)
            let a = gridPoint(world: point), b = gridPoint(world: target)
            return hypot(b.x - a.x, b.y - a.y)
            #else
            return hypot((target.x - point.x) / unit.width, (target.y - point.y) / unit.height)
            #endif
        }
        var lower: CGFloat = 0, upper = max(unit.width, unit.height) * CGFloat(step) * 2
        guard step.isFinite, step > 0, upper.isFinite, upper > 0 else { return point }
        for _ in 0..<8 where length(upper) < CGFloat(step) { upper *= 2 }
        for _ in 0..<40 {
            let middle = (lower + upper) / 2
            if length(middle) < CGFloat(step) { lower = middle } else { upper = middle }
        }
        return candidate((lower + upper) / 2)
    }
}

@MainActor
final class RoomArrangementState68 {
    var snapEnabled = true
    var bowlSelected = false
    var issues: [String: ArrangementIssue68] = [:]
    var sourceIssues: [String: ArrangementIssue68]?
    var gestureIssues: [String: ArrangementIssue68] = [:]
    var gestureActive = false
    var pendingRequest: ArrangementRequest68?
    var completedRequest: UUID?
    var pendingDrop: (id: String, point: CGPoint)?
    var worker: Task<RoomArrangementResolution68, Never>?
    var yielding = false
    var yieldContinuation: (() -> Void)?
}

struct RoomArrangementResolution68: Sendable {
    let world: RoomFurnitureWorld
    let point: CGPoint
    let issue: ArrangementIssue68?
    let catRoute: [CGPoint]
}

enum RoomArrangementPlanning68 {
    static func issue(id: String?, at point: CGPoint, world: RoomFurnitureWorld,
                      preservingLegacyFootprints: Bool = false) -> ArrangementIssue68? {
        guard point.x.isFinite, point.y.isFinite else { return .outside }
        // A real move adopts the new footprint before any bounds/overlap check.
        let world = id.map { world.replacing($0, with: point, preservingLegacyFootprint: preservingLegacyFootprints) } ?? world
        let item = id.flatMap(world.item)
        let wall = item.map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false
        let center = item == nil ? world.roomFloor.bowlGround(at: point) : point
        let footprint = item.map(world.footprint) ?? world.roomFloor.bowlFootprint
        let rectangle = CGRect(x: center.x - footprint.width / 2, y: center.y - footprint.height / 2,
                               width: footprint.width, height: footprint.height)
        #if os(macOS)
        if !wall, let model = MacRoomReservations.projection(transform: world.transform),
           MacRoomReservations.intersects(rectangle, projection: model) { return .outside }
        #endif
        for placement in world.placements where placement.itemID != id {
            guard let other = world.item(placement.itemID), FurnitureCatalog.metadata(for: other.kind).isWall == wall else { continue }
            if rectangle.intersects(world.rectangle(other, at: world.transform.point(placement.position)).insetBy(dx: -2, dy: -2)) {
                return .overlap(other.id)
            }
        }
        if !wall, item != nil, rectangle.intersects(world.roomFloor.bowlObstacle(at: world.bowlPosition).insetBy(dx: -2, dy: -2)) {
            return .overlap("bowl")
        }
        let boundary = RoomNavigation(floor: wall ? world.wallPolygon : world.roomFloor.polygon,
            obstacles: [], footprint: footprint, precomputeGrid: false,
            floorFootprintShape: item?.kind == .catBed ? .clippedCorners : .rectangle)
        return boundary.isWalkable(center) ? nil : .outside
    }

    static func resolve(id: String?, at requested: CGPoint, world: RoomFurnitureWorld, cat: CGPoint,
                        grid: RoomArrangementGrid68, snap: Bool, findNearest: Bool,
                        snapPoint: Bool = true, otherCats: [CGRect] = [], preservingLegacyFootprints: Bool = false,
                        validatesAllRestPlaces: Bool = false, placementFloor: HomeFloor? = nil) -> RoomArrangementResolution68 {
        let requested = snapPoint ? grid.snapped(requested, enabled: snap) : requested
        var candidates = [requested]
        if findNearest {
            let navigator = world.placementNavigator(for: id, catAt: CGPoint(x: -1_000_000, y: -1_000_000))
            candidates += navigator.walkablePoints.sorted {
                hypot($0.x - requested.x, $0.y - requested.y) < hypot($1.x - requested.x, $1.y - requested.y)
            }.map { grid.snapped($0, enabled: snap) }
        }
        let initialIssue = issue(id: id, at: requested, world: world, preservingLegacyFootprints: preservingLegacyFootprints)
        for point in candidates {
            if Task<Never, Never>.isCancelled { break }
            guard issue(id: id, at: point, world: world, preservingLegacyFootprints: preservingLegacyFootprints) == nil else { continue }
            let proposed: RoomFurnitureWorld
            if let id { proposed = world.replacing(id, with: point, preservingLegacyFootprint: preservingLegacyFootprints, placementFloor: placementFloor) }
            else {
                proposed = .init(transform: world.transform, catWidth: world.catWidth, bowlSize: world.bowlSize,
                    bowlPosition: point, items: world.items, placements: world.placements)
            }
            let floor = proposed.roomFloor.addingObstacles(otherCats)
            var navigation = floor.navigator(bowlAt: proposed.bowlPosition, precomputeGrid: false)
            var safeCat = cat
            var route = [cat]
            if !navigation.isWalkable(cat) {
                navigation = floor.navigator(bowlAt: proposed.bowlPosition)
                let oldNavigation = world.roomFloor.addingObstacles(otherCats).navigator(bowlAt: world.bowlPosition, precomputeGrid: false)
                guard let safe = navigation.walkablePoints.sorted(by: {
                    hypot($0.x - cat.x, $0.y - cat.y) < hypot($1.x - cat.x, $1.y - cat.y)
                }).first(where: { oldNavigation.route(from: cat, to: $0) != nil }),
                      let exit = oldNavigation.route(from: cat, to: safe) else { continue }
                safeCat = safe; route = exit
            }
            guard floor.feedingPlan(from: safeCat, bowlAt: proposed.bowlPosition,
                                    navigator: navigation, firstReachable: true) != nil else { continue }
            if let id, let item = proposed.item(id), [.catBed, .floorCushion].contains(item.kind),
               proposed.restVisit(to: id, from: safeCat, additionalObstacles: otherCats) == nil { continue }
            if validatesAllRestPlaces {
                let resting = proposed.placements.compactMap { proposed.item($0.itemID) }
                    .filter { [.catBed, .floorCushion].contains($0.kind) }
                guard resting.allSatisfy({ proposed.restVisit(to: $0.id, from: safeCat, additionalObstacles: otherCats) != nil }) else { continue }
            }
            return .init(world: proposed, point: point, issue: nil, catRoute: route)
        }
        let proposed = id.map { world.replacing($0, with: requested, preservingLegacyFootprint: preservingLegacyFootprints, placementFloor: placementFloor) } ?? world
        return .init(world: proposed, point: requested, issue: initialIssue ?? .blocked, catRoute: [])
    }
}
