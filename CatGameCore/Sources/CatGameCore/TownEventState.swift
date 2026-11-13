import Foundation

public struct TownEventReceipt: Codable, Equatable, Identifiable, Sendable {
    public let dayKey: String
    public let eventID: String
    public let choiceID: String
    public let neighborID: String
    public let completedAt: Date
    public let friendshipGained: Int
    public let stageBefore: Int
    public let stageAfter: Int
    public let rewards: TownEventRewards
    public var id: String { dayKey }
    public var responseKey: String {
        TownEventCatalog.event(id: eventID)?.choices.first { $0.id == choiceID }?.responseKey ?? "townEvents.letter.archived"
    }

    public init(dayKey: String, eventID: String, choiceID: String, neighborID: String, completedAt: Date,
                friendshipGained: Int, stageBefore: Int, stageAfter: Int, rewards: TownEventRewards) {
        self.dayKey = dayKey; self.eventID = eventID; self.choiceID = choiceID; self.neighborID = neighborID
        self.completedAt = completedAt; self.friendshipGained = friendshipGained
        self.stageBefore = stageBefore; self.stageAfter = stageAfter; self.rewards = rewards
    }

    var isValid: Bool {
        TownEventState.date(for: dayKey) != nil
            && [eventID, choiceID, neighborID].allSatisfy(TownEventState.validID)
            && completedAt.timeIntervalSince1970.isFinite
            && (0...100).contains(friendshipGained) && (1...1_000).contains(stageBefore)
            && (stageBefore...1_000).contains(stageAfter) && rewards.isValid
    }
}

public struct TownEventState: Codable, Equatable, Sendable {
    public var dayKey: String?
    public var eventID: String?
    public var letters: [TownEventReceipt]
    public var totalCompleted: Int
    public var claimedMilestoneIDs: [String]
    public var todayReceipt: TownEventReceipt? { letters.last.flatMap { $0.dayKey == dayKey ? $0 : nil } }

    public init(dayKey: String? = nil, eventID: String? = nil, letters: [TownEventReceipt] = [],
                totalCompleted: Int = 0, claimedMilestoneIDs: [String] = []) {
        self.dayKey = dayKey; self.eventID = eventID; self.letters = letters
        self.totalCompleted = totalCompleted; self.claimedMilestoneIDs = claimedMilestoneIDs
    }

    mutating func advance(to key: String?) {
        guard let key, dayKey == nil || key > dayKey! else { return }
        dayKey = key
        eventID = TownEventCatalog.eventID(for: key)
    }

    var isValid: Bool {
        guard (0...GameSnapshot.maximumGold).contains(totalCompleted), letters.count <= 64,
              totalCompleted >= letters.count,
              (totalCompleted == 0) == letters.isEmpty,
              letters.allSatisfy(\.isValid),
              Set(letters.map(\.dayKey)).count == letters.count,
              letters.map(\.dayKey) == letters.map(\.dayKey).sorted(),
              claimedMilestoneIDs.count <= 64,
              claimedMilestoneIDs.allSatisfy(Self.validID),
              Set(claimedMilestoneIDs).count == claimedMilestoneIDs.count else { return false }
        if totalCompleted == 0 && !claimedMilestoneIDs.isEmpty { return false }
        // This schema-11 receipt was issued at seven participations; future balancing cannot invalidate it.
        if claimedMilestoneIDs.contains("town_memory_7") && totalCompleted < 7 { return false }
        guard let dayKey, let eventID else {
            return self.dayKey == nil && self.eventID == nil && totalCompleted == 0
                && letters.isEmpty && claimedMilestoneIDs.isEmpty
        }
        guard Self.date(for: dayKey) != nil, Self.validID(eventID),
              letters.allSatisfy({ $0.dayKey <= dayKey }),
              todayReceipt.map({ $0.eventID == eventID }) ?? true else { return false }
        return true
    }

    static func validID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 80
    }

    static func date(for key: String) -> Date? {
        guard key.utf8.count == 10 else { return nil }
        let pieces = key.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              GameTaskState.dayKey(for: date, timeZone: calendar.timeZone) == key else { return nil }
        return date
    }
}
