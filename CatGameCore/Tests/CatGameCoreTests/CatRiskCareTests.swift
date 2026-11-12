import Foundation
import Testing
@testable import CatGameCore

@Suite("Care addresses the current health risk")
struct CatRiskCareTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func state(satiety: Int = 100, cleanliness: Int = 100, energy: Int = 100) -> GameSnapshot {
        var value = GameSnapshot.fresh(now: now)
        value.cats[0].satiety = satiety
        value.cats[0].cleanliness = cleanliness
        value.cats[0].energy = energy
        value.cats[0].healthState = CatHealthState(riskPoints: 7,
            lastEvaluatedAt: now, protectedUntil: now)
        return value
    }

    @Test(arguments: [0, 20, 29, 30, 100])
    func foodAndCleaningJudgeTheNeedBeforeCareAndAllowTies(_ need: Int) {
        var fed = state(satiety: need, cleanliness: need, energy: need)
        var cleaned = fed
        #expect(GameEngine.feed(&fed, catID: "cat_001", now: now).succeeded)
        #expect(GameEngine.clean(&cleaned, catID: "cat_001", now: now).succeeded)
        let expectedRisk = need < 30 ? 5 : 7
        #expect(fed.cats[0].healthState?.riskPoints == expectedRisk)
        #expect(cleaned.cats[0].healthState?.riskPoints == expectedRisk)
        #expect(fed.inventory.food == 2 && cleaned.inventory.litter == 1)
    }

    @Test func feedingAndCleaningCannotHideTheRemainingLowEnergy() {
        var value = state(satiety: 0, cleanliness: 0, energy: 0)
        _ = GameEngine.feed(&value, catID: "cat_001", now: now)
        _ = GameEngine.clean(&value, catID: "cat_001", now: now)
        #expect(value.cats[0].healthState?.riskPoints == 3)
        _ = GameEngine.feed(&value, catID: "cat_001", now: now)
        _ = GameEngine.clean(&value, catID: "cat_001", now: now)
        #expect(value.cats[0].healthState?.riskPoints == 3)
    }

    @Test func regularFeedingCannotPreventAColdFromExhaustion() {
        var value = state(energy: 0)
        value.cats[0].healthState?.riskPoints = 0
        value.inventory.food = 8
        for check in 1...8 {
            #expect(GameEngine.feed(&value, catID: "cat_001",
                now: now.addingTimeInterval(Double(check) * CatHealthCatalog.evaluationInterval)).succeeded)
        }
        #expect(value.cats[0].healthState?.riskPoints == 8)
        #expect(value.cats[0].healthState?.illness == .cold)
    }

    @Test func foodAndCleaningDoNotRelieveAnotherWorseNeed() {
        var fed = state(satiety: 20, cleanliness: 10)
        var cleaned = state(satiety: 10, cleanliness: 20)
        _ = GameEngine.feed(&fed, catID: "cat_001", now: now)
        _ = GameEngine.clean(&cleaned, catID: "cat_001", now: now)
        #expect(fed.cats[0].healthState?.riskPoints == 7)
        #expect(cleaned.cats[0].healthState?.riskPoints == 7)
    }

    @Test(arguments: [CatIllness.stomachache, .skinProblem])
    func restDoesNotRelieveHungerOrHygieneRisk(_ cause: CatIllness) {
        var value = state(satiety: cause == .stomachache ? 0 : 100,
                          cleanliness: cause == .skinProblem ? 0 : 100, energy: 20)
        #expect(GameEngine.startCatRest(&value, catID: "cat_001", furnitureID: "catBed",
            sessionID: "unrelated-care", now: now).succeeded)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(12))
        #expect(value.cats[0].energy > 20)
        #expect(value.cats[0].healthState?.riskPoints == 7)
    }

    @Test(arguments: [0, 20, 25, 29, 30])
    func restCreditsStopOnceEnergyIsNoLongerLowAndMatchBatchedRecovery(_ energy: Int) {
        var frequent = state(energy: energy)
        _ = GameEngine.startCatRest(&frequent, catID: "cat_001", furnitureID: "catBed",
            sessionID: "threshold-care", now: now)
        var single = frequent
        _ = GameEngine.synchronize(&single, now: now.addingTimeInterval(12))
        for second in 1...12 {
            _ = GameEngine.synchronize(&frequent, now: now.addingTimeInterval(Double(second)))
        }
        #expect(single == frequent)
        let expectedRisk = [0: 3, 20: 5, 25: 6, 29: 7, 30: 7][energy]
        #expect(single.cats[0].healthState?.riskPoints == expectedRisk)
    }

    @Test func restJudgesOtherNeedsAtRecoveryTimeAcrossDecayAndOfflineCheckpoints() {
        var frequent = state(satiety: 24, energy: 20)
        frequent.cats[0].decayTracker.satiety = now.addingTimeInterval(-716)
        _ = GameEngine.startCatRest(&frequent, catID: "cat_001", furnitureID: "catBed",
            sessionID: "rest-timeline", now: now)
        var single = frequent
        let check = now.addingTimeInterval(CatHealthCatalog.evaluationInterval)
        _ = GameEngine.synchronize(&single, now: check)
        for tick in 1...48 {
            _ = GameEngine.synchronize(&frequent, now: now.addingTimeInterval(Double(tick) / 4))
        }
        #expect(frequent.cats[0].healthState?.riskPoints == 6)
        _ = GameEngine.synchronize(&frequent, now: check)
        #expect(single == frequent)
        #expect(single.cats[0].healthState?.riskPoints == 7)
        #expect(single.cats[0].healthState?.illness == nil)
    }

    @Test func ordinaryCareCannotRemoveAnIllnessOrRestartProtection() {
        var value = state(satiety: 0, cleanliness: 0, energy: 0)
        value.cats[0].healthState?.illness = .cold
        value.cats[0].healthState?.riskPoints = 8
        _ = GameEngine.feed(&value, catID: "cat_001", now: now)
        _ = GameEngine.clean(&value, catID: "cat_001", now: now)
        _ = GameEngine.startCatRest(&value, catID: "cat_001", furnitureID: "catBed",
            sessionID: "sick-care", now: now)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(12))
        #expect(value.cats[0].healthState?.illness == .cold)
        #expect(value.cats[0].healthState?.riskPoints == 8)
        #expect(value.cats[0].healthState?.protectedUntil == now)
    }

    @Test func targetedCareCannotChangeAnotherCatsRiskOrExtendProtection() {
        var value = state(energy: 0)
        var other = CatState(id: "cat_002", name: "Milk", satiety: 20, now: now, appearance: .cow)
        other.healthState?.riskPoints = 1
        let protection = other.healthState?.protectedUntil
        value.cats.append(other)
        _ = GameEngine.feed(&value, catID: "cat_002", now: now)
        #expect(value.cats[0].healthState?.riskPoints == 7)
        #expect(value.cats[1].healthState?.riskPoints == 0)
        #expect(value.cats[1].healthState?.protectedUntil == protection)
        #expect(value.activeCatID == "cat_001")
    }
}
