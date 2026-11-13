import Foundation
import Testing
@testable import CatGameCore

@Suite("Native game rules")
struct GameEngineTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func previewStateMatchesApprovedHome() {
        let state = GameSnapshot.fresh(now: now)
        #expect(state.player.gold == 200)
        #expect(state.player.stamina == 80)
        #expect(state.inventory.food == 3)
        #expect(state.inventory.toys == 0)
        #expect(state.cats[0].id == "cat_001")
        #expect(state.cats[0].name == "小橘")
        #expect(state.cats[0].satiety == 35)
    }

    @Test func feedingConsumesFoodAndAppliesWebRule() {
        var state = GameSnapshot.fresh(now: now)
        let outcome = GameEngine.feed(&state, catID: "cat_001", now: now)
        #expect(outcome == ActionOutcome(success: .fed, amount: 1))
        #expect(state.inventory.food == 2)
        #expect(state.cats[0].satiety == 60)
        #expect(state.cats[0].mood == 89)
    }

    @Test func feedingCapsStatsAndResetsOnlyAffectedTrackers() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].satiety = 90
        state.cats[0].mood = 99
        let later = now.addingTimeInterval(60)
        _ = GameEngine.feed(&state, catID: "cat_001", now: later)
        #expect(state.cats[0].satiety == 100)
        #expect(state.cats[0].mood == 100)
        #expect(state.cats[0].decayTracker.satiety == later)
        #expect(state.cats[0].decayTracker.cleanliness == now)
    }

    @Test func pregnantCatConsumesTwoServings() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].growthState = .init(recordedSince: now, adoptedAt: now, initialAgeDays: 365, sex: .female)
        state.cats[0].isPregnant = true
        let outcome = GameEngine.feed(&state, catID: "cat_001", now: now)
        #expect(outcome.succeeded)
        #expect(outcome.amount == 2)
        #expect(state.inventory.food == 1)
        #expect(state.cats[0].satiety == 60)
    }

    @Test func insufficientFoodDoesNotPartiallyMutatePregnantCat() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].growthState = .init(recordedSince: now, adoptedAt: now, initialAgeDays: 365, sex: .female)
        state.cats[0].isPregnant = true
        state.inventory.food = 1
        let before = state
        let outcome = GameEngine.feed(&state, catID: "cat_001", now: now)
        #expect(!outcome.succeeded)
        #expect(outcome.messageKey == "care.foodRequired")
        #expect(outcome.amount == 2)
        #expect(state == before)
    }

    @Test func unknownCatCannotConsumeResources() {
        var state = GameSnapshot.fresh(now: now)
        let before = state
        #expect(!GameEngine.feed(&state, catID: "missing", now: now).succeeded)
        #expect(state == before)
    }

    @Test func cleaningConsumesLitterAndIncreasesHealth() {
        var state = GameSnapshot.fresh(now: now)
        let outcome = GameEngine.clean(&state, catID: "cat_001", now: now)
        #expect(outcome.kind == .clean)
        #expect(state.inventory.litter == 1)
        #expect(state.cats[0].cleanliness == 100)
        #expect(state.cats[0].health == 94)
        state.inventory.litter = 0
        let before = state
        #expect(!GameEngine.clean(&state, catID: "cat_001", now: now).succeeded)
        #expect(state == before)
    }

    @Test func playingRequiresToyUses() {
        var state = GameSnapshot.fresh(now: now)
        let before = state
        let outcome = GameEngine.play(&state, catID: "cat_001", now: now)
        #expect(!outcome.succeeded)
        #expect(outcome.messageKey == "care.toyRequired")
        #expect(state == before)
    }

    @Test func boughtToySuppliesSixUsesAndMatchesWebPlayBonuses() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].mood = 40
        let purchased = GameEngine.buyToy(&state, now: now)
        #expect(purchased.amount == 6)
        #expect(state.player.gold == 165)
        #expect(state.inventory.toys == 6)
        #expect(GameEngine.play(&state, catID: "cat_001", now: now).succeeded)
        #expect(state.inventory.toys == 5)
        #expect(state.cats[0].mood == 59)
        #expect(state.cats[0].intimacy == 24)
        #expect(state.cats[0].energy == 70)
        #expect(state.player.mood == 84)
    }

    @Test func storeChargesCorrectPrices() {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.buyFood(&state, quantity: 2, now: now).amount == 2)
        #expect(state.inventory.food == 5)
        #expect(state.player.gold == 160)
        #expect(GameEngine.buyLitter(&state, quantity: 1, now: now).succeeded)
        #expect(state.inventory.litter == 3)
        #expect(state.player.gold == 142)
    }

    @Test func invalidQuantityAndInsufficientGoldDoNotMutate() {
        var state = GameSnapshot.fresh(now: now)
        let before = state
        for quantity in [-1, 0, Int.max] {
            #expect(!GameEngine.buyFood(&state, quantity: quantity, now: now).succeeded)
            #expect(state == before)
        }
        #expect(!GameEngine.buyFood(&state, quantity: 11, now: now).succeeded)
        #expect(state == before)
    }

    @Test func workCompletesAtBoundaryOnlyOnce() {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.startWork(&state, now: now).kind == .workStarted)
        #expect(state.player.stamina == 70)
        #expect(state.player.mood == 75)
        #expect(state.player.activeWork?.goldReward == 60)
        #expect(state.player.activeWork?.endsAt == now.addingTimeInterval(120))
        let beforeDuplicate = state
        #expect(!GameEngine.startWork(&state, now: now).succeeded)
        #expect(state == beforeDuplicate)
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(119)).kind == .none)
        #expect(state.player.gold == 200)
        let completed = GameEngine.synchronize(&state, now: now.addingTimeInterval(120))
        #expect(completed.kind == .workFinished)
        #expect(completed.amount == 60)
        #expect(state.player.gold == 260)
        #expect(state.player.activeWork == nil)
        #expect(state.player.completedWorkCount == 1)
        let after = state
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(120)).kind == .none)
        #expect(state == after)
    }

    @Test func cannotStartWorkWithoutStamina() {
        var state = GameSnapshot.fresh(now: now)
        state.player.stamina = 9
        let before = state
        #expect(!GameEngine.startWork(&state, now: now).succeeded)
        #expect(state == before)
    }

    @Test func offlineIntervalsKeepRemainderAndAreIdempotent() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(719))
        #expect(state.cats[0].satiety == 35)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(720))
        #expect(state.cats[0].satiety == 34)
        #expect(state.cats[0].cleanliness == 74)
        #expect(state.cats[0].mood == 83)
        #expect(state.cats[0].energy == 78)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(1439))
        #expect(state.cats[0].satiety == 34)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(1440))
        #expect(state.cats[0].satiety == 33)
        let before = state
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(1440))
        #expect(state == before)
    }

    @Test func clockRollbackCannotReverseProgressOrMoveTrackersBack() {
        var state = GameSnapshot.fresh(now: now)
        let later = now.addingTimeInterval(720)
        _ = GameEngine.synchronize(&state, now: later)
        let after = state
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(-60))
        #expect(state == after)
        _ = GameEngine.feed(&state, catID: "cat_001", now: now)
        #expect(state.cats[0].decayTracker.satiety == later)
    }

    @Test func longAbsenceClampsStatsAndRestoresStamina() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(60 * 60 * 24 * 365))
        #expect(state.cats[0].satiety == 0)
        #expect(state.cats[0].cleanliness == 0)
        #expect(state.player.stamina == 100)
        #expect(state.isValid)
    }

    @Test func bowlCoordinatesClampAndInvalidNumbersAreRejected() {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.setBowlPosition(&state, .init(x: -1, y: 2), now: now).succeeded)
        #expect(state.home.bowlPosition == .init(x: 0, y: 1))
        let before = state
        #expect(!GameEngine.setBowlPosition(&state, .init(x: .nan, y: 0.5), now: now).succeeded)
        #expect(state == before)
    }

    @Test func invalidSnapshotIsNotMutated() {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.food = -1
        let before = state
        #expect(!GameEngine.feed(&state, catID: "cat_001", now: now).succeeded)
        #expect(state == before)
    }
}
