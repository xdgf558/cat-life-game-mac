import Foundation
import Testing
@testable import CatGameCore

@Suite("Neighbor visits, gift inventory and durable friendship")
struct CommunityTests {
    let now = Date(timeIntervalSince1970: 1_793_600_000)
    let mira = "neighbor_mira"

    func ready(friendship: Int = 0) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.gold = 1_000
        state.inventory.gifts = ["flower": 10, "drink": 10, "dessert": 10, "cat_snack": 10]
        state.community.relationships[mira]?.friendship = friendship
        state.community.relationships[mira]?.rewardedStageLevels = CommunityCatalog.stages
            .filter { $0.level > 1 && $0.minimumPoints <= friendship }.map(\.level)
        return state
    }

    func reload(_ state: GameSnapshot) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state))
    }

    @Test func allFourNeighborsHaveBuyableFavoriteGiftsAndStableStages() throws {
        #expect(CommunityCatalog.neighbors.map(\.id) == [mira, "neighbor_ken", "neighbor_luna", "neighbor_grace"])
        #expect(Set(CommunityCatalog.gifts.map(\.id)).count == 4)
        for neighbor in CommunityCatalog.neighbors {
            #expect(!neighbor.favoriteGiftIDs.isEmpty)
            #expect(neighbor.favoriteGiftIDs.allSatisfy { CommunityCatalog.gift(id: $0) != nil })
        }
        #expect(CommunityCatalog.stages.map(\.minimumPoints) == [0, 20, 40, 60, 80])
        #expect(CommunityCatalog.nextStage(friendship: 100) == nil)
        #expect(CommunityCatalog.giftFriendship(neighborID: mira, giftID: "missing") == 0)
    }

    @Test func firstVisitCountsOnceAcrossRepeatsAndRelaunch() throws {
        var state = ready()
        let first = GameEngine.visitNeighbor(&state, neighborID: mira, now: now)
        #expect(first.success == .neighborVisited && first.amount == 2)
        #expect(state.community.relationship(for: mira).visitedToday)
        #expect(state.community.dailyVisitCount == 1 && state.community.totalVisitCount == 1)
        #expect(state.community.relationship(for: mira).friendship == 2)
        state = try reload(state)
        let before = state
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).success == .neighborChatted)
        #expect(state == before)
    }

    @Test func dayRolloverRestoresOneVisitAndGiftButClockRollbackDoesNot() throws {
        var state = ready()
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).succeeded)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now).succeeded)
        let firstDay = state.tasks.dailyDayKey
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(GameEngine.synchronize(&state, now: tomorrow).succeeded)
        #expect(state.tasks.dailyDayKey != firstDay)
        #expect(state.community.dailyVisitCount == 0 && state.community.dailyGiftCount == 0)
        #expect(state.community.totalVisitCount == 1 && state.community.totalGiftCount == 1)
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: tomorrow).success == .neighborVisited)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: tomorrow).succeeded)
        state = try reload(state)
        let before = state
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).success == .neighborChatted)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now).failure == .communityGiftLimit)
        #expect(state == before)
    }

    @Test func westwardTravelCountsImmediateActionsInTheOpenDay() throws {
        var state = ready()
        state.tasks.dailyDayKey = GameTaskState.dayKey(for: now.addingTimeInterval(86_400))
        let openDay = state.tasks.dailyDayKey
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).success == .neighborVisited)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now).succeeded)
        #expect(state.tasks.dailyDayKey == openDay)
        #expect(state.community.dailyVisitCount == 1 && state.community.dailyGiftCount == 1)
        let before = state.community
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400)).succeeded)
        #expect(state.community == before)
    }

    @Test func giftsUsePreferenceAndOneDailySlotPerNeighbor() throws {
        var state = ready()
        let favorite = GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now)
        #expect(favorite.success == .neighborGifted && favorite.amount == 8)
        #expect(state.inventory.giftCount("flower") == 9 && state.community.totalGiftCount == 1)
        let before = state
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "drink", now: now).failure == .communityGiftLimit)
        #expect(state == before)
        let ordinary = GameEngine.giveNeighborGift(&state, neighborID: "neighbor_luna", giftID: "drink", now: now)
        #expect(ordinary.success == .neighborGifted && ordinary.amount == 4)
        #expect(state.inventory.giftCount("drink") == 9 && state.community.dailyGiftCount == 2)
    }

    @Test func purchaseAndGiftFailuresNeverChangeMoneyStockOrFriendship() {
        var state = ready()
        let original = state
        #expect(GameEngine.buyCommunityGift(&state, giftID: "flower", quantity: 0, now: now).failure == .shopInvalidQuantity)
        #expect(GameEngine.buyCommunityGift(&state, giftID: "missing", now: now).failure == .communityGiftMissing)
        #expect(GameEngine.visitNeighbor(&state, neighborID: "missing", now: now).failure == .neighborMissing)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "missing", now: now).failure == .communityGiftMissing)
        #expect(state == original)
        state.inventory.gifts["flower"] = 0
        let empty = state
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now).failure == .communityGiftRequired)
        #expect(state == empty)
        state.player.gold = 19
        let poor = state
        #expect(GameEngine.buyCommunityGift(&state, giftID: "flower", now: now).failure == .shopGoldRequired)
        #expect(state == poor)
        state.player.gold = 100
        state.inventory.gifts["flower"] = GameSnapshot.maximumStock
        let full = state
        #expect(GameEngine.buyCommunityGift(&state, giftID: "flower", now: now).failure == .shopInventoryFull)
        #expect(state == full)
    }

    @Test func purchasesAreAtomicAndRoundTripAsIndependentGiftInventory() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.buyCommunityGift(&state, giftID: "flower", quantity: 3, now: now).amount == 60)
        #expect(state.player.gold == 140 && state.inventory.giftCount("flower") == 3)
        #expect(state.inventory.food == 3 && state.inventory.litter == 2 && state.inventory.toys == 0)
        #expect(try reload(state) == state)
    }

    @Test func everyStagePaysItsSuppliesAndGoldOnceWithFriendship() throws {
        for stage in CommunityCatalog.stages where stage.level > 1 {
            var state = ready(friendship: stage.minimumPoints - 1)
            let gold = state.player.gold
            let food = state.inventory.food
            let litter = state.inventory.litter
            let toys = state.inventory.toys
            #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).succeeded)
            #expect(state.player.gold == gold + stage.goldReward)
            #expect(state.inventory.food == food + stage.foodReward)
            #expect(state.inventory.litter == litter + stage.litterReward)
            #expect(state.inventory.toys == toys + stage.toyUsesReward)
            #expect(state.community.relationship(for: mira).rewardedStageLevels.contains(stage.level))
            state = try reload(state)
            let paid = state
            #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).success == .neighborChatted)
            #expect(state == paid)
        }
    }

    @Test func fullWalletAndSuppliesDoNotBlockRelationshipOrReplayRewards() throws {
        var state = ready(friendship: 79)
        state.player.gold = GameSnapshot.maximumGold
        state.inventory.toys = GameSnapshot.maximumStock
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).succeeded)
        #expect(state.player.gold == GameSnapshot.maximumGold && state.inventory.toys == GameSnapshot.maximumStock)
        #expect(state.community.relationship(for: mira).friendship == 81)
        state.player.gold -= 100
        state.inventory.toys -= 6
        state = try reload(state)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now).succeeded)
        #expect(state.player.gold == GameSnapshot.maximumGold - 100 && state.inventory.toys == GameSnapshot.maximumStock - 6)
    }

    @Test func maxFriendshipStillAllowsDailySocialTasksWithoutExceedingCap() {
        var state = ready(friendship: 100)
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).amount == 0)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now).amount == 0)
        #expect(state.community.relationship(for: mira).friendship == 100)
        #expect(state.community.dailyVisitCount == 1 && state.community.dailyGiftCount == 1)
        #expect(state.inventory.giftCount("flower") == 9)
    }

    @Test func fourSocialTasksReadSharedProgressAndCannotBeClaimedTwice() throws {
        var state = ready(friendship: 39)
        state.player.level = 4
        state.community.relationships[mira]?.totalVisitCount = 9
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).succeeded)
        #expect(GameEngine.giveNeighborGift(&state, neighborID: mira, giftID: "flower", now: now).succeeded)
        for id in ["daily_visit", "daily_gift", "achievement_visit10", "achievement_friend40"] {
            let task = try #require(GameTaskCatalog.task(id: id))
            #expect(task.destination == .neighbors && GameTaskCatalog.isClaimable(task, in: state))
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: state.tasks.dailyDayKey, now: now).succeeded)
            state = try reload(state)
            let paid = state
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: state.tasks.dailyDayKey, now: now).failure == .taskAlreadyClaimed)
            #expect(state == paid)
        }
    }

    @Test func invalidActionStillKeepsElapsedWorkAndDailyRollover() {
        var state = ready()
        #expect(GameEngine.visitNeighbor(&state, neighborID: mira, now: now).succeeded)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let gold = state.player.gold
        #expect(GameEngine.giveNeighborGift(&state, neighborID: "missing", giftID: "flower",
                                          now: now.addingTimeInterval(86_400)).failure == .neighborMissing)
        #expect(state.player.activeWork == nil && state.player.completedWorkCount == 1 && state.player.gold > gold)
        #expect(state.community.dailyVisitCount == 0 && state.community.totalVisitCount == 1)
    }
}
