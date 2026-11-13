import Foundation
import CoreGraphics
import CatGameCore

struct RoomBowlResolution: Sendable {
    let center: CGPoint
    let catPosition: CGPoint?
    let navigation: RoomNavigation
    var openingPosition: CGPoint? = nil
#if DEBUG
    let ranOnMainThread: Bool
#endif
}

/// Restores a saved bowl to usable floor space without changing the save. This
/// immutable request and its complete navigation stay on the planning worker.
struct RoomBowlPlanner: Sendable {
    let floor: RoomFloor
    let requested: CGPoint
    let catPosition: CGPoint

    func resolve() -> RoomBowlResolution? {
        guard !Task<Never, Never>.isCancelled else { return nil }
        let placement = floor.placementNavigator()
        let ground = floor.bowlGround(at: requested)
        let nearest = placement.nearestWalkable(to: ground).map { [$0] } ?? []
        let candidates = nearest + placement.walkablePoints.sorted {
            hypot($0.x - ground.x, $0.y - ground.y) < hypot($1.x - ground.x, $1.y - ground.y)
        }
        for candidate in candidates {
            guard !Task<Never, Never>.isCancelled else { return nil }
            let center = CGPoint(x: candidate.x, y: candidate.y - floor.bowlGroundOffset)
            let navigation = floor.navigator(bowlAt: center)
            if let safe = navigation.nearestWalkable(to: catPosition),
               floor.feedingPlan(from: safe, bowlAt: center, navigator: navigation, firstReachable: true) != nil {
                return resolution(center: center, cat: safe, navigation: navigation)
            }
        }
        guard !Task<Never, Never>.isCancelled else { return nil }
        // A completely blocked old layout keeps its visual bowl. Its navigator
        // still rejects unsafe routes, matching the existing stationary fallback.
        let navigation = floor.navigator(bowlAt: requested)
        return resolution(center: requested, cat: navigation.nearestWalkable(to: catPosition), navigation: navigation)
    }

    private func resolution(center: CGPoint, cat: CGPoint?, navigation: RoomNavigation) -> RoomBowlResolution? {
        guard !Task<Never, Never>.isCancelled else { return nil }
#if DEBUG
        return .init(center: center, catPosition: cat, navigation: navigation, ranOnMainThread: Thread.isMainThread)
#else
        return .init(center: center, catPosition: cat, navigation: navigation)
#endif
    }
}
