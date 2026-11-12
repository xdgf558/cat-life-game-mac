import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// Camera and touch arbitration, including cancelling a drag before a pinch.
@MainActor
extension RoomScene {
    func resetCamera() {
        cancelSingleTouchSequence()
        beginRoomFollowing()
        roomPresentation.camera.focus(on: roomPresentation.projection.project(cat.position))
        updateRoomPresentation()
    }

    var canZoomCamera: Bool {
        #if os(macOS)
        if desktopViewTransitionTask != nil { return false }
        #endif
        return presentationActive && deferredRoomLayoutFromSize == nil
            && bowlPlanningRequest == nil && size.width > 0 && size.height > 0
    }

    #if os(iOS)
    /// UIKit supplies cumulative pinch scale and a location in SKView points.
    func handlePinch(state: UIGestureRecognizer.State, scale: CGFloat, location: CGPoint) {
        switch state {
        case .began:
            guard canZoomCamera else { return }
            cancelSingleTouchSequence()
            suspendRoomFollowing()
            roomPresentation.camera.beginPinch(at: location)
        case .changed:
            guard canZoomCamera else { roomPresentation.camera.endPinch(); return }
            roomPresentation.camera.changePinch(factor: scale, at: location)
        case .ended, .cancelled, .failed:
            // The last remaining finger must not replace the two-finger center.
            roomPresentation.camera.endPinch()
        default: break
        }
        updateRoomPresentation()
#if DEBUG
        publishNavigationStatus()
        publishDragMetrics()
        publishFurnitureStatus()
#endif
    }

    #endif

    /// Cursor-anchored wheel/trackpad zoom uses the same clamped camera as touch pinch.
    func zoomCamera(at point: CGPoint, factor: CGFloat) {
        guard canZoomCamera, !dragging, !isPlacementPending, factor.isFinite, factor > 0 else { return }
        cancelSingleTouchSequence()
        suspendRoomFollowing()
        roomPresentation.camera.beginPinch(at: point)
        roomPresentation.camera.changePinch(factor: factor, at: point)
        roomPresentation.camera.endPinch()
        updateRoomPresentation()
    }

    func zoomIn() { zoomCamera(by: 1.25) }
    func zoomOut() { zoomCamera(by: 0.8) }

    private func zoomCamera(by factor: CGFloat) {
        guard canZoomCamera else { return }
        cancelSingleTouchSequence()
        suspendRoomFollowing()
        roomPresentation.camera.zoom(by: factor)
        updateRoomPresentation()
#if DEBUG
        publishNavigationStatus()
        publishDragMetrics()
        publishFurnitureStatus()
#endif
    }

    func cancelSingleTouchSequence() {
        blockedTouchSequence = true
        #if os(iOS)
        sceneTouch = nil
        #endif
        if dragging { cancelPlacementPreview() }
        _ = roomPresentation.camera.endPan()
        touchOrigin = nil
        dragScreenPoint = nil
    }

    func cancelCameraInteraction() {
        cancelSingleTouchSequence()
        roomPresentation.camera.cancelGestures()
    }
    func previewFloorPoint(_ point: CGPoint) -> CGPoint {
        previewArrangementPoint68(point)
    }

    #if os(iOS)
    func beginTouches(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasMultipleActiveTouches(touches, event: event) { cancelSingleTouchSequence(); return }
        guard !roomPresentation.camera.isPinching, bowlPlanningRequest == nil,
              let touch = touches.first, let view else { return }
        sceneTouch = touch
        beginPointer(at: touch.location(in: view))
    }
    func moveTouches(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasMultipleActiveTouches(touches, event: event) { cancelSingleTouchSequence(); return }
        guard let touch = sceneTouch, touches.contains(touch), let view else { return }
        movePointer(to: touch.location(in: view))
    }
    func endTouches(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = sceneTouch, touches.contains(touch), let view else { return }
        defer { sceneTouch = nil }
        endPointer(at: touch.location(in: view))
    }
    func cancelTouches(_ touches: Set<UITouch>, with event: UIEvent?) {
#if DEBUG
        if diagnostics.furnitureTesting { diagnostics.lastRestInput += ";cancelled" }
#endif
        cancelSingleTouchSequence()
    }
    private func hasMultipleActiveTouches(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
        let active = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }
        return (active?.count ?? touches.count) > 1
    }
    #endif

    /// Both platforms enter the same projection, drag and release planning path.
    func beginPointer(at screen: CGPoint) {
        #if os(macOS)
        guard desktopViewTransitionTask == nil else { return }
        #endif
        guard presentationActive, !roomPresentation.camera.isPinching, bowlPlanningRequest == nil else { return }
        blockedTouchSequence = false
        let point = roomPresentation.worldPoint(screen: screen)
        touchOrigin = screen
        roomPresentation.camera.beginPan(at: screen)
#if DEBUG
        if diagnostics.furnitureTesting { diagnostics.lastRestInput = "began:\(point.x),\(point.y)" }
#endif
        guard editing, activeRest == nil else { return }
        guard !arrangementYielding68, arrangement68.pendingRequest == nil,
              arrangement68.worker == nil || newPlacementID != nil else { return }
        guard let hit = roomPresentation.hit(screen: screen, editing: true) else { return }
        let chosenID: String? = hit == "bowl" ? nil : String(hit.dropFirst("furniture-".count))
        // A pending new item can be grabbed again, but a second item must wait
        // for its placement or be reached after cancelling the current preview.
        if newPlacementID != nil && chosenID != selectedFurnitureID { return }
        if selectedFurnitureID != chosenID {
            if isPlacementPending { cancelPlacementPreview() }
            selectedFurnitureID = chosenID
            placementPrepared = false
        }
        arrangement68.bowlSelected = chosenID == nil
        onFurnitureSelected?(chosenID)
        placementRevision += 1
        placementTask?.cancel()
        placementTask = nil
        arrangement68.worker?.cancel()
        arrangement68.worker = nil
        preparePlacementNavigation()
        dragging = true
        beginArrangementGesture68()
#if DEBUG
        diagnostics.furnitureDragPreviewSamples = 0
        diagnostics.furnitureDragPreviewPoint = nil
#endif
        dragScreenPoint = screen
        _ = roomPresentation.camera.endPan()
        setPlacementPending(true)
        // The front floor is not affine; keep the grip in display pixels across its projection sectors.
        let anchor = roomPresentation.anchor(hit) ?? screen
        dragDisplayOffset = CGPoint(x: anchor.x - screen.x, y: anchor.y - screen.y)
        updateSelection()
#if DEBUG
        publishFurnitureStatus()
#endif
    }

    func movePointer(to screen: CGPoint) {
        guard !blockedTouchSequence, !roomPresentation.camera.isPinching else { return }
        if !dragging {
            if view != nil {
                if roomPresentation.camera.changePan(to: screen) { suspendRoomFollowing() }
                updateRoomPresentation()
            }
            return
        }
        dragScreenPoint = screen
#if DEBUG
        let started = CACurrentMediaTime()
#endif
        let point = roomPresentation.worldPoint(screen: screen, wall: selectedIsWall,
                                               displayOffset: dragDisplayOffset)
        selectedNode.position = previewFloorPoint(point)
#if DEBUG
        diagnostics.furnitureDragPreviewSamples += 1
        diagnostics.furnitureDragPreviewPoint = selectedNode.position
#endif
        updateSelection()
        updateBowlLayers()
        updateFurnitureLayers()
        updateRoomPresentation()
#if DEBUG
        if diagnostics.dragTesting {
            diagnostics.dragMoveSamples += 1
            diagnostics.maximumDragMoveMs = max(diagnostics.maximumDragMoveMs, (CACurrentMediaTime() - started) * 1_000)
        }
#endif
    }

    func endPointer(at screen: CGPoint) {
        guard !blockedTouchSequence, !roomPresentation.camera.isPinching else { return }
#if DEBUG
        if diagnostics.furnitureTesting { diagnostics.lastRestInput += ";ended" }
#endif
        let wasPanning = roomPresentation.camera.endPan()
        defer { dragging = false; touchOrigin = nil; dragScreenPoint = nil }
        if wasPanning { return }
        if dragging {
            let point = roomPresentation.worldPoint(screen: screen, wall: selectedIsWall,
                                                   displayOffset: dragDisplayOffset)
            selectedNode.position = previewFloorPoint(point)
            // A tap selects without doing an expensive route search.
            if let origin = touchOrigin,
               hypot(screen.x - origin.x, screen.y - origin.y) < 3,
               newPlacementID == nil {
                selectedNode.position = selectedFurnitureID.flatMap { furnitureWorld.center($0) } ?? committedBowlPosition
                setPlacementPending(false)
                preserveUnmovedArrangementIssue68(arrangement68.gestureIssues[selectedFurnitureID ?? "bowl"])
                endArrangementGesture68()
                updateSelection()
                focusArrangementSelection68()
#if DEBUG
                publishFurnitureStatus()
#endif
                return
            }
            resolveReleasedItem()
#if DEBUG
            publishDragMetrics()
            publishFurnitureStatus()
#endif
            return
        }
        guard !editing, let origin = touchOrigin else { return }
        let point = screen
        guard hypot(point.x - origin.x, point.y - origin.y) < 12 else { return }
        let hit = roomPresentation.hit(screen: point, editing: false)
        #if os(macOS)
        if hit == nil, let structure = roomPresentation.fixedStructure(at: point) {
            onFixedStructureTapped?(structure)
            return
        }
        #endif
        if hit == "bowl" { onBowlTapped?() }
        else if hit == "cat" {
            if activeRest != nil { pendingRestID = nil; leaveFurnitureRest() }
            else if canInspectResidents { onCatTapped?() }
        } else if let hit, hit.hasPrefix("resident-") {
            if canInspectResidents { onResidentTapped?(String(hit.dropFirst("resident-".count))) }
        } else {
            onBackgroundTapped?()
            if let hit, hit.hasPrefix("furniture-") { requestFurnitureRest68(String(hit.dropFirst("furniture-".count))) }
        }
    }

    private var selectedIsWall: Bool {
        selectedFurnitureID.flatMap { furnitureWorld.item($0) }.map { RoomFurnitureSpec.forItem($0).isWall } ?? false
    }

    func updateRoomEdgeScrolling(delta: TimeInterval) {
        guard dragging, let screen = dragScreenPoint,
              roomPresentation.camera.scrollNearEdge(at: screen, delta: delta) else { return }
        let point = roomPresentation.worldPoint(screen: screen, wall: selectedIsWall,
                                               displayOffset: dragDisplayOffset)
        selectedNode.position = previewFloorPoint(point)
        updateSelection()
    }
}
