import Foundation
import Testing
@testable import CatGameCore

@Suite("Cat health and hospital")
struct CatHealthTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)
    private var interval: TimeInterval { CatHealthCatalog.evaluationInterval }

    private func unprotected(illness: CatIllness? = nil, risk: Int = 0) -> GameSnapshot {
        var value = GameSnapshot.fresh(now: now)
        value.cats[0].healthState = CatHealthState(illness: illness, riskPoints: risk,
            lastEvaluatedAt: now, protectedUntil: now)
        value.cats[0].satiety = 100
        value.cats[0].cleanliness = 100
        value.cats[0].energy = 100
        return value
    }

    private func json(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(json))
    }

    @Test func freshCatsHaveAFullProtectionDay() {
        var value = GameSnapshot.fresh(now: now)
        value.cats[0].satiety = 0
        value.cats[0].cleanliness = 0
        value.cats[0].energy = 0
        #expect(value.cats[0].healthState?.protectedUntil == now.addingTimeInterval(86400))
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(86400))
        #expect(value.cats[0].healthState?.illness == nil)
        #expect(value.cats[0].healthState?.riskPoints == 0)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(86400 + interval))
        #expect(value.cats[0].healthState?.riskPoints == 1)
    }

    @Test(arguments: CatIllness.allCases)
    func sustainedLowNeedsChooseTheMatchingIllness(_ illness: CatIllness) {
        var value = unprotected()
        switch illness {
        case .cold: value.cats[0].energy = 20
        case .stomachache: value.cats[0].satiety = 20
        case .skinProblem: value.cats[0].cleanliness = 20
        }
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(interval * 7))
        #expect(value.cats[0].healthState?.riskPoints == 7)
        #expect(value.cats[0].healthState?.illness == nil)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(interval * 8))
        #expect(value.cats[0].healthState?.illness == illness)
        #expect(value.cats[0].health == 90)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(interval * 9))
        #expect(value.cats[0].health == 88)
    }

    @Test func frequentSyncMatchesOneCatchUpIncludingThresholdCrossings() {
        var value = unprotected(risk: 2)
        value.cats[0].energy = 43
        var single = value
        _ = GameEngine.synchronize(&single, now: now.addingTimeInterval(6 * 3600))
        for minute in 1...360 {
            _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(Double(minute) * 60))
        }
        #expect(value == single)
    }

    @Test func healthyNeedsReduceAccumulatedRisk() {
        var value = unprotected(risk: 3)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(interval))
        #expect(value.cats[0].healthState?.riskPoints == 2)
        #expect(value.cats[0].healthState?.illness == nil)
    }

    @Test func careLowersRiskOnlyAfterSuppliesAreSuccessfullyConsumed() {
        var value = unprotected(risk: 7)
        value.cats[0].satiety = 20
        value.cats[0].cleanliness = 20
        #expect(GameEngine.feed(&value, catID: "cat_001", now: now).succeeded)
        #expect(value.cats[0].healthState?.riskPoints == 5)
        #expect(GameEngine.clean(&value, catID: "cat_001", now: now).succeeded)
        #expect(value.cats[0].healthState?.riskPoints == 3)
        value.inventory.food = 0
        value.inventory.litter = 0
        let before = value
        #expect(!GameEngine.feed(&value, catID: "cat_001", now: now).succeeded)
        #expect(!GameEngine.clean(&value, catID: "cat_001", now: now).succeeded)
        #expect(value == before)
    }

    @Test func restRiskCreditsMatchFastTicksAndOneCompletion() {
        var value = unprotected(risk: 7)
        value.cats[0].energy = 20
        _ = GameEngine.startCatRest(&value, catID: "cat_001", furnitureID: "catBed",
            sessionID: "health-rest", now: now)
        var once = value
        _ = GameEngine.synchronize(&once, now: now.addingTimeInterval(12))
        for second in 1...12 { _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(Double(second))) }
        #expect(value == once)
        #expect(value.cats[0].healthState?.riskPoints == 5)
        let settled = value
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(12))
        #expect(value == settled)
    }

    @Test func restingAtFullEnergyCannotGrantRiskCreditsForDiscardedEnergy() {
        for energy in [99, 100] {
            var value = unprotected(risk: 7)
            value.cats[0].energy = energy
            _ = GameEngine.startCatRest(&value, catID: "cat_001", furnitureID: "catBed",
                sessionID: "full-rest", now: now)
            for second in 1...12 { _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(Double(second))) }
            #expect(value.cats[0].healthState?.riskPoints == 7)
        }
    }

    @Test func restCannotMaskAnEquallyLowHungerNeedDuringCatchUp() {
        var value = unprotected(risk: 7)
        value.cats[0].satiety = 20
        value.cats[0].energy = 20
        _ = GameEngine.startCatRest(&value, catID: "cat_001", furnitureID: "catBed",
            sessionID: "catchup-rest", now: now)
        var single = value
        _ = GameEngine.synchronize(&single, now: now.addingTimeInterval(interval))
        for second in 1...12 { _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(Double(second))) }
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(interval))
        #expect(value == single)
        #expect(value.cats[0].healthState?.riskPoints == 8)
        #expect(value.cats[0].healthState?.illness == .stomachache)
    }

    @Test func longAbsenceIsBoundedAndCannotBeReplayed() {
        var value = unprotected(illness: .cold, risk: 8)
        let later = now.addingTimeInterval(30 * 86400 + 123)
        _ = GameEngine.synchronize(&value, now: later)
        #expect(value.cats[0].health == 66) // At most twelve two-point illness steps.
        #expect(value.cats[0].healthState?.lastEvaluatedAt == later.addingTimeInterval(-123))
        let settled = value
        _ = GameEngine.synchronize(&value, now: later)
        #expect(value == settled)
        _ = GameEngine.synchronize(&value, now: now)
        #expect(value == settled)
        _ = GameEngine.synchronize(&value, now: later.addingTimeInterval(interval - 123))
        #expect(value.cats[0].health == 64)
    }

    @Test func illnessNeverRemovesCatsOrLowersNewHealthBelowRecoverableFloor() {
        var value = unprotected(illness: .skinProblem)
        for day in 1...10 { _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(Double(day) * 86400)) }
        #expect(value.cats.count == 1 && value.activeCatID == "cat_001")
        #expect(value.cats[0].health == 25 && value.cats[0].healthState?.illness == .skinProblem)
        value.cats[0].health = 12
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(11 * 86400))
        #expect(value.cats[0].health == 12) // Preserve low legacy health instead of healing via deterioration.
    }

    @Test(arguments: CatIllness.allCases)
    func treatmentUsesCatalogCostAndCannotChargeTwice(_ illness: CatIllness) {
        var value = unprotected(illness: illness, risk: 8)
        value.player.gold = 1000
        value.cats[0].health = 25
        let cost = CatHealthCatalog.definition(for: illness).treatmentCost
        let result = GameEngine.treatCat(&value, catID: "cat_001", now: now)
        #expect(result == ActionOutcome(success: .catTreated, amount: cost))
        #expect(value.player.gold == 1000 - cost)
        #expect(value.cats[0].health == 80 && value.cats[0].healthState?.riskPoints == 0)
        #expect(value.cats[0].healthState?.illness == nil)
        #expect(value.cats[0].healthState?.protectedUntil == now.addingTimeInterval(86400))
        let treated = value
        #expect(GameEngine.treatCat(&value, catID: "cat_001", now: now).failure == .hospitalHealthy)
        #expect(value == treated)
    }

    @Test func treatmentRejectsMissingCatAndInsufficientGoldWithoutPartialCharge() {
        var value = unprotected(illness: .cold, risk: 8)
        value.player.gold = 119
        let original = value
        #expect(GameEngine.treatCat(&value, catID: "cat_001", now: now)
            == ActionOutcome(failure: .hospitalGoldRequired, amount: 120))
        #expect(value == original)
        #expect(GameEngine.treatCat(&value, catID: "missing", now: now).failure == .careCatMissing)
        #expect(value == original)
    }

    @Test func treatmentSynchronizesEarnedWagesBeforeCheckingCost() {
        var value = unprotected(illness: .cold, risk: 8)
        value.player.gold = 60
        _ = GameEngine.startWork(&value, now: now)
        #expect(GameEngine.treatCat(&value, catID: "cat_001", now: now.addingTimeInterval(120)).succeeded)
        #expect(value.player.gold == 0 && value.player.completedWorkCount == 1)
        #expect(value.cats[0].healthState?.illness == nil)
    }

    @Test func twoCatsKeepIndependentConditionsAndTreatment() {
        var value = unprotected(illness: .cold, risk: 8)
        value.player.gold = 1000
        var other = CatState(id: "cat_002", name: "Milk", now: now, appearance: .cow)
        other.healthState?.illness = .skinProblem
        other.health = 50
        value.cats.append(other)
        #expect(GameEngine.treatCat(&value, catID: "cat_002", now: now).succeeded)
        #expect(value.cats[0].healthState?.illness == .cold && value.cats[0].health == 90)
        #expect(value.cats[1].healthState?.illness == nil && value.cats[1].health == 80)
        #expect(value.activeCatID == "cat_001" && value.player.gold == 740)
    }

    @Test func careImprovesNumbersButDoesNotClearAnIllness() {
        var value = unprotected(illness: .cold, risk: 8)
        _ = GameEngine.clean(&value, catID: "cat_001", now: now)
        _ = GameEngine.feed(&value, catID: "cat_001", now: now)
        #expect(value.cats[0].healthState?.illness == .cold)
        #expect(value.cats[0].health == 94)
    }

    @Test func oldSaveStartsHealthAtFirstPostUpgradeSyncWithoutBackdatedRisk() throws {
        var value = unprotected()
        value.cats[0].customName = "旧朋友"
        value.player.gold = 563
        var old = try json(value)
        old["schemaVersion"] = 4
        var cats = try #require(old["cats"] as? [[String: Any]])
        cats[0].removeValue(forKey: "healthState")
        old["cats"] = cats
        var loaded = try decode(old)
        #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion && loaded.cats[0].healthState == nil)
        #expect(loaded.player.gold == 563 && loaded.cats[0].customName == "旧朋友")
        let firstOpen = now.addingTimeInterval(20 * 86400)
        _ = GameEngine.synchronize(&loaded, now: firstOpen)
        #expect(loaded.cats[0].healthState == CatHealthState(now: firstOpen))
        #expect(loaded.cats[0].health == 90)
        #expect(try decode(json(loaded)) == loaded)
    }

    @Test func currentSchemaCannotEraseItsHealthObjectOrRequiredIllnessReceipt() throws {
        let original = try json(unprotected(illness: .cold))
        let invalidStates: [Any?] = [nil, NSNull(), "broken"]
        for invalid in invalidStates {
            var data = original
            var cats = try #require(data["cats"] as? [[String: Any]])
            cats[0]["healthState"] = invalid
            data["cats"] = cats
            #expect(throws: (any Error).self) { try decode(data) }
        }
        for field in ["illness", "riskPoints", "lastEvaluatedAt", "protectedUntil"] {
            var data = original
            var cats = try #require(data["cats"] as? [[String: Any]])
            var health = try #require(cats[0]["healthState"] as? [String: Any])
            health.removeValue(forKey: field)
            cats[0]["healthState"] = health
            data["cats"] = cats
            #expect(throws: (any Error).self) { try decode(data) }
        }
    }

    @Test func malformedAndNonfiniteHealthStateIsRejected() throws {
        var value = unprotected()
        value.cats[0].healthState?.riskPoints = 9
        #expect(!value.isValid)
        value.cats[0].healthState?.riskPoints = 0
        value.cats[0].healthState?.lastEvaluatedAt = Date(timeIntervalSince1970: .infinity)
        #expect(!value.isValid)
        value.cats[0].healthState?.lastEvaluatedAt = now
        value.cats[0].healthState?.protectedUntil = Date(timeIntervalSince1970: .nan)
        #expect(!value.isValid)
        var data = try json(unprotected())
        var cats = try #require(data["cats"] as? [[String: Any]])
        var health = try #require(cats[0]["healthState"] as? [String: Any])
        health["illness"] = "future-illness"
        cats[0]["healthState"] = health
        data["cats"] = cats
        #expect(throws: (any Error).self) { try decode(data) }
    }

    @Test func illnessPersistsThroughRealRepositoryAndRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileSaveRepository(directory: directory)
        let first = unprotected(illness: .stomachache, risk: 8)
        try await repository.save(first, now: now)
        var second = first
        second.player.gold += 1
        try await repository.save(second, now: now)
        #expect(try await repository.loadOrCreate(now: now) == second)
        try Data("damaged primary".utf8).write(to: repository.saveURL)
        #expect(try await repository.loadOrCreate(now: now) == first)
        #expect(await repository.lastLoadDisposition == .recoveredBackup)
    }

    @Test func legacyRepositoryCompletesHealthMigrationBeforeAnySave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileSaveRepository(directory: directory)
        var original = GameSnapshot.fresh(now: now)
        original.player.gold = 563
        original.cats[0].customName = "旧朋友"
        try await repository.save(original, now: now)
        var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        legacy["schemaVersion"] = 4
        var cats = try #require(legacy["cats"] as? [[String: Any]])
        cats[0].removeValue(forKey: "healthState")
        legacy["cats"] = cats
        var tasks = try #require(legacy["tasks"] as? [String: Any])
        tasks.removeValue(forKey: "dailyCleanCount")
        tasks.removeValue(forKey: "totalCleanCount")
        legacy["tasks"] = tasks
        let originalBytes = try snapshotFixtureData(legacy)
        try originalBytes.write(to: repository.saveURL)

        let firstOpen = now.addingTimeInterval(20 * 86400)
        var loaded = try await repository.loadOrCreate(now: firstOpen)
        #expect(loaded.cats[0].healthState == CatHealthState(now: firstOpen))
        #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        try await repository.save(loaded, now: firstOpen)
        #expect(try await repository.loadOrCreate(now: firstOpen) == loaded)
        #expect(try Data(contentsOf: repository.backupURL) == originalBytes)

        #expect(GameEngine.synchronize(&loaded, now: firstOpen).succeeded)
        try await repository.save(loaded, now: firstOpen)
        #expect(try await repository.loadOrCreate(now: firstOpen) == loaded)
        #expect(loaded.cats[0].healthState == CatHealthState(now: firstOpen))
        #expect(loaded.player.gold == 563 && loaded.cats[0].customName == "旧朋友")
        #expect(try Data(contentsOf: repository.backupURL) == originalBytes)
    }
}
