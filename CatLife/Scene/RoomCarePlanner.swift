import Foundation
import CoreGraphics
import CatGameCore

struct RoomPlayPlan: Sendable {
    let approach: [CGPoint]
    let landing: CGPoint
    let facing: CGFloat
    let returnPath: [CGPoint]
}

enum RoomCarePlan: Sendable {
    case feed(RoomFeedingPlan)
    case play(RoomPlayPlan)
}

struct RoomCarePlanningResult: Sendable {
    let plan: RoomCarePlan?
#if DEBUG
    let milliseconds: Double
    let ranOnMainThread: Bool
#endif
}

/// An immutable floor snapshot. No SpriteKit node or scene crosses into the
/// worker; the coordinator validates its revision before using these routes.
struct RoomCarePlanner: Sendable {
    let floor: RoomFloor
    let navigation: RoomNavigation
    let origin: CGPoint
    let bowl: CGPoint
    let catWidth: CGFloat

    func plan(_ kind: ActionKind) -> RoomCarePlanningResult {
#if DEBUG
        let began = ProcessInfo.processInfo.systemUptime
        let ranOnMainThread = Thread.isMainThread
#endif
        let result: RoomCarePlan?
        if Task<Never, Never>.isCancelled { result = nil }
        else {
            switch kind {
            case .feed:
                result = floor.feedingPlan(from: origin, bowlAt: bowl, navigator: navigation).map(RoomCarePlan.feed)
            case .play:
                result = playingPlan().map(RoomCarePlan.play)
            default: result = nil
            }
        }
#if DEBUG
        return RoomCarePlanningResult(plan: Task<Never, Never>.isCancelled ? nil : result,
            milliseconds: (ProcessInfo.processInfo.systemUptime - began) * 1_000,
            ranOnMainThread: ranOnMainThread)
#else
        return RoomCarePlanningResult(plan: Task<Never, Never>.isCancelled ? nil : result)
#endif
    }

    private func playingPlan() -> RoomPlayPlan? {
        // The fully stretched pounce has a wider footprint than walking.
        let pouncing = RoomNavigation(floor: floor.polygon,
            obstacles: floor.furnitureObstacles + [floor.bowlObstacle(at: bowl)],
            footprint: CGSize(width: catWidth * 1.60, height: catWidth * 0.28), cellSize: 7)
        let candidates = [origin] + pouncing.walkablePoints.sorted {
            hypot($0.x - origin.x, $0.y - origin.y) < hypot($1.x - origin.x, $1.y - origin.y)
        }
        for stage in candidates where pouncing.isWalkable(stage) {
            guard !Task<Never, Never>.isCancelled else { return nil }
            for direction: CGFloat in [1, -1] {
                for distance: CGFloat in [0.42, 0.28] {
                    guard !Task<Never, Never>.isCancelled else { return nil }
                    let landing = CGPoint(x: stage.x + direction * catWidth * distance, y: stage.y)
                    guard pouncing.segmentIsWalkable(from: stage, to: landing),
                          let approach = navigation.route(from: origin, to: stage),
                          let returnPath = navigation.route(from: landing, to: origin) else { continue }
                    return RoomPlayPlan(approach: approach, landing: landing, facing: direction, returnPath: returnPath)
                }
            }
        }
        return nil
    }
}
