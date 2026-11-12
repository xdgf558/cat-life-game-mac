import Foundation

public struct NeighborDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let favoriteGiftIDs: [String]
    public var nameKey: String { "community.\(id).name" }
    public var descriptionKey: String { "community.\(id).description" }
    public var homeKey: String { "community.\(id).home" }
    public var catsKey: String { "community.\(id).cats" }
    public var portraitAssetName: String { id.replacingOccurrences(of: "_", with: "-") }
    public func dialogueKey(friendship: Int) -> String {
        "community.\(id).dialogue\(friendship >= 60 ? 3 : friendship >= 20 ? 2 : 1)"
    }
    public func giftDialogueKey(giftID: String) -> String {
        "community.\(id).\(favoriteGiftIDs.contains(giftID) ? "favorite" : "thanks")"
    }
}

public struct CommunityGift: Identifiable, Equatable, Sendable {
    public let id: String
    public let price: Int
    public let symbol: String
    public var nameKey: String { "community.gift.\(id).name" }
    public var detailKey: String { "community.gift.\(id).detail" }
    public var assetName: String { "gift-" + id.replacingOccurrences(of: "_", with: "-") }
}

public struct FriendshipStage: Identifiable, Equatable, Sendable {
    public let level: Int
    public let minimumPoints: Int
    public let goldReward: Int
    public let foodReward: Int
    public let litterReward: Int
    public let toyUsesReward: Int
    public var id: Int { level }
    public var nameKey: String { "community.stage.\(level)" }
}

/// These stable IDs belong to the native save; web progress is never imported.
public enum CommunityCatalog {
    public static let dailyGiftLimit = 1
    public static let visitFriendship = 2
    public static let favoriteGiftFriendship = 8
    public static let ordinaryGiftFriendship = 4
    public static let neighbors: [NeighborDefinition] = [
        .init(id: "neighbor_mira", favoriteGiftIDs: ["flower", "cat_snack"]),
        .init(id: "neighbor_ken", favoriteGiftIDs: ["drink"]),
        .init(id: "neighbor_luna", favoriteGiftIDs: ["dessert"]),
        .init(id: "neighbor_grace", favoriteGiftIDs: ["flower"])
    ]
    public static let gifts: [CommunityGift] = [
        .init(id: "flower", price: 20, symbol: "camera.macro"),
        .init(id: "drink", price: 25, symbol: "cup.and.saucer.fill"),
        .init(id: "dessert", price: 30, symbol: "birthday.cake.fill"),
        .init(id: "cat_snack", price: 25, symbol: "fish.fill")
    ]
    public static let stages: [FriendshipStage] = [
        .init(level: 1, minimumPoints: 0, goldReward: 0, foodReward: 0, litterReward: 0, toyUsesReward: 0),
        .init(level: 2, minimumPoints: 20, goldReward: 20, foodReward: 1, litterReward: 0, toyUsesReward: 0),
        .init(level: 3, minimumPoints: 40, goldReward: 30, foodReward: 0, litterReward: 1, toyUsesReward: 0),
        .init(level: 4, minimumPoints: 60, goldReward: 40, foodReward: 1, litterReward: 0, toyUsesReward: 0),
        .init(level: 5, minimumPoints: 80, goldReward: 60, foodReward: 0, litterReward: 0, toyUsesReward: 6)
    ]

    public static func neighbor(id: String) -> NeighborDefinition? { neighbors.first { $0.id == id } }
    public static func gift(id: String) -> CommunityGift? { gifts.first { $0.id == id } }
    public static func stage(friendship: Int) -> FriendshipStage {
        stages.last { $0.minimumPoints <= friendship } ?? stages[0]
    }
    public static func nextStage(friendship: Int) -> FriendshipStage? {
        stages.first { $0.minimumPoints > friendship }
    }
    public static func giftFriendship(neighborID: String, giftID: String) -> Int {
        guard let neighbor = neighbor(id: neighborID), gift(id: giftID) != nil else { return 0 }
        return neighbor.favoriteGiftIDs.contains(giftID) ? favoriteGiftFriendship : ordinaryGiftFriendship
    }
}
