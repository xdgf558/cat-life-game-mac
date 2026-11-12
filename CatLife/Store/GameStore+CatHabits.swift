import Foundation
import CatGameCore

struct PendingCatPlayEnd {
    let id = UUID()
    let catID: String
    let sessionID: String
    let occurredAt: Date
}

extension GameStore {
    var presentedPlaySession: CatPlaySession? {
        if let active = snapshot?.catPlay.activeSession, active.id == playTogetherSessionID { return active }
        return snapshot?.catPlay.lastResult.flatMap { $0.id == playTogetherSessionID ? $0.session : nil }
    }
    var habitCornerOffer: CatRestObservationReceipt? {
        guard let cat, let receipt = cat.habits.lastRestObservation,
              cat.habits.dismissedRestOfferID != receipt.id, cat.habits.cornerFurnitureID != receipt.furnitureID,
              receipt.location.floor == visibleHomeFloor,
              snapshot?.home.furniture.contains(where: {
                  $0.itemID == receipt.furnitureID && $0.floor == receipt.location.floor && $0.position == receipt.location.position
              }) == true else { return nil }
        return receipt
    }
    var canShowPinnedHabitHint: Bool {
        guard let cat, cat.habits.pinnedMemory != nil, adoptionReminders.pendingOffer == nil else { return false }
        return CatNeed.current(in: self) == nil && cat.energy >= 30 && cat.activeRest == nil
            && roomFloorTravelReady && !isChangingHomeFloor
    }

    @discardableResult
    func pinHabitMemory(catID: String, memory: CatMemoryKind?) async -> Bool {
        await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
            CatHabitEngine.pinMemory(&$0, catID: catID, memory: memory, now: $1)
        }
    }

    @discardableResult
    func setPinnedHabitHintCollapsed(catID: String, collapsed: Bool) async -> Bool {
        await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
            CatHabitEngine.setPinnedHintCollapsed(&$0, catID: catID, collapsed: collapsed, now: $1)
        }
    }

    var canOpenPlayTogether: Bool {
        isHabitInteractionActive && pendingCatPlayEnd == nil && !isShowingPlayTogether
            && !isBusy && !isDecorating && !isInspectingHealth && !isChangingHomeFloor && !saveTransferInProgress
            && (roomFloorTravelReady || (restingFurnitureID != nil && cat?.activeRest != nil))
    }

    func presentPlayChoices() {
        guard !isDecorating, !isBusy else { return }
        showsPlayChoices = true
    }

    @discardableResult
    func openPlayTogether() async -> Bool {
        guard canOpenPlayTogether, let cat else { showNotice(GameStrings.text("catHabits.error.busy")); return false }
        let tutorial = snapshot.map { !$0.catPlay.tutorialCompleted && ($0.catPlay.tutorialCatID == nil || $0.catPlay.tutorialCatID == cat.id) } ?? false
        if !tutorial && (snapshot?.inventory.toys ?? 0) == 0 {
            showNotice(GameStrings.text("care.needToy"))
            inspectedCatID = nil; isShowingSettings = false; shopCategory = .supplies; activeSheet = .shop
            return false
        }
        let generation = saveSceneGeneration
        let saved = await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
            CatHabitEngine.beginPlay(&$0, catID: cat.id, now: $1)
        }
        guard saved, generation == saveSceneGeneration, let session = snapshot?.catPlay.activeSession,
              session.catID == cat.id else { return false }
        guard isHabitInteractionActive else {
            requestPlayEnd(catID: cat.id, sessionID: session.id, generation: generation)
            return false
        }
        playTogetherSessionID = session.id
        isShowingPlayTogether = true
        recordHabitStudy("playOpened", catID: cat.id, sessionID: session.id)
        if session.isTutorial { recordHabitStudy("tutorialEntered", catID: cat.id, sessionID: session.id) }
        return true
    }

    @discardableResult
    func submitPlayInput(catID: String, sessionID: String, report: CatPlayInputReport) async -> Bool {
        guard isHabitInteractionActive, pendingCatPlayEnd == nil,
              snapshot?.catPlay.activeSession?.id == sessionID else { return false }
        let saved = await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
            CatHabitEngine.recordPlayInput(&$0, catID: catID, sessionID: sessionID, report: report, now: $1)
        }
        if saved {
            recordHabitStudy("playInput", catID: catID, sessionID: sessionID, detail: report.kind.rawValue,
                             control: report.control.rawValue, duration: report.duration)
        }
        return saved
    }

    func requestPlayEnd(catID: String, sessionID: String, generation: UUID) {
        guard generation == saveSceneGeneration, snapshot?.catPlay.activeSession?.id == sessionID else { return }
        if pendingCatPlayEnd?.sessionID != sessionID {
            pendingCatPlayEnd = PendingCatPlayEnd(catID: catID, sessionID: sessionID, occurredAt: Date())
        }
        retrySaving()
    }

    @discardableResult
    func chooseHabitCorner(catID: String, observationID: String) async -> Bool {
        await performPersistedAction(showsSuccessNotice: true) {
            CatHabitEngine.chooseCorner(&$0, catID: catID, observationID: observationID, now: $1)
        }
    }

    func dismissHabitCorner(catID: String, observationID: String) {
        Task {
            _ = await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
                CatHabitEngine.dismissCornerOffer(&$0, catID: catID, observationID: observationID, now: $1)
            }
        }
    }

    func dismissHabitIntro() {
        Task {
            _ = await performPersistedAction(playsSound: false, showsSuccessNotice: false) { state, date in
                let outcome = GameEngine.synchronize(&state, now: date)
                if outcome.succeeded { state.catPlay.introDismissed = true }
                return outcome
            }
        }
    }

    func recordHabitStudy(_ event: String, catID: String, sessionID: String? = nil, detail: String? = nil,
                          control: String? = nil, duration: Double? = nil) {
        guard habitStudyMode, CatHabitCatalog.definition(for: catID) != nil else { return }
        let first = !recordedFirstHabitAction && ["playOpened", "restStarted", "cornerSelected"].contains(event)
        if first { recordedFirstHabitAction = true }
        Task {
            do {
                if first {
                    try await habitStudyLog.append(.init(event: "firstHabitAction", catID: catID, sessionID: sessionID,
                        detail: event, control: control, duration: nil))
                }
                try await habitStudyLog.append(.init(event: event, catID: catID, sessionID: sessionID,
                    detail: detail, control: control, duration: duration))
            } catch { habitStudyError = true }
        }
    }

    func recordHabitCommit(from previous: GameSnapshot, to current: GameSnapshot) {
        guard habitStudyMode else { return }
        if current.inventory.toys > previous.inventory.toys {
            recordHabitStudy("toysPurchased", catID: current.activeCatID,
                             detail: String(current.inventory.toys - previous.inventory.toys))
        }
        if let active = current.catPlay.activeSession, active.paidAt != nil,
           previous.catPlay.activeSession?.paidAt == nil { recordHabitStudy("playCharged", catID: active.catID, sessionID: active.id) }
        if let result = current.catPlay.lastResult, result.id != previous.catPlay.lastResult?.id {
            recordHabitStudy("playEnded", catID: result.catID, sessionID: result.id,
                             duration: result.endedAt.timeIntervalSince(result.session.openedAt))
        }
        if !previous.catPlay.tutorialCompleted && current.catPlay.tutorialCompleted {
            recordHabitStudy("tutorialCompleted", catID: current.catPlay.tutorialCatID ?? current.activeCatID)
        }
        for cat in current.cats {
            let old = previous.cats.first { $0.id == cat.id }?.habits ?? CatHabitState()
            let oldRest = previous.cats.first { $0.id == cat.id }?.activeRest
            if let rest = cat.activeRest, rest.observation != nil, rest.id != oldRest?.id {
                recordHabitStudy("restStarted", catID: cat.id, sessionID: rest.id)
            }
            if let rest = oldRest, rest.observation != nil, cat.activeRest == nil, cat.habits.lastRestObservation?.id != rest.id {
                recordHabitStudy("restInvalidated", catID: cat.id, sessionID: rest.id, detail: "interrupted")
            }
            if old.cornerFurnitureID != cat.habits.cornerFurnitureID, cat.habits.cornerFurnitureID != nil {
                recordHabitStudy("cornerSelected", catID: cat.id, detail: cat.habits.cornerFurnitureID)
            }
            if let rest = cat.habits.lastRestObservation, old.lastRestObservation?.id != rest.id {
                recordHabitStudy("restObserved", catID: cat.id, sessionID: rest.id, detail: rest.matched ? "clue" : "comparison")
            }
            if let play = cat.habits.lastPlayObservation, old.lastPlayObservation != play {
                recordHabitStudy("playObserved", catID: cat.id, sessionID: play.sessionID, detail: play.matched ? "clue" : "comparison")
            }
            for memory in cat.habits.memories where !old.memories.contains(where: { $0.kind == memory.kind }) {
                recordHabitStudy("memory", catID: cat.id, detail: memory.id)
            }
        }
    }
}
