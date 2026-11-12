import Foundation
import CoreGraphics

/// A temporary visit to one piece of furniture, in room coordinates (+y is up).
/// The target remains solid during approach. Only the short entry and its exact
/// reverse may overlap it; every other obstacle and the floor remain solid.
public struct FurnitureRestPlan: Sendable {
    public let approach: [CGPoint]
    public let entry: [CGPoint]
    public let exit: [CGPoint]
    public let stage: CGPoint
    public let restPoint: CGPoint
    public let facing: CGFloat

    public init(approach: [CGPoint], entry: [CGPoint], exit: [CGPoint],
                stage: CGPoint, restPoint: CGPoint, facing: CGFloat) {
        self.approach = approach
        self.entry = entry
        self.exit = exit
        self.stage = stage
        self.restPoint = restPoint
        self.facing = facing
    }
}

public enum FurnitureRestPlanner {
    /// `obstacles` includes all other furniture and the bowl, excluding `target`.
    /// The resting center must be inside the target. Its whole footprint may be
    /// wider than a cushion, but must still fit on the floor without touching
    /// another object. No position is projected and no unsafe fallback is used.
    public static func plan(floor: [CGPoint], obstacles: [CGRect], target: CGRect,
                            footprint: CGSize, start: CGPoint, restPoint: CGPoint,
                            preferredFacing: CGFloat = 1) -> FurnitureRestPlan? {
        guard !target.isNull, !target.isInfinite,
              target.origin.x.isFinite, target.origin.y.isFinite,
              target.width.isFinite, target.height.isFinite,
              target.width > 0, target.height > 0,
              restPoint.x.isFinite, restPoint.y.isFinite,
              preferredFacing.isFinite, target.contains(restPoint) else { return nil }

        let entryNavigation = RoomNavigation(floor: floor, obstacles: obstacles, footprint: footprint,
                                             cellSize: 7, precomputeGrid: false)
        guard entryNavigation.isWalkable(restPoint) else { return nil }
        var approachNavigation = RoomNavigation(floor: floor, obstacles: obstacles + [target],
                                                footprint: footprint, cellSize: 7, precomputeGrid: false)
        guard approachNavigation.isWalkable(start) else { return nil }

        // Prefer a diagonal step from in front of the target, so a side-facing
        // actor can climb without sliding vertically or turning at rest. A
        // centered entry remains available in tight spaces. Every entry is one
        // swept segment, never an unrestricted route through solid furniture.
        let clearance = max(1, footprint.height * 0.15)
        let stageY = target.minY - footprint.height / 2 - clearance
        let offset = min(target.width * 0.65, footprint.width * 0.50)
        let direction: CGFloat = preferredFacing < 0 ? -1 : 1
        for displacement in [-direction * offset, direction * offset, CGFloat.zero] {
            if Task<Never, Never>.isCancelled { return nil }
            let stage = CGPoint(x: restPoint.x + displacement, y: stageY)
            guard approachNavigation.isWalkable(stage),
                  entryNavigation.segmentIsWalkable(from: stage, to: restPoint),
                  entryNavigation.segmentIsWalkable(from: restPoint, to: stage) else { continue }
            // Reuse one grid if multiple front candidates need a detour.
            if approachNavigation.walkablePoints.isEmpty,
               !approachNavigation.segmentIsWalkable(from: start, to: stage) {
                approachNavigation = RoomNavigation(floor: floor, obstacles: obstacles + [target],
                                                    footprint: footprint, cellSize: 7)
            }
            guard let approach = approachNavigation.route(from: start, to: stage) else { continue }
            let entryDX = restPoint.x - stage.x
            let facing: CGFloat = entryDX == 0 ? direction : (entryDX > 0 ? 1 : -1)
            return FurnitureRestPlan(approach: approach, entry: [stage, restPoint],
                                     exit: [restPoint, stage], stage: stage, restPoint: restPoint,
                                     facing: facing)
        }
        return nil
    }
}
