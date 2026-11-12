import Foundation
import CoreGraphics
import CatGameCore

/// All inputs are frozen floor coordinates. Run this planner on a worker;
/// the scene serializes walks so these stationary obstacles stay accurate.
struct RoomResidentPlanner: Sendable {
    let floor: RoomFloor
    let bowl: CGPoint
    let world: RoomFurnitureWorld
    let active: CGPoint
    let catWidth: CGFloat

    static func obstacle(at point: CGPoint, width: CGFloat) -> CGRect {
        CGRect(x: point.x - width * 0.68 - 2, y: point.y - width * 0.18 - 2,
               width: width * 1.36 + 4, height: width * 0.36 + 4)
    }

    func positions(count: Int, existing: [CGPoint] = []) -> [CGPoint] {
        guard count > 0, !Task<Never, Never>.isCancelled else { return [] }
        let navigation = floor.navigator(bowlAt: bowl)
        guard navigation.isWalkable(active) else { return [] }
        // A different companion may use a different safe route. Keep everyone
        // in place before trying the unoccupied floor's preferred corridors.
        if existing.count == count, canFeedAll([active] + existing) {
            let obstacles = existing.map(obstacle)
            let keepsRestAccess = world.placements.allSatisfy { placement in
                world.restVisit(to: placement.itemID, from: active) == nil
                    || world.restVisit(to: placement.itemID, from: active, additionalObstacles: obstacles) != nil
            }
            if keepsRestAccess, !Task<Never, Never>.isCancelled { return existing }
        }
        guard let reserved = careRoutes(navigation: navigation) else { return [] }
        // Sample spatially distinct grid points, rather than retrying the same
        // blocked corner hundreds of times with tiny offsets.
        let candidates = sampled(navigation.walkablePoints.sorted { distance($0, active) < distance($1, active) },
                                 limit: 96)
        var result: [CGPoint] = []
        for index in 0..<count {
            if Task<Never, Never>.isCancelled { return [] }
            let preferred = index < existing.count ? [existing[index]] : []
            guard let chosen = (preferred + candidates).first(where: { candidate in
                guard !Task<Never, Never>.isCancelled,
                      spacing(candidate, from: [active] + result) >= catWidth * 0.95 else { return false }
                let occupied = [active] + result
                let placement = floor.addingObstacles(occupied.map(obstacle)).navigator(bowlAt: bowl, precomputeGrid: false)
                guard placement.isWalkable(candidate), preserves(reserved, avoiding: candidate) else { return false }
                return canFeedAll(occupied + [candidate])
            }) else { break }
            result.append(chosen)
        }
        return Task<Never, Never>.isCancelled ? [] : result
    }

    func stroll(from origin: CGPoint, others: [CGPoint], active: CGPoint) -> [CGPoint]? {
        guard !Task<Never, Never>.isCancelled else { return nil }
        let movingActive = distance(origin, active) < 0.001
        let stationary = others + (movingActive ? [] : [active])
        let walkingFloor = floor.addingObstacles(stationary.map(obstacle))
        let navigation = walkingFloor.navigator(bowlAt: bowl)
        guard navigation.isWalkable(origin) else { return nil }
        let otherObstacles = others.map(obstacle)
        let activeFloor = floor.addingObstacles(otherObstacles)
        let activeNavigation = activeFloor.navigator(bowlAt: bowl)
        let activePlanner = Self(floor: activeFloor, bowl: bowl, world: world, active: active, catWidth: catWidth)
        guard let reserved = activePlanner.careRoutes(navigation: activeNavigation,
                                                      restObstacles: otherObstacles) else { return nil }
        let nearby = navigation.walkablePoints.filter {
            let length = distance($0, origin)
            return length >= catWidth * 0.40 && length <= catWidth * 0.8
                && spacing($0, from: stationary) >= catWidth * 0.85
        }.shuffled()
        for destination in sampled(nearby, limit: 12) {
            if Task<Never, Never>.isCancelled { return nil }
            guard (movingActive || preserves(reserved, avoiding: destination)),
                  let route = navigation.route(from: origin, to: destination),
                  routeLength(route) <= catWidth,
                  canFeedAll(stationary + [destination]) else { continue }
            return route
        }
        return nil
    }

    private struct ReservedRoute {
        let points: [CGPoint]
        let footprint: CGSize
    }

    private func careRoutes(navigation: RoomNavigation, restObstacles: [CGRect] = []) -> [ReservedRoute]? {
        guard let meal = floor.feedingPlan(from: active, bowlAt: bowl, navigator: navigation,
                                          firstReachable: true) else { return nil }
        var routes = [ReservedRoute(points: meal.path, footprint: floor.catFootprint),
                      ReservedRoute(points: meal.dockingPath.map(meal.dock.footCenter(at:)),
                                    footprint: meal.dock.footprint)]
        for placement in world.placements {
            if Task<Never, Never>.isCancelled { return nil }
            guard let rest = world.restVisit(to: placement.itemID, from: active,
                                             additionalObstacles: restObstacles) else { continue }
            routes.append(.init(points: rest.plan.approach + rest.plan.entry + rest.plan.exit,
                                footprint: floor.catFootprint))
        }
        return routes
    }

    private func preserves(_ routes: [ReservedRoute], avoiding point: CGPoint) -> Bool {
        routes.allSatisfy { route in
            let space = RoomNavigation(floor: floor.polygon, obstacles: [obstacle(point)],
                footprint: route.footprint, precomputeGrid: false)
            return route.points.allSatisfy(space.isWalkable)
                && zip(route.points, route.points.dropFirst()).allSatisfy {
                    space.segmentIsWalkable(from: $0.0, to: $0.1)
                }
        }
    }

    private func canFeedAll(_ cats: [CGPoint]) -> Bool {
        for (index, position) in cats.enumerated() {
            if Task<Never, Never>.isCancelled { return false }
            let obstacles = cats.enumerated().filter { $0.offset != index }.map { obstacle($0.element) }
            let available = floor.addingObstacles(obstacles)
            guard available.feedingPlan(from: position, bowlAt: bowl,
                navigator: available.navigator(bowlAt: bowl, precomputeGrid: false), firstReachable: true) != nil else {
                return false
            }
        }
        return true
    }

    private func sampled(_ points: [CGPoint], limit: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if Task<Never, Never>.isCancelled { return [] }
            if spacing(point, from: result) >= catWidth * 0.42 { result.append(point) }
            if result.count >= limit { break }
        }
        return result
    }

    private func obstacle(_ point: CGPoint) -> CGRect { Self.obstacle(at: point, width: catWidth) }
    private func spacing(_ point: CGPoint, from others: [CGPoint]) -> CGFloat {
        others.map { distance(point, $0) }.min() ?? .infinity
    }
    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat { hypot(first.x - second.x, first.y - second.y) }
    private func routeLength(_ route: [CGPoint]) -> CGFloat {
        zip(route, route.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
}
