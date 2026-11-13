import Foundation
import Testing
@testable import CatGameCore

@Suite("Task continuity across travel and legacy purchases")
struct GameTaskExperienceTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        return value
    }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }
    var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: now)! }

    func reload(_ state: GameSnapshot, schema: Int = GameSnapshot.currentSchemaVersion) throws -> GameSnapshot {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["schemaVersion"] = schema
        return try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    @Test func westwardTravelKeepsImmediateCareAndExistingClaimsInTheOpenDay() throws {
        var state = GameSnapshot.fresh(now: now)
        // A westbound trip can leave the saved calendar day ahead of the current local date.
        let openDay = try #require(GameTaskState.dayKey(for: tomorrow))
        state.tasks = GameTaskState(dailyDayKey: openDay, dailyFeedCount: 1, totalFeedCount: 1,
                                    dailyClaimedTaskIDs: ["daily_feed"])
        state.inventory.toys = 1
        #expect(GameEngine.feed(&state, catID: state.activeCatID, now: now).succeeded)
        #expect(GameEngine.clean(&state, catID: state.activeCatID, now: now).succeeded)
        #expect(GameEngine.play(&state, catID: state.activeCatID, now: now).succeeded)
        #expect(state.tasks.dailyDayKey == openDay)
        #expect(state.tasks.dailyFeedCount == 2 && state.tasks.totalFeedCount == 2)
        #expect(state.tasks.dailyCleanCount == 1 && state.tasks.totalCleanCount == 1)
        #expect(state.tasks.dailyPlayCount == 1)
        let gold = state.player.gold
        #expect(GameEngine.claimTask(&state, id: "daily_feed", expectedDayKey: openDay, now: now).failure == .taskAlreadyClaimed)
        #expect(state.player.gold == gold)
        for id in ["daily_clean", "daily_play"] {
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: openDay, now: now).succeeded)
            #expect(GameEngine.claimTask(&state, id: id, expectedDayKey: openDay, now: now).failure == .taskAlreadyClaimed)
        }
        let savedTasks = state.tasks
        state = try reload(state)
        #expect(GameEngine.synchronize(&state, now: tomorrow).succeeded)
        #expect(state.tasks == savedTasks)
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: tomorrow))
        #expect(GameEngine.synchronize(&state, now: nextDay).succeeded)
        #expect(state.tasks.dailyDayKey != openDay && state.tasks.dailyClaimedTaskIDs.isEmpty)
        #expect(state.tasks.dailyFeedCount == 0 && state.tasks.dailyCleanCount == 0 && state.tasks.dailyPlayCount == 0)
        #expect(state.tasks.totalFeedCount == 2 && state.tasks.totalCleanCount == 1)
    }

    @Test func westwardTravelDoesNotReassignEarlierWorkToTheOpenDay() throws {
        var state = GameSnapshot.fresh(now: now)
        state.tasks.dailyDayKey = GameTaskState.dayKey(for: tomorrow)
        state.player.activeWork = ActiveWork(startedAt: now.addingTimeInterval(-120), endsAt: now)
        #expect(GameEngine.synchronize(&state, now: now).kind == .workFinished)
        #expect(state.player.completedWorkCount == 1 && state.tasks.dailyWorkCount == 0)
        #expect(state.tasks.dailyDayKey == GameTaskState.dayKey(for: tomorrow))
        #expect(GameEngine.startWork(&state, now: tomorrow).succeeded)
        let end = try #require(state.player.activeWork?.endsAt)
        #expect(GameEngine.synchronize(&state, now: end).kind == .workFinished)
        #expect(state.player.completedWorkCount == 2 && state.tasks.dailyWorkCount == 1)
        #expect(GameEngine.synchronize(&state, now: end).succeeded)
        #expect(state.player.completedWorkCount == 2 && state.tasks.dailyWorkCount == 1)
    }

    @Test func legacyAndAlreadyMigratedSavesRecoverProvenPurchasesWithoutResettingReceipts() throws {
        var original = GameSnapshot.fresh(now: now)
        original.player.level = 4
        original.inventory.furniture += [
            FurnitureItem(id: "shop_potted_plant_1", kind: .plant),
            FurnitureItem(id: "shop_potted_plant_2", kind: .plant),
            FurnitureItem(id: "shop_cozy_cushion_10", kind: .floorCushion)
        ]
        original.tasks.furniturePurchaseCount = 1
        original.tasks.claimedTaskIDs = ["tutorial_furniture"]
        for version in 1...GameSnapshot.currentSchemaVersion {
            var loaded = try reload(original, schema: version)
            var expected = original
            expected.tasks.furniturePurchaseCount = 3
            #expect(loaded == expected && loaded.isValid)
            #expect(GameEngine.claimTask(&loaded, id: "tutorial_furniture", now: now).failure == .taskAlreadyClaimed)
            #expect(GameEngine.claimTask(&loaded, id: "achievement_furniture3", now: now).succeeded)
            let claimed = loaded
            loaded = try reload(loaded)
            #expect(loaded == claimed)
            #expect(GameEngine.claimTask(&loaded, id: "achievement_furniture3", now: now).failure == .taskAlreadyClaimed)
            #expect(loaded == claimed)
        }
    }

    @Test func onlyExactPurchasedInstancesCountAndExistingHistoryNeverShrinks() throws {
        var original = GameSnapshot.fresh(now: now)
        original.inventory.furniture += [
            FurnitureItem(id: "gift_plant", kind: .plant),
            FurnitureItem(id: "shop_retired_1", kind: .plant),
            FurnitureItem(id: "shop_potted_plant_0", kind: .plant),
            FurnitureItem(id: "shop_potted_plant_11", kind: .plant),
            FurnitureItem(id: "shop_potted_plant_01", kind: .plant),
            FurnitureItem(id: "shop_potted_plant_1", kind: .catBed)
        ]
        for count in [0, 7, GameSnapshot.maximumGold] {
            original.tasks.furniturePurchaseCount = count
            let loaded = try reload(original)
            #expect(loaded == original && loaded.isValid)
            #expect(loaded.tasks.totalFeedCount == 0 && loaded.tasks.totalCleanCount == 0)
        }
    }

    @Test func aNewPurchaseAddsOnceToRecoveredHistoryAndMovingFurnitureDoesNotCount() throws {
        var original = GameSnapshot.fresh(now: now)
        original.player.level = 2
        original.player.gold = 1_000
        original.inventory.furniture.append(FurnitureItem(id: "shop_potted_plant_1", kind: .plant))
        var state = try reload(original)
        #expect(state.tasks.furniturePurchaseCount == 1)
        #expect(GameEngine.purchaseFurniture(&state, offerID: "cozy_cushion", now: now).succeeded)
        #expect(state.tasks.furniturePurchaseCount == 2)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                                         furniture: [], now: now).succeeded)
        let reloaded = try reload(state)
        #expect(reloaded == state && reloaded.tasks.furniturePurchaseCount == 2)
        #expect(reloaded.home.furniture.isEmpty && reloaded.inventory.furniture.count == 11)
    }

    @Test func purchaseEvidenceCannotRepairCorruptedCountersDuringDecode() {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.furniture.append(FurnitureItem(id: "shop_potted_plant_1", kind: .plant))
        for version in 1...GameSnapshot.currentSchemaVersion {
            for count in [-1, GameSnapshot.maximumGold + 1, Int.max] {
                state.tasks.furniturePurchaseCount = count
                #expect(throws: SaveRepositoryError.invalidSnapshot) { try reload(state, schema: version) }
            }
        }
    }
}
