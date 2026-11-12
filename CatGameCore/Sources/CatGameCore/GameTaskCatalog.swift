import Foundation

public enum GameTaskCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case tutorial, daily, achievement
    public var id: String { rawValue }
}

public enum GameTaskDestination: String, Sendable {
    case work, care, furnitureShop, upgrade, neighbors, market
}

enum GameTaskMetric: Sendable {
    case totalWork, totalFeed, furniturePurchases, dailyWork, dailyFeed, dailyPlay, totalClean, dailyClean, intimacy, roomLevel
    case dailyVisit, dailyGift, totalVisit, friendship, dailyExchange, totalExchange
}

public struct GameTaskDefinition: Identifiable, Sendable {
    public let id: String
    public let category: GameTaskCategory
    public let target: Int
    public let goldReward: Int
    public let expReward: Int
    public let destination: GameTaskDestination
    public let requiredLevel: Int
    let metric: GameTaskMetric

    init(id: String, category: GameTaskCategory, target: Int, goldReward: Int, expReward: Int,
         destination: GameTaskDestination, metric: GameTaskMetric, requiredLevel: Int = 1) {
        self.id = id
        self.category = category
        self.target = target
        self.goldReward = goldReward
        self.expReward = expReward
        self.destination = destination
        self.metric = metric
        self.requiredLevel = requiredLevel
    }
}

/// Stable IDs are saved as receipts; rewards and conditions always come from this catalog.
/// Keep IDs when renaming tasks; never reuse retired IDs for new rewards.
public enum GameTaskCatalog {
    public static let all: [GameTaskDefinition] = [
        .init(id: "tutorial_work", category: .tutorial, target: 1, goldReward: 30, expReward: 10,
              destination: .work, metric: .totalWork),
        .init(id: "tutorial_feed", category: .tutorial, target: 1, goldReward: 20, expReward: 5,
              destination: .care, metric: .totalFeed),
        .init(id: "tutorial_furniture", category: .tutorial, target: 1, goldReward: 40, expReward: 10,
              destination: .furnitureShop, metric: .furniturePurchases),
        .init(id: "daily_work", category: .daily, target: 1, goldReward: 30, expReward: 8,
              destination: .work, metric: .dailyWork),
        .init(id: "daily_feed", category: .daily, target: 1, goldReward: 15, expReward: 4,
              destination: .care, metric: .dailyFeed),
        .init(id: "daily_play", category: .daily, target: 1, goldReward: 15, expReward: 4,
              destination: .care, metric: .dailyPlay),
        .init(id: "achievement_work10", category: .achievement, target: 10, goldReward: 120, expReward: 25,
              destination: .work, metric: .totalWork),
        .init(id: "achievement_intimacy50", category: .achievement, target: 50, goldReward: 80, expReward: 20,
              destination: .care, metric: .intimacy),
        .init(id: "achievement_room2", category: .achievement, target: 2, goldReward: 100, expReward: 25,
              destination: .upgrade, metric: .roomLevel),
        .init(id: "daily_work2", category: .daily, target: 2, goldReward: 35, expReward: 8,
              destination: .work, metric: .dailyWork, requiredLevel: 2),
        .init(id: "daily_feed2", category: .daily, target: 2, goldReward: 20, expReward: 5,
              destination: .care, metric: .dailyFeed, requiredLevel: 4),
        .init(id: "daily_play2", category: .daily, target: 2, goldReward: 20, expReward: 5,
              destination: .care, metric: .dailyPlay, requiredLevel: 6),
        .init(id: "daily_work3", category: .daily, target: 3, goldReward: 45, expReward: 10,
              destination: .work, metric: .dailyWork, requiredLevel: 10),
        .init(id: "achievement_work25", category: .achievement, target: 25, goldReward: 180, expReward: 35,
              destination: .work, metric: .totalWork, requiredLevel: 2),
        .init(id: "achievement_intimacy75", category: .achievement, target: 75, goldReward: 120, expReward: 25,
              destination: .care, metric: .intimacy, requiredLevel: 2),
        .init(id: "achievement_room3", category: .achievement, target: 3, goldReward: 180, expReward: 35,
              destination: .upgrade, metric: .roomLevel, requiredLevel: 4),
        .init(id: "achievement_furniture3", category: .achievement, target: 3, goldReward: 100, expReward: 20,
              destination: .furnitureShop, metric: .furniturePurchases, requiredLevel: 4),
        .init(id: "achievement_work50", category: .achievement, target: 50, goldReward: 280, expReward: 50,
              destination: .work, metric: .totalWork, requiredLevel: 6),
        .init(id: "achievement_intimacy100", category: .achievement, target: 100, goldReward: 180, expReward: 35,
              destination: .care, metric: .intimacy, requiredLevel: 6),
        .init(id: "achievement_work100", category: .achievement, target: 100, goldReward: 500, expReward: 80,
              destination: .work, metric: .totalWork, requiredLevel: 10),
        .init(id: "achievement_furniture5", category: .achievement, target: 5, goldReward: 180, expReward: 35,
              destination: .furnitureShop, metric: .furniturePurchases, requiredLevel: 10),
        .init(id: "tutorial_clean", category: .tutorial, target: 1, goldReward: 20, expReward: 5,
              destination: .care, metric: .totalClean),
        .init(id: "daily_clean", category: .daily, target: 1, goldReward: 15, expReward: 4,
              destination: .care, metric: .dailyClean),
        .init(id: "achievement_clean10", category: .achievement, target: 10, goldReward: 100, expReward: 20,
              destination: .care, metric: .totalClean, requiredLevel: 2),
        .init(id: "achievement_clean30", category: .achievement, target: 30, goldReward: 180, expReward: 35,
              destination: .care, metric: .totalClean, requiredLevel: 6),
        .init(id: "daily_visit", category: .daily, target: 1, goldReward: 10, expReward: 3,
              destination: .neighbors, metric: .dailyVisit),
        .init(id: "daily_gift", category: .daily, target: 1, goldReward: 10, expReward: 3,
              destination: .neighbors, metric: .dailyGift, requiredLevel: 2),
        .init(id: "achievement_visit10", category: .achievement, target: 10, goldReward: 80, expReward: 15,
              destination: .neighbors, metric: .totalVisit, requiredLevel: 2),
        .init(id: "achievement_friend40", category: .achievement, target: 40, goldReward: 100, expReward: 20,
              destination: .neighbors, metric: .friendship, requiredLevel: 4),
        .init(id: "tutorial_exchange", category: .tutorial, target: 1, goldReward: 20, expReward: 5,
              destination: .market, metric: .totalExchange),
        .init(id: "daily_exchange", category: .daily, target: 1, goldReward: 10, expReward: 3,
              destination: .market, metric: .dailyExchange, requiredLevel: 2),
        .init(id: "achievement_exchange10", category: .achievement, target: 10, goldReward: 80, expReward: 15,
              destination: .market, metric: .totalExchange, requiredLevel: 2),
        .init(id: "achievement_exchange30", category: .achievement, target: 30, goldReward: 160, expReward: 30,
              destination: .market, metric: .totalExchange, requiredLevel: 4)
    ]

    public static func task(id: String) -> GameTaskDefinition? { all.first { $0.id == id } }

    public static func progress(for task: GameTaskDefinition, in state: GameSnapshot) -> Int {
        switch task.metric {
        case .totalWork: state.player.completedWorkCount
        case .totalFeed: state.tasks.totalFeedCount
        case .furniturePurchases: state.tasks.furniturePurchaseCount
        case .dailyWork: state.tasks.dailyWorkCount
        case .dailyFeed: state.tasks.dailyFeedCount
        case .dailyPlay: state.tasks.dailyPlayCount
        case .totalClean: state.tasks.totalCleanCount
        case .dailyClean: state.tasks.dailyCleanCount
        case .intimacy: state.cats.map(\.intimacy).max() ?? 0
        case .roomLevel: state.home.roomLevel
        case .dailyVisit: state.community.dailyVisitCount
        case .dailyGift: state.community.dailyGiftCount
        case .totalVisit: state.community.totalVisitCount
        case .friendship: state.community.highestFriendship
        case .dailyExchange: state.community.dailyExchangeCount
        case .totalExchange: state.community.totalExchangeCount
        }
    }

    public static func isClaimed(_ task: GameTaskDefinition, in state: GameSnapshot) -> Bool {
        (task.category == .daily ? state.tasks.dailyClaimedTaskIDs : state.tasks.claimedTaskIDs).contains(task.id)
    }

    public static func isClaimable(_ task: GameTaskDefinition, in state: GameSnapshot) -> Bool {
        isUnlocked(task, in: state) && !isClaimed(task, in: state) && progress(for: task, in: state) >= task.target
    }

    public static func isUnlocked(_ task: GameTaskDefinition, in state: GameSnapshot) -> Bool {
        state.player.level >= task.requiredLevel
    }

    public static func remainingTasks(in state: GameSnapshot, category: GameTaskCategory) -> [GameTaskDefinition] {
        all.filter { $0.category == category && isUnlocked($0, in: state) && !isClaimed($0, in: state) }
    }

    public static func nextUnlockLevel(in state: GameSnapshot, category: GameTaskCategory) -> Int? {
        all.filter { $0.category == category && !isUnlocked($0, in: state) && !isClaimed($0, in: state) }
            .map(\.requiredLevel).min()
    }
}

public struct GameTaskState: Codable, Equatable, Sendable {
    public var dailyDayKey: String?
    public var dailyWorkCount: Int
    public var dailyFeedCount: Int
    public var dailyPlayCount: Int
    public var dailyCleanCount: Int
    public var totalCleanCount: Int
    public var totalFeedCount: Int
    public var furniturePurchaseCount: Int
    public var claimedTaskIDs: [String]
    public var dailyClaimedTaskIDs: [String]

    public init(dailyDayKey: String? = nil, dailyWorkCount: Int = 0, dailyFeedCount: Int = 0,
                dailyPlayCount: Int = 0, totalFeedCount: Int = 0, furniturePurchaseCount: Int = 0,
                dailyCleanCount: Int = 0, totalCleanCount: Int = 0,
                claimedTaskIDs: [String] = [], dailyClaimedTaskIDs: [String] = []) {
        self.dailyDayKey = dailyDayKey
        self.dailyWorkCount = dailyWorkCount
        self.dailyFeedCount = dailyFeedCount
        self.dailyPlayCount = dailyPlayCount
        self.dailyCleanCount = dailyCleanCount
        self.totalCleanCount = totalCleanCount
        self.totalFeedCount = totalFeedCount
        self.furniturePurchaseCount = furniturePurchaseCount
        self.claimedTaskIDs = claimedTaskIDs
        self.dailyClaimedTaskIDs = dailyClaimedTaskIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case dailyDayKey, dailyWorkCount, dailyFeedCount, dailyPlayCount
        case totalFeedCount, furniturePurchaseCount, claimedTaskIDs, dailyClaimedTaskIDs
        case dailyCleanCount, totalCleanCount
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }

    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases where !values.contains(key) {
            if schemaVersion < 5, key == .dailyCleanCount || key == .totalCleanCount { continue }
            throw DecodingError.keyNotFound(key, .init(codingPath: values.codingPath,
                                                       debugDescription: "Incomplete task state"))
        }
        dailyDayKey = try values.decodeIfPresent(String.self, forKey: .dailyDayKey)
        dailyWorkCount = try values.decode(Int.self, forKey: .dailyWorkCount)
        dailyFeedCount = try values.decode(Int.self, forKey: .dailyFeedCount)
        dailyPlayCount = try values.decode(Int.self, forKey: .dailyPlayCount)
        // Only legacy schemas can lack cleaning counters; current saves must retain them.
        dailyCleanCount = schemaVersion < 5 && !values.contains(.dailyCleanCount)
            ? 0 : try values.decode(Int.self, forKey: .dailyCleanCount)
        totalCleanCount = schemaVersion < 5 && !values.contains(.totalCleanCount)
            ? 0 : try values.decode(Int.self, forKey: .totalCleanCount)
        totalFeedCount = try values.decode(Int.self, forKey: .totalFeedCount)
        furniturePurchaseCount = try values.decode(Int.self, forKey: .furniturePurchaseCount)
        // Retired catalog entries must not make an otherwise valid save unreadable.
        claimedTaskIDs = try values.decode([String].self, forKey: .claimedTaskIDs)
            .filter { GameTaskCatalog.task(id: $0) != nil }
        dailyClaimedTaskIDs = try values.decode([String].self, forKey: .dailyClaimedTaskIDs)
            .filter { GameTaskCatalog.task(id: $0) != nil }
        guard isValid else { throw SaveRepositoryError.invalidSnapshot }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(dailyDayKey, forKey: .dailyDayKey)
        try values.encode(dailyWorkCount, forKey: .dailyWorkCount)
        try values.encode(dailyFeedCount, forKey: .dailyFeedCount)
        try values.encode(dailyPlayCount, forKey: .dailyPlayCount)
        try values.encode(dailyCleanCount, forKey: .dailyCleanCount)
        try values.encode(totalCleanCount, forKey: .totalCleanCount)
        try values.encode(totalFeedCount, forKey: .totalFeedCount)
        try values.encode(furniturePurchaseCount, forKey: .furniturePurchaseCount)
        try values.encode(claimedTaskIDs, forKey: .claimedTaskIDs)
        try values.encode(dailyClaimedTaskIDs, forKey: .dailyClaimedTaskIDs)
    }
}
