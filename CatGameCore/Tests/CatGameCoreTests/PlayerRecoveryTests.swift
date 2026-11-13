import Foundation
import Testing
@testable import CatGameCore

@Suite("Player supplies, café dine-in and café nap")
struct PlayerRecoveryTests {
    var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = .current; return value }
    /// Inside café hours (10:00–22:00 local).
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))! }

    func state(stamina: Int = 40, mood: Int = 40, gold: Int = 2_000) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.stamina = stamina
        state.player.mood = mood
        state.player.gold = gold
        return state
    }

    @Test func buyingRespectsCarryLimitAndGold() {
        var s = state()
        #expect(GameEngine.buyPlayerSupply(&s, kind: .riceBall, quantity: 5, now: now).succeeded)
        #expect(s.player.carried(.riceBall) == 5 && s.player.gold == 2_000 - 5 * 120)
        #expect(GameEngine.buyPlayerSupply(&s, kind: .riceBall, now: now).failure == .supplyCarryLimit)
        var poor = state(gold: 50)
        #expect(GameEngine.buyPlayerSupply(&poor, kind: .flowerTea, now: now).failure == .shopGoldRequired)
        #expect(poor.player.carried(.flowerTea) == 0 && poor.player.gold == 50)
    }

    @Test func fullAttributesNeverConsumeAnItemOrPortion() {
        var s = state(mood: 100)
        _ = GameEngine.buyPlayerSupply(&s, kind: .flowerTea, now: now)
        #expect(GameEngine.usePlayerSupply(&s, kind: .flowerTea, now: now).failure == .recoveryFull)
        #expect(s.player.carried(.flowerTea) == 1 && s.suppliesUsedToday == 0)
    }

    @Test func overflowIsAllowedAndCappedAtOneHundred() {
        var s = state(stamina: 92)
        _ = GameEngine.buyPlayerSupply(&s, kind: .riceBall, now: now)
        let outcome = GameEngine.usePlayerSupply(&s, kind: .riceBall, now: now)
        #expect(outcome.success == .playerSupplyUsed && outcome.amount == 8)
        #expect(s.player.stamina == 100 && s.player.carried(.riceBall) == 0 && s.suppliesUsedToday == 1)
    }

    @Test func compositeEffectIsUsefulWhileEitherAttributeIsBelowFull() {
        var s = state(stamina: 100, mood: 50)
        _ = GameEngine.buyPlayerSupply(&s, kind: .dessert, now: now)
        #expect(GameEngine.usePlayerSupply(&s, kind: .dessert, now: now).succeeded)
        #expect(s.player.stamina == 100 && s.player.mood == 62)
    }

    @Test func carriedSuppliesAndCafeItemsShareTheDailyLimitWhichResetsNextDay() throws {
        var s = state(stamina: 10, mood: 10)
        _ = GameEngine.buyPlayerSupply(&s, kind: .riceBall, quantity: 3, now: now)
        #expect(GameEngine.usePlayerSupply(&s, kind: .riceBall, now: now).succeeded)
        #expect(GameEngine.orderCafeItem(&s, kind: .latte, now: now).succeeded)
        #expect(GameEngine.usePlayerSupply(&s, kind: .riceBall, now: now).succeeded)
        #expect(s.suppliesLeftToday == 0)
        #expect(GameEngine.usePlayerSupply(&s, kind: .riceBall, now: now).failure == .recoveryDailyLimit)
        #expect(GameEngine.orderCafeItem(&s, kind: .pancake, now: now).failure == .recoveryDailyLimit)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        _ = GameEngine.synchronize(&s, now: tomorrow)
        #expect(s.suppliesUsedToday == 0 && s.suppliesLeftToday == PlayerSupplyCatalog.dailyLimit)
    }

    @Test func cafeIsClosedOutsideOpeningHours() throws {
        let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23)))
        var s = GameSnapshot.fresh(now: late)
        s.player.mood = 20
        #expect(GameEngine.orderCafeItem(&s, kind: .latte, now: late).failure == .cafeClosed)
        #expect(GameEngine.startCafeNap(&s, now: late).failure == .cafeClosed)
    }

    @Test func napCompletesInTheBackgroundAndBlocksWorkMeanwhile() {
        var s = state()
        #expect(GameEngine.startCafeNap(&s, now: now).success == .cafeNapStarted)
        #expect(s.player.gold == 2_000 - CafeCatalog.napPrice && s.napUsedToday)
        #expect(GameEngine.startWork(&s, now: now.addingTimeInterval(60)).failure == .workNapping)
        _ = GameEngine.synchronize(&s, now: now.addingTimeInterval(CafeCatalog.napDuration + 1))
        #expect(s.player.activeNap == nil)
        #expect(s.player.lastNapResult?.gained.stamina == 30 && s.player.lastNapResult?.early == false)
        #expect(GameEngine.startCafeNap(&s, now: now.addingTimeInterval(CafeCatalog.napDuration + 2)).failure == .cafeNapUsed)
    }

    @Test func wakingEarlyGrantsTheElapsedShareRoundedDown() {
        var s = state(stamina: 40, mood: 40)
        _ = GameEngine.startCafeNap(&s, now: now)
        let third = now.addingTimeInterval(CafeCatalog.napDuration / 3)
        #expect(GameEngine.wakeFromCafeNap(&s, now: third).success == .cafeNapEnded)
        #expect(s.player.stamina == 50 && s.player.mood == 43 && s.player.lastNapResult?.early == true)
        #expect(s.napUsedToday && s.player.gold == 2_000 - CafeCatalog.napPrice)
    }

    @Test func napCannotStartWhileWorking() {
        var s = state(stamina: 80)
        #expect(GameEngine.startWork(&s, now: now).succeeded)
        #expect(GameEngine.startCafeNap(&s, now: now.addingTimeInterval(10)).failure == .cafeNapWorking)
    }

    @Test func schema16SavesLoadWithEmptyRecoveryState() throws {
        var s = state()
        _ = GameEngine.buyPlayerSupply(&s, kind: .riceBall, now: now)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        object["schemaVersion"] = 16
        var player = try #require(object["player"] as? [String: Any])
        for key in ["supplies", "recoveryDay", "activeNap", "lastNapResult"] { player.removeValue(forKey: key) }
        object["player"] = player
        let loaded = try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
        #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(loaded.player.supplies.isEmpty && loaded.suppliesUsedToday == 0 && loaded.player.activeNap == nil)
        let roundTrip = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(s))
        #expect(roundTrip.player.carried(.riceBall) == 1)
    }
}
