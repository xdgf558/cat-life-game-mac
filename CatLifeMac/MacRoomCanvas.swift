#if os(macOS)
import AppKit
import SpriteKit
import SwiftUI
import UniformTypeIdentifiers
import CatGameCore

/// Scene coordinates remain y-down view points on both Apple platforms.
enum MacRoomPointer {
    static func screenPoint(_ point: CGPoint, height: CGFloat, isFlipped: Bool) -> CGPoint {
        CGPoint(x: point.x, y: isFlipped ? point.y : height - point.y)
    }
    static func zoomFactor(delta: CGFloat, reversed: Bool) -> CGFloat {
        exp(min(0.35, max(-0.35, delta * (reversed ? -1 : 1) * 0.025)))
    }
    static func frameLimit(requested: Int, screenMaximum: Int) -> Int {
        min([30, 60, 120].contains(requested) ? requested : 60, max(1, screenMaximum))
    }
}

enum MacRoomContextAction: Equatable {
    case companion(String), profile(String), closeUp(String), play(String), hospital(String)
    case rest(String), decorate(String?), store(String)
}

/// Native input only. Every drag still enters RoomScene's asynchronous placement resolver.
@MainActor
final class MacRoomSKView: SKView {
    var inputEnabled = true { didSet { if !inputEnabled { pendingClick?.cancel(); clearHover(); roomScene?.cancelCameraInteraction() } } }
    var requestedFrameLimit = 60 { didSet { applyFrameLimit() } }
    var effectiveFrameLimit: Int {
        MacRoomPointer.frameLimit(requested: requestedFrameLimit, screenMaximum: window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60)
    }
    func applyFrameLimit() {
        preferredFramesPerSecond = effectiveFrameLimit
        roomScene?.preferredFrameLimit = effectiveFrameLimit
    }
    var wheelReversed = false
    var contextMenus = true
    var hoverHints = true { didSet { if !hoverHints { clearHover() } } }
    var contextAction: ((MacRoomContextAction) -> Void)?
    var structureAction: ((MacRoomStructure) -> Void)?
    var roomScene: RoomScene? { scene as? RoomScene }
    var residentNames: [String: String] = [:]
    private var tracking: NSTrackingArea?
    private let hoverOutline = SKShapeNode()
    private var menuActions: [MacRoomContextAction] = []
    private var pendingClick: Task<Void, Never>?
    private var pressPoint: CGPoint?
    private var pointerMoved = false
    private var ignoresMouseUp = false
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); window?.acceptsMouseMovedEvents = true; applyFrameLimit()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties(); applyFrameLimit()
    }
    private var acceptsPointerInput: Bool { inputEnabled && roomScene?.desktopViewTransitionTask == nil }
    private func point(_ event: NSEvent) -> CGPoint {
        MacRoomPointer.screenPoint(convert(event.locationInWindow, from: nil), height: bounds.height, isFlipped: isFlipped)
    }
    override func mouseDown(with event: NSEvent) {
        guard acceptsPointerInput, let roomScene else { return }
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        clearHover(); pendingClick?.cancel(); pendingClick = nil
        pressPoint = point(event); pointerMoved = false; ignoresMouseUp = false
        if event.clickCount == 2, !roomScene.editing {
            if let id = catID(hit: roomScene.roomPresentation.hit(screen: point(event), editing: false), scene: roomScene) {
                roomScene.cancelCameraInteraction(); ignoresMouseUp = true
                contextAction?(.closeUp(id))
                return
            }
            if roomScene.roomPresentation.hit(screen: point(event), editing: false) == nil,
               roomScene.roomPresentation.fixedStructure(at: point(event)) == nil {
                roomScene.cancelCameraInteraction(); ignoresMouseUp = true
                roomScene.showWholeRoom()
                return
            }
        }
        roomScene.beginPointer(at: point(event))
    }
    override func mouseDragged(with event: NSEvent) {
        guard acceptsPointerInput else { return }
        clearHover()
        if let pressPoint, hypot(point(event).x - pressPoint.x, point(event).y - pressPoint.y) >= 8 { pointerMoved = true }
        roomScene?.movePointer(to: point(event))
    }
    override func mouseUp(with event: NSEvent) {
        guard acceptsPointerInput, !ignoresMouseUp, let roomScene else { return }
        let point = point(event)
        if !pointerMoved, roomScene.roomPresentation.hit(screen: point, editing: roomScene.editing) == nil,
           let structure = roomScene.roomPresentation.fixedStructure(at: point) {
            roomScene.cancelCameraInteraction(); structureAction?(structure); return
        }
        if roomScene.editing || pointerMoved
            || catID(hit: roomScene.roomPresentation.hit(screen: point, editing: false), scene: roomScene) == nil {
            roomScene.endPointer(at: point)
            return
        }
        // Only a cat profile competes with double-click; other targets respond immediately.
        pendingClick = Task { @MainActor [weak self, weak roomScene] in
            do { try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval)) } catch { return }
            guard let self, let roomScene, self.inputEnabled, self.roomScene === roomScene, !Task.isCancelled else { return }
            roomScene.endPointer(at: point); self.pendingClick = nil
        }
    }
    override func scrollWheel(with event: NSEvent) {
        guard acceptsPointerInput else { return }
        roomScene?.zoomCamera(at: point(event), factor: MacRoomPointer.zoomFactor(delta: event.scrollingDeltaY, reversed: wheelReversed))
    }
    override func magnify(with event: NSEvent) {
        guard acceptsPointerInput else { return }
        roomScene?.zoomCamera(at: point(event), factor: max(0.1, 1 + event.magnification))
    }
    override func mouseMoved(with event: NSEvent) {
        guard acceptsPointerInput, hoverHints, let roomScene, roomScene.presentationActive, !roomScene.dragging else { clearHover(); return }
        let hit = roomScene.roomPresentation.hit(screen: point(event), editing: roomScene.editing)
        let structure = hit == nil ? roomScene.roomPresentation.fixedStructure(at: point(event)) : nil
        let hoveredFrame = hit.flatMap(roomScene.roomPresentation.frame) ?? structure.flatMap(roomScene.roomPresentation.fixedFrame)
        guard let frame = hoveredFrame else { clearHover(); return }
        if hoverOutline.parent !== roomScene.roomPresentation.root {
            hoverOutline.removeFromParent(); roomScene.roomPresentation.root.addChild(hoverOutline)
        }
        hoverOutline.zPosition = 40_000; hoverOutline.lineWidth = 2
        hoverOutline.strokeColor = NSColor(red: 0.18, green: 0.67, blue: 0.54, alpha: 0.85)
        hoverOutline.fillColor = .clear
        let rect = CGRect(x: frame.minX - roomScene.size.width / 2, y: roomScene.size.height / 2 - frame.maxY,
                          width: frame.width, height: frame.height).insetBy(dx: -3, dy: -3)
        hoverOutline.path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        hoverOutline.isHidden = false
        if let structure {
            let key: String
            if roomScene.editing { key = structure == .door ? "mac.room.doorFixed" : "mac.room.stairsFixed" }
            else if structure == .door { key = "mac.room.door" }
            else if roomScene.renderedRoomLevel < 6 { key = "mac.room.stairsLocked" }
            else { key = roomScene.homeFloor == .ground ? "mac.room.upstairs" : "mac.room.downstairs" }
            toolTip = GameStrings.text(key)
        } else if let id = catID(hit: hit, scene: roomScene), let name = residentNames[id] {
            toolTip = name + " · " + GameStrings.text("mac.hover.cat")
        } else if let hit, hit.hasPrefix("furniture-"), let item = roomScene.ownedFurniture.first(where: { "furniture-" + $0.id == hit }) {
            toolTip = GameStrings.text(FurnitureCatalog.metadata(for: item.kind).nameKey) + " · " + GameStrings.text("mac.hover.furniture")
        } else { toolTip = GameStrings.text(hit == "bowl" ? "layout.bowl" : "mac.hover.floor") }
        NSCursor.pointingHand.set()
    }
    override func mouseExited(with event: NSEvent) { clearHover() }
    func clearHover() {
        hoverOutline.isHidden = true; toolTip = nil; NSCursor.arrow.set()
    }
    override func rightMouseDown(with event: NSEvent) {
        guard acceptsPointerInput, contextMenus, let roomScene, !roomScene.isPlacementPending else { return }
        clearHover(); pendingClick?.cancel(); pendingClick = nil; roomScene.cancelCameraInteraction()
        let hit = roomScene.roomPresentation.hit(screen: point(event), editing: roomScene.editing)
        if hit == nil, let structure = roomScene.roomPresentation.fixedStructure(at: point(event)) {
            structureAction?(structure); return
        }
        var entries: [(String, MacRoomContextAction)] = []
        if let id = catID(hit: hit, scene: roomScene), roomScene.canInspectResidents {
            if id != roomScene.displayedCatID { entries.append(("companion", .companion(id))) }
            entries += [("profile", .profile(id)), ("closeUp", .closeUp(id)), ("play", .play(id)), ("hospital", .hospital(id))]
        } else if let hit, hit.hasPrefix("furniture-") {
            let id = String(hit.dropFirst("furniture-".count))
            if !roomScene.editing, let item = roomScene.ownedFurniture.first(where: { $0.id == id }),
               item.kind == .catBed || item.kind == .floorCushion { entries.append(("rest", .rest(id))) }
            entries.append(("decorate", .decorate(id)))
            if roomScene.editing { entries.append(("store", .store(id))) }
        } else { entries.append(("decorate", .decorate(nil))) }
        let menu = NSMenu()
        menuActions = entries.map(\.1)
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: GameStrings.text("mac.context." + entry.0), action: #selector(selectedContextItem(_:)), keyEquivalent: "")
            item.tag = index; item.target = self; menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        menuActions.removeAll()
    }
    @objc private func selectedContextItem(_ item: NSMenuItem) {
        guard acceptsPointerInput, menuActions.indices.contains(item.tag) else { return }
        contextAction?(menuActions[item.tag])
    }
    private func catID(hit: String?, scene: RoomScene) -> String? {
        guard let hit else { return nil }
        if hit == "cat" { return scene.displayedCatID }
        return hit.hasPrefix("resident-") ? String(hit.dropFirst("resident-".count)) : nil
    }
}

@MainActor
struct MacRoomCanvas: View {
    let store: GameStore
    let scene: RoomScene
    let isActive: Bool
    var readOnlyPreview = false
    var initialViewAngle: RoomViewAngle = .front
    var frameLimit = 60
    var wheelReversed = false
    var contextMenus = true
    var hoverHints = true
    var isDaylight = true
    var usableRect: CGRect?
    var needPresentation: CatNeedPresentation?
    var onRestRequest: ((String) -> Void)?
    var onRestSceneChanged: ((HomeRestScene68) -> Void)?
    var onContextAction: ((MacRoomContextAction) -> Void)?
    var onViewChanged: (() -> Void)?
    var onFixedStructure: ((MacRoomStructure) -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.gameReduceMotionOverride) private var motionOverride

    var body: some View {
        GeometryReader { geometry in
            MacNativeRoomCanvas(store: store, scene: scene, isActive: isActive,
                readOnlyPreview: readOnlyPreview, previewIsVisible: scenePhase == .active, initialViewAngle: initialViewAngle, canvasSize: geometry.size,
                frameLimit: frameLimit, wheelReversed: wheelReversed, contextMenus: contextMenus, hoverHints: hoverHints,
                isDaylight: isDaylight, usableRect: usableRect, reducedMotion: reducedMotion || motionOverride, needPresentation: needPresentation, onRestRequest: onRestRequest,
                onRestSceneChanged: onRestSceneChanged, onContextAction: onContextAction, onViewChanged: onViewChanged, onFixedStructure: onFixedStructure)
                .onDrop(of: [UTType.text], isTargeted: nil) { providers, point in receiveDrop(providers, at: point) }
                .onChange(of: geometry.frame(in: .global).origin, initial: true) { _, origin in needPresentation?.canvasOrigin = origin }
        }
    }
    private func receiveDrop(_ providers: [NSItemProvider], at point: CGPoint) -> Bool {
        guard isActive, store.canEditArrangement68, point.x.isFinite, point.y.isFinite,
              let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        let generation = store.saveSceneGeneration, floor = store.visibleHomeFloor
        provider.loadObject(ofClass: NSString.self) { value, error in
            guard error == nil, let id = value as? String else { return }
            Task { @MainActor in
                guard isActive, scene.presentationActive, scene.homeFloor == floor,
                      store.canDropArrangementFurniture68(id: id, generation: generation, floor: floor) else { return }
                store.placeFurniture(id: id)
                if store.placingFurnitureID == id { scene.dropStoredFurniture68(id, atViewPoint: point) }
            }
        }
        return true
    }
}

@MainActor
private struct MacNativeRoomCanvas: NSViewRepresentable {
    let store: GameStore
    let scene: RoomScene
    let isActive: Bool
    let readOnlyPreview: Bool
    let previewIsVisible: Bool
    let initialViewAngle: RoomViewAngle
    let canvasSize: CGSize
    let frameLimit: Int
    let wheelReversed: Bool
    let contextMenus: Bool
    let hoverHints: Bool
    let isDaylight: Bool
    let usableRect: CGRect?
    let reducedMotion: Bool
    let needPresentation: CatNeedPresentation?
    let onRestRequest: ((String) -> Void)?
    let onRestSceneChanged: ((HomeRestScene68) -> Void)?
    let onContextAction: ((MacRoomContextAction) -> Void)?
    let onViewChanged: (() -> Void)?
    let onFixedStructure: ((MacRoomStructure) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> MacRoomSKView {
        let view = MacRoomSKView(); view.ignoresSiblingOrder = true
        view.allowsTransparency = true; view.setAccessibilityElement(false)
        configure(view, coordinator: context.coordinator)
        return view
    }
    func updateNSView(_ view: MacRoomSKView, context: Context) { configure(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: MacRoomSKView, coordinator: Coordinator) {
        view.inputEnabled = false; view.clearHover(); view.isPaused = true
        coordinator.detach()
        if view.scene?.view === view { view.presentScene(nil) }
    }
    private func configure(_ view: MacRoomSKView, coordinator: Coordinator) {
        coordinator.source = self
        coordinator.attachIfNeeded()
        scene.reducedMotion = reducedMotion
        scene.backgroundColor = readOnlyPreview ? .clear : NSColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1)
        scene.roomPresentation.configureDesktop(isDaylight: isDaylight, showsBackdrop: !readOnlyPreview)
        let active = isActive && !readOnlyPreview && !store.isChangingHomeFloor
        let previewing = readOnlyPreview && previewIsVisible && isActive
        scene.setReadOnlyPreviewEnabled(previewing)
        if scene.presentationActive != active { scene.setPresentationActive(active) }
        if active { scene.resumeLayoutPlanningIfNeeded() }
        view.requestedFrameLimit = frameLimit
        scene.preferredFrameLimit = view.effectiveFrameLimit
        scene.scaleMode = .resizeFill
        // Fixed logical phone-sized world preserves all existing furniture and cat dimensions.
        scene.setReferenceViewportSize(CGSize(width: 390, height: 600))
        if canvasSize.width > 0, canvasSize.height > 0, scene.size != canvasSize { scene.size = canvasSize }
        scene.configureArrangement68(snapEnabled: store.arrangement68.snapEnabled, bowlSelected: store.arrangement68.bowlSelected,
                                     placementIssues: store.arrangement68.placementIssues)
        scene.habitOfferItemID = store.habitCornerOffer?.furnitureID
        scene.cornerMarkerFurnitureID68 = store.cat?.habits.cornerFurnitureID
        if let snapshot = store.sceneSnapshot {
            scene.apply(snapshot: snapshot, editing: store.isDecorating, selectedFurnitureID: store.selectedFurnitureID,
                        placingFurnitureID: store.placingFurnitureID)
        }
        let desktopArea = usableRect ?? CGRect(x: 26, y: 90, width: max(1, canvasSize.width - 52), height: max(1, canvasSize.height - 192))
        scene.setRoomViewUsableRect(desktopArea)
        coordinator.prepareDesktopView()
        if view.scene !== scene { view.presentScene(scene) }
        view.contextAction = { action in guard coordinator.acceptsUpdates else { return }; coordinator.source.onContextAction?(action) }
        view.structureAction = { structure in guard coordinator.acceptsUpdates else { return }; coordinator.source.onFixedStructure?(structure) }
        view.residentNames = Dictionary(uniqueKeysWithValues: (store.snapshot?.cats ?? []).map { ($0.id, GameStrings.catName($0)) })
        view.wheelReversed = wheelReversed; view.contextMenus = contextMenus; view.hoverHints = hoverHints
        view.inputEnabled = active && !store.isSavingLayout
        let renders = active || previewing
        view.isPaused = !renders; scene.isPaused = !renders
        view.applyFrameLimit()
        if let feedback = store.feedback, coordinator.feedbackID != feedback.id {
            coordinator.feedbackID = feedback.id
            scene.playFeedback(kind: feedback.kind, catID: feedback.catID)
        }
        if active, store.isDecorating, !store.isSavingLayout, let request = store.arrangement68.pendingRequest {
            scene.applyArrangementCommand68(request, snapEnabled: store.arrangement68.snapEnabled)
        }
    }
    @MainActor
    final class Coordinator {
        var source: MacNativeRoomCanvas
        private let ownerID = UUID()
        private var generation: UUID?
        private var floor: HomeFloor?
        var feedbackID: UUID?
        private var requestedDesktopView = false
        init(_ source: MacNativeRoomCanvas) { self.source = source }
        var acceptsUpdates: Bool {
            !source.readOnlyPreview && source.scene.macCanvasOwnerID == ownerID && generation == source.store.saveSceneGeneration
                && floor == source.store.visibleHomeFloor && !source.store.isChangingHomeFloor
        }
        func prepareDesktopView() {
            guard !requestedDesktopView else { return }
            requestedDesktopView = true
            source.scene.prepareDesktopView(initialAngle: source.initialViewAngle)
        }
        func attachIfNeeded() {
            let store = source.store, scene = source.scene
            guard generation != store.saveSceneGeneration || floor != store.visibleHomeFloor || scene.macCanvasOwnerID != ownerID else { return }
            if generation != nil { scene.invalidateArrangement68(); scene.cancelCameraInteraction() }
            generation = store.saveSceneGeneration; floor = store.visibleHomeFloor
            feedbackID = store.feedback?.id
            requestedDesktopView = false
            scene.macCanvasOwnerID = ownerID
            scene.homeFloor = store.visibleHomeFloor
            let attachedGeneration = generation, attachedFloor = floor
            let accepts: @MainActor () -> Bool = { [weak self, weak scene] in
                guard let self, let scene else { return false }
                return self.acceptsUpdates && self.generation == attachedGeneration && self.floor == attachedFloor && self.source.scene === scene
            }
            scene.onFixedStructureTapped = { [weak self] structure in
                guard let self, accepts(), self.source.isActive else { return }
                self.source.onFixedStructure?(structure)
            }
            scene.onPlacementPendingChanged = { [weak self] in guard let self, accepts() else { return }; self.source.store.setLayoutResolving($0) }
            scene.onCatTapped = { [weak self] in guard let self, accepts(), let id = self.source.store.cat?.id else { return }; self.source.onContextAction?(.profile(id)) }
            scene.onResidentTapped = { [weak self] id in guard let self, accepts() else { return }; self.source.onContextAction?(.profile(id)) }
            scene.onBackgroundTapped = { [weak self] in guard let self, accepts() else { return }; self.source.scene.restPromptFurnitureID68 = nil }
            scene.onVisibleResidentsChanged = { [weak self] ids in guard let self, accepts() else { return }; self.source.store.visibleRoomCatIDs = ids }
            scene.onCatNeedAnchorChanged = { [weak self] point in guard let self, accepts() else { return }; self.source.needPresentation?.anchor = point }
            scene.onCatVisualFrameChanged = { [weak self] frame in guard let self, accepts() else { return }; self.source.needPresentation?.localCatFrame = frame }
            scene.onRestRequest68 = { [weak self] id in
                guard let self, accepts(), self.source.isActive, !self.source.store.isDecorating else { return }
                self.source.scene.restPromptFurnitureID68 = id; self.source.onRestRequest?(id)
            }
            scene.onRestSceneChanged68 = { [weak self] state in guard let self, accepts() else { return }; self.source.onRestSceneChanged?(state) }
            scene.onRestIntroduction68 = { [weak self] catID, style in
                guard let self, accepts(), self.source.isActive, self.source.store.cat?.id == catID else { return }
                self.source.store.showNotice(GameStrings.text("home68.introduction.\(style.rawValue)"))
            }
            scene.onFloorTravelAvailabilityChanged = { [weak self] ready in
                DispatchQueue.main.async { guard let self, accepts() else { return }; self.source.store.roomFloorTravelReady = ready }
            }
            scene.onRoomViewChanged = { [weak self] in
                DispatchQueue.main.async { guard let self, accepts() else { return }
                    self.source.store.arrangement68.previewAngle = self.source.scene.roomViewAngle; self.source.onViewChanged?()
                }
            }
            scene.onSound = { [weak self] in guard let self, accepts() else { return }; self.source.store.playSceneSound($0) }
            scene.onBowlTapped = { [weak self] in guard let self, accepts() else { return }; self.source.store.feed() }
            scene.onBowlMoved = { [weak self] in guard let self, accepts() else { return }; self.source.store.moveBowl(to: $0) }
            scene.onFurnitureSelected = { [weak self] id in guard let self, accepts() else { return }
                if let id { self.source.store.selectFurniture(id: id) } else { self.source.store.selectBowl68() }
            }
            scene.onFurnitureMoved = { [weak self] id, point in guard let self, accepts() else { return }; self.source.store.moveFurniture(id: id, to: point) }
            scene.onFurniturePlacementFinished = { [weak self] id, succeeded in guard let self, accepts() else { return }
                self.source.store.finishFurniturePlacement(id: id, succeeded: succeeded, keepingResolutionPending: succeeded && self.source.scene.isPlacementPending)
            }
            scene.onArrangementGestureBegan = { [weak self] in guard let self, accepts(), !self.source.store.isSavingLayout else { return }; self.source.store.beginArrangementGesture68() }
            scene.onArrangementGestureEnded = { [weak self] in guard let self, accepts(), !self.source.store.isSavingLayout else { return }; self.source.store.endArrangementGesture68() }
            scene.onArrangementIssue = { [weak self] id, issue in guard let self, accepts(), !self.source.store.isSavingLayout else { return }; self.source.store.setArrangementIssue68(id: id, issue: issue) }
            scene.onArrangementOrientation = { [weak self] id, orientation in guard let self, accepts() else { return }; self.source.store.applyArrangementOrientation68(id: id, orientation: orientation) }
            scene.onArrangementCommandCompleted = { [weak self] id in guard let self, accepts(), !self.source.store.isSavingLayout else { return }; self.source.store.completeArrangementCommand68(id) }
            scene.onRestingFurnitureChanged = { [weak self] furnitureID, sessionID, catID in
                guard let self, accepts() else { return }
                let observation = furnitureID == nil ? nil : self.source.scene.currentRestObservation
                let occurredAt = Date(), generation = self.generation, floor = self.floor
                DispatchQueue.main.async { [weak self] in
                    guard let self, accepts(), self.generation == generation, self.floor == floor else { return }
                    self.source.store.setRestingFurniture(id: furnitureID, sessionID: sessionID, catID: catID, observation: observation, occurredAt: occurredAt)
                }
            }
            scene.onFurnitureNotice = { [weak self] key in guard let self, accepts() else { return }
                if !["room.sharedHomeNoSpace", "rest.goBed", "rest.goCushion"].contains(key) { self.source.store.showFurnitureNotice(key) }
                if let cat = self.source.store.cat, ["rest.blocked", "catHabits.rest.eating", "catHabits.rest.waitCare"].contains(key) {
                    self.source.store.recordHabitStudy("restBlocked", catID: cat.id, detail: key)
                }
            }
        }
        func detach() {
            let scene = source.scene
            guard scene.macCanvasOwnerID == ownerID else { generation = nil; floor = nil; return }
            scene.setReadOnlyPreviewEnabled(false)
            scene.setPresentationActive(false); scene.cancelCameraInteraction(); scene.invalidateArrangement68()
            if acceptsUpdates {
                // Offscreen care is already saved; changeHomeFloor settles any real rest before replacing the scene.
                source.store.roomFloorTravelReady = !source.store.isDecorating
                source.needPresentation?.anchor = nil; source.needPresentation?.localCatFrame = nil
            }
            scene.macCanvasOwnerID = nil
            generation = nil; floor = nil
        }
    }
}
#endif
