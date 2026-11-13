import Foundation

public enum CatAppearance: String, Codable, CaseIterable, Sendable {
    case orange, cow, blue, siamese, silver
}

public struct CatAdoptionOffer: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let appearance: CatAppearance
    public let price: Int
    public let requiredPlayerLevel: Int
    public let requiredRoomLevel: Int
}

public enum CatCatalog {
    public static let initialCatID = "cat_001"
    public static let cowCatID = "cat_002"
    public static let blueCatID = "cat_003"
    public static let siameseCatID = "cat_004"
    public static let silverCatID = "cat_005"
    public static let adoptionOffers: [CatAdoptionOffer] = [
        .init(id: cowCatID, name: "牛奶", appearance: .cow, price: 300,
              requiredPlayerLevel: 2, requiredRoomLevel: 2),
        .init(id: blueCatID, name: "蓝影", appearance: .blue, price: 600,
              requiredPlayerLevel: 4, requiredRoomLevel: 3),
        .init(id: siameseCatID, name: "可可", appearance: .siamese, price: 900,
              requiredPlayerLevel: 6, requiredRoomLevel: 3),
        .init(id: silverCatID, name: "霜糖", appearance: .silver, price: 1_200,
              requiredPlayerLevel: 8, requiredRoomLevel: 3)
    ]

    public static func adoptionOffer(catID: String) -> CatAdoptionOffer? {
        adoptionOffers.first { $0.id == catID }
    }
}
