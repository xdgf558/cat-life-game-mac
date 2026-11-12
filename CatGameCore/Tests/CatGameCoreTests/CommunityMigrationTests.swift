import Foundation
import Testing
@testable import CatGameCore

@Suite("Community migration preserves progress and rejects damaged new ledgers")
struct CommunityMigrationTests {
    let now = Date(timeIntervalSince1970: 1_793_600_000)

    func object(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }
    func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    @Test func schema15FurnitureMigrationKeepsReviewedCommunityLedgers() throws {
        // Freeze the v7 ledger independently of the catalog and fresh-save defaults.
        let schema7IDs = ["neighbor_grace", "neighbor_ken", "neighbor_luna", "neighbor_mira"]
        #expect(GameSnapshot.currentSchemaVersion == 15,
                "Review v15 orientation migration before changing this guard; preserve the independent v7/v8/v10, v11 events, v12/v13 habits and v14 companionship ledgers.")
        #expect(CommunityCatalog.neighbors.map(\.id).sorted() == schema7IDs,
                "Changing neighbors requires a schema/migration review, not just a new catalog entry.")
        let recordedRelationship: [String: Any] = [
            "friendship": 28, "visitedToday": true, "giftsGivenToday": 1,
            "totalVisitCount": 3, "totalGiftCount": 2, "rewardedStageLevels": [2]
        ]
        for schema in [7, 8, 10] {
            var saved = try object(GameSnapshot.fresh(now: now))
            saved["schemaVersion"] = schema
            var ledger: [String: Any] = ["relationships": Dictionary(uniqueKeysWithValues:
                schema7IDs.map { ($0, recordedRelationship) })]
            if schema >= 8 { ledger["exchangeCounts"] = ["neighbor_mira": ["today": 1, "total": 7]] }
            saved["community"] = ledger
            let loaded = try decode(saved)
            #expect(loaded.isValid)
            for id in schema7IDs {
                #expect(loaded.community.relationships[id] == NeighborRelationship(
                    friendship: 28, visitedToday: true, giftsGivenToday: 1,
                    totalVisitCount: 3, totalGiftCount: 2, rewardedStageLevels: [2]))
            }
            #expect(loaded.community.exchangeCount(for: "neighbor_mira") ==
                    (schema >= 8 ? NeighborExchangeCount(today: 1, total: 7) : NeighborExchangeCount()))
            #expect(loaded.community.events.dayKey == loaded.tasks.dailyDayKey)
            #expect(loaded.community.events.totalCompleted == 0 && loaded.community.events.letters.isEmpty)
        }
    }

    @Test func frozenSchemaElevenEventsAndSchemaTwelveAndThirteenHabitLedgersSurviveSchemaFifteen() throws {
        let schema12IDs = ["neighbor_grace", "neighbor_ken", "neighbor_luna", "neighbor_mira"]
        var original = GameSnapshot.fresh(now: now)
        original.home.furniture = FurnitureCatalog.legacyPlacementsV6
        let day = try #require(original.tasks.dailyDayKey)
        original.community.relationships = Dictionary(uniqueKeysWithValues: schema12IDs.map {
            ($0, NeighborRelationship(friendship: 28, visitedToday: true, giftsGivenToday: 1,
                                       totalVisitCount: 3, totalGiftCount: 2, rewardedStageLevels: [2]))
        })
        original.community.exchangeCounts["neighbor_mira"] = .init(today: 1, total: 7)
        original.community.events = .init(dayKey: day, eventID: "retired-v11-event",
            letters: [.init(dayKey: day, eventID: "retired-v11-event", choiceID: "old-choice",
                            neighborID: "neighbor_mira", completedAt: now, friendshipGained: 3,
                            stageBefore: 1, stageAfter: 1, rewards: .init(food: 1))], totalCompleted: 1)
        for schema in [11, 12, 13] {
            var saved = try object(original)
            saved["schemaVersion"] = schema
            var cats = try #require(saved["cats"] as? [[String: Any]])
            if schema >= 12 {
                // Freeze the released v12 receipt shape rather than using current defaults.
                cats[0]["habits"] = [
                    "restClueSessionIDs": ["v12-rest-1", "v12-rest-2"],
                    "playClueSessionIDs": ["v12-play-1", "v12-play-2"],
                    "memories": ["firstResponse", "favoriteRest", "favoritePlay"].map {
                        ["kind": $0, "createdAt": now.timeIntervalSinceReferenceDate] as [String: Any]
                    }
                ]
                saved["catPlay"] = ["tutorialCompleted": true, "introDismissed": true,
                    "tutorialID": "v12-tutorial", "tutorialCatID": "cat_001",
                    "tutorialRhythms": ["slowMove", "moveAndPause"]]
            } else {
                cats[0].removeValue(forKey: "habits")
                saved.removeValue(forKey: "catPlay")
            }
            saved["cats"] = cats
            let loaded = try decode(saved)
            #expect(loaded.isValid && loaded.schemaVersion == 15)
            #expect(loaded.community == original.community)
            #expect(loaded.home.furniture == (schema < 13 ? FurnitureCatalog.frontPlacementsV13 : FurnitureCatalog.legacyPlacementsV6))
            #expect(loaded.player == original.player && loaded.inventory == original.inventory && loaded.tasks == original.tasks)
            if schema >= 12 {
                let habits = loaded.cats[0].habits
                #expect(habits.restClueSessionIDs == ["v12-rest-1", "v12-rest-2"])
                #expect(habits.playClueSessionIDs == ["v12-play-1", "v12-play-2"])
                #expect(habits.memories.map(\.kind) == [.firstResponse, .favoriteRest, .favoritePlay])
                #expect(habits.memories.allSatisfy { $0.createdAt == now })
                #expect(loaded.catPlay.tutorialCompleted && loaded.catPlay.introDismissed)
                #expect(loaded.catPlay.tutorialID == "v12-tutorial" && loaded.catPlay.tutorialCatID == "cat_001")
                #expect(loaded.catPlay.tutorialRhythms == [.slowMove, .moveAndPause])
            } else {
                var empty = CatHabitState()
                empty.seedRestLocations(home: loaded.home, inventory: loaded.inventory)
                #expect(loaded.cats[0].habits == empty && loaded.catPlay == CatPlayState())
            }
        }
    }

    @Test func preCommunitySavesGainEmptyRelationshipsWithoutChangingExistingProgress() throws {
        var expected = GameSnapshot.fresh(now: now)
        expected.player.gold = 876
        expected.player.profile.name = "Milo"
        expected.cats[0].customName = "豆豆"
        expected.tasks.totalFeedCount = 12
        expected.tasks.claimedTaskIDs = ["tutorial_feed"]
        for schema in 1...6 {
            var legacy = try object(expected)
            legacy["schemaVersion"] = schema
            legacy.removeValue(forKey: "community")
            var inventory = try #require(legacy["inventory"] as? [String: Any])
            inventory.removeValue(forKey: "gifts")
            legacy["inventory"] = inventory
            let loaded = try decode(legacy)
            #expect(loaded == expected && loaded.isValid && loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
            #expect(loaded.community.relationships.count == 4 && loaded.inventory.gifts.isEmpty)
        }
    }

    @Test func currentSchemaNeverSilentlyResetsMissingRelationshipsOrGiftInventory() throws {
        let original = try object(GameSnapshot.fresh(now: now))
        for value in [nil, NSNull()] as [Any?] {
            var invalid = original
            invalid["community"] = value
            #expect(throws: (any Error).self) { try decode(invalid) }
            invalid = original
            var inventory = try #require(invalid["inventory"] as? [String: Any])
            inventory["gifts"] = value
            invalid["inventory"] = inventory
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
        var missingRelationship = original
        var community = try #require(original["community"] as? [String: Any])
        var relations = try #require(community["relationships"] as? [String: Any])
        relations.removeValue(forKey: "neighbor_mira")
        community["relationships"] = relations
        missingRelationship["community"] = community
        #expect(throws: (any Error).self) { try decode(missingRelationship) }
    }

    @Test func damagedRelationshipCountersAndRewardReceiptsAreRejected() throws {
        let original = try object(GameSnapshot.fresh(now: now))
        let community = try #require(original["community"] as? [String: Any])
        let relations = try #require(community["relationships"] as? [String: Any])
        let mira = try #require(relations["neighbor_mira"] as? [String: Any])
        for (key, badValue) in [
            ("friendship", -1), ("friendship", 101), ("giftsGivenToday", 2),
            ("totalVisitCount", -1), ("totalGiftCount", -1), ("visitedToday", true),
            ("rewardedStageLevels", [2, 2]), ("rewardedStageLevels", [0]),
            ("rewardedStageLevels", NSNull())
        ] as [(String, Any)] {
            var invalid = original
            var badCommunity = community
            var badRelations = relations
            var badMira = mira
            badMira[key] = badValue
            badRelations["neighbor_mira"] = badMira
            badCommunity["relationships"] = badRelations
            invalid["community"] = badCommunity
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
        for key in mira.keys {
            var invalid = original
            var badCommunity = community
            var badRelations = relations
            var badMira = mira
            badMira.removeValue(forKey: key)
            badRelations["neighbor_mira"] = badMira
            badCommunity["relationships"] = badRelations
            invalid["community"] = badCommunity
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
    }

    @Test func retiredNeighborsGiftsAndRewardReceiptsRemainReadableWithoutBecomingActionable() throws {
        var state = GameSnapshot.fresh(now: now)
        state.community.relationships["retired_neighbor"] = .init(friendship: 25, totalVisitCount: 9,
                                                                 rewardedStageLevels: [2, 99])
        state.inventory.gifts["retired_gift"] = 3
        var loaded = try decode(object(state))
        #expect(loaded == state && loaded.isValid)
        #expect(GameEngine.visitNeighbor(&loaded, neighborID: "retired_neighbor", now: now).failure == .neighborMissing)
        #expect(GameEngine.buyCommunityGift(&loaded, giftID: "retired_gift", now: now).failure == .communityGiftMissing)
        #expect(loaded == state)
    }

    @Test func malformedGiftStockAndUnscopedDailyProgressFailInsteadOfBeingReset() throws {
        let original = try object(GameSnapshot.fresh(now: now))
        for stock in [["flower": -1], ["flower": GameSnapshot.maximumStock + 1], ["": 1]] {
            var invalid = original
            var inventory = try #require(original["inventory"] as? [String: Any])
            inventory["gifts"] = stock
            invalid["inventory"] = inventory
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.visitNeighbor(&state, neighborID: "neighbor_mira", now: now).succeeded)
        var invalid = try object(state)
        var tasks = try #require(invalid["tasks"] as? [String: Any])
        tasks["dailyDayKey"] = NSNull()
        invalid["tasks"] = tasks
        #expect(throws: (any Error).self) { try decode(invalid) }
    }
}
