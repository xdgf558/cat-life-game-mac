import Foundation
import Testing
@testable import CatGameCore

@Suite("Public actions retain synchronized progress")
struct ActionSynchronizationTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func careAccountsForElapsedDecayBeforeResettingItsTrackers() {
        var state = GameSnapshot.fresh(now: now)
        let later = now.addingTimeInterval(1440)
        #expect(GameEngine.feed(&state, catID: "cat_001", now: later).succeeded)
        #expect(state.cats[0].satiety == 58) // 35 - 2 elapsed points + 25 food.
        #expect(state.cats[0].mood == 85) // 85 - 4 elapsed points + 4 food.
        #expect(state.cats[0].cleanliness == 72)
        #expect(state.cats[0].decayTracker.satiety == later)
        #expect(state.meta.lastSyncAt == later)
    }

    @Test func failedActionKeepsCompletedWorkAndPassiveProgressWithoutSpendingResources() {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.food = 0
        _ = GameEngine.startWork(&state, now: now)
        let workID = state.player.activeWork?.id
        let inventory = state.inventory
        let later = now.addingTimeInterval(1440)
        let outcome = GameEngine.feed(&state, catID: "cat_001", now: later)
        #expect(!outcome.succeeded && outcome.messageKey == "care.foodRequired")
        #expect(state.player.gold == 260 && state.player.exp == 22)
        #expect(state.player.lastWorkResult?.id == workID && state.player.activeWork == nil)
        #expect(state.player.completedWorkCount == 1)
        #expect(state.cats[0].satiety == 33 && state.cats[0].mood == 81)
        #expect(state.inventory == inventory && state.meta.lastSyncAt == later)
        let settled = state
        #expect(!GameEngine.feed(&state, catID: "cat_001", now: later).succeeded)
        #expect(state == settled)
    }

    @Test func elapsedStaminaAndCompletedWagesAreAvailableToTheRequestedAction() {
        var worker = GameSnapshot.fresh(now: now)
        worker.player.stamina = 5
        #expect(GameEngine.startWork(&worker, now: now.addingTimeInterval(3600)).succeeded)
        #expect(worker.player.stamina == 0)
        #expect(worker.player.activeWork?.startedAt == now.addingTimeInterval(3600))

        var shopper = GameSnapshot.fresh(now: now)
        shopper.player.gold = 0
        _ = GameEngine.startWork(&shopper, now: now)
        #expect(GameEngine.buyFood(&shopper, quantity: 3, now: now.addingTimeInterval(120)).succeeded)
        #expect(shopper.player.gold == 0 && shopper.inventory.food == 6)
        #expect(shopper.player.lastWorkResult?.goldReward == 60 && shopper.player.exp == 22)
    }

    @Test func everyPublicActionMatchesExplicitSynchronizationAtTheSameTime() {
        typealias Action = (inout GameSnapshot, Date) -> ActionOutcome
        let actions: [(String, Action)] = [
            ("avatar", { GameEngine.selectAvatar(&$0, avatarID: "female_scholarly", now: $1) }),
            ("equip", { GameEngine.equipItem(&$0, itemID: "starter_cap", now: $1) }),
            ("unequip", { GameEngine.unequipSlot(&$0, slot: .head, now: $1) }),
            ("starter", { GameEngine.equipStarterSet(&$0, now: $1) }),
            ("sleep", { GameEngine.startSleep(&$0, now: $1) }),
            ("wake", { GameEngine.wakeUp(&$0, now: $1) }),
            ("rest", { GameEngine.startCatRest(&$0, catID: "cat_001", furnitureID: "catBed", sessionID: "new-rest", now: $1) }),
            ("exit", { GameEngine.endCatRest(&$0, catID: "cat_001", sessionID: "old-rest", now: $1) }),
            ("feed", { GameEngine.feed(&$0, catID: "cat_001", now: $1) }),
            ("clean", { GameEngine.clean(&$0, catID: "cat_001", now: $1) }),
            ("play", { GameEngine.play(&$0, catID: "cat_001", now: $1) }),
            ("food", { GameEngine.buyFood(&$0, now: $1) }),
            ("litter", { GameEngine.buyLitter(&$0, now: $1) }),
            ("toy", { GameEngine.buyToy(&$0, now: $1) }),
            ("visit", { GameEngine.visitNeighbor(&$0, neighborID: "neighbor_mira", now: $1) }),
            ("gift", { GameEngine.giveNeighborGift(&$0, neighborID: "neighbor_mira", giftID: "flower", now: $1) }),
            ("buyGift", { GameEngine.buyCommunityGift(&$0, giftID: "flower", now: $1) }),
            ("exchange", { GameEngine.exchange(&$0, offerID: "mira_food", now: $1) }),
            ("premiumPurchase", { GameEngine.buySupply(&$0, kind: .premiumFood, now: $1) }),
            ("premiumFeed", { GameEngine.feed(&$0, catID: "cat_001", supply: .premiumFood, now: $1) }),
            ("premiumClean", { GameEngine.clean(&$0, catID: "cat_001", supply: .premiumLitter, now: $1) }),
            ("work", { GameEngine.startWork(&$0, now: $1) }),
            ("bowl", { GameEngine.setBowlPosition(&$0, .init(x: 0.6, y: 0.7), now: $1) }),
            ("layout", { state, time in
                GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.6, y: 0.7),
                    furniture: state.home.furniture.filter { $0.itemID != "catBed" }, now: time)
            })
        ]
        var original = GameSnapshot.fresh(now: now)
        original.inventory.toys = 1
        original.inventory.premiumFood = 1
        original.inventory.premiumLitter = 1
        original.inventory.gifts["flower"] = 1
        _ = GameEngine.startWork(&original, now: now)
        _ = GameEngine.startCatRest(&original, catID: "cat_001", furnitureID: "catBed", sessionID: "old-rest", now: now)
        let later = now.addingTimeInterval(1440)
        for (name, action) in actions {
            var direct = original
            var explicitlySynchronized = original
            _ = GameEngine.synchronize(&explicitlySynchronized, now: later)
            let directOutcome = action(&direct, later)
            let explicitOutcome = action(&explicitlySynchronized, later)
            // Starting two equivalent shifts allocates different UUIDs, not different terms.
            if direct.player.activeWork != nil {
                direct.player.activeWork?.id = explicitlySynchronized.player.activeWork!.id
            }
            #expect(directOutcome == explicitOutcome, "\(name)")
            #expect(direct == explicitlySynchronized, "\(name)")
            #expect(direct.isValid)
        }
    }
}
