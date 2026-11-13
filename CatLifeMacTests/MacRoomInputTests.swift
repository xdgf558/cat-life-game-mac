#if os(macOS)
import XCTest
import AppKit
@testable import CatLifeMac

@MainActor
final class MacRoomInputTests: XCTestCase {
    func testOnlyCatClicksWaitWhileBowlFurnitureAndBackgroundRespondImmediately() async throws {
        let size = CGSize(width: 800, height: 600)
        let scene = RoomScene(size: size)
        scene.reducedMotion = true
        let view = MacRoomSKView(frame: CGRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.presentScene(scene)
        scene.apply(snapshot: .fresh(now: Date()), editing: false)
        defer {
            view.inputEnabled = false
            scene.setPresentationActive(false)
            view.presentScene(nil)
            window.close()
        }
        for _ in 0..<200 where scene.bowlPlanningRequest != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(scene.bowlPlanningRequest)
        scene.updateRoomPresentation()
        var meals = 0, backgrounds = 0, profiles = 0, closeUps = 0
        scene.onBowlTapped = { meals += 1 }
        scene.onBackgroundTapped = { backgrounds += 1 }
        scene.onCatTapped = { profiles += 1 }
        view.contextAction = { if case .closeUp = $0 { closeUps += 1 } }

        let bowl = try XCTUnwrap(scene.roomPresentation.frame("bowl"))
        let bowlPoint = CGPoint(x: bowl.midX, y: bowl.midY)
        try clickRoom(at: bowlPoint, count: 1, in: view)
        XCTAssertEqual(meals, 1, "The bowl action must arrive before another click can cancel it.")
        let cabinet = try XCTUnwrap(scene.ownedFurniture.first { $0.kind == .cabinet })
        let furniture = try XCTUnwrap(scene.roomPresentation.frame("furniture-" + cabinet.id))
        try clickRoom(at: CGPoint(x: furniture.midX, y: furniture.midY), count: 1, in: view)
        XCTAssertEqual(backgrounds, 1, "Furniture must not wait for an unrelated cat double-click.")
        let empty = try XCTUnwrap(stride(from: 20, to: 580, by: 40).lazy.flatMap { y in
            stride(from: 20, to: 780, by: 40).map { CGPoint(x: CGFloat($0), y: CGFloat(y)) }
        }.first { scene.roomPresentation.hit(screen: $0, editing: false) == nil })
        try clickRoom(at: empty, count: 1, in: view)
        XCTAssertEqual(backgrounds, 2, "Background taps must clear overlays immediately.")
        try clickRoom(at: bowlPoint, count: 2, in: view)
        XCTAssertEqual(meals, 2, "A second non-cat click must not be swallowed by double-click arbitration.")

        let cat = try XCTUnwrap(scene.roomPresentation.frame("cat"))
        let catPoint = CGPoint(x: cat.midX, y: cat.midY)
        try clickRoom(at: catPoint, count: 1, in: view)
        XCTAssertEqual(profiles, 0, "A cat click must still wait for the native double-click interval.")
        try clickRoom(at: catPoint, count: 2, in: view)
        XCTAssertEqual(closeUps, 1)
        XCTAssertEqual(profiles, 0, "The second cat click must cancel the pending modal profile.")
    }

    private func clickRoom(at point: CGPoint, count: Int, in view: MacRoomSKView) throws {
        let local = MacRoomPointer.screenPoint(point, height: view.bounds.height, isFlipped: view.isFlipped)
        let location = view.convert(local, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window?.windowNumber ?? 0,
                context: nil, eventNumber: 1, clickCount: count, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
    }

    func testNativeViewCoordinatesMatchSceneTopLeftConvention() {
        let point = CGPoint(x: 240, y: 160)
        XCTAssertEqual(MacRoomPointer.screenPoint(point, height: 720, isFlipped: false), CGPoint(x: 240, y: 560))
        XCTAssertEqual(MacRoomPointer.screenPoint(point, height: 720, isFlipped: true), point)
        let converted = MacRoomPointer.screenPoint(point, height: 720, isFlipped: false)
        XCTAssertEqual(MacRoomPointer.screenPoint(converted, height: 720, isFlipped: false), point)
    }

    func testWheelReversalAndLargeDeltasStayBounded() {
        XCTAssertEqual(MacRoomPointer.zoomFactor(delta: 0, reversed: false), 1)
        for delta: CGFloat in [-100_000, -2, 2, 100_000] {
            let normal = MacRoomPointer.zoomFactor(delta: delta, reversed: false)
            let reversed = MacRoomPointer.zoomFactor(delta: delta, reversed: true)
            XCTAssertEqual(normal * reversed, 1, accuracy: 0.000_001)
            XCTAssertLessThanOrEqual(normal, exp(0.35))
            XCTAssertGreaterThanOrEqual(normal, exp(-0.35))
        }
    }

    func testFrameLimitHonorsSettingAndDisplayRefreshRate() {
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 120, screenMaximum: 120), 120)
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 120, screenMaximum: 60), 60)
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 30, screenMaximum: 120), 30)
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 999, screenMaximum: 120), 60)
    }

    func testWholeRoomZoomKeepsCenterWhenTheViewportIsWiderThanTheRoom() {
        let camera = RoomViewCamera()
        camera.configure(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            viewport: CGSize(width: 800, height: 600), usableRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            worldScale: 2, reset: true)
        // Fit includes horizontal letterboxing; keeping the room in bounds takes priority over the cursor anchor.
        camera.beginPinch(at: CGPoint(x: 430, y: 280))
        camera.changePinch(factor: MacRoomPointer.zoomFactor(delta: 8, reversed: false), at: CGPoint(x: 430, y: 280))
        camera.endPinch()
        XCTAssertGreaterThan(camera.visibleRect.width, 1000)
        XCTAssertEqual(camera.center.x, 500, accuracy: 0.000_001)
    }

    func testReadOnlyPreviewFinishesLayoutWithoutActivatingGameplay() async throws {
        let scene = RoomScene(size: CGSize(width: 800, height: 600))
        scene.setPresentationActive(false)
        scene.apply(snapshot: .fresh(now: Date()), editing: false)
        scene.prepareDesktopView(initialAngle: .right)
        scene.setReadOnlyPreviewEnabled(true)
        defer { scene.setReadOnlyPreviewEnabled(false); scene.setPresentationActive(false) }
        for _ in 0..<200 where scene.bowlPlanningRequest != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(scene.bowlPlanningRequest)
        XCTAssertFalse(scene.cat.isHidden)
        XCTAssertFalse(scene.bowl.isHidden)
        XCTAssertFalse(scene.presentationActive)
        XCTAssertEqual(scene.roomViewAngle, .right)
        XCTAssertTrue(scene.isWholeRoomView)
        scene.takeQuietStroll(now: Date().addingTimeInterval(120), restRoll: 0)
        XCTAssertNil(scene.activeRest)
    }

    func testPreviewAndRetainedRoomRepublishReadinessAndCatsToANewHost() async throws {
        let scene = RoomScene(size: CGSize(width: 800, height: 600))
        scene.setPresentationActive(false)
        scene.apply(snapshot: .fresh(now: Date()), editing: false)
        scene.setReadOnlyPreviewEnabled(true)
        defer { scene.setReadOnlyPreviewEnabled(false); scene.setPresentationActive(false) }
        for _ in 0..<200 where scene.bowlPlanningRequest != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(scene.bowlPlanningRequest)
        // The title preview consumes scene samples without forwarding them to Store.
        scene.onFloorTravelAvailabilityChanged = { _ in }
        scene.onVisibleResidentsChanged = { _ in }
        scene.update(1)
        var readiness: [Bool] = []
        var visible: [Set<String>] = []
        scene.onFloorTravelAvailabilityChanged = { readiness.append($0) }
        scene.onVisibleResidentsChanged = { visible.append($0) }
        scene.setReadOnlyPreviewEnabled(false)
        scene.setPresentationActive(true)
        scene.update(2)
        XCTAssertEqual(readiness, [true], "Title → home must publish the already-idle state.")
        XCTAssertTrue(visible.last?.contains(try XCTUnwrap(scene.displayedCatID)) == true)

        scene.setPresentationActive(false) // A shop/work page retains the scene without rendering it.
        readiness = []; visible = []
        scene.onFloorTravelAvailabilityChanged = { readiness.append($0) }
        scene.onVisibleResidentsChanged = { visible.append($0) }
        scene.setPresentationActive(true)
        scene.update(3)
        XCTAssertEqual(readiness, [true], "Home → shop → home must not retain a stale Store travel lock.")
        XCTAssertTrue(visible.last?.contains(try XCTUnwrap(scene.displayedCatID)) == true)
    }

    func testCursorAnchoredZoomKeepsTheSameRoomPoint() {
        let camera = RoomViewCamera()
        camera.configure(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            viewport: CGSize(width: 800, height: 600), usableRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            worldScale: 2, reset: true)
        camera.zoom(by: 2)
        let cursor = CGPoint(x: 430, y: 280)
        let world = camera.worldPoint(viewPoint: cursor)
        camera.beginPinch(at: cursor)
        camera.changePinch(factor: MacRoomPointer.zoomFactor(delta: 8, reversed: false), at: cursor)
        camera.endPinch()
        let result = camera.viewPoint(projectedWorld: world)
        XCTAssertEqual(result.x, cursor.x, accuracy: 0.000_001)
        XCTAssertEqual(result.y, cursor.y, accuracy: 0.000_001)
        XCTAssertFalse(camera.isPinching)
    }
}
#endif
