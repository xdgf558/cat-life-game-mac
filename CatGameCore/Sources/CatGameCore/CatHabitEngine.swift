import Foundation

/// Habit progress is committed alongside existing care. Rendering never issues clues or rewards.
public enum CatHabitEngine {
    public static func beginPlay(_ state: inout GameSnapshot, catID: String, now: Date = Date()) -> ActionOutcome {
        let sync = GameEngine.synchronize(&state, now: now)
        guard sync.succeeded else { return sync }
        guard state.activeCatID == catID, state.cats.contains(where: { $0.id == catID }),
              CatHabitCatalog.definition(for: catID) != nil else { return ActionOutcome(failure: .habitCatUnavailable) }
        if let active = state.catPlay.activeSession {
            return active.catID == catID ? ActionOutcome() : ActionOutcome(failure: .habitPlayBusy)
        }
        if !state.catPlay.tutorialCompleted, state.catPlay.tutorialID == nil {
            state.catPlay.tutorialID = UUID().uuidString
            state.catPlay.tutorialCatID = catID
        }
        let tutorial = !state.catPlay.tutorialCompleted && state.catPlay.tutorialCatID == catID
        guard tutorial || state.inventory.toys > 0 else { return ActionOutcome(failure: .careToyRequired) }
        state.catPlay.activeSession = CatPlaySession(catID: catID, openedAt: max(now, state.meta.lastSyncAt), isTutorial: tutorial)
        return ActionOutcome(success: .habitPlayOpened)
    }

    public static func recordPlayInput(_ state: inout GameSnapshot, catID: String, sessionID: String,
                                      report: CatPlayInputReport, now: Date = Date()) -> ActionOutcome {
        let sync = GameEngine.synchronize(&state, now: now)
        guard sync.succeeded else { return sync }
        guard var session = state.catPlay.activeSession, session.id == sessionID, session.catID == catID,
              state.activeCatID == catID, let index = state.cats.firstIndex(where: { $0.id == catID }),
              let habit = CatHabitCatalog.definition(for: catID) else { return ActionOutcome(failure: .habitPlaySessionEnded) }
        guard report.isValid else { return ActionOutcome(failure: .habitInputInvalid) }
        guard report.sequence > session.lastSequence else { return ActionOutcome() }
        let timestamp = max(now, state.meta.lastSyncAt)
        let elapsed = min(20, timestamp.timeIntervalSince(session.openedAt))
        guard report.duration <= elapsed + 0.01, report.movementDuration <= elapsed + 0.01 else {
            return ActionOutcome(failure: .habitInputInvalid)
        }
        let effectiveInput = report.control == .tap || report.movementDuration >= 1
        let sustainedRhythm = report.control == .tap
            || report.movementDuration >= (report.kind == .slowMove ? CatHabitCatalog.responseDuration : 0.6)
        let responseEligible = report.kind.rhythm != nil && sustainedRhythm
            && report.duration >= (report.kind == .moveAndPause ? CatHabitCatalog.pauseResponseDuration : CatHabitCatalog.responseDuration)
        if session.isTutorial && (effectiveInput || responseEligible) {
            _ = GameEngine.endCatRest(&state, catID: catID, now: timestamp)
        } else if effectiveInput && session.paidAt == nil {
            let before = state.cats[index]
            let moodBefore = state.player.mood
            let outcome = GameEngine.applyPlay(&state, index: index, now: timestamp)
            guard outcome.succeeded else { return outcome }
            session.paidAt = timestamp
            session.effects.toysSpent = 1
            session.effects.catMood = state.cats[index].mood - before.mood
            session.effects.intimacy = state.cats[index].intimacy - before.intimacy
            session.effects.energySpent = before.energy - state.cats[index].energy
            session.effects.playerMood = state.player.mood - moodBefore
        }
        session.lastSequence = report.sequence
        if session.isTutorial || session.paidAt != nil,
           responseEligible,
           let rhythm = report.kind.rhythm,
           !session.observedRhythms.contains(rhythm) {
            session.observedRhythms.append(rhythm)
            let matched = rhythm == habit.play
            let clueID = session.isTutorial ? state.catPlay.tutorialID ?? session.id : session.id
            if matched {
                let firstResponse = !session.completeResponse
                session.completeResponse = true
                state.cats[index].habits.remember(.firstResponse, at: timestamp)
                if state.cats[index].habits.playClueSessionIDs.count < CatHabitCatalog.cluesToConfirm,
                   !state.cats[index].habits.playClueSessionIDs.contains(clueID) {
                    state.cats[index].habits.playClueSessionIDs.append(clueID)
                }
                if state.cats[index].habits.playConfirmed {
                    state.cats[index].habits.remember(.favoritePlay, at: timestamp)
                    if firstResponse { state.cats[index].habits.responseFinishIndex = (state.cats[index].habits.responseFinishIndex + 1) % 2 }
                }
                rememberUnderstanding(&state.cats[index], at: timestamp)
            }
            state.cats[index].habits.lastPlayObservation = CatPlayObservation(
                sessionID: session.id, rhythm: rhythm, observedAt: timestamp, matched: matched)
            if session.isTutorial {
                if !state.catPlay.tutorialRhythms.contains(rhythm) { state.catPlay.tutorialRhythms.append(rhythm) }
                state.catPlay.tutorialCompleted = state.catPlay.tutorialRhythms.count == CatPlayRhythm.allCases.count
            }
        }
        state.catPlay.activeSession = session
        return ActionOutcome(success: .habitPlayUpdated)
    }

    public static func endPlay(_ state: inout GameSnapshot, catID: String, sessionID: String,
                               now: Date = Date()) -> ActionOutcome {
        let sync = GameEngine.synchronize(&state, now: now)
        guard sync.succeeded else { return sync }
        guard let active = state.catPlay.activeSession, active.id == sessionID, active.catID == catID else { return ActionOutcome() }
        finishPlay(&state, now: max(now, state.meta.lastSyncAt))
        return ActionOutcome(success: .habitPlayEnded)
    }

    static func finishPlay(_ state: inout GameSnapshot, now: Date) {
        guard let active = state.catPlay.activeSession else { return }
        state.catPlay.lastResult = CatPlayReceipt(session: active, endedAt: min(active.endsAt, max(active.openedAt, now)))
        state.catPlay.activeSession = nil
    }

    static func completeRest(_ cat: inout CatState, rest: CatRest, home: HomeState, inventory: InventoryState) {
        guard let location = rest.observation, let definition = CatHabitCatalog.definition(for: cat.id),
              let placement = home.furniture.first(where: { $0.itemID == rest.furnitureID }),
              placement.floor == location.floor, placement.position == location.position,
              let item = inventory.furniture.first(where: { $0.id == rest.furnitureID }),
              let kind = CatRestPreference(kind: item.kind), cat.habits.lastRestObservation?.id != rest.id else { return }
        let legacy = cat.habits.legacyRestSessionID == rest.id
        if legacy { cat.habits.legacyRestSessionID = nil }
        let matched = kind == definition.rest
        if !legacy, let known = cat.habits.restLocations[rest.furnitureID],
           location.isMeaningfullyDifferent(from: known.reference) {
            cat.habits.remember(.settledAfterMove, at: rest.endsAt)
        }
        cat.habits.restLocations[rest.furnitureID] = CatRestLocationRecord(reference: location, visited: true)
        cat.habits.lastRestObservation = CatRestObservationReceipt(id: rest.id, furnitureID: rest.furnitureID,
            kind: kind, location: location, completedAt: rest.endsAt, matched: matched)
        if matched, cat.habits.restClueSessionIDs.count < CatHabitCatalog.cluesToConfirm,
           !cat.habits.restClueSessionIDs.contains(rest.id) { cat.habits.restClueSessionIDs.append(rest.id) }
        if cat.habits.restConfirmed { cat.habits.remember(.favoriteRest, at: rest.endsAt) }
        if !legacy { rememberUnderstanding(&cat, at: rest.endsAt) }
    }

    public static func chooseCorner(_ state: inout GameSnapshot, catID: String, observationID: String,
                                    now: Date = Date()) -> ActionOutcome {
        let sync = GameEngine.synchronize(&state, now: now)
        guard sync.succeeded else { return sync }
        guard let index = state.cats.firstIndex(where: { $0.id == catID }),
              let receipt = state.cats[index].habits.lastRestObservation, receipt.id == observationID,
              state.home.furniture.contains(where: {
                  $0.itemID == receipt.furnitureID && $0.floor == receipt.location.floor && $0.position == receipt.location.position
              }) else { return ActionOutcome(failure: .habitCornerUnavailable) }
        state.cats[index].habits.cornerFurnitureID = receipt.furnitureID
        state.cats[index].habits.remember(.littleCorner, at: max(now, state.meta.lastSyncAt))
        rememberUnderstanding(&state.cats[index], at: max(now, state.meta.lastSyncAt))
        return ActionOutcome(success: .habitCornerSelected)
    }

    /// Only successful new interactions call this; ordinary synchronization never invents a memory.
    static func rememberUnderstanding(_ cat: inout CatState, at date: Date) {
        guard cat.intimacy >= 75, cat.habits.restConfirmed, cat.habits.playConfirmed,
              cat.habits.memories.contains(where: { $0.kind == .littleCorner }) else { return }
        cat.habits.remember(.understandEachOther, at: date)
    }

    public static func pinMemory(_ state: inout GameSnapshot, catID: String, memory: CatMemoryKind?,
                                 now: Date = Date()) -> ActionOutcome {
        let sync = GameEngine.synchronize(&state, now: now)
        guard sync.succeeded else { return sync }
        guard let index = state.cats.firstIndex(where: { $0.id == catID }) else { return ActionOutcome(failure: .habitCatUnavailable) }
        guard memory.map(\.isPinnable) ?? true else { return ActionOutcome(failure: .habitInputInvalid) }
        state.cats[index].habits.pinnedMemory = memory
        state.cats[index].habits.pinnedHintCollapsed = false
        return ActionOutcome()
    }

    public static func setPinnedHintCollapsed(_ state: inout GameSnapshot, catID: String, collapsed: Bool,
                                             now: Date = Date()) -> ActionOutcome {
        let sync = GameEngine.synchronize(&state, now: now)
        guard sync.succeeded else { return sync }
        guard let index = state.cats.firstIndex(where: { $0.id == catID }) else { return ActionOutcome(failure: .habitCatUnavailable) }
        guard !collapsed || state.cats[index].habits.pinnedMemory != nil else { return ActionOutcome(failure: .habitInputInvalid) }
        state.cats[index].habits.pinnedHintCollapsed = collapsed
        return ActionOutcome()
    }

    public static func dismissCornerOffer(_ state: inout GameSnapshot, catID: String, observationID: String,
                                          now: Date = Date()) -> ActionOutcome {
        let sync = GameEngine.synchronize(&state, now: now)
        guard sync.succeeded else { return sync }
        guard let index = state.cats.firstIndex(where: { $0.id == catID }),
              state.cats[index].habits.lastRestObservation?.id == observationID else { return ActionOutcome() }
        state.cats[index].habits.dismissedRestOfferID = observationID
        return ActionOutcome()
    }
}
