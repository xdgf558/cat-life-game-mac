import Foundation

/// One rolled decor copy: what it is and how good it turned out.
public struct OutingDecorRoll: Codable, Equatable, Sendable {
    public let quality: OutingDecorQuality
    public let attribute: OutingDecorAttribute
    public let value: Int
    public let foundAt: Date
    public let catID: String

    var isValid: Bool {
        attribute.range(for: quality).contains(value) && (attribute != .footprint || quality == .treasured)
            && foundAt.timeIntervalSince1970.isFinite && OutingState.validID(catID)
    }
}

/// The copy the player keeps, plus a newer duplicate waiting for the keep-old / take-new choice.
public struct OutingDecorRecord: Codable, Equatable, Sendable {
    public var kept: OutingDecorRoll
    public var pendingDuplicate: OutingDecorRoll?
    var isValid: Bool { kept.isValid && (pendingDuplicate?.isValid ?? true) }
}

public struct OutingKeepsakeRecord: Codable, Equatable, Sendable {
    public let foundAt: Date
    public let catID: String
    /// The reaction shown when it was found (the album's "那天的事").
    public let storyKey: String
    public var onShelf: Bool
    var isValid: Bool { foundAt.timeIntervalSince1970.isFinite && OutingState.validID(catID) && OutingState.validID(storyKey) }
}

public enum OutingLootKind: String, Codable, Sendable { case keepsake, decor, gold }

/// Everything the trip brought back, stored the moment it was found.
public struct OutingLoot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: OutingLootKind
    public let itemID: String?
    public let roll: OutingDecorRoll?
    public let gold: Int
    /// A keepsake already in the album (became gold) or a decor copy waiting for the compare.
    public let duplicate: Bool

    public init(id: String, kind: OutingLootKind, itemID: String?, roll: OutingDecorRoll?, gold: Int, duplicate: Bool) {
        self.id = id; self.kind = kind; self.itemID = itemID; self.roll = roll; self.gold = gold; self.duplicate = duplicate
    }

    var isValid: Bool {
        OutingState.validID(id) && (0...1_000).contains(gold) && (roll?.isValid ?? true)
            && (kind == .gold || itemID.map(OutingState.validID) == true)
    }
}

public enum OutingStepKind: String, Codable, Sendable { case find, event, outcome, nothing }

/// One line of "一路上": what happened at a spot, with the values actually applied.
public struct OutingLogEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let spot: OutingSpot
    public let kind: OutingStepKind
    public let lootID: String?
    public let eventID: String?
    public let optionID: String?
    public let reactionKey: String?
    public let catMood: Int
    public let bond: Int
    public let friendship: Int
    public let neighborID: String?
    public let gold: Int
    public let refundedFootprint: Bool
    var isValid: Bool {
        OutingState.validID(id) && [catMood, bond, friendship].allSatisfy { (0...100).contains($0) } && (0...1_000).contains(gold)
    }
}

public struct OutingTrip: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let catID: String
    public let dayKey: String
    public let startedAt: Date
    public let footprintsTotal: Int
    public var footprintsLeft: Int
    public let seed: UInt64
    public var step: Int
    public var visits: [String: Int]
    public var loot: [OutingLoot]
    public var log: [OutingLogEntry]
    public var pendingEventID: String?
    public var pendingSpot: OutingSpot?
    public var seenEventIDs: [String]

    public func visits(at spot: OutingSpot) -> Int { visits[spot.rawValue, default: 0] }
    public var footprintsUsed: Int { footprintsTotal - footprintsLeft }
    public var catMood: Int { log.reduce(0) { $0 + $1.catMood } }
    public var bond: Int { log.reduce(0) { $0 + $1.bond } }
    public var gold: Int { loot.reduce(0) { $0 + $1.gold } + log.reduce(0) { $0 + $1.gold } }
    public var neighborsMet: [String] {
        var seen: [String] = []
        for entry in log { if let id = entry.neighborID, entry.friendship > 0, !seen.contains(id) { seen.append(id) } }
        return seen
    }

    var isValid: Bool {
        OutingState.validID(id) && OutingState.validID(catID) && TownEventState.date(for: dayKey) != nil
            && startedAt.timeIntervalSince1970.isFinite
            && (1...20).contains(footprintsTotal) && (0...footprintsTotal).contains(footprintsLeft)
            && (0...1_000).contains(step) && loot.count <= 64 && log.count <= 64
            && visits.allSatisfy { OutingSpot(rawValue: $0.key) != nil && (0...100).contains($0.value) }
            && loot.allSatisfy(\.isValid) && log.allSatisfy(\.isValid)
            && (pendingEventID == nil) == (pendingSpot == nil) && seenEventIDs.count <= 32
    }
}

public enum OutingEndReason: String, Codable, Sendable { case ended, sleep, newDay }

/// The settlement card. Kept until the player has seen it, then left as the last trip's record.
public struct OutingSettlement: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let catID: String
    public let endedAt: Date
    public let reason: OutingEndReason
    public let footprintsTotal: Int
    public let footprintsUsed: Int
    public let loot: [OutingLoot]
    public let catMood: Int
    public let bond: Int
    public let gold: Int
    public let neighborsMet: [String]
    public var acknowledged: Bool
    var isValid: Bool {
        OutingState.validID(id) && OutingState.validID(catID) && endedAt.timeIntervalSince1970.isFinite
            && (0...footprintsTotal).contains(footprintsUsed) && loot.count <= 64 && loot.allSatisfy(\.isValid)
            && (0...10_000).contains(catMood) && (0...10_000).contains(bond) && (0...100_000).contains(gold)
    }
}

public struct OutingState: Codable, Equatable, Sendable {
    public var trip: OutingTrip?
    public var dayKey: String?
    public var departuresToday: Int
    public var keepsakes: [String: OutingKeepsakeRecord]
    public var decor: [String: OutingDecorRecord]
    public var lastSettlement: OutingSettlement?
    public var shelfGranted: Bool
    /// Home bonuses only accrue across back-to-back syncs while the game is open (no offline accrual).
    public var bonusTickAt: Date?
    public var bonusCarry: TimeInterval
    public var totalDepartures: Int

    public init() {
        trip = nil; dayKey = nil; departuresToday = 0; keepsakes = [:]; decor = [:]
        lastSettlement = nil; shelfGranted = false; bonusTickAt = nil; bonusCarry = 0; totalDepartures = 0
    }

    private enum CodingKeys: String, CodingKey {
        case trip, dayKey, departuresToday, keepsakes, decor, lastSettlement, shelfGranted, bonusTickAt, bonusCarry, totalDepartures
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        trip = try values.decodeIfPresent(OutingTrip.self, forKey: .trip)
        dayKey = try values.decodeIfPresent(String.self, forKey: .dayKey)
        departuresToday = try values.decodeIfPresent(Int.self, forKey: .departuresToday) ?? 0
        keepsakes = try values.decodeIfPresent([String: OutingKeepsakeRecord].self, forKey: .keepsakes) ?? [:]
        decor = try values.decodeIfPresent([String: OutingDecorRecord].self, forKey: .decor) ?? [:]
        lastSettlement = try values.decodeIfPresent(OutingSettlement.self, forKey: .lastSettlement)
        shelfGranted = try values.decodeIfPresent(Bool.self, forKey: .shelfGranted) ?? false
        bonusTickAt = try values.decodeIfPresent(Date.self, forKey: .bonusTickAt)
        bonusCarry = try values.decodeIfPresent(TimeInterval.self, forKey: .bonusCarry) ?? 0
        totalDepartures = try values.decodeIfPresent(Int.self, forKey: .totalDepartures) ?? 0
    }

    public func departuresLeft(today key: String?) -> Int {
        dayKey == key ? max(0, OutingCatalog.dailyDepartures - departuresToday) : OutingCatalog.dailyDepartures
    }
    public var foundKeepsakeCount: Int { keepsakes.keys.filter { OutingCatalog.keepsake(id: $0) != nil }.count }
    public var shelfCount: Int { keepsakes.values.filter(\.onShelf).count }
    public var pendingDuplicates: [String] {
        OutingCatalog.decor.map(\.id).filter { decor[$0]?.pendingDuplicate != nil }
    }
    public var unacknowledgedSettlement: OutingSettlement? { lastSettlement.flatMap { $0.acknowledged ? nil : $0 } }

    static func validID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 120
    }

    var isValid: Bool {
        (0...OutingCatalog.dailyDepartures).contains(departuresToday)
            && (dayKey.map { TownEventState.date(for: $0) != nil } ?? (departuresToday == 0))
            && keepsakes.count <= 64 && decor.count <= 64
            && keepsakes.allSatisfy { Self.validID($0.key) && $0.value.isValid }
            && decor.allSatisfy { Self.validID($0.key) && $0.value.isValid }
            && keepsakes.values.filter(\.onShelf).count <= OutingCatalog.shelfSlots
            && (trip?.isValid ?? true) && (lastSettlement?.isValid ?? true)
            && (bonusTickAt?.timeIntervalSince1970.isFinite ?? true)
            && bonusCarry.isFinite && (0..<3600).contains(bonusCarry)
            && (0...GameSnapshot.maximumGold).contains(totalDepartures)
    }
}
