import SpriteKit
import CatGameCore

@MainActor
extension RoomScene {
    func configureArrangement68(snapEnabled: Bool, bowlSelected: Bool = false,
                                 placementIssues: [String: ArrangementIssue68]? = nil) {
        arrangement68.snapEnabled = snapEnabled
        let wasBowlSelected = arrangement68.bowlSelected
        arrangement68.bowlSelected = bowlSelected
        if editing, wasBowlSelected, !bowlSelected, selectedFurnitureID == nil, !dragging { roomPresentation.camera.fit() }
        if let placementIssues { arrangement68.sourceIssues = placementIssues }
        onPlacementPendingChanged?(isPlacementPending)
        resumeArrangementCommand68()
    }

    func invalidateArrangement68() {
        if arrangement68.yielding {
            cat.cancelAndSettle(at: cat.position)
            residents.invalidate()
        }
        arrangement68.yielding = false
        arrangement68.yieldContinuation = nil
        arrangement68.gestureActive = false
        arrangement68.gestureIssues.removeAll()
        cancelPlacementPreview(completeCommand: false)
        arrangement68.pendingRequest = nil
        arrangement68.completedRequest = nil
        arrangement68.pendingDrop = nil
        arrangement68.issues.removeAll()
        arrangement68.sourceIssues = nil
    }

    func applyArrangementCommand68(_ request: ArrangementRequest68, snapEnabled: Bool) {
        arrangement68.snapEnabled = snapEnabled
        guard !arrangement68.yielding else { return }
        guard arrangement68.completedRequest != request.id else { return }
        if arrangement68.pendingRequest?.id == request.id, arrangement68.worker != nil { return }
        arrangement68.pendingRequest = request
        resumeArrangementCommand68()
    }

    func dropStoredFurniture68(_ id: String, atViewPoint point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        arrangement68.pendingDrop = (id, point)
        if editing, newPlacementID == id, bowlPlanningRequest == nil {
            let wall = furnitureWorld.item(id).map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false
            selectedNode.position = roomPresentation.worldPoint(screen: point, wall: wall)
            resolveArrangementPlacement68(findNearest: false)
        }
    }

    func beginArrangementGesture68() {
        guard !arrangement68.gestureActive else { return }
        arrangement68.gestureActive = true
        arrangement68.gestureIssues = arrangement68.issues
        onArrangementGestureBegan?()
    }

    func endArrangementGesture68() {
        guard arrangement68.gestureActive else { return }
        arrangement68.gestureActive = false
        onArrangementGestureEnded?()
    }

    func setArrangementIssue68(id: String, issue: ArrangementIssue68?) {
        guard arrangement68.issues[id] != issue else { return }
        arrangement68.issues[id] = issue
        onArrangementIssue?(id, issue)
    }

    func previewArrangementPoint68(_ point: CGPoint) -> CGPoint {
        let point = arrangementGrid68.snapped(point, enabled: arrangement68.snapEnabled)
        setArrangementIssue68(id: selectedFurnitureID ?? "bowl",
            issue: RoomArrangementPlanning68.issue(id: selectedFurnitureID, at: point, world: furnitureWorld))
        return point
    }

    func preserveUnmovedArrangementIssue68(_ previous: ArrangementIssue68?) {
        let issue = RoomArrangementPlanning68.issue(id: selectedFurnitureID, at: selectedNode.position, world: furnitureWorld)
        setArrangementIssue68(id: selectedFurnitureID ?? "bowl", issue: issue ?? (previous == .blocked ? .blocked : nil))
    }

    func focusArrangementSelection68() {
        let point = selectedNode.position
        let wall = selectedFurnitureID.flatMap(furnitureWorld.item).map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false
        suspendRoomFollowing()
        roomPresentation.camera.focus(on: wall ? roomPresentation.projection.wallPoint(point) : roomPresentation.projection.project(point))
        updateRoomPresentation()
    }

    func resumeArrangementCommand68() {
        guard editing, presentationActive, bowlPlanningRequest == nil, !isPlacementPending,
              arrangement68.worker == nil, let request = arrangement68.pendingRequest else { return }
        switch request.command {
        case .focus(let id):
            guard furnitureWorld.center(id) != nil, furnitureWorld.item(id) != nil else {
                completeArrangementCommand68(); return
            }
            selectedFurnitureID = id; arrangement68.bowlSelected = false
            onFurnitureSelected?(id)
            focusArrangementSelection68()
            updateSelection(); updateRoomPresentation(); completeArrangementCommand68()
        case .rotate(let id, let orientation):
            guard let item = furnitureWorld.item(id), item.kind.supportsRotation else {
                completeArrangementCommand68(); return
            }
            beginArrangementGesture68()
            selectedFurnitureID = id; arrangement68.bowlSelected = false
            ownedFurniture = furnitureWorld.replacingOrientation(id, with: orientation).items
            synchronizeFurnitureNodes()
            onArrangementOrientation?(id, orientation)
            resolveArrangementPlacement68(findNearest: true)
        case .nudge(let id, let dx, let dy, let step):
            guard abs(dx) + abs(dy) == 1 else { completeArrangementCommand68(); return }
            selectedFurnitureID = id; arrangement68.bowlSelected = id == nil
            beginArrangementGesture68()
            let wall = id.flatMap(furnitureWorld.item).map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false
            selectedNode.position = arrangementGrid68.nudged(selectedNode.position, dx: dx, dy: dy, step: step,
                projection: roomPresentation.projection, wall: wall)
            resolveArrangementPlacement68(findNearest: false, snapPoint: false)
        case .confirm(let id):
            selectedFurnitureID = id; arrangement68.bowlSelected = id == nil
            resolveArrangementPlacement68(findNearest: false, snapPoint: false)
        }
    }

    func completeArrangementCommand68() {
        guard let request = arrangement68.pendingRequest else { return }
        arrangement68.completedRequest = request.id
        arrangement68.pendingRequest = nil
        endArrangementGesture68()
        onArrangementCommandCompleted?(request.id)
    }

    func resolveArrangementPlacement68(findNearest: Bool, snapPoint: Bool = true) {
        guard editing, bowlPlanningRequest == nil else { return }
        arrangement68.worker?.cancel()
        placementRevision += 1
        let ticket = placementRevision
        let requestedFloor = homeFloor
        let id = selectedFurnitureID
        let point = selectedNode.position
        let current = furnitureWorld
        let world = RoomFurnitureWorld(transform: current.transform, catWidth: current.catWidth,
            bowlSize: current.bowlSize, bowlPosition: committedBowlPosition, items: current.items, placements: current.placements)
        let origin = cat.position
        let otherCats = residents.obstacles
        let grid = arrangementGrid68
        let snap = arrangement68.snapEnabled
        let inserted = newPlacementID
#if DEBUG
        let slowTest = diagnostics.dragTesting && ProcessInfo.processInfo.arguments.contains("--slow-placement-test")
#endif
        setPlacementPending(true)
        let worker = Task.detached(priority: .userInitiated) {
#if DEBUG
            if slowTest { try? await Task.sleep(for: .seconds(3)) }
#endif
            return RoomArrangementPlanning68.resolve(id: id, at: point, world: world, cat: origin,
                grid: grid, snap: snap, findNearest: findNearest, snapPoint: snapPoint, otherCats: otherCats)
        }
        arrangement68.worker = worker
        Task { [weak self] in
            let result = await worker.value
            guard let self, self.editing, self.presentationActive, self.homeFloor == requestedFloor,
                  self.placementRevision == ticket, !worker.isCancelled else { return }
            self.arrangement68.worker = nil
            let previousFloor = self.floor
            self.ownedFurniture = result.world.items
            self.newPlacementID = nil
            if inserted != nil { self.arrangement68.pendingDrop = nil }
            if let id {
                let normalized = self.arrangementGrid68.normalized(world: result.point)
                if let index = self.renderedFurniture.firstIndex(where: { $0.itemID == id }) {
                    self.renderedFurniture[index].position = normalized
                } else { self.renderedFurniture.append(.init(itemID: id, position: normalized, floor: self.homeFloor)) }
                self.furnitureNodes[id]?.position = result.point
                self.furnitureNodes[id]?.alpha = 1
                self.onFurnitureMoved?(id, normalized)
            } else {
                self.bowl.position = result.point
                self.committedBowlPosition = result.point
                let normalized = NormalizedPoint(x: result.point.x / self.worldGeometry.worldSize.width,
                                                  y: 1 - result.point.y / self.worldGeometry.worldSize.height)
                self.lastRequestedBowlPoint = result.point
                self.onBowlMoved?(normalized)
            }
            self.setArrangementIssue68(id: id ?? "bowl", issue: result.issue)
            if let inserted { self.onFurniturePlacementFinished?(inserted, true) }
            if result.issue == nil {
                self.floor = self.furnitureWorld.roomFloor
                self.navigation = self.floor?.navigator(bowlAt: self.bowl.position, precomputeGrid: false)
                self.arrangement68.yielding = true
                if result.catRoute.count > 1 {
                    self.cat.setIdleEnabled(false)
                    self.cat.stroll(along: result.catRoute) { [weak self] in
                        guard let self else { return }
                        self.continueArrangementYield68(previous: previousFloor, next: self.floor,
                            previousBowl: world.bowlPosition, ticket: ticket, requestedFloor: requestedFloor)
                    }
                } else {
                    self.continueArrangementYield68(previous: previousFloor, next: self.floor,
                        previousBowl: world.bowlPosition, ticket: ticket, requestedFloor: requestedFloor)
                }
                self.updateSelection(); self.updateBowlLayers(); self.updateFurnitureLayers(); self.updateRoomPresentation()
                return
            }
            self.placementPrepared = false
            self.setPlacementPending(false)
            self.updateSelection(); self.updateBowlLayers(); self.updateFurnitureLayers(); self.updateRoomPresentation()
            self.endArrangementGesture68()
            self.completeArrangementCommand68()
        }
    }

    func resumeArrangementYield68() {
        let continuation = arrangement68.yieldContinuation
        arrangement68.yieldContinuation = nil
        continuation?()
    }

    func continueArrangementYield68(previous: RoomFloor?, next: RoomFloor?, previousBowl: CGPoint,
                                     ticket: Int, requestedFloor: HomeFloor) {
        guard editing, placementRevision == ticket, homeFloor == requestedFloor, arrangement68.yielding else { return }
        guard presentationActive else {
            arrangement68.yieldContinuation = { [weak self] in
                self?.continueArrangementYield68(previous: previous, next: next, previousBowl: previousBowl,
                    ticket: ticket, requestedFloor: requestedFloor)
            }
            return
        }
        guard let previous, let next else { finishArrangementYield68(ticket: ticket, requestedFloor: requestedFloor); return }
        residents.yieldForArrangement68(from: previous, to: next, bowl: bowl.position,
            active: cat.position, previousBowl: previousBowl) { [weak self] safe in
                self?.finishArrangementYield68(ticket: ticket, requestedFloor: requestedFloor, residentsSafe: safe)
            }
    }

    func finishArrangementYield68(ticket: Int, requestedFloor: HomeFloor, residentsSafe: Bool = true) {
        guard editing, placementRevision == ticket, homeFloor == requestedFloor, arrangement68.yielding else { return }
        guard presentationActive else {
            arrangement68.yieldContinuation = { [weak self] in
                self?.finishArrangementYield68(ticket: ticket, requestedFloor: requestedFloor, residentsSafe: residentsSafe)
            }
            return
        }
        arrangement68.yielding = false
        if !residentsSafe { setArrangementIssue68(id: selectedFurnitureID ?? "bowl", issue: .blocked) }
        arrangement68.yieldContinuation = nil
        placementPrepared = false
        setPlacementPending(false)
        endArrangementGesture68()
        completeArrangementCommand68()
        updateSelection(); updateRoomPresentation()
        if deferredRoomLayoutFromSize != nil {
            deferredRoomLayoutFromSize = nil
            layoutRoom(preservingPositionFrom: worldGeometry.worldSize)
        }
    }

    func adoptArrangementDraft68(_ snapshot: GameSnapshot) {
        let proposed = scenePoint(snapshot.home.bowlPosition)
        guard ownedFurniture != snapshot.inventory.furniture || renderedFurniture != snapshot.home.furniture
            || committedBowlPosition != proposed else { return }
        ownedFurniture = snapshot.inventory.furniture
        renderedFurniture = snapshot.home.furniture
        bowl.position = proposed; committedBowlPosition = proposed; lastRequestedBowlPoint = proposed
        floor = furnitureWorld.roomFloor
        navigation = floor?.navigator(bowlAt: proposed, precomputeGrid: false)
        synchronizeFurnitureNodes()
        let previousIssues = arrangement68.sourceIssues ?? arrangement68.issues
        // shortcut: Recheck blocked paths by dragging/nudging this item; replace when neighboring edits trigger automatic revalidation.
        for id in Array(arrangement68.issues.keys) { setArrangementIssue68(id: id, issue: nil) }
        for placement in renderedFurniture {
            let issue = RoomArrangementPlanning68.issue(id: placement.itemID,
                at: artworkTransform.point(placement.position), world: furnitureWorld)
            setArrangementIssue68(id: placement.itemID, issue: issue ?? (previousIssues[placement.itemID] == .blocked ? .blocked : nil))
        }
        let issue = RoomArrangementPlanning68.issue(id: nil, at: proposed, world: furnitureWorld)
        setArrangementIssue68(id: "bowl", issue: issue ?? (previousIssues["bowl"] == .blocked ? .blocked : nil))
    }
}
