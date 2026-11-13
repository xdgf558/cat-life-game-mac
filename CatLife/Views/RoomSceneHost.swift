import SwiftUI
import SpriteKit
import CatGameCore
import UniformTypeIdentifiers

/// Stage-local UIKit rectangles; external HUD and care bars never reduce this viewport twice.
enum RoomStageLayout {
    static let controlsHeight: CGFloat = 52

    static func controlsFrame(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let width = max(0, min(344, size.width - 24))
        let height = min(controlsHeight, max(0, size.height - 24))
        return CGRect(x: (size.width - width) / 2, y: size.height - 12 - height, width: width, height: height)
    }

    static func usableRect(in size: CGSize) -> CGRect {
        guard size.width > 40, size.height > 0 else { return .zero }
        return CGRect(x: 20, y: 16, width: size.width - 40,
                      height: max(1, controlsFrame(in: size).minY - 24))
    }

    static func previewRegion(in size: CGSize) -> CGRect {
        guard size.width > 24, size.height > 0 else { return .zero }
        return CGRect(x: 12, y: 12, width: size.width - 24,
                      height: max(0, controlsFrame(in: size).minY - 20))
    }

    static func requiresPreviewSheet(in size: CGSize, accessibility: Bool) -> Bool {
        accessibility || previewRegion(in: size).height < 120
    }

    static func previewFrame(near cat: CGRect, preferredHeight: CGFloat, in size: CGSize) -> CGRect {
        let region = previewRegion(in: size)
        guard region.width > 0, region.height > 0 else { return .zero }
        let width = min(230, region.width)
        let height = min(max(44, preferredHeight), region.height)
        let above = cat.minY - height - 12
        let below = cat.maxY + 12
        let preferredY = above >= region.minY ? above
            : below + height <= region.maxY ? below : cat.midY - height / 2
        return CGRect(x: min(region.maxX - width, max(region.minX, cat.midX - width / 2)),
                      y: min(region.maxY - height, max(region.minY, preferredY)), width: width, height: height)
    }

    static func arrangementControlsFrame(in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> CGRect {
        guard size.width.isFinite, size.height.isFinite, topInset.isFinite, bottomInset.isFinite,
              size.width > 24, size.height > 0 else { return .zero }
        let panelTop = max(0, size.height - max(0, bottomInset))
        let height = min(controlsHeight, max(44, panelTop - max(0, topInset) - 12))
        let width = min(344, size.width - 24)
        return CGRect(x: (size.width - width) / 2, y: max(0, panelTop - 12 - height), width: width, height: height)
    }

    static func arrangementUsableRect(in size: CGSize, bottomInset: CGFloat, topInset: CGFloat = 160) -> CGRect {
        let controls = arrangementControlsFrame(in: size, topInset: topInset, bottomInset: bottomInset)
        guard controls.width > 0 else { return .zero }
        let top = min(size.height - 1, max(12, topInset))
        let bottom = max(top + 1, controls.minY - 8)
        return CGRect(x: 12, y: top, width: size.width - 24, height: bottom - top)
    }

}

@MainActor
struct RoomSceneHost: View {
    let store: GameStore
    let isActive: Bool
    let reducedMotion: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var attachedGeneration: UUID?
    @State private var previewCatID: String?
    @State private var previewFrame: CGRect?
    @State private var previewHeight: CGFloat = 200
    @State private var habitOfferFrame: CGRect?
    @State private var habitPromptHeight: CGFloat = 150
    @State private var restScene68 = HomeRestScene68()
    @State private var restRequestID68: String?
    @State private var restRequestCatID68: String?
    @State private var restRequestHeight68: CGFloat = 185
    @State private var restStatusHeight68: CGFloat = 145
    @State private var introductionStyle68: CatBehaviorStyle?
    @State private var introductionTask68: Task<Void, Never>?
    @State private var accessibleGrowthID: String?
    @State private var isSavingGrowth = false
    @State private var scene = RoomScene(size: CGSize(width: 390, height: 480))
    @State private var arrangementFrame: CGRect?
    @State private var viewportSize = CGSize.zero
    @State private var viewTransitionTask: Task<Void, Never>?
    @State private var canvasOpacity = 1.0
    @State private var isTransitioning = false
    @State private var roomViewAngle: RoomViewAngle = .front
    @State private var isWholeRoomView = true
    @State private var canChangeRoomView = false
    let catNeedPresentation: CatNeedPresentation
    let referenceViewportSize: CGSize
    var arrangementBottomInset: CGFloat = 0
    var arrangementTopInset: CGFloat = 160
    #if DEBUG
    @State private var animationPhase = "idle"
    @State private var navigationStatus = ""
    @State private var dragStatus = ""
    @State private var furnitureStatus = ""

    private var furnitureTesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing")
            && (args.contains("--furniture-test") || args.contains("--rest-test"))
    }

    private var dragTesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--drag-performance-test")
    }

    private var navigationTesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--navigation-test")
    }

    private var animationTesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--animation-test")
    }

    #endif

    private var effectiveReducedMotion: Bool {
        #if DEBUG
        reducedMotion || (animationTesting && ProcessInfo.processInfo.arguments.contains("--reduce-motion-test"))
        #else
        reducedMotion
        #endif
    }

    private var ownsPresentation: Bool {
        attachedGeneration == store.saveSceneGeneration && scene.homeFloor == store.visibleHomeFloor
    }

    var body: some View {
        GeometryReader { geometry in
            roomContent(geometry: geometry)
                .onChange(of: geometry.size, initial: true) { _, size in viewportSize = size }
        }
        .sheet(isPresented: Binding(get: { isActive && ownsPresentation && !store.isDecorating && usesResidentSheet && previewCatID != nil },
                                    set: { if !$0 { closePreview() } })) {
            if let cat = store.snapshot?.cats.first(where: { $0.id == previewCatID }) {
                NavigationStack {
                    Group {
                        if let id = accessibleGrowthID {
                            CatGrowthView(store: store, catID: id, isSaving: $isSavingGrowth, home: closePreview)
                        } else {
                            ScrollView {
                                RoomResidentPreviewCard(store: store, cat: cat, close: closePreview,
                                    openGrowth: { accessibleGrowthID = cat.id }).padding(20)
                            }
                        }
                    }.toolbar {
                        if accessibleGrowthID != nil {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(GameStrings.text("common.back")) { accessibleGrowthID = nil }.disabled(isSavingGrowth)
                            }
                        }
                    }
                }.presentationBackground(RoomTheme.cream).presentationDetents([.large]).presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(store.isBusy || isSavingGrowth)
            }
        }
    }


    private var usesResidentSheet: Bool {
        RoomStageLayout.requiresPreviewSheet(in: viewportSize, accessibility: dynamicTypeSize.isAccessibilitySize)
    }

    @ViewBuilder
    private func roomContent(geometry: GeometryProxy) -> some View {
        let controls = store.isDecorating
            ? RoomStageLayout.arrangementControlsFrame(in: geometry.size, topInset: arrangementTopInset, bottomInset: arrangementBottomInset)
            : RoomStageLayout.controlsFrame(in: geometry.size)
        let usable = store.isDecorating
            ? RoomStageLayout.arrangementUsableRect(in: geometry.size, bottomInset: arrangementBottomInset, topInset: arrangementTopInset)
            : RoomStageLayout.usableRect(in: geometry.size)
        ZStack {
            roomCanvas(geometry: geometry).opacity(canvasOpacity).accessibilityHidden(true)
            if isActive && ownsPresentation { accessibleRoom.accessibilityHidden(isTransitioning) }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        #if DEBUG
        .overlay {
            if furnitureTesting, isActive, ownsPresentation, previewCatID == nil, !isTransitioning {
                let target = pinchTestRect(in: usable, canvas: geometry.size)
                Color.clear
                    .frame(width: target.width * 0.8, height: target.height * 0.8)
                    .offset(x: target.midX - geometry.size.width / 2,
                            y: target.midY - geometry.size.height / 2)
                    .accessibilityElement()
                    .accessibilityLabel("Room pinch surface")
                    .accessibilityIdentifier("roomPinchSurface")
                    .allowsHitTesting(false)
            }
        }
        #endif
        .overlay {
            CatNeedBubble(reducedMotion: effectiveReducedMotion, store: store, presentation: catNeedPresentation,
                          canvasSize: geometry.size, isActive: isActive && ownsPresentation && previewCatID == nil && !isTransitioning && !showsHabitPrompt,
                          canAct: { scene.canShowCatNeed }, avoidingFrame: controls)
        }
        .overlay {
            if isActive, ownsPresentation, store.isDecorating, store.arrangementSelection68,
               !store.isResolvingLayout, usable.height >= 80, let arrangementFrame {
                RoomArrangementOverlay(store: store, selectedFrame: arrangementFrame,
                                       canvasSize: geometry.size, bottomInset: arrangementBottomInset + controls.height + 20, topInset: arrangementTopInset)
            }
        }
        .overlay {
            residentPreview(size: geometry.size)
                .opacity(isTransitioning ? 0 : 1)
                .allowsHitTesting(!isTransitioning).accessibilityHidden(isTransitioning)
        }
        .overlay { restOverlays68(in: usable) }
        .overlay { habitPrompt(in: usable) }
        .overlay { HomeMemoryBanner68(store: store, isActive: canShowMemory68, available: usable) }
        .overlay { cameraControls(frame: controls) }
        .onChange(of: usable, initial: true) { _, rect in updateRoomViewUsableRect(rect) }
        .onChange(of: isActive) { _, active in
            if active { updateRoomViewUsableRect(usable) }
        }
    }

    private var showsHabitIntro: Bool {
        guard let play = store.snapshot?.catPlay else { return false }
        return HomePromptPriority68.showsAutomaticIntro(eligible: play.tutorialID == nil && !play.introDismissed,
            hasPinnedMemory: store.cat?.habits.pinnedMemory != nil,
            hasPendingMemory: store.companionMemories.hasPending)
    }

    private var showsHabitCornerOffer: Bool {
        store.habitCornerOffer != nil && habitOfferFrame != nil
            && store.cat?.activeRest == nil && restScene68.canStart
    }

    private var canShowHomeOverlay68: Bool {
        isActive && ownsPresentation && !store.isDecorating && !store.isChangingHomeFloor
            && previewCatID == nil && store.inspectedCatID == nil && !isTransitioning
            && !store.hasSaveFailure && store.toast == nil && store.adoptionReminders.pendingOffer == nil
    }

    private var canShowMemory68: Bool {
        canShowHomeOverlay68 && !showsHabitIntro && !showsHabitCornerOffer
            && restRequestID68 == nil && store.cat?.activeRest == nil && restScene68.canStart
            && CatNeed.current(in: store) == nil && !store.isBusy
    }

    private var requestedRestFurniture68: FurnitureItem? {
        guard restRequestCatID68 == store.cat?.id, let id = restRequestID68,
              store.sceneSnapshot?.home.furniture.contains(where: { $0.itemID == id }) == true else { return nil }
        return store.snapshot?.inventory.furniture.first { $0.id == id && CatRestPreference(kind: $0.kind) != nil }
    }

    @ViewBuilder private func restOverlays68(in bounds: CGRect) -> some View {
        if isActive, ownsPresentation, !store.isDecorating, !isTransitioning,
           let cat = store.cat, let frame = restScene68.cornerFrame, let anchor = restScene68.cornerAnchor {
            HomeCornerMarker68(name: GameStrings.catName(cat), furniture: frame, anchor: anchor,
                               available: bounds, reducedMotion: effectiveReducedMotion)
        }
        if canShowHomeOverlay68, let cat = store.cat {
            if let furniture = requestedRestFurniture68 {
                let frame = HomeRestLayout68.request(near: restScene68.requestFrame, in: bounds, height: restRequestHeight68)
                ScrollView {
                    HomeRestRequest68(cat: cat, furniture: furniture,
                        reasonKey: store.isBusy ? "common.saving" : restScene68.reasonKey,
                        confirm: confirmRestRequest68, close: closeRestRequest68)
                        .background { GeometryReader { card in
                            Color.clear.onAppear { restRequestHeight68 = card.size.height }
                                .onChange(of: card.size.height) { _, height in restRequestHeight68 = height }
                        }.allowsHitTesting(false) }
                }.scrollBounceBehavior(.basedOnSize)
                    .id(furniture.id).frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            } else if let rest = cat.activeRest,
                      let furniture = store.snapshot?.inventory.furniture.first(where: { $0.id == rest.furnitureID }),
                      store.sceneSnapshot?.home.furniture.contains(where: { $0.itemID == rest.furnitureID }) == true {
                let frame = HomeRestLayout68.status(in: bounds, height: restStatusHeight68)
                let scrolling = HomeRestLayout68.statusNeedsScrolling(in: bounds, height: restStatusHeight68)
                VStack(spacing: 0) {
                    ScrollView {
                        HomeRestStatus68(store: store, cat: cat, furniture: furniture, rest: rest)
                            .background { GeometryReader { card in
                                Color.clear.onAppear { restStatusHeight68 = card.size.height }
                                    .onChange(of: card.size.height) { _, height in restStatusHeight68 = height }
                            }.allowsHitTesting(false) }
                    }.scrollBounceBehavior(.basedOnSize)
                    if scrolling {
                        Button(GameStrings.text("home68.rest.wake")) { scene.leaveFurnitureRest() }
                            .font(.caption.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 44)
                            .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
                            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("homeRestWake")
                    }
                }
                .id(rest.id).frame(width: frame.width, height: frame.height).clipped()
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(scrolling)
                if restScene68.phase == "resting", let catFrame = catNeedPresentation.localCatFrame {
                    HomeRestSleep68(reducedMotion: effectiveReducedMotion)
                        .position(x: min(bounds.maxX - 18, max(bounds.minX + 18, catFrame.maxX)),
                                  y: max(bounds.minY + 18, catFrame.minY - 12))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            if let style = introductionStyle68, let catFrame = catNeedPresentation.localCatFrame,
               CatNeed.current(in: store) == nil {
                HomeRestIntroduction68(style: style, reducedMotion: effectiveReducedMotion)
                    .frame(width: min(245, bounds.width))
                    .position(x: min(bounds.maxX - min(245, bounds.width) / 2,
                                     max(bounds.minX + min(245, bounds.width) / 2, catFrame.midX)),
                              y: max(bounds.minY + 28, catFrame.minY - 26))
            }
        }
    }

    private func closeRestRequest68() {
        restRequestID68 = nil; restRequestCatID68 = nil
        scene.restPromptFurnitureID68 = nil
    }

    private func confirmRestRequest68() {
        guard canShowHomeOverlay68, !store.isBusy, let furniture = requestedRestFurniture68,
              scene.restPresentation68.canStart else { return }
        closeRestRequest68()
        scene.confirmFurnitureRest68(furniture.id)
    }

    private func clearRestOverlays68() {
        closeRestRequest68()
        restScene68 = HomeRestScene68()
        introductionTask68?.cancel(); introductionTask68 = nil; introductionStyle68 = nil
    }

    private func showRestIntroduction68(_ style: CatBehaviorStyle) {
        introductionTask68?.cancel()
        withAnimation(scene.reducedMotion ? nil : .easeOut(duration: 0.18)) { introductionStyle68 = style }
        introductionTask68 = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            withAnimation(scene.reducedMotion ? nil : .easeOut(duration: 0.2)) { introductionStyle68 = nil }
            introductionTask68 = nil
        }
    }

    private var showsHabitPrompt: Bool {
        canShowHomeOverlay68 && restRequestID68 == nil && store.cat?.activeRest == nil
            && restScene68.canStart && store.cat?.healthState?.illness == nil
            && (showsHabitIntro || showsHabitCornerOffer
                || (store.canShowPinnedHabitHint && !store.companionMemories.hasPending))
    }

    private var habitPromptIdentity: String {
        let catID = store.cat?.id ?? ""
        if showsHabitIntro { return catID + "-intro" }
        if showsHabitCornerOffer { return catID + "-corner-" + (store.habitCornerOffer?.id ?? "") }
        return "\(catID)-\(store.cat?.habits.pinnedMemory?.rawValue ?? "")-\(store.cat?.habits.pinnedHintCollapsed ?? false)"
    }

    @ViewBuilder private func habitPrompt(in bounds: CGRect) -> some View {
        if showsHabitPrompt, bounds.width >= 150, bounds.height >= 90 {
            let anchor = showsHabitCornerOffer && !showsHabitIntro ? habitOfferFrame : catNeedPresentation.localCatFrame
            let frame = showsHabitIntro
                ? HabitRoomPromptLayout.frame(above: anchor ?? bounds, within: bounds, height: habitPromptHeight)
                : showsHabitCornerOffer ? HomeRestLayout68.bottom(in: bounds, height: habitPromptHeight)
                : HomeRestLayout68.top(in: bounds, height: habitPromptHeight)
            ScrollView {
                Group {
                    if showsHabitIntro { HabitIntroBanner(store: store) }
                    else if showsHabitCornerOffer, let receipt = store.habitCornerOffer, let cat = store.cat {
                        HabitCornerOfferView(store: store, catID: cat.id, receipt: receipt)
                    } else if store.canShowPinnedHabitHint, let cat = store.cat, let memory = cat.habits.pinnedMemory {
                        PinnedHabitPrompt(store: store, cat: cat, memory: memory)
                    }
                }
                .background { GeometryReader { prompt in
                    Color.clear.onAppear { habitPromptHeight = prompt.size.height }
                        .onChange(of: prompt.size.height) { _, height in habitPromptHeight = height }
                }.allowsHitTesting(false) }
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(habitPromptIdentity)
            .accessibilityIdentifier("habitRoomPromptScroll")
            .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
        }
    }

    @ViewBuilder
    private func residentPreview(size: CGSize) -> some View {
        if isActive, ownsPresentation, !store.isDecorating, !usesResidentSheet,
           let id = previewCatID, let anchor = previewFrame,
           let cat = store.snapshot?.cats.first(where: { $0.id == id }) {
            let frame = RoomStageLayout.previewFrame(near: anchor, preferredHeight: previewHeight, in: size)
            ScrollView {
                RoomResidentPreviewCard(store: store, cat: cat, close: closePreview)
                    .background { GeometryReader { card in
                        Color.clear.onAppear { previewHeight = card.size.height }
                            .onChange(of: card.size.height) { _, value in previewHeight = value }
                    }.allowsHitTesting(false) }
            }.scrollBounceBehavior(.basedOnSize)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func inspectResident(_ id: String) {
        guard scene.canInspectResidents, !store.isBusy, !store.isDecorating,
              let frame = scene.residentFrame(id: id) else { return }
        previewCatID = id; previewFrame = frame
        scene.inspectedResidentID = id
        catNeedPresentation.isInspectingResident = true
    }

    private func closePreview() {
        previewCatID = nil; previewFrame = nil
        scene.inspectedResidentID = nil
        accessibleGrowthID = nil
        if ownsPresentation { catNeedPresentation.isInspectingResident = false }
    }

    private func roomCanvas(geometry: GeometryProxy) -> some View {
        NativeRoomCanvas(scene: scene, isActive: isActive && ownsPresentation,
                         isInteractive: !isTransitioning && !store.isSavingLayout && !store.isChangingHomeFloor,
                         canvasSize: geometry.size)
            .allowsHitTesting(!isTransitioning && !store.isSavingLayout && !store.isChangingHomeFloor)
            .onDrop(of: [UTType.text], isTargeted: nil) { providers, point in
                receiveArrangementDrop68(providers, point: point)
            }
            .onAppear { configureScene(geometry: geometry) }
            .onChange(of: isActive) { _, active in
                scene.setPresentationActive(active && ownsPresentation)
                if active { dispatchArrangementCommand68() }
                if !active {
                    if store.arrangement68.pendingRequest == nil && !scene.arrangementYielding68 { store.endArrangementGesture68() }
                    cancelViewTransition()
                    closePreview()
                    clearRestOverlays68()
                    if ownsPresentation { catNeedPresentation.anchor = nil; catNeedPresentation.localCatFrame = nil }
                    arrangementFrame = nil
                    habitOfferFrame = nil
                    if !scene.arrangementYielding68 { scene.cancelPlacementPreview(completeCommand: false) }
                }
            }
            .onDisappear {
                if store.arrangement68.pendingRequest == nil && !scene.arrangementYielding68 { store.endArrangementGesture68() }
                cancelViewTransition()
                closePreview()
                clearRestOverlays68()
                scene.setPresentationActive(false)
                scene.invalidateArrangement68()
                scene.onCatNeedAnchorChanged = nil
                scene.onCatVisualFrameChanged = nil
                scene.onArrangementFrameChanged = nil
                scene.onFloorTravelAvailabilityChanged = nil
                scene.onRoomViewChanged = nil
                arrangementFrame = nil
                scene.onBackgroundTapped = nil
                scene.onVisibleResidentsChanged = nil
                scene.onInspectedResidentFrameChanged = nil
                scene.onHabitOfferFrameChanged = nil
                scene.onRestRequest68 = nil
                scene.onRestSceneChanged68 = nil
                scene.onRestIntroduction68 = nil
                scene.cornerMarkerFurnitureID68 = nil
                scene.onRestingFurnitureChanged = nil
                scene.onArrangementGestureBegan = nil
                scene.onArrangementGestureEnded = nil
                scene.onArrangementIssue = nil
                scene.onArrangementOrientation = nil
                scene.onArrangementCommandCompleted = nil
                habitOfferFrame = nil
                if ownsPresentation {
                    catNeedPresentation.anchor = nil; catNeedPresentation.localCatFrame = nil
                }
                scene.cancelPlacementPreview()
            }
            .onChange(of: geometry.size) { _, size in
                cancelViewTransition()
                scene.setReferenceViewportSize(referenceViewportSize)
                scene.size = size
            }
            .onChange(of: referenceViewportSize) { _, size in
                cancelViewTransition()
                scene.setReferenceViewportSize(size)
            }
            .onChange(of: geometry.frame(in: .global).origin) { _, origin in catNeedPresentation.canvasOrigin = origin }
            .onChange(of: effectiveReducedMotion) { _, value in
                cancelViewTransition()
                scene.reducedMotion = value
            }
            .onChange(of: store.visibleHomeFloor) { _, _ in scene.invalidateArrangement68(); cancelViewTransition(); clearRestOverlays68() }
            .onChange(of: store.saveSceneGeneration) { _, _ in scene.invalidateArrangement68(); cancelViewTransition(); clearRestOverlays68() }
            .onChange(of: store.isChangingHomeFloor) { _, changing in
                if changing { cancelViewTransition(); clearRestOverlays68() }
            }
            .onChange(of: store.cat?.id) { _, _ in closePreview(); clearRestOverlays68() }
            .onChange(of: store.inspectedCatID) { _, id in if id != nil { clearRestOverlays68() } }
            .onChange(of: store.sceneSnapshot) { _, _ in refreshScene() }
            .onChange(of: store.isDecorating) { _, editing in
                cancelViewTransition()
                if editing { closePreview(); clearRestOverlays68() }
                refreshScene()
            }
            .onChange(of: store.selectedFurnitureID) { _, _ in refreshScene() }
            .onChange(of: store.placingFurnitureID) { _, _ in refreshScene() }
            .onChange(of: store.arrangement68.bowlSelected) { _, _ in refreshScene() }
            .onChange(of: store.arrangement68.snapEnabled) { _, _ in configureArrangement68() }
            .onChange(of: store.arrangement68.pendingRequest?.id) { _, _ in dispatchArrangementCommand68() }
            .onChange(of: store.feedback?.id) { _, _ in
                refreshScene()
                if let feedback = store.feedback { scene.playFeedback(kind: feedback.kind, catID: feedback.catID) }
            }
    }

    private func configureScene(geometry: GeometryProxy) {
        scene.setReferenceViewportSize(referenceViewportSize)
        scene.scaleMode = .resizeFill
        if scene.size != geometry.size { scene.size = geometry.size }
        #if DEBUG
        scene.diagnostics.onPresentationChanged = { value in DispatchQueue.main.async { animationPhase = value } }
        scene.diagnostics.onNavigationChanged = { value in DispatchQueue.main.async { navigationStatus = value } }
        scene.diagnostics.onDragMetricsChanged = { value in DispatchQueue.main.async { dragStatus = value } }
        scene.diagnostics.onFurnitureDiagnosticsChanged = { value in DispatchQueue.main.async { furnitureStatus = value } }
        dragStatus = scene.diagnostics.dragDescription
        furnitureStatus = scene.diagnostics.furnitureDescription
        navigationStatus = scene.diagnostics.navigationDescription
        animationPhase = scene.presentationPhase
        #endif
        let generation = store.saveSceneGeneration
        attachedGeneration = generation
        let sourceFloor = store.visibleHomeFloor
        // Only the new floor/save owner resets inspection after the old host has relinquished ownership.
        catNeedPresentation.isInspectingResident = false
        let acceptsSceneUpdates = {
            store.saveSceneGeneration == generation && store.visibleHomeFloor == sourceFloor
                && !store.isChangingHomeFloor
        }
        scene.onPlacementPendingChanged = { if acceptsSceneUpdates() { store.setLayoutResolving($0) } }
        scene.reducedMotion = effectiveReducedMotion
        scene.homeFloor = sourceFloor
        scene.onCatTapped = { if acceptsSceneUpdates(), let id = store.cat?.id { inspectResident(id) } }
        scene.onResidentTapped = { if acceptsSceneUpdates() { inspectResident($0) } }
        scene.onBackgroundTapped = { if acceptsSceneUpdates() { closePreview(); closeRestRequest68() } }
        scene.onVisibleResidentsChanged = { if acceptsSceneUpdates() { store.visibleRoomCatIDs = $0 } }
        scene.onInspectedResidentFrameChanged = { frame in
            guard acceptsSceneUpdates() else { return }
            previewFrame = frame
            if frame == nil { closePreview() }
        }
        scene.onHabitOfferFrameChanged = { if acceptsSceneUpdates() { habitOfferFrame = $0 } }
        scene.onRestRequest68 = { id in
            guard acceptsSceneUpdates(), scene.presentationActive, !store.isDecorating else { return }
            closePreview()
            restRequestID68 = id; restRequestCatID68 = store.cat?.id
            scene.restPromptFurnitureID68 = id
            restScene68 = scene.restPresentation68
        }
        scene.onRestSceneChanged68 = { if acceptsSceneUpdates() { restScene68 = $0 } }
        scene.onRestIntroduction68 = { catID, style in
            guard acceptsSceneUpdates(), scene.presentationActive, store.cat?.id == catID else { return }
            showRestIntroduction68(style)
        }
        restScene68 = scene.restPresentation68
        scene.onFloorTravelAvailabilityChanged = { ready in
            DispatchQueue.main.async {
                guard acceptsSceneUpdates() else { return }
                store.roomFloorTravelReady = ready
            }
        }
        scene.onRoomViewChanged = {
            DispatchQueue.main.async { if acceptsSceneUpdates() { refreshRoomViewControls() } }
        }
        let presentation = catNeedPresentation
        presentation.canvasOrigin = geometry.frame(in: .global).origin
        scene.onCatNeedAnchorChanged = { [weak presentation] point in if acceptsSceneUpdates() { presentation?.anchor = point } }
        scene.onCatVisualFrameChanged = { [weak presentation] frame in if acceptsSceneUpdates() { presentation?.localCatFrame = frame } }
        scene.onArrangementFrameChanged = { if acceptsSceneUpdates() { arrangementFrame = $0 } }
        scene.onSound = { store.playSceneSound($0) }
        scene.onBowlTapped = { if acceptsSceneUpdates() { store.feed() } }
        scene.onBowlMoved = { if acceptsSceneUpdates() { store.moveBowl(to: $0) } }
        scene.onFurnitureSelected = { id in
            guard acceptsSceneUpdates() else { return }
            if let id { store.selectFurniture(id: id) } else { store.selectBowl68() }
        }
        scene.onFurnitureMoved = { if acceptsSceneUpdates() { store.moveFurniture(id: $0, to: $1) } }
        scene.onFurniturePlacementFinished = { id, succeeded in
            if acceptsSceneUpdates() {
                store.finishFurniturePlacement(id: id, succeeded: succeeded,
                    keepingResolutionPending: succeeded && scene.isPlacementPending)
            }
        }
        scene.onArrangementGestureBegan = {
            if acceptsSceneUpdates(), store.isDecorating, !store.isSavingLayout { store.beginArrangementGesture68() }
        }
        scene.onArrangementGestureEnded = {
            if acceptsSceneUpdates(), store.isDecorating, !store.isSavingLayout { store.endArrangementGesture68() }
        }
        scene.onArrangementIssue = { id, issue in
            if acceptsSceneUpdates(), !store.isSavingLayout { store.setArrangementIssue68(id: id, issue: issue) }
        }
        scene.onArrangementOrientation = { id, orientation in
            if acceptsSceneUpdates() { store.applyArrangementOrientation68(id: id, orientation: orientation) }
        }
        scene.onArrangementCommandCompleted = { id in
            if acceptsSceneUpdates(), !store.isSavingLayout { store.completeArrangementCommand68(id) }
        }
        scene.onRestingFurnitureChanged = { [weak source = scene] furnitureID, sessionID, catID in
            let observation = furnitureID != nil ? source?.currentRestObservation : nil
            let occurredAt = Date()
            // Reconciliation can run inside UIViewRepresentable updates; keep the captured time, not that render transaction.
            DispatchQueue.main.async {
                guard acceptsSceneUpdates() else { return }
                store.setRestingFurniture(id: furnitureID, sessionID: sessionID, catID: catID,
                    observation: observation, occurredAt: occurredAt)
            }
        }
        scene.onFurnitureNotice = {
            guard acceptsSceneUpdates() else { return }
            if !["room.sharedHomeNoSpace", "rest.goBed", "rest.goCushion"].contains($0) { store.showFurnitureNotice($0) }
            if let cat = store.cat, ["rest.blocked", "catHabits.rest.eating", "catHabits.rest.waitCare"].contains($0) {
                store.recordHabitStudy("restBlocked", catID: cat.id, detail: $0)
            }
        }
        refreshScene()
        scene.setPresentationActive(isActive)
        updateRoomViewUsableRect(store.isDecorating
            ? RoomStageLayout.arrangementUsableRect(in: geometry.size, bottomInset: arrangementBottomInset, topInset: arrangementTopInset)
            : RoomStageLayout.usableRect(in: geometry.size))
        refreshRoomViewControls()
        dispatchArrangementCommand68()
    }

    private func configureArrangement68() {
        guard ownsPresentation else { return }
        scene.configureArrangement68(snapEnabled: store.arrangement68.snapEnabled, bowlSelected: store.arrangement68.bowlSelected,
                                     placementIssues: store.arrangement68.placementIssues)
    }

    private func dispatchArrangementCommand68() {
        guard isActive, ownsPresentation, store.isDecorating, !store.isSavingLayout,
              let request = store.arrangement68.pendingRequest else { return }
        scene.applyArrangementCommand68(request, snapEnabled: store.arrangement68.snapEnabled)
    }

    private func receiveArrangementDrop68(_ providers: [NSItemProvider], point: CGPoint) -> Bool {
        guard isActive, ownsPresentation, store.canEditArrangement68, point.x.isFinite, point.y.isFinite,
              let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        let generation = store.saveSceneGeneration
        let floor = store.visibleHomeFloor
        let source = scene
        provider.loadObject(ofClass: NSString.self) { value, error in
            guard error == nil, let id = value as? String else { return }
            Task { @MainActor in
                guard isActive, ownsPresentation, scene === source, source.presentationActive,
                      store.canDropArrangementFurniture68(id: id, generation: generation, floor: floor) else { return }
                store.placeFurniture(id: id)
                guard store.placingFurnitureID == id else { return }
                source.dropStoredFurniture68(id, atViewPoint: point)
            }
        }
        return true
    }

    private func updateRoomViewUsableRect(_ rect: CGRect) {
        guard isActive, ownsPresentation else { return }
        scene.setRoomViewUsableRect(rect)
    }

    @ViewBuilder
    private func cameraControls(frame: CGRect) -> some View {
        if isActive, ownsPresentation {
            RoomViewControls(angle: roomViewAngle, isWholeRoomView: isWholeRoomView,
                             canChangeView: canChangeRoomView && !isTransitioning && !store.isSavingLayout && !store.isChangingHomeFloor
                                && (!store.isDecorating || store.canEditArrangement68),
                             catName: store.cat.map(GameStrings.catName) ?? "",
                             turn: { steps in transitionRoomView { scene.turnRoomView(by: steps) } },
                             showWholeRoom: { transitionRoomView { scene.showWholeRoom() } },
                             focusCat: { transitionRoomView { scene.showCatCloseUp() } })
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func transitionRoomView(_ action: @escaping @MainActor () -> Void) {
        guard isActive, ownsPresentation, scene.canChangeRoomView, !isTransitioning,
              !store.isSavingLayout, !store.isChangingHomeFloor,
              !store.isDecorating || store.canEditArrangement68 else { return }
        guard !effectiveReducedMotion else { action(); return }
        let source = scene
        let generation = store.saveSceneGeneration
        let floor = scene.homeFloor
        let editing = store.isDecorating
        scene.cancelCameraInteraction()
        isTransitioning = true
        withAnimation(.easeOut(duration: 0.225)) { canvasOpacity = 0 }
        viewTransitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(225)) } catch { return }
            guard !Task.isCancelled else { return }
            guard isActive, ownsPresentation, scene === source, source.canChangeRoomView,
                  store.saveSceneGeneration == generation, store.visibleHomeFloor == floor,
                  store.isDecorating == editing, !store.isSavingLayout, !store.isChangingHomeFloor,
                  !editing || store.canEditArrangement68 else {
                cancelViewTransition()
                return
            }
            action()
            withAnimation(.easeIn(duration: 0.225)) { canvasOpacity = 1 }
            do { try await Task.sleep(for: .milliseconds(225)) } catch { return }
            guard !Task.isCancelled else { return }
            isTransitioning = false
            viewTransitionTask = nil
        }
    }

    private func cancelViewTransition() {
        viewTransitionTask?.cancel()
        viewTransitionTask = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            canvasOpacity = 1
            isTransitioning = false
        }
    }

    private var accessibleRoom: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.text("accessibility.cat"))
            .accessibilityIdentifier("roomScene")
            .accessibilityValue(sceneAccessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                HomeRoomAccessibility68.activate(isResting: scene.activeRest != nil,
                    wake: { scene.leaveFurnitureRest() }, inspect: { store.inspectCat() })
            }
            .accessibilityActions { roomAccessibilityActions }
    }

    @ViewBuilder
    private var roomAccessibilityActions: some View {
        Group {
            Button(GameStrings.text("care.feed")) { store.feed() }
            if scene.activeRest != nil {
                Button(GameStrings.text("home68.rest.wake")) { scene.leaveFurnitureRest() }
            }
            Button(GameStrings.text("rest.bedAction")) { scene.restInFurniture(kind: .catBed) }
            Button(GameStrings.text("rest.cushionAction")) { scene.restInFurniture(kind: .floorCushion) }
        }
        roomCameraAccessibilityActions
        residentAccessibilityActions
    }

    private var roomCameraAccessibilityActions: some View {
        Group {
            Button(GameStrings.text("homeUpgrade.focusCat")) { transitionRoomView { scene.showCatCloseUp() } }
            Button(GameStrings.text("roomView.showWhole")) { transitionRoomView { scene.showWholeRoom() } }
                .disabled(!canChangeRoomView)
            Button(GameStrings.text("roomView.turnLeft")) { transitionRoomView { scene.turnRoomView(by: -1) } }
                .disabled(!canChangeRoomView || roomViewAngle == .left)
            Button(GameStrings.text("roomView.turnRight")) { transitionRoomView { scene.turnRoomView(by: 1) } }
                .disabled(!canChangeRoomView || roomViewAngle == .right)
            Button(GameStrings.text("homeUpgrade.zoomIn")) { scene.zoomIn() }
            Button(GameStrings.text("homeUpgrade.zoomOut")) { scene.zoomOut() }
        }
    }

    @ViewBuilder
    private var residentAccessibilityActions: some View {
        let cats: [CatState] = store.snapshot?.cats ?? []
        if (store.snapshot?.home.roomLevel ?? 1) >= RoomResidentCats.unlockLevel {
            ForEach(cats) { cat in
                Button(GameStrings.format("room.inspectResident", GameStrings.catName(cat))) {
                    inspectResident(cat.id)
                }
            }
        }
    }

    private var sceneAccessibilityValue: String {
        #if DEBUG
        if furnitureTesting { return furnitureStatus }
        if dragTesting { return dragStatus }
        if navigationTesting { return navigationStatus }
        if animationTesting { return animationPhase }
        return ProcessInfo.processInfo.arguments.contains("--ui-testing") ? bowlPositionDescription : store.catStatus
        #else
        return store.catStatus
        #endif
    }

    private func refreshScene() {
        guard ownsPresentation else { return }
        configureArrangement68()
        scene.habitOfferItemID = store.habitCornerOffer?.furnitureID
        scene.cornerMarkerFurnitureID68 = store.cat?.habits.cornerFurnitureID
        if let value = store.sceneSnapshot {
            scene.apply(snapshot: value, editing: store.isDecorating,
                        selectedFurnitureID: store.selectedFurnitureID,
                        placingFurnitureID: store.placingFurnitureID)
        }
    }

    private func refreshRoomViewControls() {
        roomViewAngle = scene.roomViewAngle
        store.arrangement68.previewAngle = scene.roomViewAngle
        isWholeRoomView = scene.isWholeRoomView
        canChangeRoomView = scene.canChangeRoomView
    }

    #if DEBUG
    private func pinchTestRect(in usableRect: CGRect, canvas: CGSize) -> CGRect {
        guard store.isDecorating, let arrangementFrame else { return usableRect }
        let tools = RoomArrangementOverlayLayout.center(for: arrangementFrame, canvas: canvas,
            bottomInset: arrangementBottomInset, width: min(232, max(0, canvas.width - 24)), topInset: arrangementTopInset)
        // A pinch on a native tool button belongs to that button, not the canvas underneath.
        let height = tools.y - 36 - usableRect.minY
        return height >= 80 ? CGRect(x: usableRect.minX, y: usableRect.minY,
                                      width: usableRect.width, height: height) : usableRect
    }

    private var bowlPositionDescription: String {
        guard let point = store.sceneSnapshot?.home.bowlPosition else { return "" }
        return String(format: "%.3f,%.3f", point.x, point.y)
    }
    #endif
}

/// Present the scene explicitly so scene attachment and resume ordering are
/// consistent across supported OS versions, including a cold launch from inactive.
#if os(iOS)
@MainActor
private struct NativeRoomCanvas: UIViewRepresentable {
    let scene: RoomScene
    let isActive: Bool
    let isInteractive: Bool
    let canvasSize: CGSize

    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.preferredFramesPerSecond = 30
        view.ignoresSiblingOrder = true
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.addGestureRecognizer(context.coordinator.pinch)
        context.coordinator.setActive(isActive && isInteractive)
        configure(view)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        context.coordinator.setActive(isActive && isInteractive)
        configure(view)
    }

    static func dismantleUIView(_ view: SKView, coordinator: Coordinator) {
        coordinator.setActive(false)
        view.removeGestureRecognizer(coordinator.pinch)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let pinch = UIPinchGestureRecognizer()
        private weak var scene: RoomScene?

        init(scene: RoomScene) {
            self.scene = scene
            super.init()
            pinch.addTarget(self, action: #selector(pinched(_:)))
            pinch.delegate = self
            pinch.cancelsTouchesInView = true
            pinch.delaysTouchesBegan = false
        }

        func setActive(_ active: Bool) {
            if pinch.isEnabled != active { pinch.isEnabled = active }
            if !active { scene?.handlePinch(state: .cancelled, scale: 1, location: .zero) }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            scene?.canZoomCamera == true
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began, .changed:
                guard recognizer.numberOfTouches >= 2 else { return }
            default: break
            }
            scene?.handlePinch(state: recognizer.state, scale: recognizer.scale,
                               location: recognizer.location(in: view))
        }
    }

    private func configure(_ view: SKView) {
        view.isUserInteractionEnabled = isInteractive
        if canvasSize.width > 0 && canvasSize.height > 0 && scene.size != canvasSize {
            scene.size = canvasSize
        }
        if view.scene !== scene { view.presentScene(scene) }
        scene.setPresentationActive(isActive)
        view.isPaused = !isActive
        scene.isPaused = !isActive
    }
}

#elseif os(macOS)
@MainActor
private struct NativeRoomCanvas: NSViewRepresentable {
    let scene: RoomScene
    let isActive: Bool
    let isInteractive: Bool
    let canvasSize: CGSize

    func makeNSView(context: Context) -> MacRoomSKView {
        let view = MacRoomSKView()
        view.requestedFrameLimit = 30
        view.ignoresSiblingOrder = true
        view.allowsTransparency = true
        view.setAccessibilityElement(false)
        configure(view)
        return view
    }
    func updateNSView(_ view: MacRoomSKView, context: Context) { configure(view) }
    static func dismantleNSView(_ view: MacRoomSKView, coordinator: ()) {
        view.inputEnabled = false
        view.roomScene?.cancelCameraInteraction()
        view.isPaused = true
    }
    private func configure(_ view: MacRoomSKView) {
        view.inputEnabled = isActive && isInteractive
        if canvasSize.width > 0 && canvasSize.height > 0 && scene.size != canvasSize { scene.size = canvasSize }
        if view.scene !== scene { view.presentScene(scene) }
        scene.setPresentationActive(isActive)
        view.isPaused = !isActive; scene.isPaused = !isActive
    }
}

#endif

/// VoiceOver activation matches the physical cat tap without asking for another rest.
@MainActor
enum HomeRoomAccessibility68 {
    static func activate(isResting: Bool, wake: () -> Void, inspect: () -> Void) {
        if isResting { wake() } else { inspect() }
    }
}
