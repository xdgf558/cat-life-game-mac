import Foundation
import CatGameCore

extension GameStore {
    private var arrangementDraft68: ArrangementDraft68 {
        ArrangementDraft68(bowl: draftBowlPosition, furniture: draftFurniture, orientations: draftFurnitureOrientations,
                           selectedID: selectedFurnitureID, storedID: selectedStoredFurnitureID, bowlSelected: arrangement68.bowlSelected,
                           issues: arrangement68.placementIssues)
    }
    var arrangementSelection68: Bool { selectedFurnitureID != nil || arrangement68.bowlSelected }
    var canEditArrangement68: Bool {
        isDecorating && !isBusy && !isSavingLayout && !isResolvingLayout
            && placingFurnitureID == nil && arrangement68.pendingRequest == nil
    }
    func canDropArrangementFurniture68(id: String, generation: UUID, floor: HomeFloor) -> Bool {
        canEditArrangement68 && saveSceneGeneration == generation && visibleHomeFloor == floor
            && canPlaceMoreFurniture && storedFurniture.contains { $0.id == id }
            && snapshot?.inventory.furniture.contains { $0.id == id } == true
    }
    var selectedArrangementIssue68: ArrangementIssue68? {
        arrangement68.placementIssues[selectedFurnitureID ?? "bowl"]
    }
    func arrangementIssueText68(_ issue: ArrangementIssue68) -> String {
        switch issue {
        case .outside: return GameStrings.text("build68.outside")
        case .blocked: return GameStrings.text("build68.invalid")
        case .overlap(let id):
            guard let id, let item = snapshot?.inventory.furniture.first(where: { $0.id == id }) else {
                return GameStrings.text("build68.overlap")
            }
            return GameStrings.format("build68.overlapName", GameStrings.furnitureName(item))
        }
    }
    func setArrangementIssue68(id: String, issue: ArrangementIssue68?) {
        guard isDecorating else { return }
        arrangement68.placementIssues[id] = issue
    }
    func beginArrangementGesture68() {
        guard isDecorating, !isSavingLayout else { return }
        arrangement68.begin(arrangementDraft68)
    }
    func endArrangementGesture68() {
        guard isDecorating, !isSavingLayout else { return }
        arrangement68.end(arrangementDraft68)
    }
    func undoArrangement68() {
        guard canEditArrangement68, let previous = arrangement68.undo(current: arrangementDraft68) else { return }
        restoreArrangementDraft68(previous)
    }
    func redoArrangement68() {
        guard canEditArrangement68, let next = arrangement68.redo(current: arrangementDraft68) else { return }
        restoreArrangementDraft68(next)
    }
    private func restoreArrangementDraft68(_ previous: ArrangementDraft68) {
        draftBowlPosition = previous.bowl
        draftFurniture = previous.furniture
        draftFurnitureOrientations = previous.orientations
        selectedFurnitureID = previous.selectedID
        selectedStoredFurnitureID = previous.storedID
        arrangement68.bowlSelected = previous.bowlSelected
        arrangement68.placementIssues = previous.issues
    }
    func rotateSelectedFurniture68(clockwise: Bool) {
        guard canEditArrangement68, let item = selectedFurniture else { return }
        guard item.kind.supportsRotation else { showFurnitureNotice("layout.wallCannotFlip"); return }
        beginArrangementGesture68()
        arrangement68.pendingRequest = ArrangementRequest68(command: .rotate(id: item.id,
            orientation: clockwise ? item.orientation.turnedRight : item.orientation.turnedLeft))
    }
    func nudgeSelectedFurniture68(dx: Int, dy: Int) {
        guard canEditArrangement68, arrangementSelection68, abs(dx) + abs(dy) == 1 else { return }
        beginArrangementGesture68()
        arrangement68.pendingRequest = ArrangementRequest68(command: .nudge(id: selectedFurnitureID, dx: dx, dy: dy,
                                                                          step: arrangement68.gridStep))
    }
    func confirmArrangementSelection68() {
        guard canEditArrangement68, arrangementSelection68, selectedArrangementIssue68 == nil else { return }
        arrangement68.pendingRequest = ArrangementRequest68(command: .confirm(id: selectedFurnitureID))
    }
    func focusArrangementFurniture68(id: String) {
        guard canEditArrangement68, draftFurniture?.contains(where: { $0.itemID == id }) == true else { return }
        selectFurniture(id: id)
        arrangement68.pendingRequest = ArrangementRequest68(command: .focus(id: id))
    }
    func applyArrangementOrientation68(id: String, orientation: FurnitureOrientation) {
        guard isDecorating, !isSavingLayout,
              snapshot?.inventory.furniture.contains(where: { $0.id == id && $0.kind.supportsRotation }) == true else { return }
        draftFurnitureOrientations?[id] = orientation
    }
    func completeArrangementCommand68(_ requestID: UUID) {
        guard isDecorating, let request = arrangement68.pendingRequest, request.id == requestID else { return }
        if case .confirm = request.command, selectedArrangementIssue68 == nil {
            selectedFurnitureID = nil; selectedStoredFurnitureID = nil; arrangement68.bowlSelected = false
        }
        endArrangementGesture68()
        arrangement68.pendingRequest = nil
    }
    func selectBowl68() {
        guard isDecorating, !isSavingLayout else { return }
        selectedFurnitureID = nil; selectedStoredFurnitureID = nil; arrangement68.bowlSelected = true
    }

    func setLayoutResolving(_ resolving: Bool) {
        let value = isDecorating && resolving
        guard value != isResolvingLayout else { return }
        isResolvingLayout = value
    }
    func moveBowl(to point: NormalizedPoint) {
        guard isDecorating, !isSavingLayout, point.x.isFinite, point.y.isFinite else { return }
        selectedStoredFurnitureID = nil
        selectedFurnitureID = nil
        arrangement68.bowlSelected = true
        draftBowlPosition = point
    }
    func selectFurniture(id: String?) {
        guard isDecorating, !isSavingLayout else { return }
        selectedStoredFurnitureID = nil
        arrangement68.bowlSelected = false
        guard let id else { selectedFurnitureID = nil; return }
        guard let item = snapshot?.inventory.furniture.first(where: { $0.id == id }),
              draftFurniture?.contains(where: { $0.itemID == id }) == true else { return }
        selectedFurnitureID = id
        arrangement68.filter = FurnitureCatalog.metadata(for: item.kind).isWall ? .wall : .floor
    }
    func selectStoredFurniture(id: String) {
        guard isDecorating, !isSavingLayout, canPlaceMoreFurniture,
              let item = storedFurniture.first(where: { $0.id == id }) else { return }
        isFurnitureTrayExpanded = true
        selectedFurnitureID = nil
        selectedStoredFurnitureID = id
        arrangement68.bowlSelected = false
        arrangement68.filter = FurnitureCatalog.metadata(for: item.kind).isWall ? .wall : .floor
    }
    func moveFurniture(id: String, to point: NormalizedPoint) {
        guard isDecorating, !isSavingLayout, var furniture = draftFurniture,
              snapshot?.inventory.furniture.contains(where: { $0.id == id }) == true,
              point.x.isFinite, point.y.isFinite else { return }
        if let index = furniture.firstIndex(where: { $0.itemID == id }) {
            furniture[index].position = point
        } else {
            guard placingFurnitureID == id, canPlaceMoreFurniture else { return }
            furniture.append(FurniturePlacement(itemID: id, position: point, floor: visibleHomeFloor))
        }
        draftFurniture = furniture
        selectedStoredFurnitureID = nil
        selectedFurnitureID = id
        arrangement68.bowlSelected = false
    }
    func storeSelectedFurniture() {
        guard canStoreSelectedFurniture, arrangement68.pendingRequest == nil, let id = selectedFurnitureID else { return }
        beginArrangementGesture68()
        draftFurniture?.removeAll { $0.itemID == id }
        arrangement68.placementIssues.removeValue(forKey: id)
        selectedFurnitureID = nil
        arrangement68.bowlSelected = false
        endArrangementGesture68()
        showNotice(GameStrings.text("layout.stored"))
    }
    func flipSelectedFurniture() { rotateSelectedFurniture68(clockwise: true) }
    func placeFurniture(id: String) {
        guard !isBusy, !isSavingLayout, !isResolvingLayout, arrangement68.pendingRequest == nil,
              storedFurniture.contains(where: { $0.id == id }) else { return }
        guard canPlaceMoreFurniture else { showNotice(furnitureCapacityNotice); return }
        if !isDecorating { beginDecorating() }
        guard isDecorating else { return }
        beginArrangementGesture68()
        activeSheet = nil
        selectedStoredFurnitureID = nil
        selectedFurnitureID = id
        arrangement68.bowlSelected = false
        placingFurnitureID = id
        isResolvingLayout = true
    }
    func finishFurniturePlacement(id: String, succeeded: Bool, keepingResolutionPending: Bool = false) {
        guard isDecorating, placingFurnitureID == id else { return }
        placingFurnitureID = nil
        isResolvingLayout = keepingResolutionPending
        if succeeded, draftFurniture?.contains(where: { $0.itemID == id }) == true {
            selectedFurnitureID = id
            showNotice(GameStrings.text("layout.placed"))
        } else {
            draftFurniture?.removeAll { $0.itemID == id }
            selectedFurnitureID = nil
            arrangement68.placementIssues.removeValue(forKey: id)
            showNotice(GameStrings.text("layout.noSpace"))
        }
        if !isResolvingLayout { endArrangementGesture68() }
    }
}
