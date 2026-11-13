import Foundation
import Testing
@testable import CatGameCore

@Suite("Schema 8 exchange and premium stock migrations")
struct ExchangeMigrationTests {
    let now = Date(timeIntervalSince1970: 1_793_600_000)

    func object(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }
    func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    @Test func v7LedgerKeepsFriendshipReceiptsAndAllStockWhileOnlyNewFieldsDefault() throws {
        var expected = GameSnapshot.fresh(now: now)
        expected.player.gold = 754
        expected.tasks.claimedTaskIDs = ["tutorial_feed"]
        expected.inventory.gifts = ["flower": 3, "retired_gift": 1]
        expected.community.relationships["neighbor_mira"] = .init(friendship: 80, visitedToday: true,
            giftsGivenToday: 1, totalVisitCount: 7, totalGiftCount: 9, rewardedStageLevels: [2, 3, 4, 5])
        var saved = try object(expected)
        saved["schemaVersion"] = 7
        var inventory = try #require(saved["inventory"] as? [String: Any])
        inventory.removeValue(forKey: "premiumFood")
        inventory.removeValue(forKey: "premiumLitter")
        saved["inventory"] = inventory
        var community = try #require(saved["community"] as? [String: Any])
        community.removeValue(forKey: "exchangeCounts")
        saved["community"] = community
        let migrated = try decode(saved)
        #expect(migrated == expected && migrated.isValid)
        #expect(migrated.inventory.premiumFood == 0 && migrated.inventory.premiumLitter == 0)
        #expect(migrated.community.exchangeCounts.isEmpty)
        #expect(try decode(object(migrated)) == migrated)
        for key in ["premiumFood", "premiumLitter"] {
            var corruptInventory = inventory
            corruptInventory[key] = NSNull()
            var corrupt = saved
            corrupt["inventory"] = corruptInventory
            #expect(throws: (any Error).self) { try decode(corrupt) }
        }
        community["exchangeCounts"] = NSNull()
        saved["community"] = community
        #expect(throws: (any Error).self) { try decode(saved) }
    }

    @Test func currentSchemaCannotResetMissingOrMalformedExchangeLimitsOrPremiumStock() throws {
        let valid = try object(GameSnapshot.fresh(now: now))
        for key in ["premiumFood", "premiumLitter"] {
            for value in [nil, NSNull(), "1"] as [Any?] {
                var broken = valid
                var inventory = try #require(broken["inventory"] as? [String: Any])
                inventory[key] = value
                broken["inventory"] = inventory
                #expect(throws: (any Error).self) { try decode(broken) }
            }
        }
        for value in [nil, NSNull(), ["neighbor_mira": ["today": 1]],
                      ["neighbor_mira": ["today": 1, "total": 0]],
                      ["neighbor_mira": ["today": 3, "total": 3]],
                      ["neighbor_mira": ["today": -1, "total": 3]],
                      ["neighbor_mira": ["today": 0, "total": GameSnapshot.maximumGold + 1]],
                      ["unknown": ["today": 0, "total": 1]]] as [Any?] {
            var broken = valid
            var community = try #require(broken["community"] as? [String: Any])
            community["exchangeCounts"] = value
            broken["community"] = community
            #expect(throws: (any Error).self) { try decode(broken) }
        }
        var state = GameSnapshot.fresh(now: now)
        state.community.exchangeCounts["neighbor_mira"] = .init(today: 1, total: 1)
        var broken = try object(state)
        var tasks = try #require(broken["tasks"] as? [String: Any])
        tasks["dailyDayKey"] = NSNull()
        broken["tasks"] = tasks
        #expect(throws: (any Error).self) { try decode(broken) }
    }

    @Test func exportedImportedProgressPreservesSelectedSuppliesAndDailyExchangeReceipts() throws {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.premiumFood = 6
        state.inventory.premiumLitter = 4
        #expect(GameEngine.exchange(&state, offerID: "mira_food", now: now).succeeded)
        #expect(GameEngine.claimTask(&state, id: "tutorial_exchange", now: now).succeeded)
        let encoded = try NativeSaveTransfer.encode(snapshot: state, exportedAt: now)
        let imported = try NativeSaveTransfer.decode(encoded, now: now).snapshot
        #expect(imported == state)
        #expect(imported.inventory.premiumFood == 7 && imported.inventory.premiumLitter == 4)
        #expect(imported.community.exchangeCount(for: "neighbor_mira") == .init(today: 1, total: 1))
        for kind in [SupplyKind.premiumFood, .premiumLitter] {
            for quantity in [-1, GameSnapshot.maximumStock + 1] {
                var invalid = state
                invalid.inventory[keyPath: kind.stock] = quantity
                #expect(throws: NativeSaveTransferError.invalidArchive) {
                    try NativeSaveTransfer.encode(snapshot: invalid, exportedAt: now)
                }
            }
        }
    }

    @Test func retiredNeighborExchangeCountsStayReadableAndCannotBeSpent() throws {
        var state = GameSnapshot.fresh(now: now)
        state.community.relationships["retired_neighbor"] = .init(friendship: 12, totalVisitCount: 1)
        state.community.exchangeCounts["retired_neighbor"] = .init(today: 1, total: 6)
        let restored = try decode(object(state))
        #expect(restored == state && restored.isValid && restored.community.totalExchangeCount == 6)
    }
}
