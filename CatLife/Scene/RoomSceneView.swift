import SpriteKit

/// View state stays outside saved layouts and never changes actor/path coordinates.
@MainActor
extension RoomScene {
    var roomViewAngle: RoomViewAngle { roomPresentation.projection.angle }
    var isWholeRoomView: Bool { roomPresentation.camera.isWholeRoom }
    var canChangeRoomView: Bool {
        #if os(macOS)
        if desktopViewTransitionTask != nil { return false }
        #endif
        return presentationActive && !dragging && !isPlacementPending && !arrangementYielding68
            && arrangement68.worker == nil && arrangement68.pendingRequest == nil
            && bowlPlanningRequest == nil && !residents.isPreparing
    }

    #if os(macOS)
    func cancelDesktopViewTransition() {
        desktopViewTransitionTask?.cancel()
        desktopViewTransitionTask = nil; desktopViewTransitionID = nil
        roomPresentation.root.removeAction(forKey: "mac-view-fade")
        roomPresentation.root.alpha = 1
    }

    /// Returning from the title is an explicit new viewing entry, not a per-refresh camera reset.
    func prepareDesktopEntry() {
        guard !editing else { return }
        cancelDesktopViewTransition()
        hasPreparedDesktopView = false
        desktopInitialViewAngle = .front
        prepareDesktopView(initialAngle: .front)
    }

    /// Desktop starts with the complete room; subsequent changes belong to the player.
    @discardableResult
    func prepareDesktopView(initialAngle: RoomViewAngle? = nil) -> Bool {
        if let initialAngle, !hasPreparedDesktopView { desktopInitialViewAngle = initialAngle }
        desktopViewRequested = true
        guard !hasPreparedDesktopView else { return true }
        guard let floor, bowlPlanningRequest == nil else { return false }
        hasPreparedDesktopView = true
        cancelCameraInteraction()
        suspendRoomFollowing()
        roomPresentation.configure(world: worldGeometry.worldSize, viewport: size, floor: floor.polygon,
                                   angle: desktopInitialViewAngle, level: renderedRoomLevel, homeFloor: homeFloor)
        roomPresentation.camera.fit()
        updateRoomPresentation()
        return true
    }
    #endif

    func setRoomViewUsableRect(_ rect: CGRect) {
        roomPresentation.setUsableRect(rect)
        updateRoomPresentation()
    }

    func turnRoomView(by steps: Int) {
        guard canChangeRoomView else { return }
        let next = min(1, max(-1, roomViewAngle.rawValue + steps.signum()))
        guard let angle = RoomViewAngle(rawValue: next), angle != roomViewAngle else { return }
        cancelCameraInteraction()
        suspendRoomFollowing()
        #if os(macOS)
        if !reducedMotion {
            let ticket = UUID(), owner = macCanvasOwnerID, entryFloor = homeFloor
            let entryLevel = renderedRoomLevel, entryWorld = worldGeometry.worldSize, catID = displayedCatID, entryEditing = editing
            desktopViewTransitionID = ticket
            roomPresentation.root.run(.fadeOut(withDuration: 0.18), withKey: "mac-view-fade")
            desktopViewTransitionTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard let self, self.desktopViewTransitionID == ticket else { return }
                guard self.presentationActive, self.macCanvasOwnerID == owner, self.homeFloor == entryFloor,
                      self.renderedRoomLevel == entryLevel, self.worldGeometry.worldSize == entryWorld,
                      self.displayedCatID == catID, self.editing == entryEditing else {
                    self.cancelDesktopViewTransition(); return
                }
                self.roomPresentation.configure(world: entryWorld, viewport: self.size, floor: self.floor?.polygon ?? [],
                                                angle: angle, level: entryLevel, homeFloor: entryFloor)
                self.updateRoomPresentation()
                self.roomPresentation.root.run(.fadeIn(withDuration: 0.27), withKey: "mac-view-fade")
                do { try await Task.sleep(for: .milliseconds(270)) } catch { return }
                guard self.desktopViewTransitionID == ticket else { return }
                self.cancelDesktopViewTransition(); self.updateRoomPresentation()
            }
            return
        }
        #endif
        roomPresentation.configure(world: roomPresentation.projection.worldSize, viewport: size,
                                   floor: floor?.polygon ?? [], angle: angle, level: renderedRoomLevel, homeFloor: homeFloor)
        updateRoomPresentation()
    }

    func showCatCloseUp() {
        #if os(macOS)
        guard canZoomCamera else { return }
        cancelCameraInteraction(); suspendRoomFollowing()
        roomPresentation.camera.fit()
        roomPresentation.camera.zoom(by: 1.7)
        roomPresentation.camera.recenter(on: roomPresentation.projection.project(cat.position))
        updateRoomPresentation()
        #else
        resetCamera()
        guard let frame = roomPresentation.frame("cat"), frame.width.isFinite, frame.width > 0 else { return }
        // Use the existing safe zoom range; tiny high-level companions should remain the visual focus.
        roomPresentation.camera.zoom(by: max(1, 70 / frame.width))
        updateRoomPresentation()
        #endif
    }

    func showWholeRoom() {
        guard canChangeRoomView else { return }
        cancelCameraInteraction()
        suspendRoomFollowing()
        roomPresentation.camera.fit()
        updateRoomPresentation()
    }
}
