import Foundation
import Testing
@testable import CatGameCore

@Suite("Little habits, deliberate play and non-destructive memories")
struct CatHabitTests {
    let now = Date(timeIntervalSince1970: 1_794_300_000)

    @Test func fixedProfilesMeetEveryDraftConstraintWithoutDependingOnNamesOrAppearance() throws {
        let all = CatHabitCatalog.all
        #expect(all.count == 5)
        #expect(Set(all.map(\.id)).count == 5)
        #expect(Set(all.map { "\($0.style)-\($0.rest)-\($0.play)" }).count == 5)
        for pair in zip(all, all.dropFirst()) {
            #expect([pair.0.style != pair.1.style, pair.0.rest != pair.1.rest, pair.0.play != pair.1.play].filter { $0 }.count >= 2)
        }
        for rest in CatRestPreference.allCases { #expect(all.filter { $0.rest == rest }.count >= 2) }
        for play in CatPlayRhythm.allCases { #expect(all.filter { $0.play == play }.count >= 2) }
        var cat = GameSnapshot.fresh(now: now).cats[0]
        let profile = CatHabitCatalog.definition(for: cat.id)
        cat.customName = "A new name"; cat.appearance = .silver
        #expect(CatHabitCatalog.definition(for: cat.id) == profile)
        #expect(CatHabitCatalog.definition(for: "future_cat") == nil)
    }

    @Test func dragClassifierSeparatesSlowPauseFastAndStationaryWithoutFrameBasedCredits() {
        var tracker = CatPlayInputTracker()
        tracker.move(to: .init(x: 0.2, y: 0.5), at: 0)
        for index in 1...22 { tracker.move(to: .init(x: 0.2 + Double(index) * 0.01, y: 0.5), at: Double(index) * 0.1) }
        #expect(tracker.kind == .slowMove)
        #expect(tracker.duration >= 2)
        #expect(tracker.movementDuration >= 1)
        tracker.tick(at: 2.8)
        #expect(tracker.kind == .moveAndPause)
        tracker.move(to: .init(x: 0.9, y: 0.5), at: 2.85)
        #expect(tracker.kind == .tooFast)
        tracker.reset()
        tracker.move(to: .init(x: 0.5, y: 0.5), at: 0)
        tracker.tick(at: 10)
        #expect(tracker.kind == .still)
        #expect(tracker.duration == 0)
        tracker.move(to: .init(x: .nan, y: 0.5), at: 11)
        #expect(tracker.kind == .still)
    }

    @Test func tutorialTriesBothRhythmsWithoutChargingOrCreatingTaskProgress() throws {
        var state = GameSnapshot.fresh(now: now)
        let before = state
        let id = try open(&state, at: now)
        input(&state, id: id, sequence: 1, kind: .slowMove, duration: 0, at: now)
        input(&state, id: id, sequence: 2, kind: .slowMove, duration: 2, at: now.addingTimeInterval(2))
        #expect(state.cats[0].habits.lastPlayObservation?.matched == false)
        input(&state, id: id, sequence: 3, kind: .moveAndPause, duration: 0, at: now.addingTimeInterval(2.1))
        input(&state, id: id, sequence: 4, kind: .moveAndPause, duration: 1.5, at: now.addingTimeInterval(4))
        #expect(state.catPlay.tutorialCompleted)
        #expect(state.cats[0].habits.playClueSessionIDs.count == 1)
        #expect(state.cats[0].habits.memories.map(\.kind) == [.firstResponse])
        #expect(state.cats[0].mood == before.cats[0].mood)
        #expect(state.cats[0].intimacy == before.cats[0].intimacy)
        #expect(state.cats[0].energy == before.cats[0].energy)
        #expect(state.inventory == before.inventory)
        #expect(state.player == before.player)
        #expect(state.tasks == before.tasks)
    }

    @Test func interruptedTutorialReusesOneClueEntitlementAndNeedsPaidPlayToConfirm() throws {
        var state = GameSnapshot.fresh(now: now)
        let first = try open(&state, at: now)
        input(&state, id: first, sequence: 1, kind: .moveAndPause, duration: 2, at: now.addingTimeInterval(2))
        #expect(CatHabitEngine.endPlay(&state, catID: state.activeCatID, sessionID: first, now: now.addingTimeInterval(3)).succeeded)
        let second = try open(&state, at: now.addingTimeInterval(4))
        #expect(first != second)
        input(&state, id: second, sequence: 1, kind: .moveAndPause, duration: 2, at: now.addingTimeInterval(6))
        #expect(state.cats[0].habits.playClueSessionIDs.count == 1)
        #expect(!state.cats[0].habits.playConfirmed)
        input(&state, id: second, sequence: 2, kind: .slowMove, duration: 2, at: now.addingTimeInterval(8))
        #expect(state.catPlay.tutorialCompleted)
        #expect(CatHabitEngine.endPlay(&state, catID: state.activeCatID, sessionID: second, now: now.addingTimeInterval(9)).succeeded)
        #expect(!CatHabitEngine.beginPlay(&state, catID: state.activeCatID, now: now.addingTimeInterval(10)).succeeded)
        #expect(state.inventory.toys == 0)
        #expect(GameEngine.buyToy(&state, now: now.addingTimeInterval(10)).succeeded)
        let paid = try open(&state, at: now.addingTimeInterval(11))
        input(&state, id: paid, sequence: 1, kind: .moveAndPause, duration: 2, at: now.addingTimeInterval(13))
        #expect(state.cats[0].habits.playConfirmed)
        #expect(state.cats[0].habits.memories.contains { $0.kind == .favoritePlay })
        #expect(state.inventory.toys == 5)
        #expect(state.tasks.dailyPlayCount == 1)
    }

    @Test func paidSessionMatchesQuickPlayExactlyAndCannotRepeatItsBaseOrClue() throws {
        var state = try paidSeed()
        state.cats[0].mood = 97; state.cats[0].intimacy = 99; state.cats[0].energy = 5; state.player.mood = 99
        var quick = state
        let start = state.meta.lastSyncAt.addingTimeInterval(1)
        let id = try open(&state, at: start)
        input(&state, id: id, sequence: 1, kind: .moveAndPause, duration: 0, at: start)
        #expect(GameEngine.play(&quick, catID: quick.activeCatID, now: start).succeeded)
        #expect(state.inventory == quick.inventory)
        #expect(state.player == quick.player)
        #expect(state.tasks == quick.tasks)
        #expect(state.cats[0].mood == quick.cats[0].mood)
        #expect(state.cats[0].intimacy == quick.cats[0].intimacy)
        #expect(state.cats[0].energy == quick.cats[0].energy)
        let effects = try #require(state.catPlay.activeSession?.effects)
        #expect(effects.catMood == 3 && effects.intimacy == 1 && effects.energySpent == 5 && effects.playerMood == 1)
        let stock = state.inventory.toys
        input(&state, id: id, sequence: 2, kind: .moveAndPause, duration: 2, at: start.addingTimeInterval(2))
        input(&state, id: id, sequence: 2, kind: .moveAndPause, duration: 2, at: start.addingTimeInterval(2))
        input(&state, id: id, sequence: 3, kind: .moveAndPause, duration: 3, at: start.addingTimeInterval(3))
        #expect(state.inventory.toys == stock)
        #expect(state.tasks.dailyPlayCount == 1)
        #expect(state.cats[0].habits.playClueSessionIDs.count == 2)
    }

    @Test func openingAndClosingDoesNotConsumeAndOldSessionsCannotWriteIntoNewOnes() throws {
        var state = try paidSeed()
        let before = state.inventory
        let start = state.meta.lastSyncAt
        let id = try open(&state, at: start)
        _ = CatHabitEngine.endPlay(&state, catID: state.activeCatID, sessionID: id, now: start.addingTimeInterval(1))
        #expect(state.inventory == before)
        let second = try open(&state, at: start.addingTimeInterval(2))
        let failed = CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id,
            report: .init(sequence: 1, kind: .moveAndPause, control: .tap, duration: 2, movementDuration: 0), now: start.addingTimeInterval(4))
        #expect(failed.failure == .habitPlaySessionEnded)
        #expect(state.catPlay.activeSession?.id == second)
        #expect(state.inventory == before)
    }

    @Test func dragNeedsActualMovementAndBothControlMethodsHaveTheSameEligibility() throws {
        var state = try paidSeed()
        let start = state.meta.lastSyncAt
        let id = try open(&state, at: start)
        let toys = state.inventory.toys
        let stationary = CatPlayInputReport(sequence: 1, kind: .still, control: .drag, duration: 0, movementDuration: 0)
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id, report: stationary, now: start.addingTimeInterval(3)).succeeded)
        #expect(state.inventory.toys == toys)
        let tooShort = CatPlayInputReport(sequence: 2, kind: .slowMove, control: .drag, duration: 0.5, movementDuration: 0.5)
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id, report: tooShort, now: start.addingTimeInterval(4)).succeeded)
        #expect(state.inventory.toys == toys)
        let dragging = CatPlayInputReport(sequence: 3, kind: .moveAndPause, control: .drag, duration: 2, movementDuration: 1.2)
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id, report: dragging, now: start.addingTimeInterval(5)).succeeded)
        #expect(state.inventory.toys == toys - 1)
        #expect(state.catPlay.activeSession?.completeResponse == true)
        let repeatGesture = CatPlayInputReport(sequence: 4, kind: .moveAndPause, control: .drag, duration: 1.4, movementDuration: 0.7)
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id, report: repeatGesture, now: start.addingTimeInterval(7)).succeeded)
        #expect(state.inventory.toys == toys - 1)
    }

    @Test func committedInputSurvivesArchiveAndExpiryNeverChargesAgain() throws {
        var state = try paidSeed()
        let start = state.meta.lastSyncAt
        let id = try open(&state, at: start)
        input(&state, id: id, sequence: 1, kind: .moveAndPause, duration: 2, at: start.addingTimeInterval(2))
        let data = try NativeSaveTransfer.encode(snapshot: state, exportedAt: start.addingTimeInterval(3))
        var loaded = try NativeSaveTransfer.decode(data, now: start.addingTimeInterval(4)).snapshot
        #expect(loaded == state)
        let stock = loaded.inventory.toys
        #expect(GameEngine.synchronize(&loaded, now: start.addingTimeInterval(21)).succeeded)
        #expect(loaded.catPlay.activeSession == nil)
        #expect(loaded.catPlay.lastResult?.session.effects.toysSpent == 1)
        #expect(loaded.inventory.toys == stock)
        #expect(loaded.tasks.dailyPlayCount == 1)
    }

    @Test func archivedCompletedSessionSurvivesAChangedCatalogPreferenceWithoutReplayingBenefits() throws {
        var state = try paidSeed()
        let start = state.meta.lastSyncAt
        let id = try open(&state, at: start)
        let current = try #require(CatHabitCatalog.definition(for: state.activeCatID)?.play)
        input(&state, id: id, sequence: 1, kind: CatPlayInputKind(rawValue: current.rawValue)!,
              duration: 2, at: start.addingTimeInterval(2))
        let historical: CatPlayRhythm = current == .slowMove ? .moveAndPause : .slowMove
        state.catPlay.activeSession?.observedRhythms = [historical]
        state.cats[0].habits.lastPlayObservation = CatPlayObservation(
            sessionID: id, rhythm: historical, observedAt: start.addingTimeInterval(2), matched: true)
        let loaded = try expireHistoricalSession(NativeSaveCodec.encoder().encode(state), startedAt: start)
        #expect(loaded.catPlay.lastResult?.session.observedRhythms == [historical])
        #expect(loaded.catPlay.lastResult?.session.completeResponse == true)
    }

    @Test func archivedSessionForAnOwnedCatWithoutACurrentHabitDefinitionCanStillLoadAndExpire() throws {
        var state = try paidSeed()
        let start = state.meta.lastSyncAt
        let id = try open(&state, at: start)
        input(&state, id: id, sequence: 1, kind: .moveAndPause, duration: 2, at: start.addingTimeInterval(2))
        let retired = "retired-habit-cat"
        #expect(CatHabitCatalog.definition(for: retired) == nil)
        var saved = try #require(JSONSerialization.jsonObject(with: NativeSaveCodec.encoder().encode(state)) as? [String: Any])
        saved["activeCatID"] = retired
        var cats = try #require(saved["cats"] as? [[String: Any]])
        cats[0]["id"] = retired; saved["cats"] = cats
        var play = try #require(saved["catPlay"] as? [String: Any])
        play["tutorialCatID"] = retired
        var session = try #require(play["activeSession"] as? [String: Any])
        session["catID"] = retired; play["activeSession"] = session
        var result = try #require(play["lastResult"] as? [String: Any])
        var previous = try #require(result["session"] as? [String: Any])
        previous["catID"] = retired; result["session"] = previous; play["lastResult"] = result
        saved["catPlay"] = play
        let loaded = try expireHistoricalSession(JSONSerialization.data(withJSONObject: saved), startedAt: start)
        #expect(loaded.cats[0].id == retired && loaded.catPlay.lastResult?.catID == retired)
        #expect(loaded.catPlay.lastResult?.session.effects.toysSpent == 1)
    }

    @Test func aCompletedSessionWithoutAnyObservedRhythmRemainsInvalid() throws {
        var state = GameSnapshot.fresh(now: now)
        _ = try open(&state, at: now)
        state.catPlay.activeSession?.completeResponse = true
        #expect(state.catPlay.activeSession?.observedRhythms.isEmpty == true)
        #expect(!state.isValid)
        let data = try NativeSaveCodec.encoder().encode(state)
        #expect(throws: SaveRepositoryError.invalidSnapshot) { try NativeSaveCodec.decodeSnapshot(data, now: now) }
    }

    @Test func onlyVisiblePlayerInitiatedNaturalRestsProduceClues() throws {
        var state = GameSnapshot.fresh(now: now)
        let initialHabits = state.cats[0].habits
        #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: "floorCushion", sessionID: "ambient", now: now).succeeded)
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(9)).succeeded)
        #expect(state.cats[0].habits == initialHabits)
        try observe(&state, itemID: "floorCushion", sessionID: "first", at: now.addingTimeInterval(10))
        #expect(state.cats[0].habits.restClueSessionIDs == ["first"])
        try observe(&state, itemID: "floorCushion", sessionID: "second", at: now.addingTimeInterval(20))
        #expect(state.cats[0].habits.restConfirmed)
        #expect(state.cats[0].habits.memories.map(\.kind) == [.favoriteRest])
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(30)).succeeded)
        #expect(state.cats[0].habits.restClueSessionIDs == ["first", "second"])
    }

    @Test func careAndLayoutInterruptionsCannotBecomeRestClues() throws {
        for action in ["feed", "clean", "play", "layout"] {
            var state = GameSnapshot.fresh(now: now); state.inventory.toys = 2
            let initialHabits = state.cats[0].habits
            let point = try #require(state.home.furniture.first { $0.itemID == "floorCushion" }?.position)
            #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: "floorCushion", sessionID: action,
                observation: .init(floor: .ground, position: point), now: now).succeeded)
            let date = now.addingTimeInterval(3)
            switch action {
            case "feed": _ = GameEngine.feed(&state, catID: state.activeCatID, now: date)
            case "clean": _ = GameEngine.clean(&state, catID: state.activeCatID, now: date)
            case "play": _ = GameEngine.play(&state, catID: state.activeCatID, now: date)
            default: _ = GameEngine.setBowlPosition(&state, .init(x: 0.5, y: 0.8), now: date)
            }
            #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(12)).succeeded)
            #expect(state.cats[0].habits == initialHabits)
        }
    }

    @Test func nonpreferredCornerIsAValidChoiceAndStorageCancelsItWithoutErasingMemory() throws {
        var state = GameSnapshot.fresh(now: now)
        try observe(&state, itemID: "catBed", sessionID: "neutral", at: now)
        #expect(state.cats[0].habits.restClueSessionIDs.isEmpty)
        #expect(state.cats[0].habits.lastRestObservation?.matched == false)
        #expect(CatHabitEngine.chooseCorner(&state, catID: state.activeCatID, observationID: "neutral", now: now.addingTimeInterval(13)).succeeded)
        #expect(state.cats[0].habits.cornerFurnitureID == "catBed")
        #expect(state.cats[0].habits.memories.map(\.kind) == [.littleCorner])
        let furniture = state.home.furniture.filter { $0.itemID != "catBed" }
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition, furniture: furniture, now: now.addingTimeInterval(14)).succeeded)
        #expect(state.cats[0].habits.cornerFurnitureID == nil)
        #expect(state.cats[0].habits.memories.map(\.kind) == [.littleCorner])
        #expect(!CatHabitEngine.chooseCorner(&state, catID: state.activeCatID, observationID: "neutral", now: now.addingTimeInterval(15)).succeeded)
    }

    @Test func allOlderSchemasGainEmptyHabitFieldsWithoutInventingHistory() throws {
        let original = GameSnapshot.fresh(now: now)
        for version in 1...11 {
            var json = try #require(JSONSerialization.jsonObject(with: NativeSaveCodec.encoder().encode(original)) as? [String: Any])
            json["schemaVersion"] = version; json.removeValue(forKey: "catPlay")
            var cats = try #require(json["cats"] as? [[String: Any]])
            for i in cats.indices { cats[i].removeValue(forKey: "habits") }
            json["cats"] = cats
            let migrated = try NativeSaveCodec.decodeSnapshot(snapshotFixtureData(json), now: now)
            #expect(migrated.schemaVersion == GameSnapshot.currentSchemaVersion)
            #expect(migrated.player == original.player)
            #expect(migrated.inventory == original.inventory)
            #expect(migrated.cats == original.cats)
            #expect(migrated.catPlay == CatPlayState())
            #expect(migrated.cats[0].habits.memories.isEmpty)
        }
    }

    @Test func currentSchemaMissingOrMalformedHabitProgressIsRejectedInsteadOfReset() throws {
        let original = GameSnapshot.fresh(now: now)
        for schema in [12, 13, 14] {
            for key in ["catPlay", "habits"] {
                var json = try #require(JSONSerialization.jsonObject(with: NativeSaveCodec.encoder().encode(original)) as? [String: Any])
                json["schemaVersion"] = schema
                if key == "catPlay" { json.removeValue(forKey: key) }
                else {
                    var cats = try #require(json["cats"] as? [[String: Any]])
                    cats[0].removeValue(forKey: key); json["cats"] = cats
                }
                #expect(throws: (any Error).self) { try NativeSaveCodec.decodeSnapshot(snapshotFixtureData(json), now: now) }
            }
        }
        var invalid = original
        invalid.cats[0].habits.restClueSessionIDs = ["same", "same"]
        #expect(!invalid.isValid)
        #expect(throws: NativeSaveTransferError.self) { try NativeSaveTransfer.encode(snapshot: invalid) }
    }

    @Test func habitDatesParticipateInImportClockProtection() throws {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].habits.remember(.firstResponse, at: now.addingTimeInterval(2 * 86400))
        let archive = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: now), now: now)
        #expect(throws: NativeSaveTransferError.futureProgress) { try NativeSaveTransfer.validateImportTime(archive, now: now) }
    }

    @Test func everyCatKeepsItsOwnTwoPreferencesMemoriesAndSessionOwnership() throws {
        for definition in CatHabitCatalog.all {
            var state = GameSnapshot.fresh(now: now)
            state.player.level = 8; state.player.gold = 10_000; state.home.roomLevel = 3
            for offer in CatCatalog.adoptionOffers { #expect(GameEngine.adoptCat(&state, catID: offer.id, now: now).succeeded) }
            #expect(GameEngine.selectCompanion(&state, catID: definition.id, now: now).succeeded)
            let unrelated = state.cats.filter { $0.id != definition.id }
            let id = try open(&state, at: now)
            input(&state, id: id, sequence: 1, kind: .slowMove, duration: 2, at: now.addingTimeInterval(2))
            input(&state, id: id, sequence: 2, kind: .moveAndPause, duration: 2, at: now.addingTimeInterval(4))
            #expect(state.catPlay.activeSession?.completeResponse == true)
            #expect(state.activeCat?.habits.playClueSessionIDs.count == 1)
            _ = CatHabitEngine.endPlay(&state, catID: definition.id, sessionID: id, now: now.addingTimeInterval(5))
            let preferred = definition.rest == .bed ? "catBed" : "floorCushion"
            try observe(&state, itemID: preferred, sessionID: "rest-1", at: now.addingTimeInterval(6))
            try observe(&state, itemID: preferred, sessionID: "rest-2", at: now.addingTimeInterval(20))
            #expect(state.activeCat?.habits.restConfirmed == true)
            #expect(CatHabitEngine.chooseCorner(&state, catID: definition.id, observationID: "rest-2", now: now.addingTimeInterval(34)).succeeded)
            state.inventory.toys = 2
            let paid = try open(&state, at: now.addingTimeInterval(35))
            input(&state, id: paid, sequence: 1, kind: CatPlayInputKind(rawValue: definition.play.rawValue)!,
                  duration: 2, at: now.addingTimeInterval(37))
            #expect(state.activeCat?.habits.playConfirmed == true)
            #expect(Set(state.activeCat!.habits.memories.map(\.kind)) == Set([CatMemoryKind.firstResponse, .favoriteRest, .favoritePlay, .littleCorner]))
            #expect(state.tasks.dailyPlayCount == 1)
            #expect(state.inventory.toys == 1)
            #expect(state.cats.filter { $0.id != definition.id } == unrelated)
            let other = try #require(unrelated.first)
            #expect(GameEngine.selectCompanion(&state, catID: other.id, now: now.addingTimeInterval(38)).succeeded)
            #expect(state.catPlay.activeSession == nil && state.catPlay.lastResult?.catID == definition.id)
            let stale = CatHabitEngine.recordPlayInput(&state, catID: definition.id, sessionID: paid,
                report: .init(sequence: 2, kind: .slowMove, control: .tap, duration: 2, movementDuration: 0), now: now.addingTimeInterval(39))
            #expect(stale.failure == .habitPlaySessionEnded)
            #expect(state.activeCat?.habits == other.habits)
        }
    }

    @Test func tutorialCannotEarnAResponseFromAStationaryDragOrInflatedDuration() throws {
        var state = GameSnapshot.fresh(now: now)
        let initialHabits = state.cats[0].habits
        let id = try open(&state, at: now)
        let stationary = CatPlayInputReport(sequence: 1, kind: .slowMove, control: .drag, duration: 2, movementDuration: 0)
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id, report: stationary,
            now: now.addingTimeInterval(2)).succeeded)
        #expect(state.cats[0].habits == initialHabits)
        let inflated = CatPlayInputReport(sequence: 2, kind: .moveAndPause, control: .tap, duration: 10, movementDuration: 0)
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id, report: inflated,
            now: now.addingTimeInterval(3)).failure == .habitInputInvalid)
        #expect(!state.catPlay.tutorialCompleted)
        #expect(state.catPlay.activeSession?.effects == CatPlayEffects())
    }

    @Test func gentleDraggingAccumulatesSubpixelSamplesAtEveryTouchRefreshRate() {
        for rate in [15, 30, 60, 120] {
            var tracker = CatPlayInputTracker()
            tracker.move(to: .init(x: 0.2, y: 0.5), at: 0)
            for index in 1...Int(2.4 * Double(rate)) {
                let time = Double(index) / Double(rate)
                tracker.move(to: .init(x: 0.2 + time * 0.05, y: 0.5), at: time)
            }
            #expect(tracker.kind == .slowMove)
            #expect(tracker.duration >= 2.32)
            #expect(tracker.movementDuration >= 2.32)
            tracker.tick(at: 3)
            #expect(tracker.kind == .moveAndPause)
        }
    }

    @Test func aFreeTutorialPauseResponseAlsoInterruptsTheRoomRestWithoutCharging() throws {
        var state = GameSnapshot.fresh(now: now)
        let placement = try #require(state.home.furniture.first { $0.itemID == "floorCushion" })
        #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: placement.itemID,
            sessionID: "tutorial-interrupts-rest", observation: .init(floor: .ground, position: placement.position), now: now).succeeded)
        let id = try open(&state, at: now)
        let pause = CatPlayInputReport(sequence: 1, kind: .moveAndPause, control: .drag, duration: 1.4, movementDuration: 0.7)
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id, report: pause,
            now: now.addingTimeInterval(2)).succeeded)
        #expect(state.cats[0].activeRest == nil)
        #expect(state.catPlay.activeSession?.completeResponse == true)
        #expect(state.catPlay.activeSession?.effects == CatPlayEffects())
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(15)).succeeded)
        #expect(state.cats[0].habits.restClueSessionIDs.isEmpty)
        #expect(state.cats[0].habits.lastRestObservation == nil)
        #expect(state.inventory.toys == 0 && state.tasks.dailyPlayCount == 0)
    }

    private func expireHistoricalSession(_ data: Data, startedAt start: Date) throws -> GameSnapshot {
        var loaded = try NativeSaveCodec.decodeSnapshot(data, now: start.addingTimeInterval(3))
        #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion && loaded.isValid)
        let session = try #require(loaded.catPlay.activeSession)
        let inventory = loaded.inventory
        let tasks = loaded.tasks
        let habits = loaded.cats[0].habits
        #expect(GameEngine.synchronize(&loaded, now: start.addingTimeInterval(21)).succeeded)
        #expect(loaded.catPlay.activeSession == nil && loaded.catPlay.lastResult?.session == session)
        #expect(loaded.inventory == inventory && loaded.tasks == tasks && loaded.cats[0].habits == habits)
        let receipt = loaded.catPlay.lastResult
        #expect(GameEngine.synchronize(&loaded, now: start.addingTimeInterval(22)).succeeded)
        #expect(loaded.catPlay.lastResult == receipt)
        #expect(loaded.inventory == inventory && loaded.tasks == tasks && loaded.cats[0].habits == habits)
        return loaded
    }

    private func open(_ state: inout GameSnapshot, at date: Date) throws -> String {
        #expect(CatHabitEngine.beginPlay(&state, catID: state.activeCatID, now: date).succeeded)
        return try #require(state.catPlay.activeSession?.id)
    }
    private func input(_ state: inout GameSnapshot, id: String, sequence: Int, kind: CatPlayInputKind, duration: Double, at date: Date) {
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id,
            report: .init(sequence: sequence, kind: kind, control: .tap, duration: duration, movementDuration: 0), now: date).succeeded)
    }
    private func paidSeed() throws -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        let id = try open(&state, at: now)
        input(&state, id: id, sequence: 1, kind: .slowMove, duration: 2, at: now.addingTimeInterval(2))
        input(&state, id: id, sequence: 2, kind: .moveAndPause, duration: 2, at: now.addingTimeInterval(4))
        _ = CatHabitEngine.endPlay(&state, catID: state.activeCatID, sessionID: id, now: now.addingTimeInterval(5))
        state.inventory.toys = 6
        return state
    }
    private func observe(_ state: inout GameSnapshot, itemID: String, sessionID: String, at date: Date) throws {
        let item = try #require(state.inventory.furniture.first { $0.id == itemID })
        let placement = try #require(state.home.furniture.first { $0.itemID == itemID })
        let duration = try #require(GameEngine.catRestDuration(for: item.kind))
        #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: itemID, sessionID: sessionID,
            observation: .init(floor: placement.floor, position: placement.position), now: date).succeeded)
        #expect(GameEngine.synchronize(&state, now: date.addingTimeInterval(duration)).succeeded)
    }
}
