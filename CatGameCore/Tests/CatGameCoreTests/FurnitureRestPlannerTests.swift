import Foundation
import CoreGraphics
import Testing
@testable import CatGameCore

@Suite("Furniture rest approach and return")
struct FurnitureRestPlannerTests {
    private let floor = [CGPoint(x: 0, y: 0), CGPoint(x: 320, y: 0),
                         CGPoint(x: 320, y: 240), CGPoint(x: 0, y: 240)]
    private let target = CGRect(x: 170, y: 140, width: 80, height: 50)
    private let footprint = CGSize(width: 24, height: 12)
    private let start = CGPoint(x: 60, y: 60)
    private let rest = CGPoint(x: 210, y: 165)

    @Test func visitIsContinuousAndExemptsOnlyItsTargetDuringEntryAndExit() throws {
        // Starting behind the bed requires going around it before entering from
        // the front; ignoring the target for the whole route would cut through.
        let behind = CGPoint(x: 210, y: 220)
        let plan = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: target,
                                                         footprint: footprint, start: behind, restPoint: rest,
                                                         preferredFacing: -1))
        #expect(plan.approach.first == behind && plan.approach.last == plan.stage)
        #expect(plan.entry == [plan.stage, rest] && plan.exit == [rest, plan.stage])
        #expect(plan.restPoint == rest && plan.facing == -1)
        #expect(plan.stage.y + footprint.height / 2 < target.minY)
        #expect(plan.approach.count > 2)
        let normal = RoomNavigation(floor: floor, obstacles: [target], footprint: footprint)
        #expect(normal.isWalkable(plan.stage) && !normal.isWalkable(plan.restPoint))
        checkSweptPath(plan.approach, footprint: footprint, floor: floor, blocked: [target])
        checkSweptPath(plan.entry + plan.exit.dropFirst(), footprint: footprint, floor: floor, blocked: [])
    }

    @Test func unreachableApproachDoesNotTeleportToAValidEntry() {
        let divider = CGRect(x: 135, y: 0, width: 2, height: 240)
        let normal = RoomNavigation(floor: floor, obstacles: [divider, target], footprint: footprint)
        #expect(normal.isWalkable(start))
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [divider], target: target,
                                          footprint: footprint, start: start, restPoint: rest) == nil)
    }

    @Test func thinFrontBarrierBlocksBothEntryAndReturnDespiteSafeEndpoints() {
        let barrier = CGRect(x: 150, y: 148, width: 120, height: 0.01)
        let withoutTarget = RoomNavigation(floor: floor, obstacles: [barrier], footprint: footprint)
        #expect(withoutTarget.isWalkable(rest))
        #expect(withoutTarget.isWalkable(CGPoint(x: rest.x, y: 132.2)))
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [barrier], target: target,
                                          footprint: footprint, start: start, restPoint: rest) == nil)
    }

    @Test func adjacentBowlRemainsSolidWhenEnteringAndLeavingFurniture() throws {
        let bowl = CGRect(x: 225, y: 148, width: 18, height: 18)
        let plan = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [bowl], target: target,
                                                         footprint: footprint, start: start, restPoint: rest))
        checkSweptPath(plan.approach, footprint: footprint, floor: floor, blocked: [target, bowl])
        checkSweptPath(plan.entry + plan.exit.dropFirst(), footprint: footprint, floor: floor, blocked: [bowl])
        // Moving only that other object into the resting paws must reject the
        // visit, even though the resting center still belongs to the target.
        let closer = bowl.offsetBy(dx: -4, dy: 0)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [closer], target: target,
                                          footprint: footprint, start: start, restPoint: rest) == nil)
    }

    @Test func diagonalEntryFollowsPreferredFacingWithoutFlippingAtRest() throws {
        for facing: CGFloat in [1, -1] {
            let plan = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: target,
                                                             footprint: footprint, start: start, restPoint: rest,
                                                             preferredFacing: facing))
            #expect(plan.stage.x == rest.x - facing * footprint.width / 2)
            #expect(plan.facing == facing)
            #expect((plan.restPoint.x - plan.stage.x) * plan.facing > 0)
            #expect(plan.entry == [plan.stage, rest] && plan.exit == [rest, plan.stage])
            checkSweptPath(plan.approach, footprint: footprint, floor: floor, blocked: [target])
            checkSweptPath(plan.entry + plan.exit.dropFirst(), footprint: footprint, floor: floor, blocked: [])
        }
    }

    @Test func blockedDiagonalTriesTheOtherSideThenASafeCenteredEntry() throws {
        // These objects obstruct each diagonal stage's outer paws, leaving
        // the centered stage and entry clear. They must never be ignored as
        // part of the target furniture's temporary overlap permission.
        let left = CGRect(x: 187, y: 130, width: 2, height: 2)
        let right = CGRect(x: 232, y: 130, width: 2, height: 2)
        let opposite = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [left], target: target,
                                                              footprint: footprint, start: start, restPoint: rest))
        #expect(opposite.stage.x > rest.x && opposite.facing == -1)
        checkSweptPath(opposite.approach, footprint: footprint, floor: floor, blocked: [target, left])
        checkSweptPath(opposite.entry + opposite.exit.dropFirst(), footprint: footprint, floor: floor, blocked: [left])
        let centered = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [left, right], target: target,
                                                              footprint: footprint, start: start, restPoint: rest))
        #expect(centered.stage.x == rest.x && centered.facing == 1)
        checkSweptPath(centered.approach, footprint: footprint, floor: floor, blocked: [target, left, right])
        checkSweptPath(centered.entry + centered.exit.dropFirst(), footprint: footprint, floor: floor, blocked: [left, right])
    }

    @Test func frontOffsetCanAvoidAnObstacleWithoutEnteringFromTheBack() throws {
        let small = CGRect(x: 205, y: 134, width: 2, height: 2)
        let narrowFeet = CGSize(width: 8, height: 6)
        let plan = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [small], target: target,
                                                         footprint: narrowFeet, start: start, restPoint: rest))
        #expect(plan.stage.x != rest.x)
        #expect(plan.stage.y + narrowFeet.height / 2 < target.minY)
        checkSweptPath(plan.approach, footprint: narrowFeet, floor: floor, blocked: [target, small])
        checkSweptPath(plan.entry + plan.exit.dropFirst(), footprint: narrowFeet, floor: floor, blocked: [small])
    }

    @Test func movedTargetChangesStageAndRejectsTheOldRestingCenter() throws {
        let moved = target.offsetBy(dx: -95, dy: -35)
        let movedRest = CGPoint(x: rest.x - 95, y: rest.y - 35)
        let first = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: target,
                                                          footprint: footprint, start: start, restPoint: rest))
        let second = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: moved,
                                                           footprint: footprint, start: start, restPoint: movedRest))
        #expect(second.stage != first.stage && second.restPoint == movedRest)
        #expect(second.approach.last == second.entry.first && second.exit.last == second.stage)
        checkSweptPath(second.approach, footprint: footprint, floor: floor, blocked: [moved])
        checkSweptPath(second.entry + second.exit.dropFirst(), footprint: footprint, floor: floor, blocked: [])
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: moved,
                                          footprint: footprint, start: start, restPoint: rest) == nil)
    }

    @Test func cushionCanBeNarrowerThanFeetButCannotExemptTheFloor() throws {
        let cushion = CGRect(x: 110, y: 110, width: 16, height: 10)
        let cushionRest = CGPoint(x: 118, y: 115)
        let plan = try #require(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: cushion,
                                                         footprint: footprint, start: start, restPoint: cushionRest))
        #expect(footprint.width > cushion.width && plan.restPoint == cushionRest)
        #expect(plan.stage.x < cushion.minX, "A safe diagonal stage need not be clamped to a narrow cushion's width.")
        checkSweptPath(plan.entry + plan.exit.dropFirst(), footprint: footprint, floor: floor, blocked: [])
        let offFloorCushion = CGRect(x: 0, y: 110, width: 16, height: 10)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: offFloorCushion,
                                          footprint: footprint, start: start,
                                          restPoint: CGPoint(x: 8, y: 115)) == nil)
    }

    @Test func malformedGeometryIsRejectedWithoutRecoveryOrGridAllocation() {
        #expect(FurnitureRestPlanner.plan(floor: [], obstacles: [], target: target,
                                          footprint: footprint, start: start, restPoint: rest) == nil)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: .null,
                                          footprint: footprint, start: start, restPoint: rest) == nil)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: target,
                                          footprint: CGSize(width: CGFloat.nan, height: 12), start: start, restPoint: rest) == nil)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: target,
                                          footprint: footprint, start: CGPoint(x: CGFloat.nan, y: 20), restPoint: rest) == nil)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: target,
                                          footprint: footprint, start: start, restPoint: CGPoint(x: 200, y: CGFloat.nan)) == nil)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [], target: target,
                                          footprint: footprint, start: start, restPoint: rest, preferredFacing: .nan) == nil)
        let invalidObstacle = CGRect(x: CGFloat.nan, y: 20, width: 10, height: 10)
        #expect(FurnitureRestPlanner.plan(floor: floor, obstacles: [invalidObstacle], target: target,
                                          footprint: footprint, start: start, restPoint: rest) == nil)
    }

    // Independent CoreGraphics boolean geometry sweeps a rectangle using its
    // four translated edges, rather than the navigator's convex-hull routine.
    private func checkSweptPath(_ points: [CGPoint], footprint: CGSize, floor: [CGPoint], blocked: [CGRect]) {
        let floorPath = CGMutablePath()
        floorPath.addLines(between: floor)
        floorPath.closeSubpath()
        for (a, b) in zip(points, points.dropFirst()) {
            let rect = CGRect(x: a.x - footprint.width / 2, y: a.y - footprint.height / 2,
                              width: footprint.width, height: footprint.height)
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            let dx = b.x - a.x, dy = b.y - a.y
            var swept = CGPath(rect: rect, transform: nil)
                .union(CGPath(rect: rect.offsetBy(dx: dx, dy: dy), transform: nil))
            for index in corners.indices {
                let from = corners[index], to = corners[(index + 1) % corners.count]
                let edge = CGMutablePath()
                edge.addLines(between: [from, to, CGPoint(x: to.x + dx, y: to.y + dy),
                                       CGPoint(x: from.x + dx, y: from.y + dy)])
                edge.closeSubpath()
                swept = swept.union(edge)
            }
            #expect(swept.subtracting(floorPath).isEmpty)
            for obstacle in blocked { #expect(swept.intersection(CGPath(rect: obstacle, transform: nil)).isEmpty) }
        }
    }
}
