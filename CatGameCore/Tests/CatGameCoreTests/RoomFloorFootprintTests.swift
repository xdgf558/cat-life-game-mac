import Foundation
import CoreGraphics
import Testing
@testable import CatGameCore

@Suite("Rounded furniture floor clearance preserves solid obstacles")
struct RoomFloorFootprintTests {
    private let windowFloor = [CGPoint(x: 442, y: 530), CGPoint(x: 1024, y: 825),
        CGPoint(x: 1024, y: 1180), CGPoint(x: 510, y: 1510), CGPoint(x: 0, y: 1510),
        CGPoint(x: 0, y: 785), CGPoint(x: 335, y: 635), CGPoint(x: 335, y: 585)]
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0),
        CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 200)]

    @Test func roundedBedCanReachTheWindowFloorWithoutCrossingItsBoundary() {
        // Fixed furniture dimensions expressed in the level-three source artwork.
        let size = CGSize(width: 292 / 1.5, height: 144 / 1.5)
        let rectangle = RoomNavigation(floor: windowFloor, obstacles: [], footprint: size, precomputeGrid: false)
        let rounded = RoomNavigation(floor: windowFloor, obstacles: [], footprint: size,
                                     precomputeGrid: false, floorFootprintShape: .clippedCorners)
        let destination = CGPoint(x: 270, y: 740)
        // The window wall is y = 785 - (150/335)x. At x=270 a rectangle needs
        // y>=755.687; the conservative octagon still requires y>=733.896.
        #expect(!rectangle.isWalkable(destination))
        #expect(rounded.isWalkable(destination))
        #expect(rounded.nearestWalkable(to: destination) == destination)
        #expect(!rounded.isWalkable(CGPoint(x: 270, y: 732)))
        #expect(!rounded.segmentIsWalkable(from: destination, to: CGPoint(x: 270, y: 732)))

        for shape in [RoomNavigation.FloorFootprintShape.rectangle, .clippedCorners] {
            let navigator = RoomNavigation(floor: square, obstacles: [], footprint: CGSize(width: 80, height: 40),
                                           precomputeGrid: false, floorFootprintShape: shape)
            for point in [CGPoint(x: 40, y: 20), CGPoint(x: 160, y: 180)] {
                #expect(navigator.isWalkable(point))
            }
            for point in [CGPoint(x: 39.9, y: 100), CGPoint(x: 160.1, y: 100),
                          CGPoint(x: 100, y: 19.9), CGPoint(x: 100, y: 180.1)] {
                #expect(!navigator.isWalkable(point))
            }
        }
    }

    @Test func concaveWallStillBlocksBetweenAllEightSafeVertices() {
        let floor = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 200),
            CGPoint(x: 106, y: 200), CGPoint(x: 106, y: 70), CGPoint(x: 102, y: 70),
            CGPoint(x: 102, y: 200), CGPoint(x: 0, y: 200)]
        let path = CGMutablePath()
        path.addLines(between: floor)
        path.closeSubpath()
        let vertices = [CGPoint(x: 60, y: 70), CGPoint(x: 80, y: 60),
            CGPoint(x: 120, y: 60), CGPoint(x: 140, y: 70), CGPoint(x: 140, y: 90),
            CGPoint(x: 120, y: 100), CGPoint(x: 80, y: 100), CGPoint(x: 60, y: 90)]
        #expect(vertices.allSatisfy { path.contains($0) })
        let navigator = RoomNavigation(floor: floor, obstacles: [], footprint: CGSize(width: 80, height: 40),
                                       precomputeGrid: false, floorFootprintShape: .clippedCorners)
        #expect(!navigator.isWalkable(CGPoint(x: 100, y: 80)))
        #expect(navigator.isWalkable(CGPoint(x: 100, y: 40)))
    }

    @Test func clippedFloorCornersDoNotWeakenRectangularObjectCollisionsOrSweeps() {
        let center = CGPoint(x: 100, y: 100)
        let size = CGSize(width: 80, height: 40)
        let empty = RoomNavigation(floor: square, obstacles: [], footprint: size,
                                   precomputeGrid: false, floorFootprintShape: .clippedCorners)
        #expect(empty.isWalkable(center))
        // This object lies entirely in a clipped corner. It must still collide
        // with the full rectangular footprint used for other furniture/cats/bowls.
        let cornerObject = CGRect(x: 61, y: 81, width: 3, height: 3)
        for shape in [RoomNavigation.FloorFootprintShape.rectangle, .clippedCorners] {
            let navigator = RoomNavigation(floor: square, obstacles: [cornerObject], footprint: size,
                                           precomputeGrid: false, floorFootprintShape: shape)
            #expect(!navigator.isWalkable(center))
            let barrier = RoomNavigation(floor: square,
                obstacles: [CGRect(x: 99.995, y: 0, width: 0.01, height: 200)],
                footprint: CGSize(width: 20, height: 10), precomputeGrid: false, floorFootprintShape: shape)
            let start = CGPoint(x: 40, y: 100), end = CGPoint(x: 160, y: 100)
            #expect(barrier.isWalkable(start) && barrier.isWalkable(end))
            #expect(!barrier.segmentIsWalkable(from: start, to: end))
        }
    }

    @Test func deferredDetourRetainsTheFloorShapeWhenBuildingItsGrid() throws {
        let footprint = CGSize(width: 292 / 1.5, height: 144 / 1.5)
        let obstacles = [CGRect(x: 430, y: 890, width: 30, height: 40)]
        let eager = RoomNavigation(floor: windowFloor, obstacles: obstacles, footprint: footprint,
                                   cellSize: 20, floorFootprintShape: .clippedCorners)
        let deferred = RoomNavigation(floor: windowFloor, obstacles: obstacles, footprint: footprint,
                                      cellSize: 20, precomputeGrid: false, floorFootprintShape: .clippedCorners)
        let start = CGPoint(x: 270, y: 740), end = CGPoint(x: 600, y: 1100)
        #expect(!deferred.segmentIsWalkable(from: start, to: end))
        let route = try #require(deferred.route(from: start, to: end))
        #expect(route == eager.route(from: start, to: end))
        #expect(route.count > 2 && route.first == start && route.last == end)
        #expect(deferred.walkablePoints.isEmpty)
        for (a, b) in zip(route, route.dropFirst()) {
            #expect(deferred.segmentIsWalkable(from: a, to: b))
        }
        // The existing default still rejects this endpoint before pathfinding.
        let unchanged = RoomNavigation(floor: windowFloor, obstacles: obstacles, footprint: footprint,
                                       precomputeGrid: false)
        #expect(unchanged.floorFootprintShape == .rectangle)
        #expect(unchanged.route(from: start, to: end) == nil)
    }
}
