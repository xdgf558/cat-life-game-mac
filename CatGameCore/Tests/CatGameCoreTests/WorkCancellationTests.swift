import Foundation
import Testing
@testable import CatGameCore

@Suite("Early shift cancellation")
struct WorkCancellationTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)
    @Test func earlyCancellationPaysNothingAndNeverRefundsUpfrontCosts() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let started = state.player
        #expect(GameEngine.cancelWork(&state, now: now).success == .workCancelled)
        #expect(state.player.activeWork == nil)
        #expect(state.player.gold == started.gold && state.player.exp == started.exp)
        #expect(state.player.stamina == started.stamina && state.player.mood == started.mood)
        #expect(state.player.completedWorkCount == started.completedWorkCount)
        #expect(state.player.lastWorkResult == started.lastWorkResult)
        #expect(state.isValid)
        let cancelled = state
        #expect(GameEngine.cancelWork(&state, now: now).succeeded)
        #expect(state == cancelled)
    }
    @Test func confirmationAfterDeadlineSettlesExactlyOnce() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let work = try #require(state.player.activeWork)
        let gold = state.player.gold
        #expect(GameEngine.cancelWork(&state, now: work.endsAt).succeeded)
        #expect(state.player.gold == gold + work.goldReward)
        #expect(state.player.completedWorkCount == 1)
        #expect(state.player.lastWorkResult?.id == work.id)
        let settled = state
        #expect(GameEngine.cancelWork(&state, now: work.endsAt).succeeded)
        #expect(state == settled)
    }
    @Test func rollbackDoesNotRestoreSpentResources() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.startWork(&state, now: now)
        let stamina = state.player.stamina
        #expect(GameEngine.cancelWork(&state, now: now.addingTimeInterval(-3600)).succeeded)
        #expect(state.meta.lastSyncAt == now)
        #expect(state.player.stamina == stamina)
        #expect(state.player.completedWorkCount == 0)
    }
}
