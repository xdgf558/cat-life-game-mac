import Foundation
import Testing
@testable import CatGameCore

@Suite("Station Cat (2.5)")
struct StationCatTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    /// A garden trip whose first footprint met the Station Cat.
    private func sighting() throws -> GameSnapshot {
        for seed in UInt64(1)...20_000 {
            var state = GameSnapshot.fresh(now: now)
            state.player.stamina = 100
            state.cats[0].satiety = 100
            state.cats[0].energy = 100
            guard GameEngine.startOuting(&state, catID: state.cats[0].id, seed: seed, now: now).succeeded else { continue }
            _ = GameEngine.exploreOuting(&state, spot: .path, now: now)
            if state.outing.trip?.pendingStationCat != nil { return state }
        }
        Issue.record("no seed met the Station Cat")
        throw CancellationError()
    }

    private func withStationCat(satiety: Int = 80) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.cats.append(CatState(id: CatCatalog.stationCatID, name: CatCatalog.stationCatName, satiety: satiety,
                                   now: now, appearance: .station))
        return state
    }

    @Test func oldSavesHaveNoCatGrassAndNoStationCat() throws {
        let data = try JSONEncoder().encode(GameSnapshot.fresh(now: now))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "stationCat")
        var inventory = try #require(object["inventory"] as? [String: Any])
        inventory.removeValue(forKey: "catGrass")
        object["inventory"] = inventory
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
        #expect(decoded.inventory.catGrass == 0)
        #expect(decoded.stationCat == StationCatState())
        #expect(decoded.isValid)
    }

    @Test func catGrassIsBoughtLikeAnySupply() {
        var state = GameSnapshot.fresh(now: now)
        state.player.gold = 100
        #expect(GameEngine.buySupply(&state, kind: .catGrass, quantity: 2, now: now).succeeded)
        #expect(state.inventory.catGrass == 2)
        #expect(state.player.gold == 100 - 2 * StationCatRules.catGrassPrice)
    }

    @Test func luringNeedsCatGrassAndBringsItHome() throws {
        var state = try sighting()
        let before = state
        #expect(GameEngine.exploreOuting(&state, spot: .path, now: now).failure == .stationCatPending)
        #expect(GameEngine.lureStationCat(&state, now: now).failure == .stationCatGrassRequired)
        #expect(state == before)

        state.inventory.catGrass = 1
        #expect(GameEngine.lureStationCat(&state, now: now).success == .stationCatCaught)
        let cat = try #require(state.cats.first { $0.id == CatCatalog.stationCatID })
        #expect(cat.appearance == .station && cat.growthState?.sex == .male)
        #expect(state.inventory.catGrass == 0)
        #expect(state.outing.trip?.pendingStationCat == nil)
        #expect(state.outing.trip?.log.last?.optionID == "lure")
        #expect(state.stationCat.timesCaught == 1)
    }

    @Test func lettingItGoOrEndingTheTripLeavesItInTheGarden() throws {
        var state = try sighting()
        #expect(GameEngine.letStationCatGo(&state, now: now).success == .stationCatLeft)
        #expect(!StationCatRules.owns(state) && state.outing.trip?.pendingStationCat == nil)

        var ended = try sighting()
        _ = GameEngine.endOuting(&ended, now: now)
        #expect(ended.outing.trip == nil && !StationCatRules.owns(ended))
    }

    @Test func itNeverShowsUpWhileItLivesHere() throws {
        var state = withStationCat()
        state.player.stamina = 100
        state.cats[0].satiety = 100
        state.cats[0].energy = 100
        for seed in UInt64(1)...2_000 {
            var trip = state
            _ = GameEngine.startOuting(&trip, catID: trip.cats[0].id, seed: seed, now: now)
            _ = GameEngine.exploreOuting(&trip, spot: .path, now: now)
            #expect(trip.outing.trip?.pendingStationCat == nil)
        }
    }

    @Test func shiftsStartedWhileItLivesHerePayDouble() throws {
        let job = try #require(WorkCatalog.job(id: "job_flyer"))
        var plain = GameSnapshot.fresh(now: now)
        var doubled = withStationCat()
        #expect(GameEngine.startWork(&plain, now: now).succeeded)
        #expect(GameEngine.startWork(&doubled, now: now).succeeded)
        #expect(plain.player.activeWork?.goldReward == job.goldReward)
        #expect(doubled.player.activeWork?.goldReward == job.goldReward * StationCatRules.wageMultiplier)
    }

    @Test func itRunsAwayAfterSixHungryHoursAndCanBeCaughtAgain() throws {
        var state = withStationCat(satiety: StationCatRules.hungryBelow)
        state.activeCatID = CatCatalog.stationCatID
        // Satiety drops below the line after one 12-minute step; the clock starts there.
        let hungryAt = now.addingTimeInterval(12 * 60)
        _ = GameEngine.synchronize(&state, now: hungryAt.addingTimeInterval(StationCatRules.runAwayAfter - 1))
        #expect(StationCatRules.owns(state))
        #expect(state.stationCat.hungrySince == hungryAt)

        _ = GameEngine.synchronize(&state, now: hungryAt.addingTimeInterval(StationCatRules.runAwayAfter))
        #expect(!StationCatRules.owns(state))
        #expect(state.activeCatID == state.cats[0].id)
        #expect(state.stationCat.noticePending && state.stationCat.timesRanAway == 1)
        #expect(state.stationCat.ranAwayAt == hungryAt.addingTimeInterval(StationCatRules.runAwayAfter))
        #expect(state.isValid)

        #expect(GameEngine.acknowledgeStationCatNotice(&state, now: hungryAt.addingTimeInterval(StationCatRules.runAwayAfter)).succeeded)
        #expect(!state.stationCat.noticePending)
    }

    @Test func feedingInTimeStopsTheClock() throws {
        var state = withStationCat(satiety: StationCatRules.hungryBelow)
        state.inventory.food = 3
        let later = now.addingTimeInterval(3 * 3600)
        #expect(GameEngine.feed(&state, catID: CatCatalog.stationCatID, now: later).succeeded)
        _ = GameEngine.synchronize(&state, now: later.addingTimeInterval(1))
        #expect(state.stationCat.hungrySince == nil)
        _ = GameEngine.synchronize(&state, now: later.addingTimeInterval(4 * 3600))
        #expect(StationCatRules.owns(state))
    }

    @Test func aClockSavedBeforeAMealIsNotReused() throws {
        // Fed after the clock started, then saved before any sync cleared it.
        var state = withStationCat(satiety: 80)
        state.stationCat.hungrySince = now.addingTimeInterval(-5 * 3600)
        // Satiety 80 falls under the line after 51 twelve-minute steps.
        let crossed = now.addingTimeInterval(51 * 12 * 60)
        _ = GameEngine.synchronize(&state, now: crossed.addingTimeInterval(60))
        #expect(StationCatRules.owns(state))
        #expect(state.stationCat.hungrySince == crossed)
    }
}
