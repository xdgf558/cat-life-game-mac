import SwiftUI
import CatGameCore

@MainActor
struct RoomHomeView: View {
    @Bindable var store: GameStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct PendingPlayChoice {
        let choice: PlayChoice68
        let generation: UUID
        let catID: String
    }
    @State private var pendingPlayChoice: PendingPlayChoice?
    @State private var moreVisible = false
    @State private var townSelectedPlace: TownPlace = .home
    @State private var townLayer: TownLayer = .all
    @State private var catNeedPresentation = CatNeedPresentation()
    @State private var arrangementPanelHeight: CGFloat = 0
    @State private var arrangementHeaderHeight: CGFloat = 160
    @State private var normalReferenceStageSize = CGSize.zero
    @State private var normalHeaderHeight: CGFloat = 100
    @State private var saveTransferWorking = false
    #if DEBUG
    @State private var waitingForWelcomeTestRelease = false
    private var holdsWelcomeForTesting: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--welcome-hold-load")
    }
    #endif

    private var usesReducedMotion: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return reduceMotion || (arguments.contains("--ui-testing") && arguments.contains("--animation-test")
                                && arguments.contains("--reduce-motion-test"))
        #else
        return reduceMotion
        #endif
    }

    private var homeVisible: Bool { store.activeSheet == nil && !store.isShowingSettings }
    private var catSheetVisible: Binding<Bool> {
        Binding(get: { store.inspectedCatID != nil }, set: { if !$0 { store.inspectedCatID = nil } })
    }

    var body: some View {
        Group {
            if !store.hasEnteredHome {
                #if DEBUG
                WelcomeView(store: store, releaseTestLoad: waitingForWelcomeTestRelease ? {
                    waitingForWelcomeTestRelease = false
                    Task { await store.load() }
                } : nil)
                #else
                WelcomeView(store: store)
                #endif
            } else if let snapshot = store.snapshot {
                shell(snapshot)
            }
        }
        .background(RoomTheme.cream.ignoresSafeArea())
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        #if DEBUG
        .overlay(alignment: .topLeading) { AudioDiagnosticsView(store: store) }
        #endif
        .task {
            if store.snapshot == nil {
                #if DEBUG
                if holdsWelcomeForTesting { waitingForWelcomeTestRelease = true }
                else { await store.load() }
                #else
                await store.load()
                #endif
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in store.setForeground(phase == .active) }
        .onChange(of: store.saveSceneGeneration) { _, _ in
            pendingPlayChoice = nil
            townSelectedPlace = .home
            townLayer = .all
        }
        .sheet(isPresented: catSheetVisible) {
            CatCollectionView(store: store, initialCatID: store.inspectedCatID, initialGrowth: store.inspectedCatShowsGrowth)
        }
        .sheet(isPresented: Binding(get: { store.supplyPicker != nil }, set: { if !$0 { store.supplyPicker = nil } })) {
            if let kind = store.supplyPicker {
                SupplyPickerView(store: store, kind: kind)
                    .safeAreaInset(edge: .top, spacing: 0) { if store.hasSaveFailure { SaveStatusBanner(store: store) } }
                    .saveRecoveryAlert(store: store)
                    .presentationBackground(RoomTheme.cream)
                    .interactiveDismissDisabled(store.isBusy)
            }
        }
        .sheet(isPresented: $store.showsPlayChoices, onDismiss: completePlayChoice) {
            PlayChoicesSheet68(store: store) { choice in
                guard let cat = store.cat, !store.isBusy else { return }
                pendingPlayChoice = PendingPlayChoice(choice: choice, generation: store.saveSceneGeneration, catID: cat.id)
                store.showsPlayChoices = false
            }
            .presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationBackground(RoomTheme.cream)
            .interactiveDismissDisabled(store.isBusy)
            .saveRecoveryAlert(store: store)
        }
        .sheet(isPresented: Binding(get: { store.habitGuideCatID != nil }, set: { if !$0 { store.habitGuideCatID = nil } })) {
            if let cat = store.snapshot?.cats.first(where: { $0.id == store.habitGuideCatID }) {
                HabitGuidePicker68(store: store, cat: cat)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $store.isShowingPlayTogether) {
            if let session = store.presentedPlaySession {
                CatPlayTogetherView(store: store, session: session).id(session.id)
            }
        }
        .onChange(of: store.onboarding.isPresented, initial: true) { _, presented in
            if presented {
                pendingPlayChoice = nil
                moreVisible = false
                store.supplyPicker = nil
                store.showsPlayChoices = false
                store.habitGuideCatID = nil
                store.isShowingPlayTogether = false
                store.activeSheet = nil
                store.isShowingSettings = false
            }
        }
        .saveRecoveryAlert(store: store, isActive: !store.onboarding.isPresented
                          && !store.isShowingPlayTogether && !store.showsPlayChoices && store.habitGuideCatID == nil
                          && store.inspectedCatID == nil && store.activeSheet != .town
                          && store.activeSheet != .player && store.supplyPicker == nil && !store.isPresentingExchange
                          && !store.isPresentingAdoptionConfirmation && !store.isPresentingCommunityGift)
    }

    private func completePlayChoice() {
        guard let pending = pendingPlayChoice else { return }
        pendingPlayChoice = nil
        guard pending.generation == store.saveSceneGeneration, store.cat?.id == pending.catID,
              store.isHabitInteractionActive, !store.onboarding.isPresented,
              !store.isDecorating, !store.isBusy, !store.isChangingHomeFloor else { return }
        switch pending.choice {
        case .quick: store.play()
        case .together: Task { _ = await store.openPlayTogether() }
        }
    }

    private func shell(_ snapshot: GameSnapshot) -> some View {
        ZStack(alignment: .top) {
            // A keyboard on another page must not resize and cancel a paused cat action.
            GeometryReader { geometry in
                room(snapshot)
                    .frame(width: geometry.size.width, height: max(0, geometry.size.height - (store.isDecorating ? 0 : 64)))
                    .opacity(homeVisible ? 1 : 0)
                    .allowsHitTesting(homeVisible && !moreVisible)
                    .accessibilityHidden(!homeVisible || moreVisible)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            VStack(spacing: 0) {
                if store.hasSaveFailure && (!homeVisible || moreVisible) {
                    SaveStatusBanner(store: store)
                }
                ZStack {
                    Color.clear.allowsHitTesting(false).accessibilityHidden(true)
                    if !homeVisible {
                        destination
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoomTheme.cream)
                            .accessibilityHidden(moreVisible)
                    }
                    if moreVisible {
                        GameMoreMenu(store: store, close: { moreVisible = false }, select: select)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if store.hasSaveFailure && homeVisible && !moreVisible { SaveStatusBanner(store: store) }
                    else if !store.hasSaveFailure, let toast = store.toast, !toast.isEmpty, !moreVisible {
                        Text(toast).font(.system(size: 13, weight: .bold)).lineLimit(6)
                            .multilineTextAlignment(.center).accessibilityLabel(toast)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .gameCard(cornerRadius: 24).padding(.horizontal, 16)
                            .padding(.top, homeVisible ? homeNoticeTop : 4)
                            .accessibilityIdentifier(homeVisible ? "actionToast" : "sheetToast")
                            .accessibilityAddTraits(.updatesFrequently)
                            .allowsHitTesting(false)
                    }
                    else if !store.hasSaveFailure, !store.onboarding.isPresented,
                            !store.isShowingNeighbors, !store.isShowingMarket, !store.isShowingTownBoard,
                            !moreVisible, store.inspectedCatID == nil,
                            !store.isPresentingAdoptionConfirmation, !store.isDecorating,
                            (homeVisible || store.activeSheet == .upgrade),
                            let offer = store.adoptionReminders.pendingOffer {
                        AdoptionAvailableBanner(store: store, offer: offer)
                            .padding(.horizontal, 16).padding(.top, homeVisible ? homeNoticeTop : 4)
                    }
                }
                if store.onboarding.isActive && !homeVisible && !moreVisible && !store.isDecorating {
                    GuideResumeBar(store: store)
                        .padding(.horizontal, 14).padding(.vertical, 6).background(RoomTheme.cream)
                }
                if !store.isDecorating {
                    GameBottomBar(store: store, moreVisible: $moreVisible, select: select)
                        .disabled(saveTransferWorking || store.saveTransferInProgress)
                        .frame(height: 64)
                        .background(RoomTheme.paper.ignoresSafeArea(edges: .bottom))
                }
            }
        }
        .overlayPreferenceValue(OnboardingTargetKey.self) { targets in
            if store.onboarding.isPresented {
                GeometryReader { geometry in
                    OnboardingSpotlight(store: store,
                        target: store.onboarding.step.flatMap { targets[$0] }.map { geometry[$0] },
                        size: geometry.size, onExplore: { step in
                            moreVisible = false
                            store.exploreOnboarding(step)
                        })
                }
            }
        }
        .onChange(of: catNeedPresentation.headerFrame?.height) { _, height in
            guard !store.isDecorating, let height, height.isFinite, height > 0 else { return }
            normalHeaderHeight = height
        }
        .onChange(of: store.isDecorating) { _, editing in
            moreVisible = false
            if !editing { store.activeSheet = nil }
        }
        .overlay {
            if let celebration = store.homeUpgradeCelebration {
                HomeUpgradeCelebrationView(celebration: celebration) {
                    store.homeUpgradeCelebration = nil
                    store.activeSheet = nil
                    store.isShowingSettings = false
                }
                .id(celebration.id)
            }
        }
    }

    @ViewBuilder private var destination: some View {
        if store.isShowingSettings {
            SettingsView(store: store, onSaveTransferWorkingChange: { saveTransferWorking = $0 })
        }
        else {
            switch store.activeSheet {
            case .work: WorkDestinationView(store: store)
            case .player: PlayerProfileView(store: store)
            case .tasks: TaskDestinationView(store: store)
            case .town: TownView(store: store, selectedPlace: $townSelectedPlace, layer: $townLayer)
            case .hospital: HospitalView(store: store, initialCatID: store.hospitalCatID)
            case .shop, .inventory, .upgrade:
                NavigationStack {
                    Group {
                        switch store.activeSheet {
                        case .shop: ShopView(store: store)
                        case .inventory: InventoryView(store: store)
                        case .upgrade: HomeUpgradeView(store: store)
                        default: EmptyView()
                        }
                    }
                    .toolbar {
                        if store.isDecorating {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { store.activeSheet = nil } label: {
                                    Label(GameStrings.text("layout.edit"), systemImage: "chevron.left")
                                }.accessibilityIdentifier("layoutReturnButton")
                            }
                        }
                    }
                }
                .id(store.activeSheet)
                .tint(RoomTheme.darkMint)
            case nil: EmptyView()
            }
        }
    }

    private func select(_ destination: HomeSheet?) {
        guard !saveTransferWorking, !store.saveTransferInProgress else { return }
        moreVisible = false
        store.isShowingSettings = false
        if destination == .town { store.inspectedCatID = nil }
        store.activeSheet = destination
    }

    private var homeNoticeTop: CGFloat {
        guard let stage = catNeedPresentation.stageFrame, let header = catNeedPresentation.headerFrame else { return 116 }
        return max(0, stage.minY - header.minY + 10)
    }

    private func room(_ snapshot: GameSnapshot) -> some View {
        GeometryReader { geometry in
            // Editing removes navigation space, but must not change the room's physical reference viewport.
            let normalCanvas = CGSize(width: geometry.size.width, height: max(0, geometry.size.height - (store.isDecorating ? 64 : 0)))
            let referenceStage = HomeRoomLayout.stageFrame(in: normalCanvas, headerHeight: normalHeaderHeight, editing: false)
            let referenceSize = store.isDecorating && normalReferenceStageSize.width > 0 && normalReferenceStageSize.height > 0
                ? normalReferenceStageSize : referenceStage.size
            let stage = store.isDecorating ? CGRect(origin: .zero, size: geometry.size) : referenceStage
            let careHeight = HomeRoomLayout.careHeight(in: geometry.size)
            ZStack(alignment: .topLeading) {
                RoomSceneHost(store: store,
                              isActive: scenePhase == .active && homeVisible && !moreVisible
                                  && !store.isShowingPlayTogether && !store.showsPlayChoices && store.habitGuideCatID == nil && !store.showSaveError
                                  && store.homeUpgradeCelebration == nil && store.inspectedCatID == nil && store.supplyPicker == nil && !store.onboarding.isPresented,
                              reducedMotion: usesReducedMotion, catNeedPresentation: catNeedPresentation,
                              referenceViewportSize: referenceSize,
                              arrangementBottomInset: store.isDecorating ? arrangementPanelHeight : 0,
                              arrangementTopInset: store.isDecorating ? arrangementHeaderHeight : 0)
                    .id("\(store.saveSceneGeneration)-\(store.visibleHomeFloor.rawValue)")
                    .frame(width: stage.width, height: stage.height)
                    .background {
                        RoundedRectangle(cornerRadius: store.isDecorating ? 0 : 30)
                            .fill(RoomTheme.rewardPaper)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: store.isDecorating ? 0 : 30))
                    .overlay {
                        if !store.isDecorating { RoundedRectangle(cornerRadius: 30).strokeBorder(.white, lineWidth: 3).allowsHitTesting(false) }
                    }
                    .background {
                        GeometryReader { bounds in
                            Color.clear.onAppear { catNeedPresentation.stageFrame = bounds.frame(in: .global) }
                                .onChange(of: bounds.frame(in: .global)) { _, frame in catNeedPresentation.stageFrame = frame }
                        }.allowsHitTesting(false)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("roomStage63")
                    .position(x: stage.midX, y: stage.midY)
                if store.isDecorating {
                    VStack(spacing: 6) {
                        ArrangementHeader68(store: store)
                        ArrangementStageTools68(store: store).padding(.horizontal, 14)
                    }
                    .frame(width: geometry.size.width)
                    .background { GeometryReader { header in
                        Color.clear.onAppear { updateArrangementHeaderHeight(header.size.height) }
                            .onChange(of: header.size.height) { _, height in updateArrangementHeaderHeight(height) }
                    } }
                    VStack { Spacer(minLength: 0); RoomArrangementPanel(store: store) }
                        .onPreferenceChange(ArrangementPanelHeightKey.self) { height in
                            if height.isFinite, height >= 0 { arrangementPanelHeight = height }
                        }
                } else {
                    RoomHomeHUD(store: store, catNeedPresentation: catNeedPresentation)
                        .frame(width: geometry.size.width)
                    RoomCareBar63(store: store, presentation: catNeedPresentation, reducedMotion: usesReducedMotion)
                        .frame(width: max(1, geometry.size.width - 20), height: careHeight)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 8 - careHeight / 2)
                }
            }
            .background(RoomTheme.paleMint.opacity(0.28))
            .onChange(of: referenceStage.size, initial: true) { _, size in
                guard !store.isDecorating, size.width.isFinite, size.height.isFinite,
                      size.width > 0, size.height > 0 else { return }
                normalReferenceStageSize = size
            }
            .onChange(of: store.isDecorating) { _, editing in
                guard !editing, referenceStage.width > 0, referenceStage.height > 0 else { return }
                normalReferenceStageSize = referenceStage.size
            }
            .onDisappear { catNeedPresentation.stageFrame = nil }
        }
    }

    private func updateArrangementHeaderHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        arrangementHeaderHeight = height
    }
}

#if DEBUG
@MainActor
struct AudioDiagnosticsView: View {
    let store: GameStore
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--audio-test") {
            Text("Audio diagnostics").font(.system(size: 1)).frame(width: 1, height: 1)
                .accessibilityIdentifier("audioDiagnostics").accessibilityValue(store.audioDiagnostics)
                .allowsHitTesting(false)
        }
    }
}
#endif
