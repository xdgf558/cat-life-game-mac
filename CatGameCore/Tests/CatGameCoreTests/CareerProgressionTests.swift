import Foundation
import Testing
@testable import CatGameCore

@Suite("Career progression and durable work receipts")
struct CareerProgressionTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func directory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatCareerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func legacyData(from data: Data) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var player = try #require(object["player"] as? [String: Any])
        for field in ["level", "exp", "lastWorkResult"] { player.removeValue(forKey: field) }
        if var work = player["activeWork"] as? [String: Any] {
            work.removeValue(forKey: "expReward")
            player["activeWork"] = work
        }
        object["player"] = player
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test func careerValuesPreserveFiveWebJobsAndAppendTwoNativeHigherTiers() {
        #expect(WorkCatalog.all.map(\.id) == ["job_flyer", "job_store", "job_petshop", "job_it_engineer", "job_cat_cafe_manager",
                                            "job_pet_photographer", "job_pet_brand_designer"])
        #expect(WorkCatalog.all.map(\.unlockLevel) == [1, 2, 4, 6, 10, 15, 20])
        #expect(WorkCatalog.all.map(\.durationMinutes) == [2, 3, 4, 10, 30, 45, 60])
        #expect(WorkCatalog.all.map(\.staminaCost) == [10, 15, 20, 30, 50, 65, 80])
        #expect(WorkCatalog.all.map(\.moodCost) == [5, 8, 12, 12, 20, 24, 28])
        #expect(WorkCatalog.all.map(\.goldReward) == [60, 100, 160, 400, 800, 1400, 2000])
        #expect(WorkCatalog.all.map(\.expReward) == [22, 35, 52, 100, 200, 320, 450])
        #expect(WorkCatalog.requiredExperience(forLevel: 1) == 100)
        #expect(WorkCatalog.requiredExperience(forLevel: 10) == 1000)
    }

    @Test func everyUnlockedCareerChargesOnceAndFinishesAtItsOwnDeadline() throws {
        for job in WorkCatalog.all {
            var state = GameSnapshot.fresh(now: now)
            state.player.level = job.unlockLevel
            state.player.stamina = 100
            state.player.mood = 100
            #expect(GameEngine.startWork(&state, jobID: job.id, now: now).succeeded)
            let work = try #require(state.player.activeWork)
            #expect(work.jobID == job.id && work.goldReward == job.goldReward && work.expReward == job.expReward)
            #expect(work.endsAt.timeIntervalSince(now) == Double(job.durationMinutes * 60))
            #expect(state.player.stamina == 100 - job.staminaCost)
            #expect(state.player.mood == 100 - job.moodCost)
            let started = state
            #expect(!GameEngine.startWork(&state, jobID: job.id, now: now).succeeded)
            #expect(state == started)
            #expect(GameEngine.synchronize(&state, now: work.endsAt.addingTimeInterval(-0.1)).kind == .none)
            #expect(state.player.gold == 200 && state.player.exp == 0 && state.player.lastWorkResult == nil)
            #expect(GameEngine.synchronize(&state, now: work.endsAt).kind == .workFinished)
            #expect(state.player.gold == 200 + job.goldReward && state.player.exp == job.expReward)
            #expect(state.player.level == job.unlockLevel && state.player.completedWorkCount == 1)
            #expect(state.player.lastWorkResult?.id == work.id)
            #expect(state.player.lastWorkResult?.completedAt == work.endsAt)
            let settled = state
            #expect(GameEngine.synchronize(&state, now: work.endsAt).kind == .none)
            #expect(state == settled)
        }
    }

    @Test func higherTierEquipmentQuotesSurviveReloadAndPayOnlyOnceOffline() async throws {
        for (id, seconds, stamina, mood) in [("job_pet_photographer", 2295, 56, 20),
                                            ("job_pet_brand_designer", 3060, 68, 23)] {
            let folder = try directory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let repository = FileSaveRepository(directory: folder)
            let job = try #require(WorkCatalog.job(id: id))
            var state = GameSnapshot.fresh(now: now)
            state.player.level = job.unlockLevel
            state.player.stamina = 100
            state.player.mood = 100
            #expect(GameEngine.equipStarterSet(&state, now: now).succeeded)
            let quote = try #require(GameEngine.workQuote(for: state.player, jobID: id))
            #expect(quote.durationSeconds == seconds && quote.staminaCost == stamina && quote.moodCost == mood)
            state.player.stamina = stamina - 1
            let insufficient = state
            #expect(GameEngine.startWork(&state, jobID: id, now: now).messageKey == "work.staminaRequired")
            #expect(state == insufficient)
            state.player.stamina = 100
            #expect(GameEngine.startWork(&state, jobID: id, now: now).succeeded)
            let work = try #require(state.player.activeWork)
            #expect(work.quote == quote && work.endsAt.timeIntervalSince(now) == Double(seconds))
            #expect(state.player.stamina == 100 - stamina && state.player.mood == 100 - mood)
            for slot in EquipmentSlot.allCases { _ = GameEngine.unequipSlot(&state, slot: slot, now: now) }
            #expect(state.player.activeWork == work)
            try await repository.save(state)
            let returnDate = work.endsAt.addingTimeInterval(86_400)
            var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: returnDate)
            #expect(loaded.player.activeWork == work)
            #expect(GameEngine.synchronize(&loaded, now: returnDate).kind == .workFinished)
            #expect(loaded.player.gold == 200 + job.goldReward && loaded.player.exp == job.expReward)
            #expect(loaded.player.completedWorkCount == 1 && loaded.player.lastWorkResult?.id == work.id)
            try await repository.save(loaded)
            var reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: returnDate)
            #expect(reopened == loaded)
            #expect(GameEngine.synchronize(&reopened, now: now).kind == .none)
            #expect(reopened == loaded)
        }
    }

    @Test func higherTierUnlocksAppearOnTheExactLevelBoundary() throws {
        for (level, id) in [(15, "job_pet_photographer"), (20, "job_pet_brand_designer")] {
            var state = GameSnapshot.fresh(now: now)
            state.player.level = level - 1
            state.player.exp = WorkCatalog.requiredExperience(forLevel: level - 1) - 22
            let locked = state
            #expect(GameEngine.startWork(&state, jobID: id, now: now).messageKey == "work.levelRequired")
            #expect(state == locked)
            #expect(GameEngine.startWork(&state, now: now).succeeded)
            let end = try #require(state.player.activeWork?.endsAt)
            #expect(GameEngine.synchronize(&state, now: end).kind == .workFinished)
            #expect(state.player.level == level && state.player.exp == 0)
            #expect(state.player.lastWorkResult?.newlyUnlockedJobIDs == [id])
        }
    }

    @Test func lockedUnknownAndInsufficientStaminaNeverChargeOrReplaceReceipt() {
        for job in WorkCatalog.all {
            var state = GameSnapshot.fresh(now: now)
            if job.unlockLevel > 1 {
                state.player.level = job.unlockLevel - 1
                let before = state
                #expect(GameEngine.startWork(&state, jobID: job.id, now: now).messageKey == "work.levelRequired")
                #expect(state == before)
            }
            state.player.level = job.unlockLevel
            state.player.stamina = job.staminaCost - 1
            let before = state
            #expect(GameEngine.startWork(&state, jobID: job.id, now: now).messageKey == "work.staminaRequired")
            #expect(state == before)
        }
        var state = GameSnapshot.fresh(now: now)
        let before = state
        #expect(GameEngine.startWork(&state, jobID: "missing", now: now).messageKey == "work.jobMissing")
        #expect(state == before)
    }

    @Test func selectedCareerStillExcludesSleepAndClampsMoodCost() {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 10
        state.player.mood = 2
        _ = GameEngine.startSleep(&state, now: now)
        let sleeping = state
        #expect(GameEngine.startWork(&state, jobID: "job_cat_cafe_manager", now: now).messageKey == "work.sleeping")
        #expect(state == sleeping)
        _ = GameEngine.wakeUp(&state, now: now)
        #expect(GameEngine.startWork(&state, jobID: "job_cat_cafe_manager", now: now).succeeded)
        #expect(state.player.mood == 0 && state.player.stamina == 30)
        #expect(GameEngine.startSleep(&state, now: now.addingTimeInterval(1)).messageKey == "sleep.workActive")
    }

    @Test func experienceUnlocksOnlyAfterTheShiftActuallyFinishes() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.exp = 78
        _ = GameEngine.startWork(&state, now: now)
        let work = try #require(state.player.activeWork)
        _ = GameEngine.synchronize(&state, now: work.endsAt.addingTimeInterval(-1))
        #expect(state.player.level == 1 && state.player.exp == 78)
        #expect(GameEngine.startWork(&state, jobID: "job_store", now: now).messageKey == "work.levelRequired")
        _ = GameEngine.synchronize(&state, now: work.endsAt)
        #expect(state.player.level == 2 && state.player.exp == 0)
        let result = try #require(state.player.lastWorkResult)
        #expect(result.levelBefore == 1 && result.levelAfter == 2 && result.expAfter == 0)
        #expect(result.expReward == 22 && result.newlyUnlockedJobIDs == ["job_store"])
        #expect(GameEngine.startWork(&state, jobID: "job_store", now: work.endsAt).succeeded)
    }

    @Test func aSavedRewardCrossingSeveralLevelsKeepsRemainderAndEveryUnlock() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.exp = 95
        state.player.activeWork = ActiveWork(id: "multi-level", startedAt: now,
                                             endsAt: now.addingTimeInterval(120), expReward: 1410)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(120))
        #expect(state.player.level == 6 && state.player.exp == 5)
        let result = try #require(state.player.lastWorkResult)
        #expect(result.levelBefore == 1 && result.levelAfter == 6 && result.expAfter == 5)
        #expect(result.newlyUnlockedJobIDs == ["job_store", "job_petshop", "job_it_engineer"])
        #expect(state.player.gold == 260 && state.player.completedWorkCount == 1 && state.isValid)
    }

    @Test func startingAnotherJobRetainsTheReceiptAndNextCompletionReplacesIt() throws {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.startWork(&state, now: now)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(120))
        let first = try #require(state.player.lastWorkResult)
        _ = GameEngine.startWork(&state, now: now.addingTimeInterval(120))
        let second = try #require(state.player.activeWork)
        #expect(second.id != first.id && state.player.lastWorkResult == first)
        _ = GameEngine.synchronize(&state, now: second.endsAt)
        #expect(state.player.lastWorkResult?.id == second.id)
        #expect(state.player.exp == 44 && state.player.gold == 320 && state.player.completedWorkCount == 2)
    }

    @Test func offlineCompletionAndClockRollbackCannotRepeatGoldExperienceOrReceipt() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.exp = 99
        _ = GameEngine.startWork(&state, now: now)
        let deadline = try #require(state.player.activeWork?.endsAt)
        let returnDate = now.addingTimeInterval(86_400)
        _ = GameEngine.synchronize(&state, now: returnDate)
        #expect(state.player.level == 2 && state.player.exp == 21)
        #expect(state.player.lastWorkResult?.completedAt == deadline)
        let settled = state
        for time in [returnDate, now, now.addingTimeInterval(-60)] {
            #expect(GameEngine.synchronize(&state, now: time).kind == .none)
            #expect(state == settled)
        }
    }

    @Test func receiptAndProgressSurviveRealRepositoryReloadWithoutAnotherPayout() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.exp = 99
        _ = GameEngine.startWork(&state, now: now)
        try await repository.save(state)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(180))
        _ = GameEngine.synchronize(&loaded, now: now.addingTimeInterval(180))
        try await repository.save(loaded)
        var reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(181))
        let result = try #require(reopened.player.lastWorkResult)
        #expect(reopened.player.gold == 260 && reopened.player.level == 2 && reopened.player.exp == 21)
        #expect(result.newlyUnlockedJobIDs == ["job_store"])
        #expect(GameEngine.synchronize(&reopened, now: now.addingTimeInterval(181)).kind == .none)
        #expect(reopened.player.gold == 260 && reopened.player.exp == 21 && reopened.player.lastWorkResult == result)
        try await repository.save(reopened)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == reopened)
    }

    @Test func oldSaveDefaultsProgressWithoutRewritingResourcesOrAwardingPastWork() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var original = GameSnapshot.fresh(now: now)
        original.player.gold = 912
        original.player.completedWorkCount = 12
        original.inventory.food = 8
        original.home.name = "Quiet Home"
        original.home.bowlPosition = .init(x: 0.6, y: 0.7)
        original.settings.language = .english
        original.cats.append(CatState(id: "generated_kitten", name: "Bean", now: now))
        try await repository.save(original)
        let legacy = try legacyData(from: Data(contentsOf: repository.saveURL))
        try legacy.write(to: repository.saveURL)
        let loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(loaded == original)
        #expect(loaded.player.level == 1 && loaded.player.exp == 0 && loaded.player.lastWorkResult == nil)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
        try await repository.save(loaded)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == original)
    }

    @Test func oldInFlightFlyerKeepsItsDeadlineAndEarnsNewExperienceOnce() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = GameSnapshot.fresh(now: now)
        state.player.completedWorkCount = 7
        _ = GameEngine.startWork(&state, now: now)
        let originalWork = try #require(state.player.activeWork)
        try await repository.save(state)
        try legacyData(from: Data(contentsOf: repository.saveURL)).write(to: repository.saveURL)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(119))
        #expect(loaded.player.activeWork == originalWork)
        #expect(loaded.player.level == 1 && loaded.player.exp == 0)
        _ = GameEngine.synchronize(&loaded, now: now.addingTimeInterval(120))
        #expect(loaded.player.gold == 260 && loaded.player.exp == 22 && loaded.player.completedWorkCount == 8)
        #expect(loaded.player.lastWorkResult?.id == originalWork.id)
        try await repository.save(loaded)
        var reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(130))
        _ = GameEngine.synchronize(&reopened, now: now.addingTimeInterval(130))
        #expect(reopened.player.gold == 260 && reopened.player.exp == 22 && reopened.player.completedWorkCount == 8)
    }

    @Test func legacyUnknownJobPreservesCapturedPayAndGetsNoInventedExperience() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = GameSnapshot.fresh(now: now)
        state.player.activeWork = ActiveWork(id: "legacy-work", jobID: "old-custom-job",
                                             startedAt: now, endsAt: now.addingTimeInterval(60), goldReward: 37)
        try await repository.save(state)
        try legacyData(from: Data(contentsOf: repository.saveURL)).write(to: repository.saveURL)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(60))
        #expect(loaded.player.activeWork?.expReward == 0)
        _ = GameEngine.synchronize(&loaded, now: now.addingTimeInterval(60))
        #expect(loaded.player.gold == 237 && loaded.player.exp == 0)
        #expect(loaded.player.lastWorkResult?.jobID == "old-custom-job")
        try await repository.save(loaded)
    }

    @Test func malformedProgressOrReceiptCannotOverwritePrimaryOrBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        _ = GameEngine.startWork(&state, now: now)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(120))
        try await repository.save(state)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        let mutations: [(inout GameSnapshot) -> Void] = [
            { $0.player.level = 0 }, { $0.player.level = Int.max },
            { $0.player.exp = -1 }, { $0.player.exp = 100 },
            { $0.player.lastWorkResult?.expReward = -1 },
            { $0.player.lastWorkResult?.expAfter = 100 },
            { $0.player.lastWorkResult?.levelAfter = 0 },
            { $0.player.lastWorkResult?.completedAt = Date(timeIntervalSince1970: .infinity) },
            { $0.player.lastWorkResult?.id = " " },
            { $0.player.activeWork = ActiveWork(id: $0.player.lastWorkResult!.id,
                                               startedAt: now, endsAt: now.addingTimeInterval(120)) }
        ]
        for mutate in mutations {
            var invalid = state
            mutate(&invalid)
            #expect(!invalid.isValid)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid) }
            #expect(try Data(contentsOf: repository.saveURL) == primary)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    @Test func goldCapPaysOnlyAvailableCapacityWithoutBlockingTimeOrExperience() {
        for remainingCapacity in [0, 1, 59, 60] {
            var state = GameSnapshot.fresh(now: now)
            state.player.gold = GameSnapshot.maximumGold - remainingCapacity
            state.player.exp = 90
            state.player.completedWorkCount = GameSnapshot.maximumGold
            _ = GameEngine.startWork(&state, now: now)
            let workID = state.player.activeWork?.id
            let outcome = GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400))
            #expect(outcome.succeeded && outcome.kind == .workFinished)
            #expect(outcome.amount == remainingCapacity)
            #expect(state.player.gold == GameSnapshot.maximumGold)
            #expect(state.player.level == 2 && state.player.exp == 12)
            #expect(state.player.completedWorkCount == GameSnapshot.maximumGold)
            #expect(state.player.lastWorkResult?.id == workID)
            #expect(state.player.lastWorkResult?.goldReward == remainingCapacity)
            #expect(state.player.lastWorkResult?.expReward == 22)
            #expect(state.player.activeWork == nil)
            #expect(state.cats[0].satiety == 0 && state.player.stamina == 100)
            #expect(state.meta.lastSyncAt == now.addingTimeInterval(86_400))
            #expect(state.isValid)
            let settled = state
            #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400)).kind == .none)
            #expect(state == settled)
            _ = GameEngine.buyFood(&state, now: now.addingTimeInterval(86_401))
            #expect(state.player.gold == GameSnapshot.maximumGold - GameEngine.foodPrice)
            #expect(state.player.exp == 12)
        }
    }

    @Test func unrepresentableExperienceCannotPartiallyPayOrDecayState() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.startWork(&state, now: now)
        #expect(CatHabitEngine.beginPlay(&state, catID: state.activeCatID, now: now).succeeded)
        state.player.level = Int.max / 100
        state.player.exp = WorkCatalog.requiredExperience(forLevel: state.player.level) - 1
        #expect(state.isValid)
        let beforeLevelLimit = state
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400)).messageKey == "work.progressLimit")
        #expect(state == beforeLevelLimit)
        #expect(WorkCatalog.requiredExperience(forLevel: Int.max) == 0)
        #expect(WorkCatalog.requiredExperience(forLevel: -1) == 0)
    }

    @Test func capturedRewardsAreNotReplacedByCurrentCatalogValues() {
        var state = GameSnapshot.fresh(now: now)
        state.player.activeWork = ActiveWork(id: "fixed-contract", startedAt: now,
                                             endsAt: now.addingTimeInterval(60), goldReward: 73, expReward: 40)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(60))
        #expect(state.player.gold == 273 && state.player.exp == 40)
        #expect(state.player.lastWorkResult?.goldReward == 73 && state.player.lastWorkResult?.expReward == 40)
    }

    @Test func workAndCatRestCompleteInOneSyncWithoutRepeatingEitherReward() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].energy = 40
        _ = GameEngine.startWork(&state, now: now)
        _ = GameEngine.startCatRest(&state, catID: "cat_001", furnitureID: "catBed",
                                    sessionID: "parallel-rest", now: now.addingTimeInterval(108))
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(120))
        #expect(state.cats[0].energy == 61 && state.cats[0].activeRest == nil)
        #expect(state.player.gold == 260 && state.player.exp == 22 && state.player.activeWork == nil)
        let settled = state
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(120))
        #expect(state == settled)
    }
}
