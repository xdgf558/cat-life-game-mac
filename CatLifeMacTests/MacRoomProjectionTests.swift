#if os(macOS)
import XCTest
import CatGameCore
@testable import CatLifeMac

final class MacRoomProjectionTests: XCTestCase {
    func testAllAnglesRoundTripTheSameTwelveBySevenFloorAtEveryHomeLevel() throws {
        for level in HomeCatalog.all {
            var state = GameSnapshot.fresh(now: Date(timeIntervalSince1970: 1_793_600_000))
            state.home = HomeState(roomLevel: level.level)
            let world = MacRoomLayoutRepair.makeWorld(state, floor: .ground)
            for angle in RoomViewAngle.allCases {
                let model = try XCTUnwrap(MacRoomProjection(legacyFloor: world.roomFloor.polygon,
                    worldSize: world.transform.sceneSize, angle: angle))
                for x in 0...24 { for z in 0...14 {
                    let cell = CGPoint(x: CGFloat(x) / 2, y: CGFloat(z) / 2)
                    let logical = model.logicalPoint(cell: cell)
                    let result = model.unproject(model.project(logical))
                    XCTAssertEqual(result.x, logical.x, accuracy: 0.000_001)
                    XCTAssertEqual(result.y, logical.y, accuracy: 0.000_001)
                    let back = model.cellPoint(logical: logical)
                    XCTAssertEqual(back.x, cell.x, accuracy: 0.000_001)
                    XCTAssertEqual(back.y, cell.y, accuracy: 0.000_001)
                } }
                for x in stride(from: CGFloat(0.5), through: 11.5, by: 0.5) {
                    let point = model.wallPoint(x: x, height: 2.9)
                    let cell = model.wallCoordinates(projected: point)
                    XCTAssertEqual(cell.x, x, accuracy: 0.000_001)
                    XCTAssertEqual(cell.y, 2.9, accuracy: 0.000_001)
                }
            }
        }
    }

    func testMacGridSnapAndNudgeUseCellsRatherThanTheOldArtworkAxes() throws {
        let world = MacRoomLayoutRepair.makeWorld(.fresh(now: Date()), floor: .ground)
        let model = try XCTUnwrap(MacRoomReservations.projection(transform: world.transform))
        let grid = RoomArrangementGrid68(transform: world.transform)
        let point = model.logicalPoint(cell: CGPoint(x: 5.32, y: 2.77))
        let snapped = grid.gridPoint(world: grid.snapped(point, enabled: true))
        XCTAssertEqual(snapped.x, 5.5, accuracy: 0.000_001)
        XCTAssertEqual(snapped.y, 3, accuracy: 0.000_001)
        var projection = RoomViewProjection(worldSize: world.transform.sceneSize, angle: .front)
        projection.macRoom = model
        let nudged = grid.gridPoint(world: grid.nudged(point, dx: 1, dy: 0, step: 0.1, projection: projection, wall: false))
        XCTAssertEqual(hypot(nudged.x - 5.32, nudged.y - 2.77), 0.1, accuracy: 0.000_001)
    }

    func testDoorClearanceRejectsPlacementButRemainsWalkableAndStairsBlockWalking() throws {
        let original = MacRoomLayoutRepair.makeWorld(.fresh(now: Date()), floor: .ground)
        let world = RoomFurnitureWorld(transform: original.transform, catWidth: original.catWidth,
            bowlSize: original.bowlSize, bowlPosition: original.bowlPosition, items: original.items, placements: [])
        let model = try XCTUnwrap(MacRoomReservations.projection(transform: world.transform))
        let door = model.logicalPoint(cell: CGPoint(x: 1, y: 2))
        let stairs = model.logicalPoint(cell: CGPoint(x: 11, y: 5.5))
        let navigation = RoomNavigation(floor: world.roomFloor.polygon, obstacles: world.floorObstacles(),
            footprint: CGSize(width: 1, height: 1), precomputeGrid: false)
        XCTAssertTrue(navigation.isWalkable(door), "Door clearance is a passage, not an obstacle.")
        XCTAssertFalse(navigation.isWalkable(stairs))
        let floorItem = try XCTUnwrap(world.items.first { $0.kind == .plant })
        XCTAssertNotNil(RoomArrangementPlanning68.issue(id: floorItem.id, at: door, world: world))
        XCTAssertNotNil(RoomArrangementPlanning68.issue(id: floorItem.id, at: stairs, world: world))
    }

    @MainActor
    func testFullRoomFitContainsShellAndAllViewAnglesUseTheSameZoomLimit() throws {
        let world = MacRoomLayoutRepair.makeWorld(.fresh(now: Date()), floor: .ground)
        for angle in RoomViewAngle.allCases {
            let model = try XCTUnwrap(MacRoomProjection(legacyFloor: world.roomFloor.polygon,
                worldSize: world.transform.sceneSize, angle: angle))
            for viewport in [CGSize(width: 920, height: 650), CGSize(width: 1400, height: 820)] {
                let camera = RoomViewCamera()
                let safe = CGRect(x: 26, y: 90, width: viewport.width - 52, height: viewport.height - 192)
                camera.configure(bounds: model.contentBounds, viewport: viewport, usableRect: safe, worldScale: 1.0625, reset: true)
                for point in [CGPoint(x: model.contentBounds.minX, y: model.contentBounds.minY),
                              CGPoint(x: model.contentBounds.maxX, y: model.contentBounds.maxY)] {
                    let display = camera.viewPoint(projectedWorld: point)
                    XCTAssertTrue(safe.insetBy(dx: -0.001, dy: -0.001).contains(display))
                }
                camera.zoom(by: 100)
                XCTAssertEqual(camera.fitScale / camera.scale, 1.7, accuracy: 0.000_001)
            }
        }
    }

    @MainActor
    func testDecoratingCanFinishAViewTurnAndReducedMotionChangesAngleImmediately() async throws {
        let size = CGSize(width: 900, height: 700)
        let scene = RoomScene(size: size)
        let view = MacRoomSKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        scene.setReferenceViewportSize(CGSize(width: 390, height: 600))
        let snapshot = try await MacRoomSaveRepair.prepare(.fresh(now: Date()), now: Date(), isNewHome: true)
        scene.apply(snapshot: snapshot, editing: true)
        defer { scene.setPresentationActive(false); view.presentScene(nil) }
        for _ in 0..<200 where scene.bowlPlanningRequest != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(scene.editing)
        XCTAssertTrue(scene.canChangeRoomView)
        scene.reducedMotion = false
        scene.turnRoomView(by: 1)
        XCTAssertNotNil(scene.desktopViewTransitionTask)
        try await Task.sleep(for: .milliseconds(230))
        XCTAssertEqual(scene.roomViewAngle, .right, "The fade must allow a view turn while editing stays true.")
        scene.cancelDesktopViewTransition()
        scene.reducedMotion = true
        scene.turnRoomView(by: -1)
        XCTAssertEqual(scene.roomViewAngle, .front)
        XCTAssertNil(scene.desktopViewTransitionTask)
        XCTAssertEqual(scene.roomPresentation.root.alpha, 1)
    }

    @MainActor
    func testReadOnlyPreviewShowsRealResidentIdleWithoutStartingCareOrRest() async throws {
        let date = Date()
        var snapshot = GameSnapshot.fresh(now: date)
        snapshot.home = HomeState(roomLevel: 4)
        snapshot.cats.append(CatState(id: CatCatalog.cowCatID, name: "Cow", now: date, appearance: .cow))
        snapshot = try await MacRoomSaveRepair.prepare(snapshot, now: date)
        let scene = RoomScene(size: CGSize(width: 900, height: 700))
        scene.setReferenceViewportSize(CGSize(width: 390, height: 600))
        scene.setPresentationActive(false)
        scene.apply(snapshot: snapshot, editing: false)
        var restChanges = 0, careRequests = 0
        scene.onRestingFurnitureChanged = { _, _, _ in restChanges += 1 }
        scene.onBowlTapped = { careRequests += 1 }
        scene.setReadOnlyPreviewEnabled(true)
        defer { scene.setReadOnlyPreviewEnabled(false); scene.setPresentationActive(false) }
        for _ in 0..<400 where scene.bowlPlanningRequest != nil || scene.residents.isPreparing {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(scene.presentationActive)
        XCTAssertFalse(scene.cat.isHidden)
        XCTAssertNotNil(scene.cat.action(forKey: "breathing"))
        XCTAssertNotNil(scene.cat.action(forKey: "idle-event"))
        let resident = try XCTUnwrap(scene.residents.actors[CatCatalog.cowCatID])
        XCTAssertFalse(resident.isHidden)
        XCTAssertNotNil(resident.action(forKey: "breathing"))
        XCTAssertNil(scene.action(forKey: "ambient-walk"))
        scene.takeQuietStroll(now: date.addingTimeInterval(120), restRoll: 0)
        XCTAssertNil(scene.activeRest)
        XCTAssertFalse(scene.cat.isPerforming)
        XCTAssertEqual(restChanges, 0)
        XCTAssertEqual(careRequests, 0)
        scene.setReadOnlyPreviewEnabled(false)
        XCTAssertNil(scene.cat.action(forKey: "breathing"))
        XCTAssertNil(resident.action(forKey: "breathing"))
    }

    @MainActor
    func testLeavingTheRoomCancelsAnUnfinishedViewFadeAndRestoresVisibility() {
        let scene = RoomScene(size: CGSize(width: 900, height: 700))
        scene.desktopViewTransitionID = UUID()
        scene.desktopViewTransitionTask = Task { try? await Task.sleep(for: .seconds(10)) }
        scene.roomPresentation.root.alpha = 0.2
        scene.setPresentationActive(false)
        XCTAssertNil(scene.desktopViewTransitionTask)
        XCTAssertNil(scene.desktopViewTransitionID)
        XCTAssertEqual(scene.roomPresentation.root.alpha, 1)
    }

    @MainActor
    func testTransparentPreviewHidesOnlyTheSimulationParentAndKeepsSourceVisibilityIntact() {
        let scene = RoomScene(size: CGSize(width: 900, height: 700))
        scene.setPresentationActive(false)
        scene.setReadOnlyPreviewEnabled(true)
        scene.cat.isHidden = false
        XCTAssertTrue(scene.simulationRoot.isHidden)
        XCTAssertTrue(scene.cat.parent === scene.simulationRoot)
        XCTAssertFalse(scene.cat.isHidden, "Mirrors must still read each source node's own visibility.")
        scene.prepareDesktopEntry()
        XCTAssertEqual(scene.desktopInitialViewAngle, .front)
    }
}
#endif
