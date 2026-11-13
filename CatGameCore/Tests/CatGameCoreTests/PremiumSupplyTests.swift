import Foundation
import Testing
@testable import CatGameCore

@Suite("Premium supplies are independent stock and preserve ordinary care")
struct PremiumSupplyTests {
    let now = Date(timeIntervalSince1970: 1_793_600_000)

    @Test func purchaseEnforcesLevelsPriceAndStockWithoutReplacingBasicSupplies() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        #expect(GameEngine.buySupply(&state, kind: .premiumFood, now: now).failure == .shopLevelRequired)
        #expect(state == original)
        state.player.level = 2
        #expect(GameEngine.buySupply(&state, kind: .premiumFood, quantity: 2, now: now).amount == 2)
        #expect(state.player.gold == 120 && state.inventory.premiumFood == 2 && state.inventory.food == 3)
        let beforeLitter = state
        #expect(GameEngine.buySupply(&state, kind: .premiumLitter, now: now).failure == .shopLevelRequired)
        #expect(state == beforeLitter)
        state.player.level = 3
        #expect(GameEngine.buySupply(&state, kind: .premiumLitter, now: now).success == .supplyPurchased)
        #expect(state.player.gold == 75 && state.inventory.premiumLitter == 1 && state.inventory.litter == 2)
        let beforeFailure = state
        #expect(GameEngine.buySupply(&state, kind: .premiumLitter, quantity: 2, now: now).failure == .shopGoldRequired)
        #expect(GameEngine.buySupply(&state, kind: .premiumFood, quantity: 0, now: now).failure == .shopInvalidQuantity)
        #expect(state == beforeFailure)
        state.inventory.premiumFood = GameSnapshot.maximumStock
        let full = state
        #expect(GameEngine.buySupply(&state, kind: .premiumFood, now: now).failure == .shopInventoryFull)
        #expect(state == full)
    }

    @Test func premiumFoodUsesItsOwnStockAndFeedsExistingTasks() {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.premiumFood = 2
        let catID = state.activeCatID
        let basicStock = state.inventory.food
        #expect(GameEngine.feed(&state, catID: catID, supply: .premiumFood, now: now).success == .fed)
        #expect(state.inventory.premiumFood == 1 && state.inventory.food == basicStock)
        #expect(state.cats[0].satiety == 90 && state.cats[0].mood == 90 && state.cats[0].intimacy == 15)
        #expect(state.tasks.dailyFeedCount == 1 && state.tasks.totalFeedCount == 1)
        #expect(GameEngine.feed(&state, catID: catID, supply: .premiumFood, now: now).succeeded)
        #expect(state.cats[0].satiety == 100 && state.cats[0].intimacy == 18)
        let empty = state
        #expect(GameEngine.feed(&state, catID: catID, supply: .premiumFood, now: now).failure == .carePremiumFoodRequired)
        #expect(state == empty)
        #expect(GameEngine.feed(&state, catID: catID, now: now).succeeded)
        #expect(state.inventory.food == basicStock - 1 && state.cats[0].intimacy == 18)
    }

    @Test func pregnantCatsNeedTwoUnitsOfTheSelectedFoodWithoutMixingTiers() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].growthState = .init(recordedSince: now, adoptedAt: now, initialAgeDays: 365, sex: .female)
        state.cats[0].isPregnant = true
        state.inventory.premiumFood = 1
        let original = state
        #expect(GameEngine.feed(&state, catID: state.activeCatID, supply: .premiumFood, now: now).failure == .carePremiumFoodRequired)
        #expect(state == original)
        state.inventory.premiumFood = 2
        #expect(GameEngine.feed(&state, catID: state.activeCatID, supply: .premiumFood, now: now).amount == 2)
        #expect(state.inventory.premiumFood == 0 && state.inventory.food == 3 && state.tasks.totalFeedCount == 1)
    }

    @Test func premiumLitterImprovesCleanlinessButDoesNotTreatAnExistingIllness() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].cleanliness = 20
        state.cats[0].health = 70
        state.cats[0].healthState?.illness = .cold
        state.inventory.premiumLitter = 1
        #expect(GameEngine.clean(&state, catID: state.activeCatID, supply: .premiumLitter, now: now).success == .cleaned)
        #expect(state.inventory.premiumLitter == 0 && state.inventory.litter == 2)
        #expect(state.cats[0].cleanliness == 85 && state.cats[0].health == 75)
        #expect(state.cats[0].healthState?.illness == .cold)
        #expect(state.tasks.totalCleanCount == 1 && state.tasks.dailyCleanCount == 1)
        let empty = state
        #expect(GameEngine.clean(&state, catID: state.activeCatID, supply: .premiumLitter, now: now).failure == .carePremiumLitterRequired)
        #expect(state == empty)
    }

    @Test func wrongSupplyKindCannotBeSpentByCare() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        #expect(GameEngine.feed(&state, catID: state.activeCatID, supply: .litter, now: now).failure == .careSupplyInvalid)
        #expect(GameEngine.clean(&state, catID: state.activeCatID, supply: .premiumFood, now: now).failure == .careSupplyInvalid)
        #expect(state == original)
    }

    @Test func selectedPremiumCareStopsRestAndRetainsLowEnergyRisk() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].energy = 5
        state.cats[0].healthState?.riskPoints = 4
        state.inventory.premiumFood = 1
        #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: "catBed",
                                        sessionID: "premium-care", now: now).succeeded)
        #expect(GameEngine.feed(&state, catID: state.activeCatID, supply: .premiumFood, now: now).succeeded)
        #expect(state.cats[0].activeRest == nil && state.cats[0].healthState?.riskPoints == 4)
    }
}
