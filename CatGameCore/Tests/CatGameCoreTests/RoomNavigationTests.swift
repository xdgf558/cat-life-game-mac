import Foundation
import CoreGraphics
import Testing
@testable import CatGameCore

@Suite("Room floor and obstacle navigation")
struct RoomNavigationTests {
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0),
                          CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 200)]

    @Test func unobstructedWalkKeepsExactEndpoints() throws {
        let navigator = RoomNavigation(floor: square, obstacles: [], footprint: CGSize(width: 24, height: 12))
        let start = CGPoint(x: 20.3, y: 30.7), finish = CGPoint(x: 170.4, y: 155.8)
        #expect(navigator.route(from: start, to: finish) == [start, finish])
        #expect(navigator.route(from: start, to: start) == [start])
    }

    @Test func safeEndpointsDoNotAllowWalkingThroughBowl() throws {
        let bowl = CGRect(x: 85, y: 72, width: 30, height: 28)
        let footprint = CGSize(width: 26, height: 14)
        let navigator = RoomNavigation(floor: square, obstacles: [bowl], footprint: footprint)
        let start = CGPoint(x: 30, y: 86), finish = CGPoint(x: 170, y: 86)
        #expect(navigator.isWalkable(start))
        #expect(navigator.isWalkable(finish))
        #expect(!navigator.segmentIsWalkable(from: start, to: finish))
        let path = try #require(navigator.route(from: start, to: finish))
        #expect(path.count > 2)
        #expect(path.first == start && path.last == finish)
        checkSweptPath(path, footprint: footprint, blocked: [bowl])
        for (a, b) in zip(path, path.dropFirst()) { #expect(navigator.segmentIsWalkable(from: a, to: b)) }
    }

    @Test func movedBowlUsesItsNewPosition() throws {
        let footprint = CGSize(width: 24, height: 16)
        let oldBowl = CGRect(x: 45, y: 80, width: 30, height: 30)
        let newBowl = CGRect(x: 120, y: 80, width: 30, height: 30)
        let start = CGPoint(x: 20, y: 95), finish = CGPoint(x: 180, y: 95)
        let oldNavigation = RoomNavigation(floor: square, obstacles: [oldBowl], footprint: footprint)
        let newNavigation = RoomNavigation(floor: square, obstacles: [newBowl], footprint: footprint)
        let oldPath = try #require(oldNavigation.route(from: start, to: finish))
        let newPath = try #require(newNavigation.route(from: start, to: finish))
        #expect(oldPath != newPath)
        checkSweptPath(newPath, footprint: footprint, blocked: [newBowl])
    }

    @Test func thinBarrierIsSweptAndNeverCrossedAsFallback() {
        let wall = CGRect(x: 99.995, y: 0, width: 0.01, height: 200)
        let navigator = RoomNavigation(floor: square, obstacles: [wall], footprint: CGSize(width: 18, height: 10))
        let start = CGPoint(x: 30, y: 100), finish = CGPoint(x: 170, y: 100)
        #expect(navigator.isWalkable(start) && navigator.isWalkable(finish))
        #expect(!navigator.segmentIsWalkable(from: start, to: finish))
        #expect(navigator.route(from: start, to: finish) == nil)
    }

    @Test func concaveWallBetweenFootprintCornersIsStillSolid() {
        let floor = notchedFloor
        let navigator = RoomNavigation(floor: floor, obstacles: [], footprint: CGSize(width: 80, height: 40))
        // All four corners (60/140, 60/100) are on floor. The narrow wall notch
        // enters the middle of the body from above and must still block it.
        #expect(!navigator.isWalkable(CGPoint(x: 100, y: 80)))
        #expect(navigator.isWalkable(CGPoint(x: 100, y: 35)))
    }

    @Test func routeAroundConcaveWallDoesNotCutTheInsideCorner() throws {
        let footprint = CGSize(width: 20, height: 16)
        let navigator = RoomNavigation(floor: notchedFloor, obstacles: [], footprint: footprint)
        let start = CGPoint(x: 50, y: 150), finish = CGPoint(x: 150, y: 150)
        #expect(!navigator.segmentIsWalkable(from: start, to: finish))
        let path = try #require(navigator.route(from: start, to: finish))
        #expect(path.contains { $0.y < 62 })
        checkSweptPath(path, footprint: footprint, blocked: [CGRect(x: 90, y: 70, width: 20, height: 130)])
    }

    @Test func passageMustFitWholeCatAndSmallerCatCanFit() throws {
        let walls = [CGRect(x: 90, y: 0, width: 20, height: 90),
                     CGRect(x: 90, y: 110, width: 20, height: 90)]
        let start = CGPoint(x: 40, y: 100), finish = CGPoint(x: 160, y: 100)
        let large = RoomNavigation(floor: square, obstacles: walls, footprint: CGSize(width: 24, height: 22))
        let small = RoomNavigation(floor: square, obstacles: walls, footprint: CGSize(width: 20, height: 18))
        #expect(large.route(from: start, to: finish) == nil)
        let path = try #require(small.route(from: start, to: finish))
        checkSweptPath(path, footprint: CGSize(width: 20, height: 18), blocked: walls)
    }

    @Test func floorEdgesConstrainBodyInsteadOfOnlyCenter() {
        let navigator = RoomNavigation(floor: square, obstacles: [], footprint: CGSize(width: 40, height: 20))
        #expect(!navigator.isWalkable(CGPoint(x: 10, y: 100)))
        #expect(!navigator.isWalkable(CGPoint(x: 180, y: 195)))
        #expect(navigator.isWalkable(CGPoint(x: 20, y: 10)))
        #expect(navigator.route(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 100, y: 100)) == nil)
        #expect(navigator.walkablePoints.allSatisfy { $0.x >= 20 && $0.x <= 180 && $0.y >= 10 && $0.y <= 190 })
    }

    @Test func diagonalCornerCannotBeSkippedByPathSimplification() throws {
        let obstacle = CGRect(x: 60, y: 60, width: 20, height: 20)
        let footprint = CGSize(width: 20, height: 20)
        let navigator = RoomNavigation(floor: square, obstacles: [obstacle], footprint: footprint)
        let start = CGPoint(x: 30, y: 80), finish = CGPoint(x: 80, y: 30)
        #expect(!navigator.segmentIsWalkable(from: start, to: finish))
        let path = try #require(navigator.route(from: start, to: finish))
        checkSweptPath(path, footprint: footprint, blocked: [obstacle])
    }

    @Test func invalidOrFullyBlockedLayoutHasNoRecoveryPoint() {
        let blocked = RoomNavigation(floor: square, obstacles: [CGRect(x: 0, y: 0, width: 200, height: 200)],
                                     footprint: CGSize(width: 20, height: 12))
        #expect(blocked.walkablePoints.isEmpty)
        #expect(blocked.nearestWalkable(to: CGPoint(x: 100, y: 100)) == nil)
        let invalid = RoomNavigation(floor: [], obstacles: [], footprint: .zero)
        #expect(!invalid.isWalkable(.zero))
        #expect(invalid.route(from: .zero, to: CGPoint(x: 10, y: 10)) == nil)
        let valid = RoomNavigation(floor: square, obstacles: [], footprint: CGSize(width: 20, height: 12))
        #expect(valid.nearestWalkable(to: CGPoint(x: CGFloat.nan, y: 10)) == nil)
        #expect(valid.nearestWalkable(to: CGPoint(x: -10, y: 50)).map { valid.isWalkable($0) } == true)
    }

    @Test func deferredGridPreservesWholeFootprintAndSweptCollisionChecks() {
        let obstacle = CGRect(x: 145, y: 20, width: 20, height: 20)
        let footprint = CGSize(width: 24, height: 16)
        let eager = RoomNavigation(floor: notchedFloor, obstacles: [obstacle], footprint: footprint)
        let deferred = RoomNavigation(floor: notchedFloor, obstacles: [obstacle], footprint: footprint,
                                      precomputeGrid: false)
        #expect(!eager.walkablePoints.isEmpty)
        #expect(deferred.walkablePoints.isEmpty)
        #expect(deferred.cellSize == eager.cellSize)

        let positions: [(CGPoint, Bool)] = [
            // The notch enters between the body's four otherwise-safe corners.
            (CGPoint(x: 100, y: 64), false), (CGPoint(x: 100, y: 60), true),
            (CGPoint(x: 12, y: 8), true), (CGPoint(x: 11, y: 8), false),
            // Contact with the inflated obstacle is blocked, not just its center.
            (CGPoint(x: 133, y: 30), false), (CGPoint(x: 132, y: 30), true),
            (CGPoint(x: 180, y: 30), true), (CGPoint(x: CGFloat.nan, y: 30), false)
        ]
        for (point, expected) in positions {
            #expect(eager.isWalkable(point) == expected)
            #expect(deferred.isWalkable(point) == expected)
        }
        let segments: [(CGPoint, CGPoint, Bool)] = [
            (CGPoint(x: 30, y: 30), CGPoint(x: 180, y: 30), false),
            (CGPoint(x: 30, y: 10), CGPoint(x: 180, y: 10), true),
            (CGPoint(x: 50, y: 150), CGPoint(x: 150, y: 150), false),
            (CGPoint(x: 30, y: 30), CGPoint(x: 30, y: 170), true),
            (CGPoint(x: 30, y: 30), CGPoint(x: 5, y: 30), false)
        ]
        for (start, end, expected) in segments {
            #expect(eager.segmentIsWalkable(from: start, to: end) == expected)
            #expect(deferred.segmentIsWalkable(from: start, to: end) == expected)
        }
    }

    @Test func deferredRoutesMatchEagerDetoursAndUnreachableResults() throws {
        let footprint = CGSize(width: 26, height: 14)
        let start = CGPoint(x: 30, y: 86), finish = CGPoint(x: 170, y: 86)
        let bowl = CGRect(x: 85, y: 72, width: 30, height: 28)
        let divider = CGRect(x: 99.995, y: 0, width: 0.01, height: 200)
        for obstacles in [[], [bowl], [divider]] {
            let eager = RoomNavigation(floor: square, obstacles: obstacles, footprint: footprint)
            let deferred = RoomNavigation(floor: square, obstacles: obstacles, footprint: footprint,
                                          precomputeGrid: false)
            let path = deferred.route(from: start, to: finish)
            #expect(path == eager.route(from: start, to: finish))
            if obstacles == [divider] {
                #expect(path == nil)
            } else {
                let reachablePath = try #require(path)
                #expect(reachablePath.first == start && reachablePath.last == finish)
                #expect(obstacles.isEmpty ? reachablePath == [start, finish] : reachablePath.count > 2)
                checkSweptPath(reachablePath, footprint: footprint, blocked: obstacles)
            }
            #expect(deferred.route(from: start, to: start) == [start])
            // Routing may build a temporary grid without changing candidate state.
            #expect(deferred.walkablePoints.isEmpty)
        }
    }

    @Test func narrowPassageRemainsReachableAfterWalkingAwayFromFeedingStage() throws {
        // Reduced from the room floor at 420×640 with a bowl below the pictures.
        // The long safe link through `bridge` has no chain of adjacent grid
        // cells. Only keeping the 12 nearest endpoint links loses the return
        // route, even though the cat can walk out through the same passage.
        let floor = [CGPoint(x: 186.250, y: 369.167), CGPoint(x: 263.333, y: 377.500),
                     CGPoint(x: 330.000, y: 340.000), CGPoint(x: 397.733, y: 153.600),
                     CGPoint(x: 201.467, y: 44.800), CGPoint(x: 103.333, y: 179.200),
                     CGPoint(x: 196.667, y: 335.833)]
        let bowl = CGRect(x: 278.723, y: 314.443, width: 44.554, height: 16.380)
        let footprint = CGSize(width: 79.968, height: 14.700)
        let away = CGPoint(x: 243.333, y: 142.800)
        let bridge = CGPoint(x: 236.333, y: 352.800)
        let stage = CGPoint(x: 263.004, y: 340.173)
        let eager = RoomNavigation(floor: floor, obstacles: [bowl], footprint: footprint, cellSize: 7)
        let deferred = RoomNavigation(floor: floor, obstacles: [bowl], footprint: footprint,
                                      cellSize: 7, precomputeGrid: false)
        #expect(eager.segmentIsWalkable(from: bridge, to: away))
        #expect(eager.segmentIsWalkable(from: bridge, to: stage))
        #expect(!eager.segmentIsWalkable(from: away, to: stage))

        let route = try #require(eager.route(from: away, to: stage))
        #expect(route.first == away && route.last == stage)
        #expect(route.count > 2)
        #expect(deferred.route(from: away, to: stage) == route)
        #expect(eager.route(from: stage, to: away) != nil)

        // CoreGraphics boolean geometry is independent of the navigator's
        // intersection/hull code and checks the entire continuously swept body.
        let floorPath = CGMutablePath()
        floorPath.addLines(between: floor)
        floorPath.closeSubpath()
        for (start, end) in zip(route, route.dropFirst()) {
            let swept = sweptFootprintPath(from: start, to: end, footprint: footprint)
            #expect(swept.subtracting(floorPath).isEmpty, "Return route leaves the floor")
            #expect(!swept.intersects(CGPath(rect: bowl, transform: nil)), "Return route crosses the bowl")
        }
    }

    private var notchedFloor: [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 200),
         CGPoint(x: 110, y: 200), CGPoint(x: 110, y: 70), CGPoint(x: 90, y: 70),
         CGPoint(x: 90, y: 200), CGPoint(x: 0, y: 200)]
    }

    /// Union the two endpoint rectangles and the four swept edge quadrilaterals.
    /// This does not share the production navigator's convex-hull algorithm.
    private func sweptFootprintPath(from start: CGPoint, to end: CGPoint, footprint: CGSize) -> CGPath {
        func rectangle(at point: CGPoint) -> CGRect {
            CGRect(x: point.x - footprint.width / 2, y: point.y - footprint.height / 2,
                   width: footprint.width, height: footprint.height)
        }
        func corners(_ rect: CGRect) -> [CGPoint] {
            [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
             CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        }
        let first = rectangle(at: start), last = rectangle(at: end)
        let firstCorners = corners(first), lastCorners = corners(last)
        var swept = CGPath(rect: first, transform: nil).union(CGPath(rect: last, transform: nil))
        for index in 0..<4 {
            let next = (index + 1) % 4
            let edge = CGMutablePath()
            edge.addLines(between: [firstCorners[index], firstCorners[next], lastCorners[next], lastCorners[index]])
            edge.closeSubpath()
            swept = swept.union(edge)
        }
        return swept
    }

    /// Independent dense geometric assertions: do not use the navigator's own
    /// collision routine as the only oracle for its generated paths.
    private func checkSweptPath(_ path: [CGPoint], footprint: CGSize, blocked: [CGRect],
                                sourceLocation: SourceLocation = #_sourceLocation) {
        for (a, b) in zip(path, path.dropFirst()) {
            let steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) * 2)))
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
                let body = CGRect(x: point.x - footprint.width / 2, y: point.y - footprint.height / 2,
                                  width: footprint.width, height: footprint.height)
                #expect(body.minX >= -0.0001 && body.maxX <= 200.0001 && body.minY >= -0.0001 && body.maxY <= 200.0001,
                        sourceLocation: sourceLocation)
                for obstacle in blocked {
                    #expect(!body.intersects(obstacle), "Swept cat footprint overlaps a solid object", sourceLocation: sourceLocation)
                }
            }
        }
    }
}
