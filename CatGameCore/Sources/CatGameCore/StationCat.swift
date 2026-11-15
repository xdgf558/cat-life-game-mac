import Foundation

/// 2.5: 车站猫. It never comes from adoption: it turns up rarely on a garden outing, comes home if the
/// player lures it with cat grass, doubles every shift's wage while it lives here, and runs back
/// to the garden if it stays hungry too long. Catching it again starts over as a new friend.
public struct StationCatState: Codable, Equatable, Sendable {
    /// When the Station Cat's satiety fell below the hungry line; nil while it is fed or away.
    public var hungrySince: Date?
    public var timesCaught: Int
    public var timesRanAway: Int
    public var ranAwayAt: Date?
    /// The "it ran away" card is waiting to be seen.
    public var noticePending: Bool

    public init() { hungrySince = nil; timesCaught = 0; timesRanAway = 0; ranAwayAt = nil; noticePending = false }

    private enum CodingKeys: String, CodingKey { case hungrySince, timesCaught, timesRanAway, ranAwayAt, noticePending }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hungrySince = try? values.decodeIfPresent(Date.self, forKey: .hungrySince)
        timesCaught = (try? values.decodeIfPresent(Int.self, forKey: .timesCaught)) ?? 0
        timesRanAway = (try? values.decodeIfPresent(Int.self, forKey: .timesRanAway)) ?? 0
        ranAwayAt = try? values.decodeIfPresent(Date.self, forKey: .ranAwayAt)
        noticePending = (try? values.decodeIfPresent(Bool.self, forKey: .noticePending)) ?? false
    }

    /// When the cat runs off if nobody feeds it.
    public var runsAwayAt: Date? { hungrySince?.addingTimeInterval(StationCatRules.runAwayAfter) }

    var isValid: Bool {
        (0...GameSnapshot.maximumGold).contains(timesCaught) && (0...GameSnapshot.maximumGold).contains(timesRanAway)
            && [hungrySince, ranAwayAt].allSatisfy { $0?.timeIntervalSince1970.isFinite ?? true }
    }
}

public enum StationCatRules {
    /// Chance per footprint, in thousandths. With 6 footprints and 2 trips a day that is about one
    /// sighting every six days of full play.
    public static let sightingPerMille = 15
    public static let catGrassPrice = 30
    public static let wageMultiplier = 2
    /// Below this satiety the cat counts as hungry (the same line that stops an outing).
    public static let hungryBelow = OutingCatalog.minimumSatiety
    public static let runAwayAfter: TimeInterval = 6 * 3600
    public static let logEventID = "station-cat"
    private static let decayInterval: TimeInterval = 12 * 60

    public static func owns(_ state: GameSnapshot) -> Bool { state.cats.contains { $0.id == CatCatalog.stationCatID } }

    /// A shift's wage, doubled while the Station Cat lives here when the shift starts.
    public static func wage(_ base: Int, in state: GameSnapshot) -> Int {
        owns(state) ? min(1_000_000, base * wageMultiplier) : base
    }

    /// Rolled on its own stream, so adding the Station Cat never changes any other outing result.
    static func appears(on trip: OutingTrip, in state: GameSnapshot) -> Bool {
        guard !owns(state), !trip.metStationCat else { return false }
        var random = OutingRandom(seed: trip.seed ^ 0x5354_4154_494F_4E43, step: trip.step)
        return random.int(0...999) < sightingPerMille
    }

    static func resolveSighting(_ trip: inout OutingTrip, caught: Bool) {
        guard let spot = trip.pendingStationCat else { return }
        trip.pendingStationCat = nil
        guard let index = trip.log.lastIndex(where: { $0.kind == .stationCat }) else { return }
        let entry = trip.log[index]
        trip.log[index] = OutingLogEntry(id: entry.id, spot: spot, kind: .outcome, lootID: nil, eventID: logEventID,
                                         optionID: caught ? "lure" : "leave",
                                         reactionKey: caught ? "stationCat.log.caught" : "stationCat.log.left",
                                         catMood: 0, bond: 0, friendship: 0, neighborID: nil, gold: 0, refundedFootprint: false)
    }

    /// Called for the Station Cat on every sync, right after its needs are settled. The hungry clock starts
    /// at the moment satiety actually crossed the line, worked out from the decay, so time spent with the
    /// game closed counts the same as time with it open.
    /// A cat that was fed at the start of this sync always gets a fresh clock: a feed raises satiety without
    /// a sync of its own, so a clock saved from before the meal must not carry over.
    static func trackHunger(_ station: inout StationCatState, cat: CatState, before: (satiety: Int, tracker: Date), at timestamp: Date) {
        guard cat.satiety < hungryBelow else { station.hungrySince = nil; return }
        if before.satiety >= hungryBelow {
            let steps = Double(before.satiety - hungryBelow + 1)
            station.hungrySince = min(timestamp, before.tracker.addingTimeInterval(steps * decayInterval))
        } else if station.hungrySince == nil {
            station.hungrySince = timestamp
        }
    }
}

extension GameEngine {
    /// Spend one cat grass on the waiting Station Cat; it follows the player home.
    public static func lureStationCat(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard var trip = state.outing.trip, trip.pendingStationCat != nil else { return .init(failure: .stationCatMissing) }
        guard !StationCatRules.owns(state) else { return .init(failure: .catAlreadyOwned) }
        guard state.inventory.catGrass >= 1 else { return .init(failure: .stationCatGrassRequired) }
        let timestamp = effectiveTime(state, now: now)
        var candidate = state
        candidate.inventory.catGrass -= 1
        StationCatRules.resolveSighting(&trip, caught: true)
        candidate.outing.trip = trip
        candidate.cats.append(CatState(id: CatCatalog.stationCatID, name: CatCatalog.stationCatName,
            satiety: 50, cleanliness: 70, mood: 75, intimacy: 5, energy: 70, health: 100,
            now: timestamp, appearance: .station))
        candidate.cats[candidate.cats.count - 1].habits.seedRestLocations(home: candidate.home, inventory: candidate.inventory)
        candidate.stationCat.timesCaught = min(GameSnapshot.maximumGold, candidate.stationCat.timesCaught + 1)
        candidate.stationCat.hungrySince = nil
        candidate.stationCat.noticePending = false
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .stationCatCaught)
    }

    /// Leave the Station Cat be; it may turn up on another trip.
    public static func letStationCatGo(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard var trip = state.outing.trip, trip.pendingStationCat != nil else { return .init(failure: .stationCatMissing) }
        StationCatRules.resolveSighting(&trip, caught: false)
        var candidate = state
        candidate.outing.trip = trip
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .stationCatLeft)
    }

    public static func acknowledgeStationCatNotice(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        state.stationCat.noticePending = false
        return .init(success: .stationCatNoticeSeen)
    }

    /// The Station Cat leaves for the garden once it has been hungry for `runAwayAfter`. Everything it was
    /// doing ends first (an outing is settled, a play or rest stops), then it is removed; another cat
    /// becomes the companion if it was the one.
    static func stationCatRunsAwayIfDue(_ state: inout GameSnapshot, at timestamp: Date) {
        guard let leavesAt = state.stationCat.runsAwayAt, timestamp >= leavesAt,
              let index = state.cats.firstIndex(where: { $0.id == CatCatalog.stationCatID }),
              state.cats.count > 1 else { return }
        let catID = state.cats[index].id
        if state.outing.trip?.catID == catID { settleOuting(&state, reason: .ended, at: timestamp) }
        if state.catPlay.activeSession?.catID == catID { CatHabitEngine.finishPlay(&state, now: timestamp) }
        finishCatRest(&state, index: index, now: timestamp)
        state.cats.remove(at: index)
        if state.activeCatID == catID { state.activeCatID = state.cats[0].id }
        if state.catPlay.lastResult?.catID == catID { state.catPlay.lastResult = nil }
        if state.catPlay.tutorialCatID == catID { state.catPlay.tutorialCatID = nil; state.catPlay.tutorialID = nil }
        state.stationCat.hungrySince = nil
        state.stationCat.ranAwayAt = leavesAt
        state.stationCat.timesRanAway = min(GameSnapshot.maximumGold, state.stationCat.timesRanAway + 1)
        state.stationCat.noticePending = true
    }
}
