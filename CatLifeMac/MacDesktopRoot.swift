#if os(macOS)
import SwiftUI
import AppKit
import CatGameCore

@MainActor
struct MacDesktopRoot: View {
    let delegate: MacApplicationDelegate
    @State private var store = GameStore()
    @State private var preferences = Self.makePreferences()
    @State private var page = MacPage.home
    @State private var titleVisible = true
    @State private var showsHelp = false
    @State private var auxiliary: MacAuxiliary?
    @State private var scene: RoomScene? = nil
    @State private var windowController: MacWindowController?
    @State private var keyboard: MacKeyboardRouter?
    @State private var hadSave = false
    @State private var quitting = false
    @State private var creatingHome = false
    @State private var appIsActive = NSApp.isActive
    @State private var workNotifications = MacWorkNotificationTracker()
    @State private var catUrgencies = MacCatUrgencyTracker()
    @State private var restRequest: String?
    @State private var pendingPlayChoice: (choice: PlayChoice68, generation: UUID, catID: String)?
    @State private var neighborID: String?
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var appForeground: Bool { appIsActive && phase == .active && !quitting }
    private var active: Bool { appForeground && auxiliary == nil && !showsHelp && !store.showsPlayChoices && !store.isShowingPlayTogether && store.supplyPicker == nil }
    var body: some View { observedContent }
    private var baseContent: some View {
        ZStack {
            RoomTheme.cream.ignoresSafeArea()
            if titleVisible {
                MacTitleView(store: store, scene: scene, preferences: preferences, hadSave: hadSave, isActive: active,
                             lastSeenAt: store.hasEnteredHome ? store.snapshot?.meta.lastSyncAt : store.macPreviousSaveAt,
                             onContinue: enterHome, onNew: newGame, onLoad: { auxiliary = .saves },
                             onSettings: { titleVisible = false; page = .settings }, onQuit: { NSApp.terminate(nil) })
                    .disabled(creatingHome)
            } else {
                HStack(spacing: 0) {
                    MacNavigationRail(page: page, preferences: preferences, isWorking: store.snapshot?.player.activeWork != nil, select: select, help: { showsHelp = true })
                    VStack(spacing: 0) {
                        MacTopBar(store: store, page: page, onSaves: { auxiliary = .saves }, onPlayer: { store.activeSheet = .player })
                        pageContent.padding(16)
                    }
                }
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .environment(\.gameReduceMotionOverride, systemReduceMotion || preferences.reduceMotion)
        .transaction { if preferences.reduceMotion { $0.disablesAnimations = true } }
        .preferredColorScheme(.light)
    }
    private var scaledContent: some View {
        GeometryReader { geometry in
            let layout = MacInterfaceLayout(viewport: geometry.size, scale: preferences.interfaceScale)
            ScrollView([.horizontal, .vertical]) {
                baseContent.frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                    .scaleEffect(preferences.interfaceScale, anchor: .topLeading)
                    .frame(width: layout.displayedSize.width, height: layout.displayedSize.height, alignment: .topLeading)
            }
            .accessibilityIdentifier("macDesktopViewport")
        }
    }
    private var statusContent: some View {
        scaledContent.background { if let windowController { MacWindowAttachment(controller: windowController) } }
        .overlay(alignment: .top) {
            if store.hasSaveFailure && !titleVisible {
                Button { store.retrySaving() } label: {
                    Label(GameStrings.text("mac.save.retry"), systemImage: "exclamationmark.triangle.fill").padding(10).background(RoomTheme.paleCoral, in: Capsule())
                }.buttonStyle(.plain).padding(.top, 6)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast).font(.system(size: 14, weight: .bold, design: .rounded)).padding(14).background(RoomTheme.ink, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white).padding(24).allowsHitTesting(false)
            }
        }
    }
    private var presentedContent: some View {
        statusContent.sheet(item: $auxiliary, onDismiss: clearAuxiliary) { item in auxiliaryView(item).frame(minWidth: 600, idealWidth: 780, minHeight: 600, idealHeight: 760) }
        .sheet(isPresented: $showsHelp) { MacShortcutsHelpView(preferences: preferences).frame(width: 800, height: 660) }
        .sheet(isPresented: $store.showsPlayChoices, onDismiss: completePlayChoice) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button(GameStrings.text("common.cancel"), role: .cancel) {
                    pendingPlayChoice = nil; store.showsPlayChoices = false
                }.keyboardShortcut(.cancelAction).accessibilityIdentifier("macPlayChoiceCancel") }.padding(12)
                PlayChoicesSheet68(store: store) { choice in
                    guard let cat = store.cat, !store.isBusy else { return }
                    pendingPlayChoice = (choice, store.saveSceneGeneration, cat.id)
                    store.showsPlayChoices = false
                }
            }.frame(width: 620, height: 530).background(RoomTheme.cream)
                .interactiveDismissDisabled(store.isBusy)
                .saveRecoveryAlert(store: store)
        }
        .sheet(isPresented: $store.isShowingPlayTogether) {
            if let session = store.presentedPlaySession { CatPlayTogetherView(store: store, session: session).id(session.id).frame(width: 1000, height: 720) }
        }
        .sheet(isPresented: Binding(get: { store.supplyPicker != nil }, set: { if !$0 { store.supplyPicker = nil } })) {
            if let kind = store.supplyPicker { SupplyPickerView(store: store, kind: kind).frame(width: 600, height: 580).saveRecoveryAlert(store: store).interactiveDismissDisabled(store.isBusy) }
        }
        .confirmationDialog(GameStrings.text("mac.rest.title"), isPresented: Binding(get: { restRequest != nil }, set: { if !$0 { restRequest = nil } })) {
            Button(GameStrings.text("mac.rest.confirm")) { if let id = restRequest { scene?.confirmFurnitureRest68(id) }; restRequest = nil }
            Button(GameStrings.text("common.cancel"), role: .cancel) { restRequest = nil }
        }
        .saveRecoveryAlert(store: store, isActive: auxiliary == nil && !store.showsPlayChoices && !store.isShowingPlayTogether && store.supplyPicker == nil && !store.isPresentingHabitGuide && !store.isPresentingHabitMemory)
    }
    private var observedContent: some View {
        presentedContent.task { await start() }
        .onChange(of: phase) { _, _ in store.setForeground(appForeground) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appIsActive = true; store.setForeground(appForeground)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appIsActive = false; store.setForeground(false)
        }
        .onChange(of: store.activeSheet) { _, value in route(value) }
        .onChange(of: store.isShowingNeighbors) { _, shown in if shown { auxiliary = neighborID == nil ? .neighbors : .neighborDetail } }
        .onChange(of: store.isShowingMarket) { _, shown in if shown { auxiliary = .market } }
        .onChange(of: store.isShowingTownBoard) { _, shown in if shown { auxiliary = .board } }
        .onChange(of: store.isShowingSettings) { _, shown in if shown { select(.settings); store.isShowingSettings = false } }
        .onChange(of: store.inspectedCatID) { _, id in if id != nil { auxiliary = .catProfile } }
        .onChange(of: store.saveSceneGeneration) { _, _ in hadSave = true; scene = canCreateRoomScene ? makeScene() : nil; auxiliary = nil }
        .onChange(of: store.visibleHomeFloor) { _, _ in scene = canCreateRoomScene ? makeScene() : nil }
        .onChange(of: store.isLoading) { _, loading in
            if loading { scene = nil }
            else if canCreateRoomScene, scene == nil { scene = makeScene() }
        }
        .onChange(of: store.loadFailed) { _, failed in
            if failed { scene = nil }
            else if canCreateRoomScene, scene == nil { scene = makeScene() }
        }
        .onChange(of: preferences.alwaysOnTop) { _, _ in windowController?.apply() }
        .onChange(of: preferences.windowMode) { _, _ in windowController?.apply() }
        .onChange(of: workNotificationState) { _, state in
            guard let completed = workNotifications.observe(state), !appForeground, !quitting else { return }
            Task { await MacNotifications.post(title: GameStrings.text("mac.work.finished"), body: GameStrings.text("mac.work.return"), id: completed, preferences: preferences,
                isCurrent: { state.generation == store.saveSceneGeneration && !quitting }) }
        }
        .onChange(of: catUrgencyState) { _, state in
            let notices = catUrgencies.observe(state, isInBackground: !appForeground && !quitting,
                                               notificationsEnabled: preferences.notificationsEnabled)
            for notice in notices {
                guard let cat = store.snapshot?.cats.first(where: { $0.id == notice.catID }) else { continue }
                let name = GameStrings.catName(cat)
                Task { await MacNotifications.post(title: GameStrings.text(notice.titleKey),
                    body: GameStrings.format(notice.bodyKey, name), id: notice.identifier(generation: state.generation), preferences: preferences,
                    isCurrent: { state.generation == store.saveSceneGeneration && !quitting }) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOpenSettings69)) { _ in select(.settings) }
    }
    private var catUrgencyState: MacCatUrgencyState {
        MacCatUrgencyState(snapshot: store.snapshot, generation: store.saveSceneGeneration,
                           isRestoring: store.isLoading || store.saveTransferInProgress)
    }
    private var workNotificationState: MacWorkNotificationState {
        MacWorkNotificationState(generation: store.saveSceneGeneration,
            activeWorkID: store.snapshot?.player.activeWork?.id,
            completedWorkID: store.snapshot?.player.lastWorkResult?.id,
            isRestoring: store.isLoading || store.saveTransferInProgress)
    }
    @ViewBuilder private var pageContent: some View {
        if store.isDecorating {
            if let scene {
                MacBuildView(store: store, scene: scene, preferences: preferences, isActive: active, onDone: {}, onRestRequest: { restRequest = $0 }, onContextAction: context, onFixedStructure: fixedStructure)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        } else {
            switch page {
            case .home:
                if let scene {
                    MacHomeView(store: store, scene: scene, preferences: preferences, isActive: active,
                        onTasks: { store.activeSheet = .tasks }, onInventory: { store.activeSheet = .inventory },
                        onCats: { select(.cats) }, onRest: { restRequest = $0 }, onContext: context, onFixedStructure: fixedStructure)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            case .work: MacWorkView(store: store, onHome: { select(.home) }, preferences: preferences)
            case .shop: MacShopView(store: store, onHome: { page = .home }, preferences: preferences)
            case .cats: MacCatsView(store: store, onHome: { select(.home) }, preferences: preferences)
            case .town: MacTownView(store: store, onEnter: enterPlace, preferences: preferences, onNeighbor: openNeighbor)
            case .settings:
                if let windowController { MacSettingsView(store: store, preferences: preferences, windowController: windowController, onTitle: { titleVisible = true }) }
            }
        }
    }
    private static func makePreferences() -> MacPreferences {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let suite = "com.stationcat.catlife.mac.ui-testing"
            let defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("--reset-ui-test-save") { defaults.removePersistentDomain(forName: suite) }
            return MacPreferences(defaults: defaults)
        }
        #endif
        return MacPreferences()
    }
    private func start() async {
        #if DEBUG
        if NativeSaveLocation.isAppUnitTesting { return }
        #endif
        guard delegate.prepareSaveAccess(directory: store.saveDirectory) else { return }
        let controller = MacWindowController(preferences: preferences)
        controller.shouldClose = { NSApp.terminate(nil); return false }
        windowController = controller
        delegate.requestQuit = requestQuit
        let router = MacKeyboardRouter(preferences: preferences, handler: handle)
        keyboard = router; router.start()
        hadSave = store.hasSavedProgress
        await store.load()
        if canCreateRoomScene { scene = makeScene() }
        appIsActive = NSApp.isActive
        workNotifications.reset(workNotificationState); catUrgencies.reset(catUrgencyState); store.setForeground(appForeground)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--skip-welcome") { enterHome() }
        #endif
    }
    private var canCreateRoomScene: Bool { store.snapshot != nil && !store.isLoading && !store.loadFailed }
    private func makeScene() -> RoomScene { RoomScene(size: CGSize(width: 900, height: 720)) }
    private func enterHome() { guard store.snapshot != nil, !store.isLoading else { return }; scene?.prepareDesktopEntry(); store.enterHome(); hadSave = true; store.onboarding.isPresented = false; titleVisible = false; page = .home }
    private func newGame() {
        guard !store.isBusy, !store.isLoading, !creatingHome else { return }
        if !hadSave { enterHome(); return }
        guard confirm("mac.new.title", body: "mac.new.body") else { return }
        creatingHome = true
        Task {
            defer { creatingHome = false }
            do {
                let now = Date()
                let fresh = try await MacRoomSaveRepair.prepare(.fresh(now: now), now: now, isNewHome: true)
                guard !quitting else { return }
                let data = try NativeSaveTransfer.encode(snapshot: fresh, exportedAt: now)
                let archive = try NativeSaveTransfer.decode(data)
                try await store.importSaveArchive(archive); hadSave = true; enterHome()
            } catch { store.showNotice(GameStrings.text("saveTransfer.writeFailed")) }
        }
    }
    private func completePlayChoice() {
        guard let pending = pendingPlayChoice else { return }
        pendingPlayChoice = nil
        guard pending.generation == store.saveSceneGeneration, pending.catID == store.cat?.id,
              store.isHabitInteractionActive, !store.isBusy, !store.isDecorating else { return }
        if pending.choice == .quick { store.play() }
        else {
            Task { @MainActor in
                // Resume the underlying native scene before checking its room-idle gate.
                await Task.yield()
                guard pending.generation == store.saveSceneGeneration, pending.catID == store.cat?.id else { return }
                _ = await store.openPlayTogether()
            }
        }
    }
    private func select(_ next: MacPage) {
        guard !store.isSavingLayout, !store.saveTransferInProgress else { return }
        if store.isDecorating {
            guard !store.hasUnsavedLayoutChanges || confirm("mac.draft.title", body: "mac.draft.body") else { return }
            store.cancelDecorating()
        }
        titleVisible = false; page = next; store.playNavigationSound()
        store.activeSheet = next == .shop ? .shop : next == .town ? .town : next == .work ? .work : nil
    }
    private func route(_ sheet: HomeSheet?) {
        guard let sheet else { if auxiliary?.usesActiveSheet == true { auxiliary = nil }; return }
        switch sheet {
        case .work: page = .work; auxiliary = nil
        case .shop: page = .shop; auxiliary = nil
        case .town: page = .town; auxiliary = nil
        case .inventory: auxiliary = .inventory
        case .tasks: auxiliary = .tasks
        case .player: auxiliary = .player
        case .upgrade: auxiliary = .upgrade
        case .hospital: auxiliary = .hospital
        }
    }
    private func openNeighbor(_ id: String) {
        neighborID = id; store.activeSheet = .town; store.isShowingNeighbors = true; auxiliary = .neighborDetail
    }
    private func enterPlace(_ place: TownPlace) {
        switch place {
        case .home: select(.home)
        case .work: select(.work)
        case .shop: select(.shop)
        case .adoption: select(.cats)
        case .hospital: store.openHospital()
        case .street: store.openNeighbors()
        case .market: store.openExchangeMarket()
        case .plaza, .board: store.openTownBoard()
        default: break
        }
    }
    private func fixedStructure(_ structure: MacRoomStructure) {
        guard !store.isBusy, !store.isSavingLayout, !store.saveTransferInProgress else { return }
        if store.isDecorating {
            store.showNotice(GameStrings.text(structure == .door ? "mac.room.doorFixed" : "mac.room.stairsFixed"))
            return
        }
        switch structure {
        case .door: select(.town)
        case .stairs:
            guard (store.snapshot?.home.roomLevel ?? 1) >= 6 else {
                store.showNotice(GameStrings.text("mac.room.stairsLocked"))
                store.activeSheet = .upgrade
                return
            }
            Task { _ = await store.changeHomeFloor(to: store.visibleHomeFloor == .ground ? .upper : .ground) }
        }
    }
    private func context(_ action: MacRoomContextAction) {
        switch action {
        case .companion(let id): Task { _ = await store.selectCompanion(catID: id) }
        case .profile(let id): store.inspectCat(catID: id)
        case .closeUp(let id): Task {
            let generation = store.saveSceneGeneration
            if store.cat?.id != id, !(await store.selectCompanion(catID: id)) { return }
            guard store.saveSceneGeneration == generation, store.cat?.id == id else { return }
            scene?.showCatCloseUp()
        }
        case .play(let id): Task {
            let generation = store.saveSceneGeneration
            if store.cat?.id != id, !(await store.selectCompanion(catID: id)) { return }
            guard store.saveSceneGeneration == generation, store.cat?.id == id else { return }
            store.presentPlayChoices()
        }
        case .hospital(let id): store.openHospital(catID: id)
        case .rest(let id): restRequest = id
        case .decorate(let id): store.beginDecorating(); if let id { store.selectFurniture(id: id) }
        case .store(let id): store.beginDecorating(); store.selectFurniture(id: id); store.storeSelectedFurniture()
        }
    }
    private func handle(_ command: MacCommand) -> Bool {
        guard !creatingHome else { return true }
        if command == .settings { select(.settings); return true }
        if command == .fullscreen { windowController?.toggleFullscreen(); return true }
        if command == .help { showsHelp.toggle(); return true }
        if command == .escape {
            if store.showsPlayChoices { pendingPlayChoice = nil; store.showsPlayChoices = false }
            else if store.supplyPicker != nil { if !store.isBusy { store.supplyPicker = nil } }
            else if auxiliary != nil { if !store.isBusy { auxiliary = nil } } else if showsHelp { showsHelp = false }
            else if store.isDecorating { select(.home) } else if !titleVisible { titleVisible = true }
            return true
        }
        if titleVisible, command == .confirm, auxiliary == nil, !store.isLoading, !store.loadFailed {
            NotificationCenter.default.post(name: .macTitleConfirm, object: nil)
            return true
        }
        guard !titleVisible, auxiliary == nil, !showsHelp, !store.isShowingPlayTogether, !store.showsPlayChoices, store.supplyPicker == nil else { return false }
        let scope: MacShortcutScope = store.isDecorating ? .arrangement : page == .home ? .home : page == .town ? .town : page == .shop ? .shop : .list
        guard command.scope.overlaps(scope) else { return false }
        switch command {
        case .home: select(.home)
        case .work: select(.work)
        case .shop: select(.shop)
        case .town: select(.town)
        case .cats: select(.cats)
        default:
            if store.isDecorating {
                switch command {
                case .rotateLeft: store.rotateSelectedFurniture68(clockwise: false)
                case .rotateRight: store.rotateSelectedFurniture68(clockwise: true)
                case .nudgeLeft: store.nudgeSelectedFurniture68(dx: -1, dy: 0)
                case .nudgeRight: store.nudgeSelectedFurniture68(dx: 1, dy: 0)
                case .nudgeUp: store.nudgeSelectedFurniture68(dx: 0, dy: -1)
                case .nudgeDown: store.nudgeSelectedFurniture68(dx: 0, dy: 1)
                case .grid: store.arrangement68.snapEnabled.toggle()
                case .putAway: store.storeSelectedFurniture()
                case .confirm:
                    if let id = store.selectedStoredFurnitureID { store.placeFurniture(id: id) }
                    else { store.confirmArrangementSelection68() }
                case .undo: store.undoArrangement68()
                case .redo: store.redoArrangement68()
                case .save: store.finishDecorating()
                case .search: NotificationCenter.default.post(name: Notification.Name("MacSearchRequested"), object: nil)
                case .viewLeft: scene?.turnRoomView(by: -1)
                case .viewRight: scene?.turnRoomView(by: 1)
                case .focusCat: scene?.showWholeRoom()
                case .decorate: select(.home)
                default: return false
                }
            } else if page == .home {
                switch command {
                case .feed: store.feed()
                case .clean: store.clean()
                case .play: store.presentPlayChoices()
                case .nextCat: if let cats = store.snapshot?.cats, let index = cats.firstIndex(where: { $0.id == store.cat?.id }), !cats.isEmpty { Task { _ = await store.selectCompanion(catID: cats[(index + 1) % cats.count].id) } }
                case .catProfile: store.inspectCat()
                case .decorate: store.beginDecorating()
                case .focusCat:
                    if scene?.isWholeRoomView == true { scene?.showCatCloseUp() }
                    else { scene?.showWholeRoom() }
                case .viewLeft: scene?.turnRoomView(by: -1)
                case .viewRight: scene?.turnRoomView(by: 1)
                default: return false
                }
            } else if page == .town && command == .returnHome { select(.home) }
            else if [.work, .shop, .cats, .town].contains(page) {
                NotificationCenter.default.post(name: Notification.Name("MacContentCommand"), object: command.rawValue)
            } else { return false }
        }
        return true
    }
    private var hasPendingQuitWrites: Bool { store.isBusy || store.isSavingLayout || store.saveTransferInProgress }
    private func requestQuit() -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateCancel }
        if store.isDecorating && !store.isSavingLayout {
            guard !store.hasUnsavedLayoutChanges || confirm("mac.draft.title", body: "mac.quit.draft") else { return .terminateCancel }
            store.cancelDecorating()
        }
        quitting = true
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: MacQuitWaitPolicy.budget)
        let settings = MacSettingsFlushRequest()
        NotificationCenter.default.post(name: .macFlushSettings69, object: settings)
        let completion = MacQuitSettingsCompletion(finished: settings.save == nil)
        // This observer cannot reply to AppKit, even if the save finishes after the deadline.
        let settingsObserver = settings.save.map { save in
            Task { @MainActor in await save.value; completion.finished = true }
        }
        store.setForeground(false)
        Task { @MainActor in
            defer { settingsObserver?.cancel() }
            var outcome = MacQuitWaitPolicy.outcome(settingsFinished: completion.finished, storeBusy: hasPendingQuitWrites,
                                                    elapsed: started.duration(to: clock.now))
            while outcome == .waiting {
                try? await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(50))))
                outcome = MacQuitWaitPolicy.outcome(settingsFinished: completion.finished, storeBusy: hasPendingQuitWrites,
                                                    elapsed: started.duration(to: clock.now))
            }
            let allowed = outcome == .timedOut ? confirmQuitAfterTimeout()
                : !store.hasSaveFailure || confirm("mac.quit.failed", body: "mac.quit.failedBody")
            quitting = false; NSApp.reply(toApplicationShouldTerminate: allowed)
            if !allowed { appIsActive = NSApp.isActive; store.setForeground(appForeground) }
        }
        return .terminateLater
    }
    private func confirmQuitAfterTimeout() -> Bool {
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = GameStrings.text("mac.quit.timeout")
        alert.informativeText = GameStrings.text("mac.quit.timeoutBody")
        alert.addButton(withTitle: GameStrings.text("mac.quit.cancelExit"))
        alert.addButton(withTitle: GameStrings.text("mac.quit.exitAnyway"))
        return alert.runModal() == .alertSecondButtonReturn
    }
    private func confirm(_ title: String, body: String) -> Bool {
        let alert = NSAlert(); alert.messageText = GameStrings.text(title); alert.informativeText = GameStrings.text(body)
        alert.addButton(withTitle: GameStrings.text("common.done")); alert.addButton(withTitle: GameStrings.text("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
    @ViewBuilder private func auxiliaryView(_ item: MacAuxiliary) -> some View {
        VStack(spacing: 0) {
            HStack { Text(GameStrings.text(item.key)).font(.title3.bold()); Spacer(); Button(GameStrings.text("common.done")) { auxiliary = nil }.keyboardShortcut(.cancelAction).disabled(store.isBusy || store.saveTransferInProgress) }.padding(16)
            Divider()
            Group {
                switch item {
                case .tasks: TaskDestinationView(store: store)
                case .inventory: InventoryView(store: store)
                case .upgrade: HomeUpgradeView(store: store)
                case .hospital: HospitalView(store: store, initialCatID: store.hospitalCatID)
                case .neighborDetail: NavigationStack { if let neighborID { NeighborDetailView(store: store, neighborID: neighborID) } }
                case .neighbors: CommunityView(store: store, onClose: { auxiliary = nil })
                case .market: NavigationStack { ExchangeMarketView(store: store, onClose: { auxiliary = nil }) }
                case .board: TownNoticeBoardView(store: store, onClose: { auxiliary = nil })
                case .saves: SaveManagementView(store: store, recoveryOnly: store.loadFailed, onRecovered: { auxiliary = nil }, onRetryLoad: { Task { await store.load() } })
                case .player: PlayerProfileView(store: store)
                case .catProfile: CatCollectionView(store: store, initialCatID: store.inspectedCatID)
                }
            }
        }.background(RoomTheme.cream).interactiveDismissDisabled(store.isBusy || store.saveTransferInProgress)
            .saveRecoveryAlert(store: store, isActive: ![.player, .catProfile].contains(item)
                && !store.isPresentingCommunityGift && !store.isPresentingExchange && !store.isInspectingHealth)
    }
    private func clearAuxiliary() {
        neighborID = nil; store.activeSheet = page == .town ? .town : page == .shop ? .shop : page == .work ? .work : nil; store.inspectedCatID = nil
        store.isShowingNeighbors = false; store.isShowingMarket = false; store.isShowingTownBoard = false
    }
}
@MainActor
private final class MacQuitSettingsCompletion {
    var finished: Bool
    init(finished: Bool) { self.finished = finished }
}

enum MacQuitWaitPolicy {
    enum Outcome: Equatable { case waiting, ready, timedOut }
    static let budget: Duration = .seconds(5)
    static func outcome(settingsFinished: Bool, storeBusy: Bool, elapsed: Duration) -> Outcome {
        if settingsFinished && !storeBusy { return .ready }
        return elapsed >= budget ? .timedOut : .waiting
    }
}

private enum MacAuxiliary: String, Identifiable {
    case tasks, inventory, upgrade, hospital, neighbors, neighborDetail, market, board, saves, player, catProfile
    var id: String { rawValue }
    var usesActiveSheet: Bool { [.tasks, .inventory, .upgrade, .hospital, .player].contains(self) }
    var key: String { switch self {
        case .tasks: "tasks.title"; case .inventory: "inventory.title"; case .upgrade: "homeUpgrade.title"; case .hospital: "hospital.title"
        case .neighbors, .neighborDetail: "community.title"; case .market: "market.title"; case .board: "townEvents.title"; case .saves: "saveTransfer.title"
        case .player: "player.title"; case .catProfile: "town.title"
    } }
}
#endif
