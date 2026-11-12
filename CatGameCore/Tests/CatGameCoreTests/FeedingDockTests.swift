import Foundation
import CoreGraphics
import Testing
@testable import CatGameCore

@Suite("Meal contact and docking clearance")
struct FeedingDockTests {
    // Independently measured cat-meal.png lower lip/tongue landmarks after
    // registration, rather than the mean landmark used to construct the dock.
    private let mouthFrames = [CGPoint(x: 0.3791, y: 0.1472), CGPoint(x: 0.3084, y: 0.1472)]

    @Test(arguments: [44.0, 88.0, 132.0], [-1.0, 1.0])
    func loweredMouthTouchesFoodWhilePawsClearSolidBowl(catWidth: Double, facing: Double) {
        let width = CGFloat(catWidth), direction = CGFloat(facing)
        for bowlRatio: CGFloat in [1, 0.245 / 0.22, 1.25] {
            let size = CGSize(width: width * bowlRatio, height: width * bowlRatio * 1145 / 1374)
            // Translation must not affect either contact or collision checks.
            let center = CGPoint(x: 175.3 + width, y: -42.7 + width / 2)
            let dock = FeedingDock(catWidth: width, bowlSize: size, bowlCenter: center, facing: direction)
            for landmark in mouthFrames {
                let mouth = CGPoint(x: dock.eatingPoint.x + direction * landmark.x * width,
                                    y: dock.eatingPoint.y + landmark.y * width)
                #expect(dock.containsFoodContact(mouth), "Both lowered-mouth poses must reach actual food.")
            }

            let feet = dock.feetRect(at: dock.eatingPoint)
            let bowl = solidBowl(center: center, size: size)
            #expect(!feet.intersects(bowl), "Mouth contact must not require standing inside the solid bowl.")
            #expect(feet.minY > bowl.maxY, "Paws stay behind the bowl while the head reaches forward.")
            // Horizontal overlap is intentional in this perspective; rejecting
            // it alone was the regression that made the cat eat empty floor.
            #expect(feet.minX < bowl.maxX && feet.maxX > bowl.minX)
            #expect((dock.footCenter(at: dock.eatingPoint).x - dock.eatingPoint.x) * direction < 0,
                    "Ground contact is biased behind the actor anchor and mirrors with facing.")
        }
    }

    @Test(arguments: [-1.0, 1.0])
    func raisedHeadAndBowlBodyDoNotCountAsFoodContact(facing: Double) {
        let width: CGFloat = 88
        let size = CGSize(width: 98, height: 98 * 1145.0 / 1374)
        let center = CGPoint(x: 210, y: 170)
        let direction = CGFloat(facing)
        let dock = FeedingDock(catWidth: width, bowlSize: size, bowlCenter: center, facing: direction)
        // Frame 4's lower lip is visibly raised; only frames 2/3 should increment
        // the scene's true food-contact samples.
        let raisedLip = CGPoint(x: dock.eatingPoint.x + direction * 0.4327 * width,
                                y: dock.eatingPoint.y + 0.2669 * width)
        #expect(!dock.containsFoodContact(raisedLip))
        #expect(!dock.containsFoodContact(center), "The texture center lies on the ceramic front, below the food.")
        #expect(!dock.containsFoodContact(imagePoint(x: 650, y: 675, center: center, size: size)),
                "The decorative paw emblem on the bowl is not food.")
        #expect(!dock.containsFoodContact(imagePoint(x: 980, y: 415, center: center, size: size)),
                "A point outside the food ellipse must not count even when it is inside the sprite.")
        #expect(dock.containsFoodContact(imagePoint(x: 687, y: 415, center: center, size: size)))
        #expect(!dock.containsFoodContact(CGPoint(x: CGFloat.nan, y: center.y)))
    }

    @Test(arguments: [0.5, 1.0, 1.5], [-1.0, 1.0])
    func walkToStageAndDockBackwardsSweepClearBowlAndFloor(scale: Double, facing: Double) throws {
        let width = 88 * CGFloat(scale), direction = CGFloat(facing)
        let size = CGSize(width: width * 0.245 / 0.22, height: width * 0.245 / 0.22 * 1145 / 1374)
        let center = CGPoint(x: 3 * width, y: 1.5 * width)
        let floorBounds = CGRect(x: 0, y: 0, width: 6 * width, height: 4 * width)
        let bowl = solidBowl(center: center, size: size)
        let dock = FeedingDock(catWidth: width, bowlSize: size, bowlCenter: center, facing: direction)
        let walkingFootprint = CGSize(width: 1.36 * width, height: 0.25 * width)
        // Stage behind the bowl, with room for the normal footprint to turn.
        // The final corridor then travels diagonally forward into the food dock.
        let stage = CGPoint(x: dock.eatingPoint.x - direction * 0.36 * width,
                            y: bowl.maxY + walkingFootprint.height / 2 + 0.025 * width)
        let home = CGPoint(x: stage.x - direction * 0.5 * width, y: stage.y - 0.35 * width)
        let walking = RoomNavigation(floor: corners(floorBounds), obstacles: [bowl],
                                     footprint: walkingFootprint, cellSize: 7 * CGFloat(scale))
        let approach = try #require(walking.route(from: home, to: stage))
        #expect(approach.first == home && approach.last == stage)
        #expect(approach.count > 2, "The ordinary approach must first go around the bowl to its safe stage.")
        for (start, end) in zip(approach, approach.dropFirst()) {
            #expect(walking.segmentIsWalkable(from: start, to: end))
            for actor in samples(from: start, to: end) {
                let feet = centeredRect(at: actor, size: walkingFootprint)
                #expect(floorBounds.contains(feet))
                #expect(!feet.intersects(bowl))
            }
        }

        // Normal walking cannot occupy the contact point. The narrow final
        // movement must use the measured, offset paw footprint explicitly.
        #expect(!walking.isWalkable(dock.eatingPoint))
        let docking = RoomNavigation(floor: corners(floorBounds), obstacles: [bowl],
                                     footprint: dock.footprint, cellSize: 7 * CGFloat(scale))
        let stageCenter = dock.footCenter(at: stage)
        let eatingCenter = dock.footCenter(at: dock.eatingPoint)
        #expect(docking.route(from: stageCenter, to: eatingCenter) == [stageCenter, eatingCenter])
        #expect(docking.segmentIsWalkable(from: eatingCenter, to: stageCenter),
                "The same fixed-facing footprint must also clear the backward exit.")
        for actor in samples(from: stage, to: dock.eatingPoint) {
            // CGRect is a separate collision oracle from RoomNavigation's
            // swept-footprint implementation, so a shared navigator bug cannot
            // make both the proposed route and its sole assertion pass.
            let feet = dock.feetRect(at: actor)
            #expect(floorBounds.contains(feet))
            #expect(!feet.intersects(bowl))
        }
    }

    @Test(arguments: [-1.0, 1.0])
    func dockingStillRejectsBowlPenetrationAndWallOverlap(facing: Double) {
        let width: CGFloat = 88
        let size = CGSize(width: width * 0.245 / 0.22, height: width * 0.245 / 0.22 * 1145 / 1374)
        let center = CGPoint(x: 3 * width, y: 1.5 * width)
        let floorBounds = CGRect(x: 0, y: 0, width: 6 * width, height: 4 * width)
        let direction = CGFloat(facing)
        let dock = FeedingDock(catWidth: width, bowlSize: size, bowlCenter: center, facing: direction)
        let bowl = solidBowl(center: center, size: size)
        let docking = RoomNavigation(floor: corners(floorBounds), obstacles: [bowl], footprint: dock.footprint)

        // Only 0.03C toward the camera is enough to enter the physical bowl.
        // Docking is not a blanket exception to collision detection.
        let tooLow = CGPoint(x: dock.eatingPoint.x, y: dock.eatingPoint.y - 0.03 * width)
        #expect(dock.feetRect(at: tooLow).intersects(bowl))
        #expect(!docking.isWalkable(dock.footCenter(at: tooLow)))
        #expect(docking.route(from: dock.footCenter(at: dock.eatingPoint),
                              to: dock.footCenter(at: tooLow)) == nil)

        let tightFloor = CGRect(x: 0, y: 0, width: floorBounds.width, height: dock.eatingPoint.y + 0.10 * width)
        let nearWall = RoomNavigation(floor: corners(tightFloor), obstacles: [bowl], footprint: dock.footprint)
        #expect(tightFloor.contains(dock.eatingPoint), "The actor anchor alone appears to fit below the wall.")
        #expect(!tightFloor.contains(dock.feetRect(at: dock.eatingPoint)))
        #expect(!nearWall.isWalkable(dock.footCenter(at: dock.eatingPoint)),
                "Docking must still reject a wall that crosses the upper paws.")

        // Smaller bowls can put the target too low for this pose. The contact
        // model supplies geometry; the navigator must reject unsafe size ratios.
        let smallSize = CGSize(width: 0.90 * width, height: 0.90 * width * 1145 / 1374)
        let smallDock = FeedingDock(catWidth: width, bowlSize: smallSize, bowlCenter: center, facing: direction)
        let smallBowl = solidBowl(center: center, size: smallSize)
        let smallNavigation = RoomNavigation(floor: corners(floorBounds), obstacles: [smallBowl],
                                             footprint: smallDock.footprint)
        #expect(smallDock.feetRect(at: smallDock.eatingPoint).intersects(smallBowl))
        #expect(!smallNavigation.isWalkable(smallDock.footCenter(at: smallDock.eatingPoint)))
    }

    private func solidBowl(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: center.x - 0.34 * size.width, y: center.y - 0.09 * size.width - 0.15 * size.height,
               width: 0.68 * size.width, height: 0.30 * size.height)
    }

    private func imagePoint(x: CGFloat, y: CGFloat, center: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: center.x + (x / 1374 - 0.5) * size.width,
                y: center.y + (0.5 - y / 1145) * size.height)
    }

    private func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    private func centeredRect(at point: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }

    private func samples(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        (0...40).map { step in
            let fraction = CGFloat(step) / 40
            return CGPoint(x: start.x + (end.x - start.x) * fraction,
                           y: start.y + (end.y - start.y) * fraction)
        }
    }
}
