import Foundation
import Testing
@testable import CatGameCore

@Suite("Town-event save migration and archived letters")
struct TownEventMigrationTests {
    let now = Date(timeIntervalSince1970: 1_793_750_400)

    func object(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }
    func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    @Test func schema10AddsAnUncompletedDayWithoutTouchingOldProgress() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.visitNeighbor(&state, neighborID: "neighbor_mira", now: now).succeeded)
        state.player.gold = 871
        state.community.exchangeCounts["neighbor_mira"] = .init(today: 1, total: 8)
        var saved = try object(state)
        saved["schemaVersion"] = 10
        var community = try #require(saved["community"] as? [String: Any])
        community.removeValue(forKey: "events")
        saved["community"] = community
        let loaded = try decode(saved)
        #expect(loaded == state && loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(loaded.community.events.todayReceipt == nil && loaded.community.events.totalCompleted == 0)
        #expect(loaded.community.events.eventID != nil)
        #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: loaded)).snapshot == loaded)
    }

    @Test func currentSchemaMissingFieldsAndCorruptReceiptsDoNotSilentlyReset() throws {
        var state = GameSnapshot.fresh(now: now)
        #expect(GameEngine.resolveTownEvent(&state, eventID: try #require(state.community.events.eventID),
            choiceID: "help", dayKey: try #require(state.community.events.dayKey), now: now).succeeded)
        let saved = try object(state)
        let community = try #require(saved["community"] as? [String: Any])
        let events = try #require(community["events"] as? [String: Any])
        for key in events.keys {
            var damaged = saved
            var badCommunity = community
            var badEvents = events
            badEvents.removeValue(forKey: key)
            badCommunity["events"] = badEvents
            damaged["community"] = badCommunity
            #expect(throws: (any Error).self) { try decode(damaged) }
        }
        for (key, value) in [
            ("letters", []), ("totalCompleted", -1), ("totalCompleted", 0),
            ("claimedMilestoneIDs", ["town_memory_7"]), ("claimedMilestoneIDs", ["retired", "retired"]),
            ("eventID", ""), ("dayKey", "2026-02-30")
        ] as [(String, Any)] {
            var damaged = saved
            var badCommunity = community
            var badEvents = events
            badEvents[key] = value
            badCommunity["events"] = badEvents
            damaged["community"] = badCommunity
            #expect(throws: (any Error).self) { try decode(damaged) }
        }
        let letters = try #require(events["letters"] as? [[String: Any]])
        for key in try #require(letters.first).keys {
            var damaged = saved
            var badCommunity = community
            var badEvents = events
            var badLetter = try #require(letters.first)
            badLetter.removeValue(forKey: key)
            badEvents["letters"] = [badLetter]
            badCommunity["events"] = badEvents
            damaged["community"] = badCommunity
            #expect(throws: (any Error).self) { try decode(damaged) }
        }
    }

    @Test func retiredEventChoiceNeighborAndMilestoneIDsRemainReadableButNotActionable() throws {
        var state = GameSnapshot.fresh(now: now)
        let key = try #require(state.tasks.dailyDayKey)
        let archived = TownEventReceipt(dayKey: key, eventID: "retired-event", choiceID: "old-choice",
            neighborID: "retired-neighbor", completedAt: now, friendshipGained: 3,
            stageBefore: 1, stageAfter: 1, rewards: .init(food: 1))
        state.community.events = .init(dayKey: key, eventID: "retired-event", letters: [archived],
            totalCompleted: 1, claimedMilestoneIDs: ["retired-milestone"])
        var loaded = try decode(object(state))
        #expect(loaded == state && loaded.isValid)
        #expect(loaded.community.events.todayReceipt?.responseKey == "townEvents.letter.archived")
        #expect(TownEventCatalog.current(in: loaded) == nil)
        #expect(GameEngine.resolveTownEvent(&loaded, eventID: "retired-event", choiceID: "old-choice",
            dayKey: key, now: now).failure == .townEventCompleted)
        #expect(GameEngine.claimTownMilestone(&loaded, milestoneID: "retired-milestone", now: now).failure == .townEventMissing)
        #expect(loaded == state)
    }

    @Test func importedLetterTimestampsAreIncludedInTheFutureProgressCheck() throws {
        var state = GameSnapshot.fresh(now: now)
        let key = try #require(state.tasks.dailyDayKey)
        state.community.events.letters = [.init(dayKey: key, eventID: try #require(state.community.events.eventID),
            choiceID: "help", neighborID: "neighbor_mira", completedAt: now.addingTimeInterval(86_401),
            friendshipGained: 4, stageBefore: 1, stageAfter: 1, rewards: .init())]
        state.community.events.totalCompleted = 1
        let archive = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state), now: now)
        #expect(throws: NativeSaveTransferError.futureProgress) {
            try NativeSaveTransfer.validateImportTime(archive, now: now)
        }
        try NativeSaveTransfer.validateImportTime(archive, now: now.addingTimeInterval(1))
    }

    @Test func schema11ClaimedMementoKeepsItsOriginalSevenParticipationFloor() throws {
        var state = try TownEventTests().completedSeven()
        let date = state.meta.lastSyncAt
        #expect(GameEngine.claimTownMilestone(&state, milestoneID: "town_memory_7", now: date).succeeded)
        // Lifetime claims survive compacted or retired letter history independently of today's catalog rewards.
        state.community.events.letters = [try #require(state.community.events.letters.last)]
        #expect(try decode(object(state)) == state)
        state.community.events.totalCompleted = 6
        #expect(throws: (any Error).self) { try decode(object(state)) }
    }
}
