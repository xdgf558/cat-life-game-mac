import Foundation
import Testing
@testable import CatGameCore

struct ActionFailureTests {
    @Test func resourceFailuresCarryTypedReasonsWithoutMatchingText() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var state = GameSnapshot.fresh(now: date)
        state.player.gold = 0
        let purchase = GameEngine.buyFood(&state, now: date)
        #expect(!purchase.succeeded)
        #expect(purchase.failure == .shopGoldRequired)
        #expect(purchase.amount == GameEngine.foodPrice)
        state.inventory.food = 0
        let feed = GameEngine.feed(&state, catID: state.cats[0].id, now: date)
        #expect(feed.failure == .careFoodRequired)
        #expect(feed.messageKey == "care.foodRequired")
        #expect(state.inventory.food == 0)
    }

    @Test func careerLockAndSuccessHaveDistinctFailureState() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var state = GameSnapshot.fresh(now: date)
        let locked = GameEngine.startWork(&state, jobID: "job_it_engineer", now: date)
        #expect(locked.failure == .workLevelRequired)
        #expect(state.player.activeWork == nil)
        let started = GameEngine.startWork(&state, now: date)
        #expect(started.succeeded)
        #expect(started.failure == nil)
    }
}
