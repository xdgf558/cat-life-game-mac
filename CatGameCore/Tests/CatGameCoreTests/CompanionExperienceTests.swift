import Foundation
import Testing
@testable import CatGameCore

@Suite("Companion memories, real place history and durable guidance")
struct CompanionExperienceTests {
    private let now = Date(timeIntervalSince1970: 1_794_500_000)

    @Test func earlierSchemasSeedOnlyRealPlacesAndNeverInventNewMemoriesOrGuidance() throws {
        var original = GameSnapshot.fresh(now: now)
        original.home = HomeState(roomLevel: 6)
        original.home.furniture[2].position = .init(x: 0.41, y: 0.67)
        original.home.furniture[6].floor = .upper
        original.player.gold = 321
        original.player.profile.name = "Milo"
        original.cats[0].customName = "豆豆"
        for schema in 1...13 {
            var object = try json(original)
            object["schemaVersion"] = schema
            var cats = try #require(object["cats"] as? [[String: Any]])
            if schema < 12 { cats[0].removeValue(forKey: "habits") }
            else {
                cats[0]["habits"] = ["restClueSessionIDs": ["old-rest"], "playClueSessionIDs": [], "memories": []]
            }
            object["cats"] = cats
            // Pre-floor saves could only contain ground-floor level 1...3 homes.
            if schema < 10 {
                var home = try #require(object["home"] as? [String: Any])
                home["roomLevel"] = 3
                home.removeValue(forKey: "upperBowlPosition")
                var placements = try #require(home["furniture"] as? [[String: Any]])
                for index in placements.indices { placements[index].removeValue(forKey: "floor") }
                home["furniture"] = placements
                object["home"] = home
            }
            let loaded = try decode(object)
            #expect(loaded.schemaVersion == 15 && loaded.isValid)
            #expect(loaded.player == original.player && loaded.inventory == original.inventory)
            #expect(loaded.cats[0].customName == original.cats[0].customName)
            #expect(loaded.cats[0].intimacy == original.cats[0].intimacy)
            let habits = loaded.cats[0].habits
            #expect(habits.restClueSessionIDs == (schema >= 12 ? ["old-rest"] : []))
            #expect(habits.memories.isEmpty && habits.pinnedMemory == nil && !habits.pinnedHintCollapsed)
            #expect(habits.responseFinishIndex == 0 && habits.legacyRestSessionID == nil)
            for placement in loaded.home.furniture {
                guard loaded.inventory.furniture.contains(where: { $0.id == placement.itemID && CatRestPreference(kind: $0.kind) != nil }) else { continue }
                #expect(habits.restLocations[placement.itemID] == CatRestLocationRecord(
                    reference: .init(floor: placement.floor, position: placement.position)))
            }
            #expect(try decode(json(loaded)) == loaded)
        }
    }

    @Test func currentSchemaRequiresEveryNewFieldAndRejectsDamagedRecordsInsteadOfResetting() throws {
        let original = GameSnapshot.fresh(now: now)
        for key in ["restLocations", "pinnedMemory", "pinnedHintCollapsed", "responseFinishIndex", "legacyRestSessionID"] {
            var object = try json(original)
            var cats = try #require(object["cats"] as? [[String: Any]])
            var habits = try #require(cats[0]["habits"] as? [String: Any])
            habits.removeValue(forKey: key); cats[0]["habits"] = habits; object["cats"] = cats
            #expect(throws: (any Error).self) { try decode(object) }
        }
        for (key, value) in [("restLocations", NSNull()), ("pinnedHintCollapsed", NSNull()),
                              ("responseFinishIndex", -1), ("responseFinishIndex", 2),
                              ("pinnedMemory", "firstResponse"), ("legacyRestSessionID", "")] as [(String, Any)] {
            var object = try json(original)
            var cats = try #require(object["cats"] as? [[String: Any]])
            var habits = try #require(cats[0]["habits"] as? [String: Any])
            habits[key] = value; cats[0]["habits"] = habits; object["cats"] = cats
            #expect(throws: (any Error).self) { try decode(object) }
        }
        for missing in ["reference", "visited"] {
            var object = try json(original)
            var cats = try #require(object["cats"] as? [[String: Any]])
            var habits = try #require(cats[0]["habits"] as? [String: Any])
            var places = try #require(habits["restLocations"] as? [String: Any])
            var record = try #require(places["catBed"] as? [String: Any])
            record.removeValue(forKey: missing); places["catBed"] = record
            habits["restLocations"] = places; cats[0]["habits"] = habits; object["cats"] = cats
            #expect(throws: (any Error).self) { try decode(object) }
        }
        var invalid = original
        invalid.cats[0].habits.restLocations[""] = .init(reference: .init(floor: .ground, position: .init(x: 0.5, y: 0.5)))
        #expect(!invalid.isValid)
        invalid = original
        invalid.cats[0].habits.restLocations["retired"] = .init(reference: .init(floor: .ground, position: .init(x: .nan, y: 0.5)))
        #expect(!invalid.isValid)
        invalid = original; invalid.cats[0].habits.pinnedHintCollapsed = true
        #expect(!invalid.isValid)
    }

    @Test func significantMoveRequiresACompletedObservationAndRetainsInterleavedFurnitureHistory() throws {
        var state = GameSnapshot.fresh(now: now)
        try observe(&state, id: "floorCushion", session: "cushion-old", at: now)
        try observe(&state, id: "catBed", session: "bed-between", at: now.addingTimeInterval(12))
        let original = try #require(state.cats[0].habits.restLocations["floorCushion"])
        let target = NormalizedPoint(x: original.reference.position.x + 0.2, y: original.reference.position.y)
        try move(&state, id: "floorCushion", to: target, at: now.addingTimeInterval(26))
        #expect(state.cats[0].habits.needsRestIntroduction(furnitureID: "floorCushion", location: .init(floor: .ground, position: target)))
        #expect(!has(.settledAfterMove, in: state))
        #expect(CatHabitEngine.pinMemory(&state, catID: state.activeCatID, memory: .settledAfterMove, now: now.addingTimeInterval(26)).succeeded)
        try beginRest(&state, id: "floorCushion", session: "new-place", at: now.addingTimeInterval(27))
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(35)).succeeded)
        #expect(!has(.settledAfterMove, in: state))
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(36)).succeeded)
        #expect(has(.settledAfterMove, in: state))
        #expect(state.cats[0].habits.memories.first { $0.kind == .settledAfterMove }?.createdAt == now.addingTimeInterval(36))
        #expect(state.cats[0].habits.pinnedMemory == .settledAfterMove, "Completing a memory must retain the player's chosen guidance.")
        #expect(state.cats[0].habits.restLocations["catBed"]?.visited == true)
        #expect(!state.cats[0].habits.needsRestIntroduction(furnitureID: "floorCushion", location: .init(floor: .ground, position: target)))
        let memories = state.cats[0].habits.memories
        try observe(&state, id: "floorCushion", session: "same-place", at: now.addingTimeInterval(38))
        try move(&state, id: "floorCushion", to: original.reference.position, at: now.addingTimeInterval(48))
        try observe(&state, id: "floorCushion", session: "returned-place", at: now.addingTimeInterval(49))
        #expect(state.cats[0].habits.memories == memories)
    }

    @Test func microAdjustmentsAndInterruptedOrAutomaticRestsDoNotEarnMovedPlaceMemory() throws {
        for delta in [0.001, 0.15] {
            var state = GameSnapshot.fresh(now: now)
            let original = try #require(state.cats[0].habits.restLocations["floorCushion"]?.reference.position)
            try move(&state, id: "floorCushion", to: .init(x: original.x + delta, y: original.y), at: now)
            try observe(&state, id: "floorCushion", session: "small-move", at: now.addingTimeInterval(1))
            #expect(!has(.settledAfterMove, in: state))
        }
        let point = CatRestObservation(floor: .ground, position: .init(x: 0.2, y: 0.5))
        #expect(!CatRestObservation(floor: .ground, position: .init(x: 0.35, y: 0.5)).isMeaningfullyDifferent(from: point))
        #expect(CatRestObservation(floor: .ground, position: .init(x: 0.35001, y: 0.5)).isMeaningfullyDifferent(from: point))
        #expect(CatRestObservation(floor: .upper, position: point.position).isMeaningfullyDifferent(from: point))
        for automatic in [false, true] {
            var state = GameSnapshot.fresh(now: now)
            let reference = state.cats[0].habits.restLocations["floorCushion"]
            try move(&state, id: "floorCushion", to: .init(x: 0.5, y: 0.74), at: now)
            if automatic {
                #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: "floorCushion", sessionID: "auto", now: now).succeeded)
            } else {
                try beginRest(&state, id: "floorCushion", session: "interrupted", at: now)
                #expect(GameEngine.feed(&state, catID: state.activeCatID, now: now.addingTimeInterval(3)).succeeded)
            }
            #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(12)).succeeded)
            #expect(!has(.settledAfterMove, in: state))
            #expect(state.cats[0].habits.restLocations["floorCushion"] == reference)
        }
    }

    @Test func aNewlyPlacedRestItemGetsARealReferenceAndStorageRetainsHistoricalPlaces() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 2; state.player.gold = 1000; state.home.roomLevel = 3
        #expect(GameEngine.purchaseFurniture(&state, offerID: "cozy_cushion", now: now).succeeded)
        let item = try #require(state.inventory.furniture.last)
        #expect(state.cats[0].habits.restLocations[item.id] == nil)
        let point = NormalizedPoint(x: 0.6, y: 0.7)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture + [.init(itemID: item.id, position: point)], now: now).succeeded)
        #expect(state.cats[0].habits.restLocations[item.id] == CatRestLocationRecord(reference: .init(floor: .ground, position: point)))
        try observe(&state, id: item.id, session: "new-item", at: now)
        #expect(!has(.settledAfterMove, in: state), "A first placement establishes a reference, not a fictional earlier visit.")
        let history = state.cats[0].habits.restLocations
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture.filter { $0.itemID != item.id }, now: now.addingTimeInterval(10)).succeeded)
        #expect(state.cats[0].habits.restLocations == history)
        state.cats[0].habits.restLocations["retired-rest-item"] = .init(reference: .init(floor: .upper, position: .init(x: 0.4, y: 0.5)), visited: true)
        #expect(state.isValid)
        #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: now), now: now).snapshot == state)
    }

    @Test func storingAndMovingTheSameInstanceUpstairsRetainsItsGroundFloorReferenceUntilAValidVisit() throws {
        var state = GameSnapshot.fresh(now: now)
        state.home = HomeState(roomLevel: 6)
        let placement = try #require(state.home.furniture.first { $0.itemID == "floorCushion" })
        let reference = state.cats[0].habits.restLocations[placement.itemID]
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture.filter { $0.itemID != placement.itemID }, now: now).succeeded)
        #expect(state.cats[0].habits.restLocations[placement.itemID] == reference)
        let upstairsBowl = try #require(state.home.bowlPosition(on: .upper))
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: upstairsBowl,
            furniture: [.init(itemID: placement.itemID, position: placement.position, floor: .upper)],
            floor: .upper, now: now).succeeded)
        #expect(!has(.settledAfterMove, in: state))
        try observe(&state, id: placement.itemID, session: "upstairs", at: now)
        #expect(has(.settledAfterMove, in: state))
        #expect(state.cats[0].habits.restLocations[placement.itemID]?.reference.floor == .upper)
        #expect(state.isValid)
    }

    @Test func understandingRequiresAllFourConditionsAndOnlyANewSuccessfulInteraction() throws {
        for missing in ["intimacy", "rest", "play", "corner", "none"] {
            var state = readyForUnderstanding()
            if missing == "intimacy" { state.cats[0].intimacy = 74 }
            if missing == "rest" {
                state.cats[0].habits.restClueSessionIDs = ["r1"]
                state.cats[0].habits.memories.removeAll { $0.kind == .favoriteRest }
            }
            if missing == "play" {
                state.cats[0].habits.playClueSessionIDs = ["p1"]
                state.cats[0].habits.memories.removeAll { $0.kind == .favoritePlay }
            }
            if missing == "corner" { state.cats[0].habits.memories.removeAll { $0.kind == .littleCorner } }
            #expect(state.isValid)
            #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(1)).succeeded)
            #expect(!has(.understandEachOther, in: state), "Time synchronization cannot invent the new memory.")
            #expect(CatHabitEngine.pinMemory(&state, catID: state.activeCatID, memory: .favoritePlay, now: now.addingTimeInterval(1)).succeeded)
            #expect(!has(.understandEachOther, in: state))
            #expect(GameEngine.clean(&state, catID: state.activeCatID, now: now.addingTimeInterval(2)).succeeded)
            #expect(has(.understandEachOther, in: state) == (missing == "none"))
            #expect(state.isValid)
        }
        var state = readyForUnderstanding(); state.cats[0].intimacy = 72; state.inventory.premiumFood = 1
        #expect(GameEngine.feed(&state, catID: state.activeCatID, supply: .premiumFood, now: now).succeeded)
        #expect(state.cats[0].intimacy == 75 && has(.understandEachOther, in: state))
    }

    @Test func autonomousRestsRecoverEnergyWithoutCreatingUnderstandingWhenEveryConditionIsReady() throws {
        var state = readyForUnderstanding()
        state.cats[0].energy = 60
        let habits = state.cats[0].habits
        let inventory = state.inventory
        let gold = state.player.gold
        for attempt in 0..<2 {
            let startedAt = now.addingTimeInterval(Double(attempt * 30))
            #expect(GameEngine.startCatRest(&state, catID: state.activeCatID,
                furnitureID: "floorCushion", sessionID: "ambient-\(attempt)", now: startedAt).succeeded)
            let rest = try #require(state.cats[0].activeRest)
            #expect(rest.observation == nil)
            #expect(state.cats[0].habits == habits)
            #expect(GameEngine.synchronize(&state, now: rest.endsAt).succeeded)
            #expect(state.cats[0].activeRest == nil)
            #expect(state.cats[0].habits == habits)
        }
        #expect(state.cats[0].energy > 60)
        #expect(state.inventory == inventory && state.player.gold == gold)
        #expect(state.isValid)
    }

    @Test func playerRestCreatesUnderstandingOnlyAfterACompleteObservationAndNeverAfterInterruption() throws {
        for interrupted in [true, false] {
            var state = readyForUnderstanding()
            let inventory = state.inventory
            let gold = state.player.gold
            try beginRest(&state, id: "floorCushion", session: "observed", at: now)
            let rest = try #require(state.cats[0].activeRest)
            #expect(!has(.understandEachOther, in: state))
            if interrupted {
                #expect(GameEngine.endCatRest(&state, catID: state.activeCatID,
                    sessionID: rest.id, now: now.addingTimeInterval(3)).succeeded)
            } else {
                #expect(GameEngine.synchronize(&state, now: rest.endsAt.addingTimeInterval(-0.001)).succeeded)
                #expect(!has(.understandEachOther, in: state))
            }
            #expect(GameEngine.synchronize(&state, now: rest.endsAt).succeeded)
            #expect(has(.understandEachOther, in: state) == !interrupted)
            if !interrupted {
                #expect(state.cats[0].habits.memories.first { $0.kind == .understandEachOther }?.createdAt == rest.endsAt)
                #expect(state.cats[0].habits.lastRestObservation?.id == rest.id)
            }
            let memories = state.cats[0].habits.memories
            #expect(GameEngine.synchronize(&state, now: rest.endsAt.addingTimeInterval(20)).succeeded)
            #expect(state.cats[0].habits.memories == memories)
            #expect(state.inventory == inventory && state.player.gold == gold)
            #expect(state.isValid)
        }
    }

    @Test func legacyInFlightRestKeepsItsOriginalClueButCannotInventEitherNewMemoryOnLoad() throws {
        var old = readyForUnderstanding()
        old.cats[0].habits.restClueSessionIDs = ["old-first"]
        old.cats[0].habits.memories.removeAll { $0.kind == .favoriteRest }
        let location = try #require(old.home.furniture.first { $0.itemID == "floorCushion" })
        old.cats[0].activeRest = CatRest(id: "legacy-rest", furnitureID: location.itemID,
            startedAt: now, endsAt: now.addingTimeInterval(9), energyReward: 20,
            observation: .init(floor: location.floor, position: location.position))
        old.cats[0].lastRestSessionID = "legacy-rest"
        var object = try json(old); object["schemaVersion"] = 13
        var cats = try #require(object["cats"] as? [[String: Any]])
        var habits = try #require(cats[0]["habits"] as? [String: Any])
        for key in ["restLocations", "pinnedMemory", "pinnedHintCollapsed", "responseFinishIndex", "legacyRestSessionID"] { habits.removeValue(forKey: key) }
        cats[0]["habits"] = habits; object["cats"] = cats
        var loaded = try decode(object)
        #expect(loaded.cats[0].habits.legacyRestSessionID == "legacy-rest")
        #expect(!has(.understandEachOther, in: loaded) && !has(.settledAfterMove, in: loaded))
        #expect(GameEngine.synchronize(&loaded, now: now.addingTimeInterval(30)).succeeded)
        #expect(loaded.cats[0].habits.restConfirmed && has(.favoriteRest, in: loaded))
        #expect(!has(.understandEachOther, in: loaded) && !has(.settledAfterMove, in: loaded))
        #expect(loaded.cats[0].habits.legacyRestSessionID == nil)
        #expect(GameEngine.clean(&loaded, catID: loaded.activeCatID, now: now.addingTimeInterval(31)).succeeded)
        #expect(has(.understandEachOther, in: loaded))
    }

    @Test func interruptingAMigratedRestClearsOnlyItsSuppressionMarkerWithoutGivingP1Progress() throws {
        var old = readyForUnderstanding()
        let placement = try #require(old.home.furniture.first { $0.itemID == "floorCushion" })
        old.cats[0].activeRest = CatRest(id: "old-interrupted", furnitureID: placement.itemID,
            startedAt: now, endsAt: now.addingTimeInterval(9), energyReward: 20,
            observation: .init(floor: placement.floor, position: placement.position))
        old.cats[0].lastRestSessionID = "old-interrupted"
        var object = try json(old); object["schemaVersion"] = 13
        var loaded = try decode(object)
        #expect(loaded.cats[0].habits.legacyRestSessionID == "old-interrupted")
        #expect(GameEngine.endCatRest(&loaded, catID: loaded.activeCatID, now: now.addingTimeInterval(3)).succeeded)
        #expect(loaded.cats[0].habits.legacyRestSessionID == nil)
        #expect(loaded.cats[0].activeRest == nil)
        #expect(!has(.understandEachOther, in: loaded) && !has(.settledAfterMove, in: loaded))
        #expect(loaded.cats[0].habits.lastRestObservation == nil)
    }

    @Test func aNewSchemaObservationCanFinishTheLastUnderstandingConditionAndDeduplicateIt() throws {
        var state = readyForUnderstanding()
        state.cats[0].habits.restClueSessionIDs = ["first"]
        state.cats[0].habits.memories.removeAll { $0.kind == .favoriteRest }
        try beginRest(&state, id: "floorCushion", session: "current-rest", at: now)
        #expect(!has(.understandEachOther, in: state))
        var loaded = try decode(json(state))
        #expect(loaded.cats[0].habits.legacyRestSessionID == nil)
        #expect(GameEngine.synchronize(&loaded, now: now.addingTimeInterval(9)).succeeded)
        #expect(has(.understandEachOther, in: loaded))
        let memories = loaded.cats[0].habits.memories
        #expect(GameEngine.synchronize(&loaded, now: now.addingTimeInterval(20)).succeeded)
        #expect(GameEngine.clean(&loaded, catID: loaded.activeCatID, now: now.addingTimeInterval(21)).succeeded)
        #expect(loaded.cats[0].habits.memories == memories)
    }

    @Test func onePinnedGuidePerCatSurvivesCompletionCollapseSwitchingAndArchiveRoundTrip() throws {
        var state = GameSnapshot.fresh(now: now)
        for memory in [CatMemoryKind.favoritePlay, .littleCorner, .settledAfterMove] {
            #expect(CatHabitEngine.pinMemory(&state, catID: state.activeCatID, memory: memory, now: now).succeeded)
            #expect(state.cats[0].habits.pinnedMemory == memory && !state.cats[0].habits.pinnedHintCollapsed)
            #expect(CatHabitEngine.setPinnedHintCollapsed(&state, catID: state.activeCatID, collapsed: true, now: now).succeeded)
            #expect(state.cats[0].habits.pinnedMemory == memory && state.cats[0].habits.pinnedHintCollapsed)
        }
        state.cats[0].habits.remember(.settledAfterMove, at: now)
        #expect(CatHabitEngine.pinMemory(&state, catID: state.activeCatID, memory: .settledAfterMove, now: now).succeeded)
        #expect(state.cats[0].habits.pinnedMemory == .settledAfterMove && !state.cats[0].habits.pinnedHintCollapsed)
        state.player.level = 8; state.player.gold = 10_000; state.home.roomLevel = 3
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(state.cats[1].habits.restLocations.count == 2 && state.cats[1].habits.pinnedMemory == nil)
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(CatHabitEngine.pinMemory(&state, catID: state.activeCatID, memory: .littleCorner, now: now).succeeded)
        #expect(state.cats[0].habits.pinnedMemory == .settledAfterMove)
        #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: now), now: now).snapshot == state)
        #expect(CatHabitEngine.pinMemory(&state, catID: state.activeCatID, memory: nil, now: now).succeeded)
        #expect(state.activeCat?.habits.pinnedMemory == nil && state.activeCat?.habits.pinnedHintCollapsed == false)
        let before = state
        #expect(CatHabitEngine.pinMemory(&state, catID: state.activeCatID, memory: .firstResponse, now: now).failure == .habitInputInvalid)
        #expect(state == before)
        #expect(CatHabitEngine.setPinnedHintCollapsed(&state, catID: state.activeCatID, collapsed: true, now: now).failure == .habitInputInvalid)
        #expect(state == before)
    }

    @Test func confirmedResponseFinishAlternatesAcrossSessionsWithoutExtraChargesOrDuplicateAdvances() throws {
        var state = GameSnapshot.fresh(now: now)
        let tutorial = try beginPlay(&state, at: now)
        try input(&state, id: tutorial, kind: .slowMove, sequence: 1, at: now.addingTimeInterval(2))
        try input(&state, id: tutorial, kind: .moveAndPause, sequence: 2, at: now.addingTimeInterval(4))
        #expect(!state.cats[0].habits.playConfirmed && state.cats[0].habits.responseFinishIndex == 0)
        #expect(CatHabitEngine.endPlay(&state, catID: state.activeCatID, sessionID: tutorial, now: now.addingTimeInterval(5)).succeeded)
        state.inventory.toys = 4
        for offset in 0..<3 {
            let start = now.addingTimeInterval(Double(10 + offset * 10))
            let id = try beginPlay(&state, at: start)
            let toys = state.inventory.toys
            try input(&state, id: id, kind: .moveAndPause, sequence: 1, at: start.addingTimeInterval(2))
            #expect(state.cats[0].habits.playConfirmed)
            #expect(state.cats[0].habits.lastResponseFinishIndex == offset % 2)
            #expect(state.inventory.toys == toys - 1)
            let index = state.cats[0].habits.responseFinishIndex
            try input(&state, id: id, kind: .moveAndPause, sequence: 1, at: start.addingTimeInterval(2))
            try input(&state, id: id, kind: .moveAndPause, sequence: 2, at: start.addingTimeInterval(3))
            #expect(state.cats[0].habits.responseFinishIndex == index && state.inventory.toys == toys - 1)
            #expect(CatHabitEngine.endPlay(&state, catID: state.activeCatID, sessionID: id, now: start.addingTimeInterval(4)).succeeded)
            state = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: start), now: start).snapshot
            #expect(state.cats[0].habits.responseFinishIndex == index)
        }
        #expect(state.tasks.dailyPlayCount == 3)
    }

    private func json(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }
    private func decode(_ value: [String: Any]) throws -> GameSnapshot {
        try NativeSaveCodec.validated(JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(value)), migrationDate: now)
    }
    private func has(_ memory: CatMemoryKind, in state: GameSnapshot) -> Bool {
        state.cats[0].habits.memories.contains { $0.kind == memory }
    }
    private func readyForUnderstanding() -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].intimacy = 75
        state.cats[0].habits.restClueSessionIDs = ["r1", "r2"]
        state.cats[0].habits.playClueSessionIDs = ["p1", "p2"]
        for memory in [CatMemoryKind.firstResponse, .favoriteRest, .favoritePlay, .littleCorner] {
            state.cats[0].habits.remember(memory, at: now)
        }
        return state
    }
    private func move(_ state: inout GameSnapshot, id: String, to position: NormalizedPoint, at date: Date) throws {
        var placements = state.home.furniture
        let index = try #require(placements.firstIndex { $0.itemID == id })
        placements[index].position = position
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition, furniture: placements, now: date).succeeded)
    }
    private func beginRest(_ state: inout GameSnapshot, id: String, session: String, at date: Date) throws {
        let placement = try #require(state.home.furniture.first { $0.itemID == id })
        #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: id, sessionID: session,
            observation: .init(floor: placement.floor, position: placement.position), now: date).succeeded)
    }
    private func observe(_ state: inout GameSnapshot, id: String, session: String, at date: Date) throws {
        let item = try #require(state.inventory.furniture.first { $0.id == id })
        try beginRest(&state, id: id, session: session, at: date)
        let duration = try #require(GameEngine.catRestDuration(for: item.kind))
        #expect(GameEngine.synchronize(&state, now: date.addingTimeInterval(duration)).succeeded)
    }
    private func beginPlay(_ state: inout GameSnapshot, at date: Date) throws -> String {
        #expect(CatHabitEngine.beginPlay(&state, catID: state.activeCatID, now: date).succeeded)
        return try #require(state.catPlay.activeSession?.id)
    }
    private func input(_ state: inout GameSnapshot, id: String, kind: CatPlayInputKind, sequence: Int, at date: Date) throws {
        #expect(CatHabitEngine.recordPlayInput(&state, catID: state.activeCatID, sessionID: id,
            report: .init(sequence: sequence, kind: kind, control: .tap, duration: 2, movementDuration: 0), now: date).succeeded)
    }
}
