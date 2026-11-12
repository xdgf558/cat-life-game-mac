import Foundation
import Testing
@testable import CatGameCore

@Suite("Level-gated tasks and remaining-task projections")
struct GameTaskUnlockTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    func readyState(level: Int = 10) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = level
        state.player.completedWorkCount = 100
        state.cats[0].intimacy = 100
        state.home.roomLevel = 3
        state.tasks.totalFeedCount = 2
        state.tasks.furniturePurchaseCount = 5
        state.tasks.dailyFeedCount = 2
        state.tasks.dailyWorkCount = 3
        state.tasks.dailyPlayCount = 2
        state.tasks.dailyCleanCount = 1
        state.tasks.totalCleanCount = 30
        state.community.relationships["neighbor_mira"] = .init(friendship: 40,
            visitedToday: true, giftsGivenToday: 1, totalVisitCount: 10, totalGiftCount: 10,
            rewardedStageLevels: [2, 3])
        state.community.exchangeCounts["neighbor_mira"] = .init(today: 2, total: 30)
        return state
    }

    func task(_ id: String) throws -> GameTaskDefinition { try #require(GameTaskCatalog.task(id: id)) }

    @Test func addedTasksMatchTheTwelveSpecifiedUnlocksTargetsAndRewards() throws {
        let expected: [(String, Int, Int, Int, Int)] = [
            ("daily_work2", 2, 2, 35, 8), ("daily_feed2", 4, 2, 20, 5),
            ("daily_play2", 6, 2, 20, 5), ("daily_work3", 10, 3, 45, 10),
            ("achievement_work25", 2, 25, 180, 35), ("achievement_intimacy75", 2, 75, 120, 25),
            ("achievement_room3", 4, 3, 180, 35), ("achievement_furniture3", 4, 3, 100, 20),
            ("achievement_work50", 6, 50, 280, 50), ("achievement_intimacy100", 6, 100, 180, 35),
            ("achievement_work100", 10, 100, 500, 80), ("achievement_furniture5", 10, 5, 180, 35)
        ]
        #expect(GameTaskCatalog.all.count == 33 && Set(GameTaskCatalog.all.map(\.id)).count == 33)
        #expect(GameTaskCatalog.all.filter { $0.category == .tutorial }.count == 5)
        #expect(GameTaskCatalog.all.filter { $0.category == .daily }.count == 11)
        #expect(GameTaskCatalog.all.filter { $0.category == .achievement }.count == 17)
        for (id, level, target, gold, exp) in expected {
            let definition = try task(id)
            #expect(definition.requiredLevel == level && definition.target == target)
            #expect(definition.goldReward == gold && definition.expReward == exp)
        }
    }

    @Test func everyNewTaskEnforcesItsLevelBeforePayingEvenWhenProgressIsComplete() {
        for definition in GameTaskCatalog.all where definition.requiredLevel > 1 {
            var state = readyState(level: definition.requiredLevel - 1)
            #expect(GameTaskCatalog.progress(for: definition, in: state) >= definition.target)
            #expect(!GameTaskCatalog.isUnlocked(definition, in: state))
            #expect(!GameTaskCatalog.isClaimable(definition, in: state))
            let before = state
            let blocked = GameEngine.claimTask(&state, id: definition.id, expectedDayKey: state.tasks.dailyDayKey, now: now)
            #expect(blocked.failure == .taskLevelRequired && blocked.amount == definition.requiredLevel)
            #expect(state == before)
            state.player.level = definition.requiredLevel
            #expect(GameTaskCatalog.isUnlocked(definition, in: state))
            #expect(GameTaskCatalog.isClaimable(definition, in: state))
            #expect(GameEngine.claimTask(&state, id: definition.id, expectedDayKey: state.tasks.dailyDayKey,
                                        now: now).success == .taskClaimed)
        }
    }

    @Test func unlockedTasksStillRequireTheirOwnHigherProgressTarget() {
        let fresh = GameSnapshot.fresh(now: now)
        for definition in GameTaskCatalog.all where definition.requiredLevel > 1 {
            var state = fresh
            state.player.level = definition.requiredLevel
            #expect(GameTaskCatalog.isUnlocked(definition, in: state))
            let before = state
            #expect(GameEngine.claimTask(&state, id: definition.id, expectedDayKey: state.tasks.dailyDayKey,
                                        now: now).failure == .taskIncomplete)
            #expect(state == before)
        }
    }

    @Test func remainingTasksIncludeIncompleteTasksAndExcludeBothLockedAndClaimedTasks() {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameTaskCatalog.remainingTasks(in: state, category: .daily).map(\.id) == ["daily_work", "daily_feed", "daily_play", "daily_clean", "daily_visit"])
        #expect(GameTaskCatalog.remainingTasks(in: state, category: .achievement).map(\.id) ==
            ["achievement_work10", "achievement_intimacy50", "achievement_room2"])
        _ = GameEngine.feed(&state, catID: state.activeCatID, now: now)
        _ = GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: state.tasks.dailyDayKey, now: now)
        #expect(GameTaskCatalog.remainingTasks(in: state, category: .daily).map(\.id) == ["daily_work", "daily_play", "daily_clean", "daily_visit"])
        state.player.level = 2
        #expect(GameTaskCatalog.remainingTasks(in: state, category: .daily).map(\.id) == ["daily_work", "daily_play", "daily_work2", "daily_clean", "daily_visit", "daily_gift", "daily_exchange"])
        #expect(GameTaskCatalog.remainingTasks(in: state, category: .achievement).count == 8)
    }

    @Test func claimingEveryVisibleTaskRemovesOnlyThatTaskUntilEachCategoryIsEmpty() {
        var state = readyState()
        for category in GameTaskCategory.allCases {
            let visible = GameTaskCatalog.remainingTasks(in: state, category: category)
            for definition in visible {
                let previousIDs = GameTaskCatalog.remainingTasks(in: state, category: category).map(\.id)
                #expect(GameEngine.claimTask(&state, id: definition.id, expectedDayKey: state.tasks.dailyDayKey,
                                            now: now).succeeded)
                #expect(GameTaskCatalog.remainingTasks(in: state, category: category).map(\.id) ==
                    previousIDs.filter { $0 != definition.id })
            }
            #expect(GameTaskCatalog.remainingTasks(in: state, category: category).isEmpty)
            #expect(GameTaskCatalog.nextUnlockLevel(in: state, category: category) == nil)
        }
    }

    @Test func nextUnlockLevelTracksTheNextTierEvenWhenCurrentTasksRemain() {
        let levels: [(Int, Int?)] = [(1, 2), (2, 4), (4, 6), (6, 10), (10, nil)]
        for (level, expected) in levels {
            var state = readyState(level: level)
            for category in [GameTaskCategory.daily, .achievement] {
                #expect(!GameTaskCatalog.remainingTasks(in: state, category: category).isEmpty)
                #expect(GameTaskCatalog.nextUnlockLevel(in: state, category: category) == expected)
                for definition in GameTaskCatalog.remainingTasks(in: state, category: category) {
                    if category == .daily { state.tasks.dailyClaimedTaskIDs.append(definition.id) }
                    else { state.tasks.claimedTaskIDs.append(definition.id) }
                }
                #expect(GameTaskCatalog.remainingTasks(in: state, category: category).isEmpty)
                #expect(GameTaskCatalog.nextUnlockLevel(in: state, category: category) == expected)
            }
            #expect(GameTaskCatalog.nextUnlockLevel(in: state, category: .tutorial) == nil)
        }
    }

    @Test func rewardLevelUpImmediatelyUnlocksExistingSameDayProgress() throws {
        var state = readyState(level: 1)
        state.player.exp = 99
        let secondShift = try task("daily_work2")
        #expect(!GameTaskCatalog.isClaimable(secondShift, in: state))
        let counters = state.tasks
        #expect(GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: state.tasks.dailyDayKey,
                                    now: now).succeeded)
        #expect(state.player.level == 2 && state.player.exp == 3)
        #expect(state.tasks.dailyWorkCount == counters.dailyWorkCount && state.tasks.dailyFeedCount == counters.dailyFeedCount)
        #expect(GameTaskCatalog.isClaimable(secondShift, in: state))
        #expect(GameTaskCatalog.remainingTasks(in: state, category: .daily).contains { $0.id == secondShift.id })
        #expect(state.player.gold == 215)
        #expect(GameEngine.claimTask(&state, id: secondShift.id, expectedDayKey: state.tasks.dailyDayKey,
                                    now: now).amount == 35)
        #expect(state.player.gold == 250)
    }

    @Test func claimSynchronizesAnExpiringShiftBeforeCheckingTheNewLevelGate() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.exp = 78
        state.tasks.dailyWorkCount = 1
        _ = GameEngine.startWork(&state, now: now)
        let end = try #require(state.player.activeWork?.endsAt)
        #expect(!GameTaskCatalog.isUnlocked(try task("daily_work2"), in: state))
        #expect(GameEngine.claimTask(&state, id: "daily_work2", expectedDayKey: state.tasks.dailyDayKey,
                                    now: end).success == .taskClaimed)
        #expect(state.player.level == 2 && state.player.exp == 8 && state.player.gold == 295)
        #expect(state.tasks.dailyWorkCount == 2 && state.tasks.dailyClaimedTaskIDs == ["daily_work2"])
    }

    @Test func relatedDailyMilestonesShareProgressButHaveIndependentOnceOnlyRewards() {
        var state = readyState()
        let gold = state.player.gold
        for id in ["daily_work", "daily_work2", "daily_work3"] {
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: state.tasks.dailyDayKey, now: now).succeeded)
            let paid = state
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: state.tasks.dailyDayKey,
                                        now: now).failure == .taskAlreadyClaimed)
            #expect(state == paid)
        }
        #expect(state.player.gold == gold + 110 && state.player.exp == 26)
        #expect(state.tasks.dailyWorkCount == 3)
    }

    @Test func schemaThreeMigrationPreservesAllReceiptsAndDoesNotAutoAwardNewTasks() throws {
        var old = readyState()
        old.tasks.claimedTaskIDs = ["tutorial_work", "tutorial_feed", "achievement_work10"]
        old.tasks.dailyClaimedTaskIDs = ["daily_work", "daily_feed"]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json["schemaVersion"] = 3
        var upgraded = try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(json))
        #expect(upgraded == old && upgraded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(GameTaskCatalog.isClaimable(try task("daily_work2"), in: upgraded))
        #expect(GameTaskCatalog.isClaimable(try task("achievement_work100"), in: upgraded))
        #expect(GameEngine.claimTask(&upgraded, id: "daily_work", expectedDayKey: upgraded.tasks.dailyDayKey,
                                    now: now).failure == .taskAlreadyClaimed)
        #expect(upgraded == old)
        json.removeValue(forKey: "tasks")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(json))
        }
    }

    @Test func midnightClearsNewDailyClaimsButKeepsPermanentReceiptsAndCounters() {
        var state = readyState()
        for id in ["tutorial_work", "daily_work", "daily_work2", "daily_work3", "achievement_furniture5"] {
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: state.tasks.dailyDayKey, now: now).succeeded)
        }
        let oldDay = state.tasks.dailyDayKey
        let permanent = state.tasks.claimedTaskIDs
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400))
        #expect(state.tasks.dailyDayKey != oldDay && state.tasks.dailyClaimedTaskIDs.isEmpty)
        #expect(state.tasks.dailyWorkCount == 0 && state.tasks.dailyFeedCount == 0 && state.tasks.dailyPlayCount == 0 && state.tasks.dailyCleanCount == 0)
        #expect(state.tasks.claimedTaskIDs == permanent && state.tasks.furniturePurchaseCount == 5 && state.tasks.totalFeedCount == 2 && state.tasks.totalCleanCount == 30)
        #expect(GameTaskCatalog.remainingTasks(in: state, category: .daily).count == 11)
        #expect(GameEngine.claimTask(&state, id: "daily_work3", expectedDayKey: oldDay,
                                    now: now.addingTimeInterval(86_400)).failure == .taskDayChanged)
    }

    @Test func newReceiptsPersistUnderCurrentSchemaAndOlderInMemoryHeadersCannotOverwriteThem() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatTaskUnlockTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = readyState()
        _ = GameEngine.claimTask(&state, id: "daily_work3", expectedDayKey: state.tasks.dailyDayKey, now: now)
        _ = GameEngine.claimTask(&state, id: "achievement_work100", now: now)
        try await repository.save(state)
        let bytes = try Data(contentsOf: repository.saveURL)
        let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == GameSnapshot.currentSchemaVersion)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == state)
        var stale = state
        stale.schemaVersion = 3
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(3)) { try await repository.save(stale) }
        #expect(try Data(contentsOf: repository.saveURL) == bytes)
        let nextSchema = GameSnapshot.currentSchemaVersion + 1
        let future = Data("{\"schemaVersion\":\(nextSchema),\"tasks\":null}".utf8)
        try future.write(to: repository.saveURL)
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(nextSchema)) {
            try await repository.loadOrCreate(now: now)
        }
        #expect(try Data(contentsOf: repository.saveURL) == future)
    }
}
