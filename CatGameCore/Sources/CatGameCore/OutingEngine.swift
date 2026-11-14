import Foundation

/// A placed garden decor piece whose attribute is counted right now.
public struct OutingActiveBonus: Equatable, Sendable, Identifiable {
    public let decorID: String
    public let attribute: OutingDecorAttribute
    public let value: Int
    public let quality: OutingDecorQuality
    public var id: String { decorID }
}

/// Only placed decor counts; per attribute only the best copy, and at most three at once.
public enum OutingBonuses {
    public static func active(in state: GameSnapshot) -> [OutingActiveBonus] {
        let placed = Set(state.home.furniture.map(\.itemID))
        var best: [OutingDecorAttribute: (bonus: OutingActiveBonus, order: Int)] = [:]
        for (order, definition) in OutingCatalog.decor.enumerated() where placed.contains(definition.itemID) {
            guard let roll = state.outing.decor[definition.id]?.kept else { continue }
            let bonus = OutingActiveBonus(decorID: definition.id, attribute: roll.attribute, value: roll.value, quality: roll.quality)
            if let current = best[roll.attribute]?.bonus, (current.value, current.quality.rank) >= (bonus.value, bonus.quality.rank) { continue }
            best[roll.attribute] = (bonus, order)
        }
        let sorted = best.values.sorted { a, b in
            a.bonus.quality.rank != b.bonus.quality.rank ? a.bonus.quality.rank > b.bonus.quality.rank : a.order < b.order
        }
        return Array(sorted.prefix(OutingCatalog.maximumActiveDecor).map(\.bonus))
    }

    public static func value(_ attribute: OutingDecorAttribute, in state: GameSnapshot) -> Int {
        active(in: state).first { $0.attribute == attribute }?.value ?? 0
    }

    /// Placed decor that is not counted (a better copy of its attribute, or over the limit of three).
    public static func inactivePlaced(in state: GameSnapshot) -> [String] {
        let placed = Set(state.home.furniture.map(\.itemID))
        let active = Set(active(in: state).map(\.decorID))
        return OutingCatalog.decor.filter { placed.contains($0.itemID) && state.outing.decor[$0.id] != nil && !active.contains($0.id) }.map(\.id)
    }
}

/// SplitMix64. Each step's seed is stored in the trip, so reloading can't re-roll a result.
struct OutingRandom {
    private var state: UInt64
    init(seed: UInt64, step: Int) { state = seed &+ UInt64(truncatingIfNeeded: step) &* 0x5851_F42D_4C95_7F2D }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func percent() -> Int { int(0...99) }
    mutating func pick<T>(_ items: [T]) -> T? { items.isEmpty ? nil : items[int(0...(items.count - 1))] }
}

extension OutingCatBlocker {
    var failure: ActionFailure {
        switch self {
        case .sick: .outingCatSick
        case .hungry: .outingCatHungry
        case .tired: .outingCatTired
        case .playing: .outingCatBusy
        }
    }
}

extension GameEngine {
    /// Departure is the only time costs are paid: player stamina and the cat's energy, once.
    public static func startOuting(_ state: inout GameSnapshot, catID: String,
                                   seed: UInt64 = .random(in: .min ... .max), now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard state.outing.trip == nil else { return .init(failure: .outingActive) }
        guard let index = state.cats.firstIndex(where: { $0.id == catID }) else { return .init(failure: .careCatMissing) }
        guard state.player.activeWork == nil else { return .init(failure: .outingWorking) }
        guard state.player.activeSleep == nil else { return .init(failure: .outingSleeping) }
        guard state.player.activeNap == nil else { return .init(failure: .outingNapping) }
        guard let today = state.tasks.dailyDayKey else { return .init(failure: .gameInvalidState) }
        guard state.outing.departuresLeft(today: today) > 0 else { return .init(failure: .outingDailyLimit) }
        if let blocker = OutingCatalog.blocker(for: state.cats[index], in: state) { return .init(failure: blocker.failure) }
        guard state.player.stamina >= OutingCatalog.staminaCost else { return .init(failure: .outingStaminaRequired) }
        let timestamp = effectiveTime(state, now: now)
        var candidate = state
        finishCatRest(&candidate, index: index, now: timestamp)
        if candidate.player.stamina == 100 {
            candidate.player.staminaUpdatedAt = max(candidate.player.staminaUpdatedAt, timestamp)
        }
        candidate.player.stamina -= OutingCatalog.staminaCost
        candidate.cats[index].energy = max(0, candidate.cats[index].energy - OutingCatalog.energyCost)
        candidate.cats[index].decayTracker.energy = max(candidate.cats[index].decayTracker.energy, timestamp)
        if candidate.outing.dayKey != today { candidate.outing.dayKey = today; candidate.outing.departuresToday = 0 }
        candidate.outing.departuresToday += 1
        candidate.outing.totalDepartures = min(GameSnapshot.maximumGold, candidate.outing.totalDepartures + 1)
        let footprints = OutingCatalog.footprints + OutingBonuses.value(.footprint, in: candidate)
        candidate.outing.lastSettlement?.acknowledged = true
        candidate.outing.trip = OutingTrip(
            id: "outing-\(Int(timestamp.timeIntervalSince1970))-\(candidate.outing.totalDepartures)", catID: catID,
            dayKey: today, startedAt: timestamp, footprintsTotal: footprints, footprintsLeft: footprints,
            seed: seed, step: 0, visits: [:], loot: [], log: [], pendingEventID: nil, pendingSpot: nil, seenEventIDs: [])
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .outingStarted)
    }

    /// One footprint: a find (keepsake, decor or a little gold), a small event, or a happier cat.
    /// Finds are stored immediately, so leaving early never loses them.
    public static func exploreOuting(_ state: inout GameSnapshot, spot: OutingSpot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard var trip = state.outing.trip else { return .init(failure: .outingMissing) }
        guard trip.pendingEventID == nil else { return .init(failure: .outingEventPending) }
        guard trip.footprintsLeft > 0 else { return .init(failure: .outingNoFootprints) }
        guard let index = state.cats.firstIndex(where: { $0.id == trip.catID }) else { return .init(failure: .careCatMissing) }
        let timestamp = effectiveTime(state, now: now)
        var candidate = state
        var random = OutingRandom(seed: trip.seed, step: trip.step)
        trip.step += 1
        trip.footprintsLeft -= 1
        trip.visits[spot.rawValue, default: 0] += 1
        let entryID = "\(trip.id)-\(trip.step)"
        let favored = OutingHabit.style(spot.favoredStyle).isKnown(for: candidate.cats[index])
        let pool = OutingCatalog.events.filter { ($0.spot == nil || $0.spot == spot) && !trip.seenEventIDs.contains($0.id) }
        if random.percent() < OutingCatalog.eventChance, let event = random.pick(pool) {
            trip.pendingEventID = event.id
            trip.pendingSpot = spot
            trip.seenEventIDs.append(event.id)
            trip.log.append(.init(id: entryID, spot: spot, kind: .event, lootID: nil, eventID: event.id, optionID: nil,
                                  reactionKey: nil, catMood: 0, bond: 0, friendship: 0, neighborID: nil, gold: 0, refundedFootprint: false))
        } else if random.percent() < OutingCatalog.findChance + (favored ? OutingCatalog.favoredFindBonus : 0) {
            let reaction = favored ? "outing.reaction.\(spot.favoredStyle.rawValue)" : "outing.reaction.plain"
            let loot = rollFind(&candidate, spot: spot, catID: trip.catID, random: &random, at: timestamp,
                                lootID: entryID, reaction: reaction)
            trip.loot.append(loot)
            trip.log.append(.init(id: entryID, spot: spot, kind: .find, lootID: loot.id, eventID: nil, optionID: nil,
                                  reactionKey: reaction, catMood: 0, bond: 0, friendship: 0, neighborID: nil, gold: 0, refundedFootprint: false))
        } else {
            let mood = raiseMood(&candidate.cats[index], by: OutingCatalog.nothingMood, at: timestamp)
            trip.log.append(.init(id: entryID, spot: spot, kind: .nothing, lootID: nil, eventID: nil, optionID: nil,
                                  reactionKey: "outing.reaction.nothing", catMood: mood, bond: 0, friendship: 0,
                                  neighborID: nil, gold: 0, refundedFootprint: false))
        }
        candidate.outing.trip = trip
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .outingExplored)
    }

    /// Every option gives something; a habit option is a little warmer, never required.
    public static func chooseOutingEvent(_ state: inout GameSnapshot, optionID: String, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard var trip = state.outing.trip else { return .init(failure: .outingMissing) }
        guard let eventID = trip.pendingEventID, let spot = trip.pendingSpot,
              let event = OutingCatalog.event(id: eventID),
              let index = state.cats.firstIndex(where: { $0.id == trip.catID }),
              let option = event.options(for: state.cats[index]).first(where: { $0.id == optionID })
        else { return .init(failure: .outingEventMissing) }
        let timestamp = effectiveTime(state, now: now)
        var candidate = state
        let effect = option.effect
        let mood = raiseMood(&candidate.cats[index], by: effect.catMood, at: timestamp)
        let bond = min(effect.bond, 100 - candidate.cats[index].intimacy)
        candidate.cats[index].intimacy += bond
        var friendship = 0
        if let neighborID = effect.neighborID, effect.friendship > 0, CommunityCatalog.neighbor(id: neighborID) != nil {
            var relationship = candidate.community.relationship(for: neighborID)
            friendship = applyFriendship(effect.friendship, to: &relationship, in: &candidate)
            candidate.community.relationships[neighborID] = relationship
        }
        let gold = min(effect.gold, GameSnapshot.maximumGold - candidate.player.gold)
        candidate.player.gold += gold
        let refunded = effect.refundsFootprint && trip.footprintsLeft < trip.footprintsTotal
        if refunded { trip.footprintsLeft += 1 }
        let outcome = OutingLogEntry(id: "\(trip.id)-\(trip.step)-\(option.id)", spot: spot, kind: .outcome, lootID: nil,
                                     eventID: eventID, optionID: option.id, reactionKey: event.resultKey(option),
                                     catMood: mood, bond: bond, friendship: friendship, neighborID: effect.neighborID,
                                     gold: gold, refundedFootprint: refunded)
        if let last = trip.log.lastIndex(where: { $0.kind == .event && $0.eventID == eventID }) { trip.log[last] = outcome }
        else { trip.log.append(outcome) }
        trip.pendingEventID = nil
        trip.pendingSpot = nil
        candidate.outing.trip = trip
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .outingEventChosen)
    }

    /// "结束出游": remaining footprints are given up and the trip is settled.
    public static func endOuting(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard state.outing.trip != nil else { return .init(failure: .outingMissing) }
        var candidate = state
        settleOuting(&candidate, reason: .ended, at: effectiveTime(state, now: now))
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .outingEnded)
    }

    public static func acknowledgeOutingSettlement(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard state.outing.lastSettlement?.acknowledged == false else { return ActionOutcome() }
        state.outing.lastSettlement?.acknowledged = true
        return .init(success: .outingAcknowledged)
    }

    /// Keep the old copy or take the new one; the other becomes gold. The piece keeps its place
    /// in the room because the furniture item itself never changes.
    public static func resolveDecorDuplicate(_ state: inout GameSnapshot, decorID: String, keepNew: Bool,
                                             now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard var record = state.outing.decor[decorID], let pending = record.pendingDuplicate else {
            return .init(failure: .outingDuplicateMissing)
        }
        var candidate = state
        if keepNew { record.kept = pending }
        record.pendingDuplicate = nil
        candidate.outing.decor[decorID] = record
        candidate.player.gold += min(OutingCatalog.duplicateDecorGold, GameSnapshot.maximumGold - candidate.player.gold)
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .outingDuplicateResolved)
    }

    public static func setKeepsakeOnShelf(_ state: inout GameSnapshot, keepsakeID: String, onShelf: Bool,
                                          now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard var record = state.outing.keepsakes[keepsakeID] else { return .init(failure: .outingKeepsakeMissing) }
        guard record.onShelf != onShelf else { return ActionOutcome() }
        if onShelf {
            guard state.inventory.furniture.contains(where: { $0.id == OutingCatalog.shelfItemID }) else {
                return .init(failure: .outingShelfMissing)
            }
            guard state.outing.shelfCount < OutingCatalog.shelfSlots else { return .init(failure: .outingShelfFull) }
        }
        var candidate = state
        record.onShelf = onShelf
        candidate.outing.keepsakes[keepsakeID] = record
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .outingShelfUpdated)
    }

    // MARK: Internals

    static func settleOuting(_ state: inout GameSnapshot, reason: OutingEndReason, at timestamp: Date) {
        guard let trip = state.outing.trip else { return }
        state.outing.lastSettlement = OutingSettlement(
            id: trip.id, catID: trip.catID, endedAt: timestamp, reason: reason,
            footprintsTotal: trip.footprintsTotal, footprintsUsed: trip.footprintsUsed, loot: trip.loot,
            catMood: trip.catMood, bond: trip.bond, gold: trip.gold, neighborsMet: trip.neighborsMet, acknowledged: false)
        state.outing.trip = nil
    }

    private static func raiseMood(_ cat: inout CatState, by points: Int, at timestamp: Date) -> Int {
        let gained = max(0, min(points, 100 - cat.mood))
        cat.mood += gained
        if gained > 0 { cat.decayTracker.mood = max(cat.decayTracker.mood, timestamp) }
        return gained
    }

    private static func rollFind(_ state: inout GameSnapshot, spot: OutingSpot, catID: String,
                                 random: inout OutingRandom, at timestamp: Date, lootID: String, reaction: String) -> OutingLoot {
        let roll = random.percent()
        if roll < OutingCatalog.keepsakeShare {
            let here = OutingCatalog.keepsakes(at: spot)
            if let found = random.pick(here.filter { state.outing.keepsakes[$0.id] == nil }) {
                state.outing.keepsakes[found.id] = .init(foundAt: timestamp, catID: catID, storyKey: reaction, onShelf: false)
                grantShelfIfEarned(&state)
                return .init(id: lootID, kind: .keepsake, itemID: found.id, roll: nil, gold: 0, duplicate: false)
            }
            let again = random.pick(here)?.id ?? spot.rawValue
            let gold = addGold(&state, OutingCatalog.duplicateKeepsakeGold)
            return .init(id: lootID, kind: .keepsake, itemID: again, roll: nil, gold: gold, duplicate: true)
        }
        if roll < OutingCatalog.keepsakeShare + OutingCatalog.decorShare, let definition = random.pick(OutingCatalog.decor(at: spot)) {
            let qualityRoll = random.percent()
            let quality: OutingDecorQuality = qualityRoll < 60 ? .common : qualityRoll < 90 ? .fine : .treasured
            let attributes = OutingDecorAttribute.allCases.filter { $0 != .footprint || quality == .treasured }
            let attribute = random.pick(attributes) ?? .catMood
            let decorRoll = OutingDecorRoll(quality: quality, attribute: attribute,
                                            value: random.int(attribute.range(for: quality)), foundAt: timestamp, catID: catID)
            if var record = state.outing.decor[definition.id] {
                // An older copy still waiting for the compare is kept as gold, never lost.
                let gold = record.pendingDuplicate == nil ? 0 : addGold(&state, OutingCatalog.duplicateDecorGold)
                record.pendingDuplicate = decorRoll
                state.outing.decor[definition.id] = record
                return .init(id: lootID, kind: .decor, itemID: definition.id, roll: decorRoll, gold: gold, duplicate: true)
            }
            state.outing.decor[definition.id] = .init(kept: decorRoll, pendingDuplicate: nil)
            if !state.inventory.furniture.contains(where: { $0.id == definition.itemID }) {
                state.inventory.furniture.append(.init(id: definition.itemID, kind: definition.kind))
            }
            return .init(id: lootID, kind: .decor, itemID: definition.id, roll: decorRoll, gold: 0, duplicate: false)
        }
        let gold = addGold(&state, random.int(OutingCatalog.goldRange))
        return .init(id: lootID, kind: .gold, itemID: nil, roll: nil, gold: gold, duplicate: false)
    }

    private static func addGold(_ state: inout GameSnapshot, _ amount: Int) -> Int {
        let gold = min(amount, GameSnapshot.maximumGold - state.player.gold)
        state.player.gold += gold
        return gold
    }

    private static func grantShelfIfEarned(_ state: inout GameSnapshot) {
        guard !state.outing.shelfGranted, state.outing.foundKeepsakeCount >= OutingCatalog.keepsakeShelfThreshold else { return }
        state.outing.shelfGranted = true
        if !state.inventory.furniture.contains(where: { $0.id == OutingCatalog.shelfItemID }) {
            state.inventory.furniture.append(.init(id: OutingCatalog.shelfItemID, kind: .keepsakeShelf))
        }
    }

    /// Home bonuses accrue only across back-to-back syncs (the open game syncs at least once a
    /// minute), so a closed game earns nothing. Not while working or out on a trip.
    static func accrueHomeBonuses(_ state: inout GameSnapshot, at timestamp: Date) {
        let last = state.outing.bonusTickAt
        state.outing.bonusTickAt = timestamp
        guard let last, timestamp > last else { return }
        let gap = timestamp.timeIntervalSince(last)
        let mood = OutingBonuses.value(.catMood, in: state)
        let stamina = OutingBonuses.value(.playerStamina, in: state)
        guard gap <= 150, mood > 0 || stamina > 0, state.player.activeWork == nil, state.outing.trip == nil else {
            if mood == 0 && stamina == 0 { state.outing.bonusCarry = 0 }
            return
        }
        let total = state.outing.bonusCarry + gap
        let hours = Int(total / 3600)
        state.outing.bonusCarry = total - Double(hours) * 3600
        guard hours > 0 else { return }
        for index in state.cats.indices {
            state.cats[index].mood = min(100, state.cats[index].mood + mood * hours)
        }
        if stamina > 0, state.player.activeSleep == nil, state.player.stamina < 100 {
            state.player.stamina = min(100, state.player.stamina + stamina * hours)
            if state.player.stamina == 100 { state.player.staminaUpdatedAt = max(state.player.staminaUpdatedAt, timestamp) }
        }
    }
}
