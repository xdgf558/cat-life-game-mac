import Foundation
import Testing
@testable import CatGameCore

@Suite("Neighbor exchange inventory, limits and task receipts")
struct ExchangeTests {
    let now = Date(timeIntervalSince1970: 1_793_600_000)
    let mira = "neighbor_mira"

    func ready(friendship: Int = 0) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 4
        state.inventory.food = 20
        state.inventory.litter = 20
        state.inventory.toys = 20
        state.inventory.gifts = Dictionary(uniqueKeysWithValues: CommunityCatalog.gifts.map { ($0.id, 20) })
        for neighbor in CommunityCatalog.neighbors {
            state.community.relationships[neighbor.id]?.friendship = friendship
            state.community.relationships[neighbor.id]?.rewardedStageLevels = CommunityCatalog.stages
                .filter { $0.level > 1 && $0.minimumPoints <= friendship }.map(\.level)
        }
        return state
    }

    func reload(_ state: GameSnapshot) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state))
    }

    @Test func eightOffersUseRealNeighborsUsableItemsAndTwoProgressionTiers() {
        #expect(ExchangeCatalog.offers.count == 8 && Set(ExchangeCatalog.offers.map(\.id)).count == 8)
        for neighbor in CommunityCatalog.neighbors {
            let offers = ExchangeCatalog.offers.filter { $0.neighborID == neighbor.id }
            #expect(offers.map(\.requiredStage) == [1, 3])
            for offer in offers {
                #expect(!offer.inputs.isEmpty && !offer.outputs.isEmpty)
                for stack in offer.inputs + offer.outputs {
                    #expect(stack.quantity > 0 && stack.quantity <= 6)
                    if case .gift(let id) = stack.item { #expect(CommunityCatalog.gift(id: id) != nil) }
                }
            }
        }
    }

    @Test func everyOfferMovesExactlyItsQuotedItemsOnceAndKeepsGold() throws {
        for offer in ExchangeCatalog.offers {
            var state = ready(friendship: 40)
            let before = state
            #expect(ExchangeCatalog.eligibility(of: offer, in: state) == nil)
            #expect(GameEngine.exchange(&state, offerID: offer.id, now: now).success == .exchanged)
            for stack in offer.inputs {
                let returned = offer.outputs.filter { $0.item == stack.item }.reduce(0) { $0 + $1.quantity }
                #expect(stack.item.count(in: state.inventory) == stack.item.count(in: before.inventory) - stack.quantity + returned)
            }
            for stack in offer.outputs {
                let paid = offer.inputs.filter { $0.item == stack.item }.reduce(0) { $0 + $1.quantity }
                #expect(stack.item.count(in: state.inventory) == stack.item.count(in: before.inventory) + stack.quantity - paid)
            }
            #expect(state.player.gold == before.player.gold)
            #expect(state.community.exchangeCount(for: offer.neighborID) == .init(today: 1, total: 1))
            #expect(state.community.relationship(for: offer.neighborID).friendship == 42)
            #expect(try reload(state) == state)
        }
    }

    @Test func missingLockedMaterialAndCapacityFailuresNeverChargeOrConsumeDailySlot() throws {
        var state = ready()
        let original = state
        #expect(GameEngine.exchange(&state, offerID: "missing", now: now).failure == .exchangeMissing)
        #expect(GameEngine.exchange(&state, offerID: "mira_feast", now: now).failure == .exchangeStageRequired)
        #expect(state == original)
        state.inventory.food = 1
        let poor = state
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).failure == .exchangeMaterialsRequired)
        #expect(state == poor)
        state.inventory.food = 2
        state.inventory.premiumFood = GameSnapshot.maximumStock
        let full = state
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).failure == .shopInventoryFull)
        #expect(state == full)
        state = ready(friendship: 40)
        state.inventory.premiumLitter = GameSnapshot.maximumStock
        let secondOutputFull = state
        #expect(GameEngine.exchange(&state, offerID: "grace_care", now: now).failure == .shopInventoryFull)
        #expect(state == secondOutputFull && state.inventory.premiumFood == 0)
        let lockedOffer = try #require(ExchangeCatalog.offer(id: "grace_care"))
        #expect(ExchangeCatalog.eligibility(of: lockedOffer, in: state) == .shopInventoryFull)
    }

    @Test func bothOffersShareOneNeighborDailyLimitAcrossReload() throws {
        var state = ready(friendship: 40)
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).succeeded)
        state = try reload(state)
        #expect(GameEngine.exchange(&state, offerID: "mira_feast", now: now).succeeded)
        let capped = state
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).failure == .exchangeDailyLimit)
        #expect(state == capped)
        #expect(GameEngine.exchange(&state, offerID: "ken_toy", now: now).succeeded)
        #expect(state.community.dailyExchangeCount == 3 && state.community.totalExchangeCount == 3)
    }

    @Test func midnightResetsLimitsAndRollbackCannotGrantAnotherDay() throws {
        var state = ready()
        for _ in 0..<2 { #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).succeeded) }
        let originalDay = state.tasks.dailyDayKey
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: tomorrow).succeeded)
        #expect(state.tasks.dailyDayKey != originalDay)
        #expect(state.community.exchangeCount(for: mira) == .init(today: 1, total: 3))
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: tomorrow).succeeded)
        state = try reload(state)
        let beforeRollback = state
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).failure == .exchangeDailyLimit)
        #expect(state == beforeRollback)
    }

    @Test func westwardTravelStillCountsInOpenLedgerWithoutResettingIt() {
        var state = ready()
        state.tasks.dailyDayKey = GameTaskState.dayKey(for: now.addingTimeInterval(86_400))
        let openDay = state.tasks.dailyDayKey
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).succeeded)
        #expect(state.tasks.dailyDayKey == openDay && state.community.dailyExchangeCount == 1)
        let counts = state.community.exchangeCounts
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400)).succeeded)
        #expect(state.community.exchangeCounts == counts)
    }

    @Test func exchangeCanUnlockStageRewardOnlyOnceWithoutTruncatingTradedOutput() {
        var state = ready(friendship: 18)
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).amount == 2)
        #expect(state.community.relationship(for: mira).rewardedStageLevels == [2])
        #expect(state.inventory.food == 19 && state.inventory.premiumFood == 1 && state.player.gold == 220)
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).succeeded)
        #expect(state.inventory.food == 17 && state.inventory.premiumFood == 2 && state.player.gold == 220)
        state = ready(friendship: 100)
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).amount == 0)
        #expect(state.community.relationship(for: mira).friendship == 100)
        #expect(state.inventory.premiumFood == 1 && state.community.totalExchangeCount == 1)
    }

    @Test func exchangeGoalsUseSavedCountsHideClaimsAndRefreshOnlyDailyRewards() throws {
        var state = ready()
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).succeeded)
        for id in ["tutorial_exchange", "daily_exchange"] {
            let task = try #require(GameTaskCatalog.task(id: id))
            #expect(task.destination == .market && GameTaskCatalog.isClaimable(task, in: state))
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: state.tasks.dailyDayKey, now: now).succeeded)
            let paid = state
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: state.tasks.dailyDayKey, now: now).failure == .taskAlreadyClaimed)
            #expect(state == paid)
            #expect(!GameTaskCatalog.remainingTasks(in: state, category: task.category).contains { $0.id == id })
        }
        state = try reload(state)
        let claimedDay = state.tasks.dailyDayKey
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(GameEngine.synchronize(&state, now: tomorrow).succeeded)
        #expect(state.tasks.claimedTaskIDs.contains("tutorial_exchange"))
        #expect(!state.tasks.dailyClaimedTaskIDs.contains("daily_exchange") && state.community.dailyExchangeCount == 0)
        #expect(GameEngine.claimTask(&state, id: "daily_exchange", expectedDayKey: claimedDay, now: tomorrow).failure == .taskDayChanged)
        state.community.exchangeCounts[mira] = .init(today: 0, total: 30)
        for id in ["achievement_exchange10", "achievement_exchange30"] {
            let task = try #require(GameTaskCatalog.task(id: id))
            #expect(GameTaskCatalog.isClaimable(task, in: state))
        }
    }
}
