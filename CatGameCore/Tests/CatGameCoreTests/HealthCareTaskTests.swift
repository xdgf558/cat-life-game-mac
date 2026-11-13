import Foundation
import Testing
@testable import CatGameCore

@Suite("Health care goals and cleaning progress migration")
struct HealthCareTaskTests {
    let now = Date(timeIntervalSince1970: 1_793_793_600)

    @Test func cleaningGoalsRewardCareAndKeepTheirLevelGates() throws {
        let expected: [(String, GameTaskCategory, Int, Int, Int, Int)] = [
            ("tutorial_clean", .tutorial, 1, 1, 20, 5),
            ("daily_clean", .daily, 1, 1, 15, 4),
            ("achievement_clean10", .achievement, 2, 10, 100, 20),
            ("achievement_clean30", .achievement, 6, 30, 180, 35)
        ]
        for (id, category, level, target, gold, exp) in expected {
            let task = try #require(GameTaskCatalog.task(id: id))
            #expect(task.category == category && task.requiredLevel == level && task.target == target)
            #expect(task.goldReward == gold && task.expReward == exp && task.destination == .care)
        }
    }

    @Test func cleaningCountsAcrossCatsOnlyAfterSuppliesAreConsumed() {
        var state = GameSnapshot.fresh(now: now)
        state.cats.append(CatState(id: "second", name: "Milk", now: now))
        state.inventory.litter = 2
        for id in ["cat_001", "second"] {
            #expect(GameEngine.clean(&state, catID: id, now: now).succeeded)
        }
        #expect(state.inventory.litter == 0)
        #expect(state.tasks.totalCleanCount == 2 && state.tasks.dailyCleanCount == 2)
        let counted = state
        #expect(GameEngine.clean(&state, catID: "second", now: now).failure == .careLitterRequired)
        #expect(GameEngine.clean(&state, catID: "missing", now: now).failure == .careCatMissing)
        #expect(state == counted)
    }

    @Test func legacyTaskSavesStartCleaningAtZeroAndRetainAllPreviousProgress() throws {
        var state = GameSnapshot.fresh(now: now)
        state.tasks.totalFeedCount = 12
        state.tasks.dailyFeedCount = 2
        state.tasks.furniturePurchaseCount = 3
        state.tasks.claimedTaskIDs = ["tutorial_feed", "tutorial_furniture"]
        state.tasks.dailyClaimedTaskIDs = ["daily_feed"]
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        for version in [3, 4] {
            var object = original
            object["schemaVersion"] = version
            var tasks = try #require(object["tasks"] as? [String: Any])
            tasks.removeValue(forKey: "totalCleanCount")
            tasks.removeValue(forKey: "dailyCleanCount")
            object["tasks"] = tasks
            let upgraded = try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
            #expect(upgraded.tasks == state.tasks && upgraded.player == state.player)
            #expect(upgraded.schemaVersion == GameSnapshot.currentSchemaVersion)
            for id in ["tutorial_clean", "daily_clean", "achievement_clean10", "achievement_clean30"] {
                let task = try #require(GameTaskCatalog.task(id: id))
                #expect(GameTaskCatalog.progress(for: task, in: upgraded) == 0)
                #expect(!GameTaskCatalog.isClaimable(task, in: upgraded))
            }
            // A current header cannot turn a missing counter into a fresh reward opportunity.
            object["schemaVersion"] = GameSnapshot.currentSchemaVersion
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
            }
        }
    }

    @Test func legacyCleaningFieldsIfPresentMustStillBeValid() throws {
        let state = GameSnapshot.fresh(now: now)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        for version in 3...GameSnapshot.currentSchemaVersion {
            for (key, value) in [("dailyCleanCount", NSNull()), ("totalCleanCount", NSNull()),
                                 ("totalCleanCount", -1), ("dailyCleanCount", 1)] as [(String, Any)] {
                var object = original
                object["schemaVersion"] = version
                var tasks = try #require(object["tasks"] as? [String: Any])
                tasks[key] = value
                object["tasks"] = tasks
                #expect(throws: (any Error).self) {
                    try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
                }
            }
        }
    }

    @Test func cleaningRewardsStayHiddenAfterReloadAndDailyProgressResetsWithoutLosingLifetimeCount() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.clean(&state, catID: state.activeCatID, now: now).succeeded)
        let day = state.tasks.dailyDayKey
        for id in ["tutorial_clean", "daily_clean"] {
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: day, now: now).succeeded)
        }
        #expect(state.player.gold == 235 && state.player.exp == 9)
        var reopened = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state))
        #expect(reopened == state)
        for (id, category) in [("tutorial_clean", GameTaskCategory.tutorial), ("daily_clean", .daily)] {
            #expect(!GameTaskCatalog.remainingTasks(in: reopened, category: category).contains { $0.id == id })
            #expect(GameEngine.claimTask(&reopened, id: id, expectedDayKey: day, now: now).failure == .taskAlreadyClaimed)
        }
        #expect(GameEngine.synchronize(&reopened, now: now.addingTimeInterval(-86_400)).succeeded)
        #expect(reopened == state)
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(GameEngine.synchronize(&reopened, now: tomorrow).succeeded)
        #expect(reopened.tasks.totalCleanCount == 1 && reopened.tasks.dailyCleanCount == 0)
        #expect(reopened.tasks.claimedTaskIDs == ["tutorial_clean"] && reopened.tasks.dailyClaimedTaskIDs.isEmpty)
        #expect(GameEngine.claimTask(&reopened, id: "daily_clean", expectedDayKey: day, now: tomorrow).failure == .taskDayChanged)
        #expect(GameEngine.clean(&reopened, catID: reopened.activeCatID, now: tomorrow).succeeded)
        #expect(reopened.tasks.totalCleanCount == 2 && reopened.tasks.dailyCleanCount == 1)
        #expect(GameEngine.claimTask(&reopened, id: "daily_clean", expectedDayKey: reopened.tasks.dailyDayKey,
                                    now: tomorrow).succeeded)
        #expect(reopened.player.gold == 250 && reopened.player.exp == 13)
    }
}
