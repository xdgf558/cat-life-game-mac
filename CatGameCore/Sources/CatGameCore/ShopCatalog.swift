import Foundation

public struct EquipmentOffer: Identifiable, Equatable, Sendable {
    public let itemID: String
    public let price: Int
    public let unlockLevel: Int
    public var id: String { itemID }
}

public struct FurnitureOffer: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: FurnitureKind
    public let price: Int
    public let unlockLevel: Int
    public let maxOwned: Int
    public var nameKey: String { "shop.furniture.\(id).name" }
    public var detailKey: String { "shop.furniture.\(id).detail" }
    public var assetName: String { FurnitureCatalog.metadata(for: kind).assetName }

    var instancePrefix: String { "shop_\(id)_" }
    func instanceID(_ number: Int) -> String { instancePrefix + String(number) }
}

public enum ShopCatalog {
    public static let equipmentOffers: [EquipmentOffer] = [
        .init(itemID: "advanced_cap", price: 360, unlockLevel: 2),
        .init(itemID: "advanced_jacket", price: 480, unlockLevel: 3),
        .init(itemID: "advanced_sneakers", price: 600, unlockLevel: 4),
        .init(itemID: "advanced_charm", price: 720, unlockLevel: 4)
    ]
    public static let furnitureOffers: [FurnitureOffer] = [
        .init(id: "potted_plant", kind: .plant, price: 120, unlockLevel: 2, maxOwned: 10),
        .init(id: "cozy_cushion", kind: .floorCushion, price: 180, unlockLevel: 2, maxOwned: 10),
        .init(id: "oak_bookcase", kind: .bookcase, price: 260, unlockLevel: 3, maxOwned: 10),
        .init(id: "rattan_chair", kind: .rattanChair, price: 320, unlockLevel: 3, maxOwned: 10),
        .init(id: "round_side_table", kind: .sideTable, price: 220, unlockLevel: 2, maxOwned: 10),
        .init(id: "sunrise_art", kind: .wallSunrise, price: 160, unlockLevel: 2, maxOwned: 10)
    ]

    public static func equipmentOffer(itemID: String) -> EquipmentOffer? {
        equipmentOffers.first { $0.itemID == itemID }
    }

    public static func furnitureOffer(id: String) -> FurnitureOffer? {
        furnitureOffers.first { $0.id == id }
    }

    /// Purchased instances are separate from the original room's gifts.
    public static func ownedFurnitureCount(offerID: String, in furniture: [FurnitureItem]) -> Int {
        guard let offer = furnitureOffer(id: offerID) else { return 0 }
        return furniture.filter { $0.id.hasPrefix(offer.instancePrefix) }.count
    }
}
