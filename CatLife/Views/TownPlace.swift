import SwiftUI

enum TownLayer: String, CaseIterable, Identifiable {
    case all, life, neighbors, community
    var id: String { rawValue }
    var titleKey: String { "town.layer.\(rawValue)" }
    var symbol: String {
        switch self {
        case .all: "map.fill"
        case .life: "house.fill"
        case .neighbors: "person.2.fill"
        case .community: "sparkles"
        }
    }
}

/// These places describe navigation only. Future locations never imply unlocked gameplay.
enum TownPlace: String, CaseIterable, Identifiable {
    case street, hospital, cafe, work, plaza, shop, home, board, market, adoption, lot1, lot2
    var id: String { rawValue }
    var isEmpty: Bool { self == .lot1 || self == .lot2 }
    var isFuture: Bool { self == .cafe }
    var layer: TownLayer {
        if self == .street || self == .market { return .neighbors }
        return [.cafe, .plaza, .board].contains(self) ? .community : .life
    }
    var titleKey: String {
        switch self {
        case .hospital: "hospital.title"
        case .shop: "tab.shop"
        case .adoption: "town.title"
        case .lot1, .lot2: "town.place.empty"
        default: "town.place.\(rawValue)"
        }
    }
    var descriptionKey: String {
        if self == .board { return "townEvents.mapDescription" }
        if self == .plaza { return "townEvents.mapPlazaDescription" }
        return isEmpty ? "town.description.empty" : "town.description.\(rawValue)"
    }
    var asset: String {
        switch self {
        case .street: "town-street-cartoon"
        case .hospital: "town-hospital-cartoon"
        case .cafe: "town-cafe-cartoon"
        case .work: "town-work-cartoon"
        case .plaza: "town-plaza-cartoon"
        case .shop: "icon-shop"
        case .home: "town-home-cartoon"
        case .board: "town-board-cartoon"
        case .market: "town-market-cartoon"
        case .adoption: "town-collection-cartoon"
        case .lot1, .lot2: "town-lot-cartoon"
        }
    }
    var symbol: String {
        switch self {
        case .street: "house.fill"
        case .hospital: "cross.case.fill"
        case .cafe: "cup.and.saucer.fill"
        case .work: "briefcase.fill"
        case .plaza: "tree.fill"
        case .shop: "storefront.fill"
        case .home: "house.fill"
        case .board: "pin.fill"
        case .market: "arrow.left.arrow.right.square.fill"
        case .adoption: "book.closed.fill"
        case .lot1, .lot2: "leaf.fill"
        }
    }
    var tint: Color {
        if isFuture { return RoomTheme.lilac }
        switch self {
        case .hospital: return RoomTheme.coral
        case .work, .adoption: return RoomTheme.gold
        case .shop: return Color(red: 0.24, green: 0.50, blue: 0.66)
        case .lot1, .lot2: return TownPalette.emptyEdge
        default: return RoomTheme.darkMint
        }
    }
    var tile: Color {
        if isFuture { return TownPalette.community }
        switch self {
        case .hospital: return Color(red: 0.98, green: 0.89, blue: 0.86)
        case .work: return Color(red: 0.98, green: 0.92, blue: 0.78)
        case .shop: return Color(red: 0.86, green: 0.92, blue: 0.95)
        case .adoption: return Color(red: 0.98, green: 0.89, blue: 0.72)
        case .lot1, .lot2: return .clear
        default: return RoomTheme.paleMint
        }
    }
    func statusKey(sickCount: Int) -> String {
        if isFuture { return "town.comingSoon" }
        if isEmpty { return "town.reserved" }
        return self == .hospital && sickCount > 0 ? "town.attention" : "town.open"
    }
    var actionKey: String {
        if isFuture || isEmpty { return "town.comingSoon" }
        switch self {
        case .plaza, .board: return "townEvents.enter"
        case .street: return "community.enter"
        case .hospital: return "town.enterHospital"
        case .work: return "town.goWork"
        case .shop: return "town.goShop"
        case .home: return "town.goHome"
        case .market: return "market.enter"
        default: return "town.meetCat"
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .hospital: "townHospitalMarker"
        case .home: "townHomeMarker"
        case .adoption: "townAdoptionMarker"
        default: "townPlot_\(rawValue)"
        }
    }
}

enum TownPalette {
    static let grass = Color(red: 0.81, green: 0.90, blue: 0.77)
    static let road = Color(red: 0.91, green: 0.85, blue: 0.72)
    static let community = Color(red: 0.94, green: 0.89, blue: 0.96)
    static let communityEdge = Color(red: 0.79, green: 0.68, blue: 0.85)
    static let emptyEdge = Color(red: 0.62, green: 0.75, blue: 0.56)
    static let woodEdge = Color(red: 0.78, green: 0.55, blue: 0.32)
}
