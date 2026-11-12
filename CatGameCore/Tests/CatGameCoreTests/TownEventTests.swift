import Foundation
import Testing
@testable import CatGameCore

@Suite("Daily town choices, letters and one-time keepsakes")
struct TownEventTests {
    let now = Date(timeIntervalSince1970: 1_793_750_400)

    func ready(eventID: String? = nil) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.food = 20; state.inventory.litter = 20; state.inventory.toys = 20
        state.inventory.gifts = ["flower": 10, "drink": 10, "dessert": 10]
        if let eventID { state.community.events.eventID = eventID }
        return state
    }

    func choose(_ state: inout GameSnapshot, choice: String = "help", at date: Date? = nil) -> ActionOutcome {
        GameEngine.resolveTownEvent(&state, eventID: state.community.events.eventID ?? "",
            choiceID: choice, dayKey: state.community.events.dayKey ?? "", now: date ?? now)
    }

    func completedSeven() throws -> GameSnapshot {
        var state = ready()
        for day in 0..<7 {
            let date = now.addingTimeInterval(Double(day) * 86_400)
            #expect(GameEngine.synchronize(&state, now: date).succeeded)
            #expect(choose(&state, at: date).succeeded)
        }
        return state
    }

    @Test func eightEventsHaveTwoExplicitAffordableChoicesAndAStableKeepsake() throws {
        #expect(Set(TownEventCatalog.all.map(\.id)).count == 8)
        #expect(TownEventCatalog.milestones == [TownEventMilestone(id: "town_memory_7", target: 7,
            furnitureKind: .wallTownMemory, itemID: "town-event-memory")],
            "Published milestone IDs and their thresholds must not be repurposed.")
        for event in TownEventCatalog.all {
            #expect(CommunityCatalog.neighbor(id: event.neighborID) != nil)
            #expect(event.choices.map(\.id) == ["help", "supply"])
            for choice in event.choices {
                var state = ready(eventID: event.id)
                let before = state
                #expect(TownEventCatalog.eligibility(eventID: event.id, choiceID: choice.id,
                    dayKey: try #require(state.community.events.dayKey), in: state) == nil)
                #expect(choose(&state, choice: choice.id).success == .townEventCompleted)
                let receipt = try #require(state.community.events.todayReceipt)
                #expect(receipt.eventID == event.id && receipt.choiceID == choice.id)
                #expect(receipt.neighborID == event.neighborID && receipt.completedAt == now)
                #expect(receipt.responseKey == choice.responseKey)
                #expect(state.player.stamina == before.player.stamina - choice.staminaCost)
                #expect(receipt.friendshipGained == choice.friendshipReward)
                #expect(state.tasks.dailyFeedCount == 0 && state.community.dailyExchangeCount == 0)
                #expect(state.isValid)
            }
        }
    }

    @Test func daySelectionIsStableAcrossReloadAndRotatesWithoutRerolling() throws {
        var state = ready()
        let first = state.community.events.eventID
        #expect(TownEventCatalog.current(in: state)?.id == first)
        let loaded = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state)).snapshot
        #expect(loaded.community.events == state.community.events)
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(2)).succeeded)
        #expect(state.community.events.eventID == first)
        var seen = Set<String>()
        for day in 0..<8 {
            #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(Double(day) * 86_400)).succeeded)
            seen.insert(try #require(state.community.events.eventID))
        }
        #expect(seen.count == 8)
    }

    @Test func aCompletedDayCannotSpendAgainEvenWithTheOtherChoiceOrAfterReload() throws {
        var state = ready()
        #expect(choose(&state).succeeded)
        state = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state))
        let completed = state
        #expect(choose(&state, choice: "supply").failure == .townEventCompleted)
        #expect(state == completed)
        #expect(state.community.events.totalCompleted == 1 && state.community.events.letters.count == 1)
    }

    @Test func midnightRejectsTheStaleCardAndClockRollbackNeverResetsCompletion() throws {
        var state = ready()
        let oldEvent = try #require(state.community.events.eventID)
        let oldDay = try #require(state.community.events.dayKey)
        #expect(choose(&state).succeeded)
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(GameEngine.resolveTownEvent(&state, eventID: oldEvent, choiceID: "supply",
            dayKey: oldDay, now: tomorrow).failure == .townEventDayChanged)
        #expect(state.community.events.totalCompleted == 1 && state.community.events.todayReceipt == nil)
        #expect(choose(&state, at: tomorrow).succeeded)
        let after = state
        #expect(choose(&state, at: now).failure == .townEventCompleted)
        #expect(state == after)
    }

    @Test func westwardLocalDateUsesTheStillOpenLedger() throws {
        var state = ready()
        // The saved day was opened east of the new time zone. Its ledger must not go backward.
        let nextKey = try #require(GameTaskState.dayKey(for: now.addingTimeInterval(86_400)))
        state.tasks.dailyDayKey = nextKey
        state.community.events = TownEventState(dayKey: nextKey, eventID: TownEventCatalog.eventID(for: nextKey))
        #expect(state.isValid)
        #expect(choose(&state).succeeded)
        #expect(state.community.events.dayKey == nextKey)
        #expect(choose(&state).failure == .townEventCompleted)
    }

    @Test func missingMaterialsInsufficientStaminaAndBusyWorkNeverSpendOrComplete() throws {
        for reason in 0..<4 {
            var state = ready(eventID: "mira_tidy")
            if reason == 0 { state.inventory.litter = 0 }
            if reason == 1 { state.player.stamina = 0 }
            if reason == 2 { #expect(GameEngine.startWork(&state, now: now).succeeded) }
            if reason == 3 { #expect(GameEngine.startSleep(&state, now: now).succeeded) }
            let original = state
            let result = choose(&state, choice: reason == 0 ? "supply" : "help")
            #expect(result.failure == [ActionFailure.townEventSuppliesRequired, .townEventStaminaRequired,
                                      .townEventBusy, .townEventBusy][reason])
            #expect(state == original)
        }
    }

    @Test func receiptSeparatesInputFromOutputAndIncludesActualStageRewards() throws {
        var state = ready(eventID: "grace_welcome")
        state.community.relationships["neighbor_grace"]?.friendship = 18
        let before = state
        #expect(choose(&state, choice: "supply").succeeded)
        let receipt = try #require(state.community.events.todayReceipt)
        #expect(receipt.stageBefore == 1 && receipt.stageAfter == 2)
        #expect(receipt.rewards == .init(gold: 20, food: 1, litter: 1))
        #expect(state.inventory.food == before.inventory.food,
                "One food was given and a different food was awarded by the stage reward.")
        #expect(state.inventory.litter == before.inventory.litter + 1)
        let saved = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state)).snapshot
        #expect(saved.community.events == state.community.events)
    }

    @Test func fullStockAndWalletReportOnlyActualAwardsWithoutBlockingTheStory() throws {
        var state = ready(eventID: "mira_tidy")
        state.player.gold = GameSnapshot.maximumGold
        state.inventory.food = GameSnapshot.maximumStock
        state.inventory.litter = GameSnapshot.maximumStock
        state.community.relationships["neighbor_mira"]?.friendship = 18
        #expect(choose(&state).succeeded)
        let receipt = try #require(state.community.events.todayReceipt)
        #expect(receipt.rewards == TownEventRewards())
        #expect(receipt.friendshipGained == 4 && receipt.stageAfter == 2)
        #expect(state.community.relationship(for: "neighbor_mira").rewardedStageLevels == [2])
        #expect(state.player.gold == GameSnapshot.maximumGold && state.isValid)
    }

    @Test func sevenParticipationsUnlockOnlyOneWallKeepsakeEvenInAFullRoom() throws {
        var state = ready()
        #expect(GameEngine.claimTownMilestone(&state, milestoneID: "town_memory_7", now: now).failure == .townMilestoneIncomplete)
        state = try completedSeven()
        let roomBefore = state.home
        #expect(state.home.furniture.count == HomeCatalog.level(state.home.roomLevel)?.capacity)
        let purchases = state.tasks.furniturePurchaseCount
        let date = state.meta.lastSyncAt
        var wrongKind = state
        wrongKind.inventory.furniture.append(.init(id: "town-event-memory", kind: .plant))
        let wrongBefore = wrongKind
        #expect(GameEngine.claimTownMilestone(&wrongKind, milestoneID: "town_memory_7", now: date).failure == .gameInvalidState)
        #expect(wrongKind == wrongBefore, "A conflicting instance must not consume the one-time milestone claim.")
        #expect(GameEngine.claimTownMilestone(&state, milestoneID: "town_memory_7", now: date).success == .townMilestoneClaimed)
        #expect(state.home == roomBefore && state.tasks.furniturePurchaseCount == purchases)
        #expect(state.inventory.furniture.filter { $0.id == "town-event-memory" } == [.init(id: "town-event-memory", kind: .wallTownMemory)])
        let after = state
        #expect(GameEngine.claimTownMilestone(&state, milestoneID: "town_memory_7", now: date).failure == .townMilestoneClaimed)
        #expect(state == after)
        #expect(FurnitureCatalog.metadata(for: .wallTownMemory).isWall && !FurnitureKind.wallTownMemory.supportsRotation)
        #expect(!ShopCatalog.furnitureOffers.contains { $0.kind == .wallTownMemory })
        #expect(throws: SaveRepositoryError.invalidSnapshot) {
            try JSONDecoder().decode(FurnitureItem.self,
                from: JSONEncoder().encode(FurnitureItem(id: "memory", kind: .wallTownMemory, orientation: .left)))
        }
        #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state)).snapshot == state)
    }

    @Test func retainedLettersAreBoundedWithoutResettingLifetimeProgress() throws {
        var state = ready()
        for day in 0..<70 {
            let date = now.addingTimeInterval(Double(day) * 86_400)
            #expect(GameEngine.synchronize(&state, now: date).succeeded)
            #expect(choose(&state, at: date).succeeded)
        }
        #expect(state.community.events.letters.count == 64 && state.community.events.totalCompleted == 70)
        #expect(state.community.events.letters.first?.dayKey == GameTaskState.dayKey(for: now.addingTimeInterval(6 * 86_400)))
        #expect(state.isValid)
    }
}
