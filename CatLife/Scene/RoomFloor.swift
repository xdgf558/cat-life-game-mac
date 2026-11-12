import Foundation
import CoreGraphics
import CatGameCore


/// The artwork is aspect-filled, so its floor must use the same transform.
/// Coordinates below follow the 1024 × 1536 source image, from its top left.
struct RoomFloor: Sendable {
    let catWidth: CGFloat
    let bowlSize: CGSize
    let polygon: [CGPoint]
    let catFootprint: CGSize
    let bowlFootprint: CGSize
    let bowlGroundOffset: CGFloat
    private(set) var furnitureObstacles: [CGRect]
    #if os(macOS)
    private let doorPlacementObstacle: CGRect?
    #endif

    init(sceneSize: CGSize, artworkSize: CGSize, catWidth: CGFloat, bowlSize: CGSize, furnitureObstacles: [CGRect] = []) {
        self.furnitureObstacles = furnitureObstacles
        self.catWidth = catWidth
        self.bowlSize = bowlSize
        let scale = max(sceneSize.width / artworkSize.width, sceneSize.height / artworkSize.height)
        let rendered = CGSize(width: artworkSize.width * scale, height: artworkSize.height * scale)
        // The new background contains only architecture. Furniture supplies
        // separate movable obstacles instead of cutting holes into the floor.
        let sourceFloor: [CGPoint] = [
            .init(x: 442.0/1024, y: 530.0/1536), .init(x: 1, y: 825.0/1536),
            .init(x: 1, y: 1180.0/1536), .init(x: 510.0/1024, y: 1510.0/1536),
            .init(x: 0, y: 1510.0/1536), .init(x: 0, y: 785.0/1536),
            .init(x: 335.0/1024, y: 635.0/1536), .init(x: 335.0/1024, y: 585.0/1536)
        ]
        let mapped = sourceFloor.map {
            CGPoint(x: sceneSize.width / 2 + ($0.x - 0.5) * rendered.width,
                    y: sceneSize.height / 2 + (0.5 - $0.y) * rendered.height)
        }
        // Clip to the complete room world. A 1× camera may show only part of
        // an expanded floor; its edges still keep paws inside the room.
        polygon = Self.clip(mapped, to: CGRect(x: 6, y: 24,
                                               width: max(1, sceneSize.width - 12),
                                               height: max(1, sceneSize.height - 30)))
        #if os(macOS)
        let displayScale = MacRoomProjection.spriteScale
        #else
        let displayScale: CGFloat = 1
        #endif
        catFootprint = CGSize(width: catWidth * 1.36 * displayScale, height: catWidth * 0.25 * displayScale)
        bowlFootprint = CGSize(width: bowlSize.width * 0.68 * displayScale, height: bowlSize.height * 0.30 * displayScale)
        bowlGroundOffset = -bowlSize.width * 0.09
        #if os(macOS)
        doorPlacementObstacle = MacRoomProjection(legacyFloor: polygon, worldSize: sceneSize, angle: .front)
            .map { MacRoomProjection.bounds($0.logicalBoundary(of: MacRoomProjection.doorClearanceCells)) }
        #endif
    }

    func bowlGround(at center: CGPoint) -> CGPoint {
        CGPoint(x: center.x, y: center.y + bowlGroundOffset)
    }

    func addingObstacles(_ obstacles: [CGRect]) -> Self {
        var result = self
        result.furnitureObstacles += obstacles
        return result
    }

    func bowlObstacle(at center: CGPoint) -> CGRect {
        let ground = bowlGround(at: center)
        return CGRect(x: ground.x - bowlFootprint.width / 2,
                      y: ground.y - bowlFootprint.height / 2,
                      width: bowlFootprint.width, height: bowlFootprint.height)
    }

    func navigator(bowlAt center: CGPoint, precomputeGrid: Bool = true) -> RoomNavigation {
        RoomNavigation(floor: polygon, obstacles: furnitureObstacles + [bowlObstacle(at: center)],
                       footprint: catFootprint, cellSize: 7, precomputeGrid: precomputeGrid)
    }

    /// Placement uses the same floor as walking and never drops the bowl onto
    /// the stationary cat. Existing saved positions are only projected visually.
    func placementNavigator(catAt catPosition: CGPoint? = nil) -> RoomNavigation {
        var obstacles = catPosition.map {
            [CGRect(x: $0.x - catFootprint.width / 2 - 3,
                    y: $0.y - catFootprint.height / 2 - 3,
                    width: catFootprint.width + 6, height: catFootprint.height + 6)]
        } ?? []
        #if os(macOS)
        if let doorPlacementObstacle { obstacles.append(doorPlacementObstacle) }
        #endif
        return RoomNavigation(floor: polygon, obstacles: furnitureObstacles + obstacles,
                              footprint: bowlFootprint, cellSize: 7)
    }

    /// Full route validation runs after release, away from the UI thread.
    /// The drag preview only uses nearestWalkable on the existing placement grid.
    func resolvePlacement(near point: CGPoint, catAt start: CGPoint,
                          placement: RoomNavigation) -> RoomPlacementResult? {
        let ground = bowlGround(at: point)
        let nearest = placement.nearestWalkable(to: ground).map { [$0] } ?? []
        let candidates = nearest + placement.walkablePoints.sorted {
            hypot($0.x - ground.x, $0.y - ground.y) < hypot($1.x - ground.x, $1.y - ground.y)
        }
        for safe in candidates {
            guard !Task<Never, Never>.isCancelled else { return nil }
            let center = CGPoint(x: safe.x, y: safe.y - bowlGroundOffset)
            let proposed = navigator(bowlAt: center, precomputeGrid: false)
            guard proposed.isWalkable(start),
                  feedingPlan(from: start, bowlAt: center, navigator: proposed, firstReachable: true) != nil else { continue }
            // Construct the committed navigation once on this same worker.
            return RoomPlacementResult(center: center, navigation: navigator(bowlAt: center))
        }
        return nil
    }

    func feedingPlan(from start: CGPoint, bowlAt center: CGPoint,
                     navigator: RoomNavigation, firstReachable: Bool = false) -> RoomFeedingPlan? {
        let obstacle = bowlObstacle(at: center)
        var best: RoomFeedingPlan?
        var routeNavigator = navigator
        var bestLength = CGFloat.infinity
        for facing: CGFloat in [1, -1] {
            let dock = FeedingDock(catWidth: catWidth, bowlSize: bowlSize, bowlCenter: center, facing: facing)
            let dockNavigation = RoomNavigation(floor: polygon, obstacles: furnitureObstacles + [obstacle],
                                                footprint: dock.footprint, cellSize: 7, precomputeGrid: false)
            let stageY = max(dock.eatingPoint.y, obstacle.maxY + catFootprint.height / 2 + 2)
            for retreat: CGFloat in [0.12, 0, 0.24] {
                if Task<Never, Never>.isCancelled { return nil }
                let stage = CGPoint(x: dock.eatingPoint.x - facing * catWidth * retreat, y: stageY)
                guard dockNavigation.segmentIsWalkable(from: dock.footCenter(at: stage),
                                                        to: dock.footCenter(at: dock.eatingPoint)),
                      routeNavigator.isWalkable(start), routeNavigator.isWalkable(stage) else { continue }
                // A deferred navigator otherwise reconstructs the same grid
                // for every staging point. Reuse it for this candidate bowl.
                if routeNavigator.walkablePoints.isEmpty,
                   !routeNavigator.segmentIsWalkable(from: start, to: stage) {
                    routeNavigator = self.navigator(bowlAt: center)
                }
                guard let path = routeNavigator.route(from: start, to: stage) else { continue }
                let plan = RoomFeedingPlan(dock: dock, facing: facing, path: path,
                                           dockingPath: [stage, dock.eatingPoint], dockingNavigation: dockNavigation)
                // Placement only needs proof of a route; gameplay still picks
                // the shortest safe approach across all sides and staging spots.
                if firstReachable { return plan }
                let length = zip(path, path.dropFirst()).reduce(CGFloat.zero) {
                    $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
                } + hypot(stage.x - dock.eatingPoint.x, stage.y - dock.eatingPoint.y)
                if length < bestLength { best = plan; bestLength = length }
            }
        }
        return best
    }

    /// Sutherland–Hodgman clipping preserves the concave room outline.
    static func clip(_ polygon: [CGPoint], to rect: CGRect) -> [CGPoint] {
        var result = polygon
        for edge in 0..<4 {
            let input = result
            result = []
            guard let last = input.last else { break }
            func inside(_ p: CGPoint) -> Bool {
                switch edge {
                case 0: p.x >= rect.minX
                case 1: p.x <= rect.maxX
                case 2: p.y >= rect.minY
                default: p.y <= rect.maxY
                }
            }
            func intersection(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                if edge < 2 {
                    let x = edge == 0 ? rect.minX : rect.maxX
                    let t = (x - a.x) / (b.x - a.x)
                    return CGPoint(x: x, y: a.y + (b.y - a.y) * t)
                }
                let y = edge == 2 ? rect.minY : rect.maxY
                let t = (y - a.y) / (b.y - a.y)
                return CGPoint(x: a.x + (b.x - a.x) * t, y: y)
            }
            var previous = last
            for current in input {
                if inside(current) {
                    if !inside(previous) { result.append(intersection(previous, current)) }
                    result.append(current)
                } else if inside(previous) {
                    result.append(intersection(previous, current))
                }
                previous = current
            }
        }
        return result
    }
}

struct RoomPlacementResult: Sendable {
    let center: CGPoint
    let navigation: RoomNavigation
}

struct RoomFeedingPlan: Sendable {
    let dock: FeedingDock
    let facing: CGFloat
    let path: [CGPoint]
    let dockingPath: [CGPoint]
    let dockingNavigation: RoomNavigation
}
