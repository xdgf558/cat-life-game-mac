import Foundation
import Testing
@testable import CatGameCore

@Suite("Task progress, daily boundaries and durable rewards")
struct GameTaskTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        return value
    }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }
    var midnight: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))! }

    func task(_ id: String) throws -> GameTaskDefinition { try #require(GameTaskCatalog.task(id: id)) }

    func json(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    @Test func originalNineTasksKeepTheirIDsRewardsAndLevelOneAvailability() {
        let original = Array(GameTaskCatalog.all.prefix(9))
        #expect(original.map(\.id) == ["tutorial_work", "tutorial_feed", "tutorial_furniture",
            "daily_work", "daily_feed", "daily_play", "achievement_work10", "achievement_intimacy50", "achievement_room2"])
        #expect(original.map(\.goldReward) == [30, 20, 40, 30, 15, 15, 120, 80, 100])
        #expect(original.map(\.expReward) == [10, 5, 10, 8, 4, 4, 25, 20, 25])
        #expect(original.map(\.target) == [1, 1, 1, 1, 1, 1, 10, 50, 2])
        #expect(original.allSatisfy { $0.requiredLevel == 1 })
        #expect(GameTaskCatalog.task(id: "missing") == nil)
    }

    @Test func schemaOneAndTwoMigrateKnownProgressWithoutInventingCare() throws {
        var original = GameSnapshot.fresh(now: now)
        original.player.completedWorkCount = 12
        original.cats[0].intimacy = 65
        original.home.roomLevel = 2
        original.inventory.furniture.append(FurnitureItem(id: "shop_potted_plant_1", kind: .plant))
        for version in [1, 2] {
            var object = try json(original)
            object["schemaVersion"] = version
            object.removeValue(forKey: "tasks")
            let migrated = try decode(object)
            var expected = original
            expected.tasks.furniturePurchaseCount = 1
            #expect(migrated == expected && migrated.schemaVersion == GameSnapshot.currentSchemaVersion)
            for id in ["tutorial_work", "tutorial_furniture", "achievement_work10", "achievement_intimacy50", "achievement_room2"] {
                #expect(GameTaskCatalog.isClaimable(try task(id), in: migrated))
            }
            for id in ["tutorial_feed", "tutorial_clean", "daily_work", "daily_feed", "daily_play", "daily_clean"] {
                #expect(GameTaskCatalog.progress(for: try task(id), in: migrated) == 0)
            }
            #expect(migrated.tasks.claimedTaskIDs.isEmpty && migrated.tasks.dailyClaimedTaskIDs.isEmpty)
            #expect(migrated.player.gold == original.player.gold && migrated.player.exp == original.player.exp)
        }
    }

    @Test func currentSchemaNeverResetsMissingNullOrIncompleteTaskReceipts() throws {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.feed(&state, catID: state.activeCatID, now: now)
        _ = GameEngine.claimTask(&state, id: "tutorial_feed", now: now)
        let original = try json(state)
        for replacement in [nil, NSNull()] as [Any?] {
            var object = original
            object["tasks"] = replacement
            #expect(throws: (any Error).self) { try decode(object) }
        }
        let tasks = try #require(original["tasks"] as? [String: Any])
        for key in tasks.keys {
            var incomplete = tasks
            incomplete.removeValue(forKey: key)
            var object = original
            object["tasks"] = incomplete
            #expect(throws: (any Error).self) { try decode(object) }
        }
    }

    @Test func malformedTaskValuesAndReceiptsFailValidationInsteadOfBeingDropped() throws {
        let original = try json(GameSnapshot.fresh(now: now))
        let tasks = try #require(original["tasks"] as? [String: Any])
        let invalid: [(String, Any)] = [
            ("dailyDayKey", "2026-02-30"), ("dailyDayKey", "2026-1-02"), ("dailyDayKey", "not-a-date"),
            ("dailyWorkCount", -1), ("dailyPlayCount", GameSnapshot.maximumGold + 1),
            ("dailyFeedCount", 1), ("dailyCleanCount", 1), ("totalCleanCount", -1),
            ("dailyCleanCount", NSNull()), ("totalCleanCount", GameSnapshot.maximumGold + 1),
            ("totalCleanCount", "one"), ("totalFeedCount", "one"), ("furniturePurchaseCount", -1),
            ("claimedTaskIDs", ["retired_task", "daily_work"]),
            ("claimedTaskIDs", ["tutorial_work", "tutorial_work"]),
            ("claimedTaskIDs", ["retired_task", "tutorial_work", "tutorial_work"]),
            ("claimedTaskIDs", ["tutorial_work", 7]), ("claimedTaskIDs", NSNull()),
            ("dailyClaimedTaskIDs", ["retired_daily", "tutorial_work"]),
            ("dailyClaimedTaskIDs", ["retired_daily", "daily_work", "daily_work"]),
            ("dailyClaimedTaskIDs", ["daily_work", 7]), ("dailyClaimedTaskIDs", NSNull())
        ]
        for (key, value) in invalid {
            var badTasks = tasks
            badTasks[key] = value
            var object = original
            object["tasks"] = badTasks
            #expect(throws: (any Error).self) { try decode(object) }
        }
    }

    @Test func retiredTaskReceiptsAreIgnoredWithoutResettingKnownProgressOrRewards() throws {
        var expected = GameSnapshot.fresh(now: now)
        #expect(GameEngine.feed(&expected, catID: expected.activeCatID, now: now).succeeded)
        #expect(GameEngine.claimTask(&expected, id: "tutorial_feed", now: now).succeeded)
        #expect(GameEngine.claimTask(&expected, id: "daily_feed", expectedDayKey: expected.tasks.dailyDayKey, now: now).succeeded)
        for version in 3...GameSnapshot.currentSchemaVersion {
            var object = try json(expected)
            object["schemaVersion"] = version
            var tasks = try #require(object["tasks"] as? [String: Any])
            tasks["claimedTaskIDs"] = ["retired_tutorial", "tutorial_feed", "retired_achievement"]
            tasks["dailyClaimedTaskIDs"] = ["retired_daily", "daily_feed"]
            object["tasks"] = tasks
            var loaded = try decode(object)
            #expect(loaded == expected && loaded.isValid)
            #expect(GameEngine.claimTask(&loaded, id: "tutorial_feed", now: now).failure == .taskAlreadyClaimed)
            #expect(GameEngine.claimTask(&loaded, id: "daily_feed", expectedDayKey: loaded.tasks.dailyDayKey, now: now).failure == .taskAlreadyClaimed)
            #expect(GameEngine.claimTask(&loaded, id: "retired_daily", expectedDayKey: loaded.tasks.dailyDayKey, now: now).failure == .taskMissing)
            #expect(loaded == expected)

            tasks["claimedTaskIDs"] = ["retired_tutorial"]
            tasks["dailyClaimedTaskIDs"] = ["retired_daily"]
            object["tasks"] = tasks
            var noKnownReceipts = expected
            noKnownReceipts.tasks.claimedTaskIDs = []
            noKnownReceipts.tasks.dailyClaimedTaskIDs = []
            #expect(try decode(object) == noKnownReceipts)
        }
    }

    @Test func successfulCareCountsAcrossCatsAndFailedActionsDoNotCount() throws {
        var state = GameSnapshot.fresh(now: now)
        state.cats.append(CatState(id: "second", name: "Milk", intimacy: 40, now: now))
        state.inventory.toys = 2
        #expect(GameEngine.feed(&state, catID: "cat_001", now: now).succeeded)
        #expect(GameEngine.feed(&state, catID: "second", now: now).succeeded)
        #expect(GameEngine.play(&state, catID: "second", now: now).succeeded)
        #expect(GameEngine.play(&state, catID: "cat_001", now: now).succeeded)
        #expect(state.tasks.totalFeedCount == 2 && state.tasks.dailyFeedCount == 2 && state.tasks.dailyPlayCount == 2)
        #expect(GameTaskCatalog.isClaimable(try task("achievement_intimacy50"), in: state))
        let progress = state.tasks
        state.inventory.food = 0
        #expect(!GameEngine.feed(&state, catID: "second", now: now).succeeded)
        #expect(!GameEngine.feed(&state, catID: "missing", now: now).succeeded)
        #expect(!GameEngine.play(&state, catID: "second", now: now).succeeded)
        #expect(state.tasks == progress)
    }

    @Test func pregnantFeedingCountsOneActionRatherThanTwoFoodUnits() {
        var state = GameSnapshot.fresh(now: now)
        state.cats[0].growthState = .init(recordedSince: now, adoptedAt: now, initialAgeDays: 365, sex: .female)
        state.cats[0].isPregnant = true
        #expect(GameEngine.feed(&state, catID: "cat_001", now: now).amount == 2)
        #expect(state.tasks.dailyFeedCount == 1 && state.tasks.totalFeedCount == 1)
    }

    @Test func starterFurnitureSuppliesAndFailedPurchasesCannotCompleteFurnitureTask() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(!state.inventory.furniture.isEmpty && state.tasks.furniturePurchaseCount == 0)
        #expect(!GameEngine.purchaseFurniture(&state, offerID: "potted_plant", now: now).succeeded)
        state.player.level = 2
        state.player.gold = 1
        #expect(!GameEngine.purchaseFurniture(&state, offerID: "potted_plant", now: now).succeeded)
        state.player.gold = 10_000
        #expect(!GameEngine.purchaseFurniture(&state, offerID: "missing", now: now).succeeded)
        #expect(GameEngine.buyFood(&state, now: now).succeeded)
        #expect(GameEngine.purchaseEquipment(&state, itemID: "advanced_cap", now: now).succeeded)
        #expect(state.tasks.furniturePurchaseCount == 0)
        for _ in 0..<10 { #expect(GameEngine.purchaseFurniture(&state, offerID: "potted_plant", now: now).succeeded) }
        #expect(state.tasks.furniturePurchaseCount == 10)
        #expect(!GameEngine.purchaseFurniture(&state, offerID: "potted_plant", now: now).succeeded)
        #expect(state.tasks.furniturePurchaseCount == 10)
        #expect(GameTaskCatalog.isClaimable(try task("tutorial_furniture"), in: state))
    }

    @Test func startingWorkDoesNotCountAndCompletionCountsExactlyOnce() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        #expect(state.tasks.dailyWorkCount == 0 && state.player.completedWorkCount == 0)
        let end = try #require(state.player.activeWork?.endsAt)
        _ = GameEngine.synchronize(&state, now: end)
        #expect(state.tasks.dailyWorkCount == 1 && state.player.completedWorkCount == 1)
        #expect(GameTaskCatalog.isClaimable(try task("tutorial_work"), in: state))
        _ = GameEngine.synchronize(&state, now: end)
        #expect(state.tasks.dailyWorkCount == 1 && state.player.completedWorkCount == 1)
    }

    @Test func roomAchievementTracksSuccessfulUpgradeAndUsesExistingLevel() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(!GameTaskCatalog.isClaimable(try task("achievement_room2"), in: state))
        #expect(!GameEngine.upgradeHome(&state, toLevel: 2, now: now).succeeded)
        state.player.level = 2
        state.player.gold = 450
        #expect(GameEngine.upgradeHome(&state, toLevel: 2, now: now).succeeded)
        #expect(GameTaskCatalog.isClaimable(try task("achievement_room2"), in: state))
    }

    @Test func eachTaskPaysCatalogRewardOnceAndRetainsReceipt() throws {
        for definition in GameTaskCatalog.all {
            var state = GameSnapshot.fresh(now: now)
            state.player.level = 10
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
            let before = state.player
            let outcome = GameEngine.claimTask(&state, id: definition.id, expectedDayKey: state.tasks.dailyDayKey, now: now)
            #expect(outcome.success == .taskClaimed && outcome.amount == definition.goldReward)
            #expect(state.player.gold == before.gold + definition.goldReward)
            #expect(state.player.exp == before.exp + definition.expReward)
            #expect(GameTaskCatalog.isClaimed(definition, in: state))
            let claimed = state
            #expect(GameEngine.claimTask(&state, id: definition.id, expectedDayKey: state.tasks.dailyDayKey,
                                        now: now).failure == .taskAlreadyClaimed)
            #expect(state == claimed)
            #expect(try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state)) == claimed)
        }
    }

    @Test func unknownIncompleteAndMissingDailyDateNeverPayRewards() {
        var state = GameSnapshot.fresh(now: now)
        let before = state
        #expect(GameEngine.claimTask(&state, id: "missing", now: now).failure == .taskMissing)
        #expect(GameEngine.claimTask(&state, id: "tutorial_feed", now: now).failure == .taskIncomplete)
        #expect(GameEngine.claimTask(&state, id: "daily_feed", now: now).failure == .taskDayChanged)
        #expect(GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: state.tasks.dailyDayKey,
                                    now: now).failure == .taskIncomplete)
        #expect(state == before)
    }

    @Test func midnightResetsOnlyDailyProgressAndReceiptsAndRejectsStaleCard() throws {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.feed(&state, catID: "cat_001", now: now)
        let previousDay = state.tasks.dailyDayKey
        _ = GameEngine.claimTask(&state, id: "tutorial_feed", now: now)
        _ = GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: previousDay, now: now)
        let gold = state.player.gold
        #expect(GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: previousDay,
                                    now: midnight).failure == .taskDayChanged)
        #expect(state.player.gold == gold && state.tasks.dailyFeedCount == 0 && state.tasks.dailyClaimedTaskIDs.isEmpty)
        #expect(state.tasks.totalFeedCount == 1 && state.tasks.claimedTaskIDs == ["tutorial_feed"])
        #expect(state.tasks.dailyDayKey != previousDay && state.meta.lastSyncAt == midnight)
        _ = GameEngine.feed(&state, catID: "cat_001", now: midnight)
        #expect(GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: previousDay,
                                    now: midnight).failure == .taskDayChanged)
        #expect(GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: state.tasks.dailyDayKey,
                                    now: midnight).succeeded)
    }

    @Test func clockRollbackCannotResetDailyClaimsOrGiveAnotherDailyReward() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.feed(&state, catID: "cat_001", now: now)
        _ = GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: state.tasks.dailyDayKey, now: now)
        let claimed = state
        for time in [now.addingTimeInterval(-120), now.addingTimeInterval(-86_400)] {
            _ = GameEngine.synchronize(&state, now: time)
            #expect(state == claimed)
            #expect(GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: state.tasks.dailyDayKey,
                                        now: time).failure == .taskAlreadyClaimed)
            #expect(state == claimed)
        }
    }

    @Test func offlineWorkUsesEndDateAndCannotBecomeTodaysWorkWhenItEndedYesterday() {
        for end in [midnight.addingTimeInterval(-1), midnight, midnight.addingTimeInterval(60)] {
            var state = GameSnapshot.fresh(now: now)
            state.player.activeWork = ActiveWork(startedAt: end.addingTimeInterval(-120), endsAt: end)
            let outcome = GameEngine.synchronize(&state, now: midnight.addingTimeInterval(3600))
            #expect(outcome.kind == .workFinished && state.player.completedWorkCount == 1)
            #expect(state.tasks.dailyWorkCount == (end < midnight ? 0 : 1))
            let settled = state
            _ = GameEngine.synchronize(&state, now: midnight.addingTimeInterval(3600))
            #expect(state == settled)
        }
    }

    @Test func dailyKeysUseGregorianLocalDatesAndForwardOnlyRollover() throws {
        let instant = Date(timeIntervalSince1970: 1_799_020_800) // Fixed instant; offset determines local date.
        let west = try #require(TimeZone(secondsFromGMT: -8 * 3600))
        let east = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        #expect(GameTaskState.dayKey(for: instant, timeZone: west) != GameTaskState.dayKey(for: instant, timeZone: east))
        var progress = GameTaskState(dailyDayKey: "2030-01-01", dailyWorkCount: 1, dailyClaimedTaskIDs: ["daily_work"])
        progress.advanceDay(to: now)
        #expect(progress.dailyDayKey == "2030-01-01" && progress.dailyWorkCount == 1 && progress.dailyClaimedTaskIDs == ["daily_work"])
    }

    @Test func claimSynchronizesWorkFirstAndAwardsExperienceAcrossLevelBoundary() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.exp = 75
        _ = GameEngine.startWork(&state, now: now)
        let end = try #require(state.player.activeWork?.endsAt)
        #expect(GameEngine.claimTask(&state, id: "tutorial_work", now: end).success == .taskClaimed)
        #expect(state.player.level == 2 && state.player.exp == 7)
        #expect(state.player.gold == 290 && state.player.activeWork == nil && state.tasks.dailyWorkCount == 1)
        #expect(state.player.lastWorkResult?.expAfter == 97)
    }

    @Test func goldCapClampsActualRewardAndKeepsTimeAndClaimsMoving() {
        for capacity in [0, 1, 19, 20] {
            var state = GameSnapshot.fresh(now: now)
            _ = GameEngine.feed(&state, catID: "cat_001", now: now)
            state.player.gold = GameSnapshot.maximumGold - capacity
            let later = now.addingTimeInterval(60)
            let outcome = GameEngine.claimTask(&state, id: "tutorial_feed", now: later)
            #expect(outcome.success == .taskClaimed && outcome.amount == capacity)
            #expect(state.player.gold == GameSnapshot.maximumGold && state.player.exp == 5)
            #expect(state.meta.lastSyncAt == later && state.tasks.claimedTaskIDs == ["tutorial_feed"])
            #expect(state.isValid)
        }
    }

    @Test func unrepresentableExperienceLeavesRewardUnclaimedWithoutLosingElapsedTime() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.feed(&state, catID: "cat_001", now: now)
        state.player.level = Int.max / 100
        state.player.exp = WorkCatalog.requiredExperience(forLevel: state.player.level) - 1
        let gold = state.player.gold
        let later = now.addingTimeInterval(60)
        #expect(GameEngine.claimTask(&state, id: "tutorial_feed", now: later).failure == .taskProgressLimit)
        #expect(state.player.gold == gold && state.tasks.claimedTaskIDs.isEmpty)
        #expect(state.meta.lastSyncAt == later && state.isValid)
    }

    @Test func progressCountersSaturateAndNeverOverflowOnSuccessfulActions() {
        var state = GameSnapshot.fresh(now: now)
        state.tasks.totalFeedCount = GameSnapshot.maximumGold
        state.tasks.dailyFeedCount = GameSnapshot.maximumGold
        state.tasks.dailyPlayCount = GameSnapshot.maximumGold
        state.tasks.dailyCleanCount = GameSnapshot.maximumGold
        state.tasks.totalCleanCount = GameSnapshot.maximumGold
        state.tasks.dailyWorkCount = GameSnapshot.maximumGold
        state.tasks.furniturePurchaseCount = GameSnapshot.maximumGold
        state.player.level = 2
        state.inventory.toys = 1
        #expect(GameEngine.clean(&state, catID: "cat_001", now: now).succeeded)
        #expect(GameEngine.feed(&state, catID: "cat_001", now: now).succeeded)
        #expect(GameEngine.play(&state, catID: "cat_001", now: now).succeeded)
        #expect(GameEngine.purchaseFurniture(&state, offerID: "potted_plant", now: now).succeeded)
        state.player.activeWork = ActiveWork(startedAt: now, endsAt: now)
        #expect(GameEngine.synchronize(&state, now: now).succeeded)
        #expect(state.tasks.totalFeedCount == GameSnapshot.maximumGold && state.tasks.dailyFeedCount == GameSnapshot.maximumGold)
        #expect(state.tasks.dailyPlayCount == GameSnapshot.maximumGold && state.tasks.dailyWorkCount == GameSnapshot.maximumGold)
        #expect(state.tasks.furniturePurchaseCount == GameSnapshot.maximumGold && state.isValid)
        #expect(state.tasks.dailyCleanCount == GameSnapshot.maximumGold && state.tasks.totalCleanCount == GameSnapshot.maximumGold)
    }

    @Test func durableReloadPreservesReceiptsAndColdLaunchCrossesDayOnce() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatTaskTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        _ = GameEngine.feed(&state, catID: "cat_001", now: now)
        _ = GameEngine.claimTask(&state, id: "tutorial_feed", now: now)
        _ = GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: state.tasks.dailyDayKey, now: now)
        try await repository.save(state)
        var reloaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: midnight)
        #expect(reloaded == state)
        _ = GameEngine.synchronize(&reloaded, now: midnight)
        #expect(reloaded.tasks.dailyFeedCount == 0 && reloaded.tasks.dailyClaimedTaskIDs.isEmpty)
        #expect(reloaded.tasks.claimedTaskIDs == ["tutorial_feed"] && reloaded.player.gold == state.player.gold)
        try await repository.save(reloaded)
        var reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: midnight)
        #expect(GameEngine.claimTask(&reopened, id: "tutorial_feed", now: midnight).failure == .taskAlreadyClaimed)
        #expect(reopened == reloaded)
    }
}
