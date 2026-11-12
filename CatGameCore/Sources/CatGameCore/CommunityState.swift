import Foundation

public struct NeighborRelationship: Codable, Equatable, Sendable {
    public var friendship: Int
    public var visitedToday: Bool
    public var giftsGivenToday: Int
    public var totalVisitCount: Int
    public var totalGiftCount: Int
    public var rewardedStageLevels: [Int]

    public init(friendship: Int = 0, visitedToday: Bool = false, giftsGivenToday: Int = 0,
                totalVisitCount: Int = 0, totalGiftCount: Int = 0, rewardedStageLevels: [Int] = []) {
        self.friendship = friendship
        self.visitedToday = visitedToday
        self.giftsGivenToday = giftsGivenToday
        self.totalVisitCount = totalVisitCount
        self.totalGiftCount = totalGiftCount
        self.rewardedStageLevels = rewardedStageLevels
    }

    public var stage: FriendshipStage { CommunityCatalog.stage(friendship: friendship) }
    public var nextStage: FriendshipStage? { CommunityCatalog.nextStage(friendship: friendship) }
    public var canEarnVisitFriendship: Bool { !visitedToday && friendship < 100 }
    public var remainingGiftsToday: Int { max(0, CommunityCatalog.dailyGiftLimit - giftsGivenToday) }

    var isValid: Bool {
        (0...100).contains(friendship)
            && (0...CommunityCatalog.dailyGiftLimit).contains(giftsGivenToday)
            && (0...GameSnapshot.maximumGold).contains(totalVisitCount)
            && (0...GameSnapshot.maximumGold).contains(totalGiftCount)
            && (!visitedToday || totalVisitCount > 0)
            && giftsGivenToday <= totalGiftCount
            && rewardedStageLevels.count <= 32
            && Set(rewardedStageLevels).count == rewardedStageLevels.count
            && rewardedStageLevels.allSatisfy { (2...1_000).contains($0) }
    }
}

public struct CommunityState: Codable, Equatable, Sendable {
    public var relationships: [String: NeighborRelationship]
    public var exchangeCounts: [String: NeighborExchangeCount]
    public var events: TownEventState

    public init(relationships: [String: NeighborRelationship]? = nil,
                exchangeCounts: [String: NeighborExchangeCount] = [:], events: TownEventState = TownEventState()) {
        self.relationships = relationships ?? Dictionary(uniqueKeysWithValues:
            CommunityCatalog.neighbors.map { ($0.id, NeighborRelationship()) })
        self.exchangeCounts = exchangeCounts
        self.events = events
    }

    private enum CodingKeys: String, CodingKey { case relationships, exchangeCounts, events }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }

    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        relationships = try values.decode([String: NeighborRelationship].self, forKey: .relationships)
        // Only old ledgers predate exchange limits; damaged current counters must not reset.
        exchangeCounts = schemaVersion < 8 && !values.contains(.exchangeCounts)
            ? [:] : try values.decode([String: NeighborExchangeCount].self, forKey: .exchangeCounts)
        events = schemaVersion < 11 && !values.contains(.events)
            ? TownEventState() : try values.decode(TownEventState.self, forKey: .events)
        guard isValid else { throw SaveRepositoryError.invalidSnapshot }
    }

    public func relationship(for neighborID: String) -> NeighborRelationship {
        relationships[neighborID] ?? NeighborRelationship()
    }
    public var dailyVisitCount: Int { relationships.values.filter(\.visitedToday).count }
    public var dailyGiftCount: Int { relationships.values.reduce(0) { $0 + $1.giftsGivenToday } }
    public var totalVisitCount: Int { min(GameSnapshot.maximumGold, relationships.values.reduce(0) { $0 + $1.totalVisitCount }) }
    public var totalGiftCount: Int { min(GameSnapshot.maximumGold, relationships.values.reduce(0) { $0 + $1.totalGiftCount }) }
    public var highestFriendship: Int { relationships.values.map(\.friendship).max() ?? 0 }
    public func exchangeCount(for neighborID: String) -> NeighborExchangeCount {
        exchangeCounts[neighborID] ?? NeighborExchangeCount()
    }
    public var dailyExchangeCount: Int { exchangeCounts.values.reduce(0) { $0 + $1.today } }
    public var totalExchangeCount: Int {
        min(GameSnapshot.maximumGold, exchangeCounts.values.reduce(0) { $0 + $1.total })
    }

    mutating func startNewDay() {
        for id in relationships.keys {
            relationships[id]?.visitedToday = false
            relationships[id]?.giftsGivenToday = 0
        }
        for id in exchangeCounts.keys { exchangeCounts[id]?.today = 0 }
    }

    var isValid: Bool {
        guard relationships.count <= 32, exchangeCounts.count <= 32, events.isValid,
              exchangeCounts.allSatisfy({ id, count in
                  relationships[id] != nil && count.isValid
              }),
              CommunityCatalog.neighbors.allSatisfy({ relationships[$0.id] != nil }),
              relationships.allSatisfy({ id, relationship in
                  !id.isEmpty && id.utf8.count <= 80 && relationship.isValid
              }) else { return false }
        return true
    }
}

public struct NeighborExchangeCount: Codable, Equatable, Sendable {
    public var today: Int
    public var total: Int
    public init(today: Int = 0, total: Int = 0) { self.today = today; self.total = total }
    public var remainingToday: Int { max(0, ExchangeCatalog.dailyLimit - today) }
    var isValid: Bool {
        (0...ExchangeCatalog.dailyLimit).contains(today)
            && (0...GameSnapshot.maximumGold).contains(total) && today <= total
    }
}
