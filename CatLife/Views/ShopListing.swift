import SwiftUI
import CatGameCore

enum ShopCategory: String, CaseIterable { case supplies, furniture, equipment }

struct ShopListing: Identifiable, Hashable {
    enum Kind: Hashable { case supply(SupplyKind), equipment, furniture }
    let id: String
    let kind: Kind
    let nameKey: String
    let detailKey: String
    let asset: String
    let symbol: String
    let price: Int
    let unlockLevel: Int
    var limit: Int? = nil

    @MainActor static func list(_ category: ShopCategory) -> [Self] {
        switch category {
        case .supplies:
            return SupplyKind.allCases.map { kind in
                let supply = SupplyCatalog.definition(for: kind)
                return .init(id: kind.rawValue, kind: .supply(kind), nameKey: supply.nameKey,
                             detailKey: supply.detailKey, asset: kind.asset, symbol: kind.symbol,
                             price: supply.price, unlockLevel: supply.unlockLevel)
            }
        case .equipment:
            return ShopCatalog.equipmentOffers.compactMap { offer in
                guard let item = PlayerCatalog.item(id: offer.itemID) else { return nil }
                return .init(id: item.id, kind: .equipment, nameKey: item.nameKey, detailKey: item.detailKey,
                             asset: item.displayAssetName, symbol: "tshirt.fill", price: offer.price,
                             unlockLevel: offer.unlockLevel)
            }
        case .furniture:
            return ShopCatalog.furnitureOffers.map { offer in
                .init(id: offer.id, kind: .furniture, nameKey: offer.nameKey, detailKey: offer.detailKey,
                      asset: FurnitureArtwork68.assetName(for: .init(id: offer.id, kind: offer.kind)), symbol: "sofa.fill", price: offer.price,
                      unlockLevel: offer.unlockLevel, limit: offer.maxOwned)
            }
        }
    }

    func count(in snapshot: GameSnapshot?) -> Int {
        guard let snapshot else { return 0 }
        switch kind {
        case .supply(let supply): return snapshot.inventory.count(supply)
        case .equipment: return snapshot.player.profile.ownedEquipmentIDs.contains(id) ? 1 : 0
        case .furniture: return ShopCatalog.ownedFurnitureCount(offerID: id, in: snapshot.inventory.furniture)
        }
    }

    func isOwned(in snapshot: GameSnapshot?) -> Bool { kind == .equipment && count(in: snapshot) > 0 }

    var tint: Color {
        switch kind {
        case .supply(let supply): supply.tint
        case .equipment: RoomTheme.lilac
        case .furniture: RoomTheme.darkMint
        }
    }

    func canPurchase(in snapshot: GameSnapshot?) -> Bool {
        guard let snapshot else { return false }
        if case .supply(let supply) = kind,
           count(in: snapshot) > GameSnapshot.maximumStock - SupplyCatalog.definition(for: supply).unitsPerPurchase { return false }
        return !isOwned(in: snapshot) && !(limit.map { count(in: snapshot) >= $0 } ?? false)
            && snapshot.player.level >= unlockLevel && snapshot.player.gold >= price
    }

    @MainActor func status(in snapshot: GameSnapshot?) -> String {
        if isOwned(in: snapshot) { return GameStrings.text("gear.owned") }
        if case .supply(let supply) = kind,
           count(in: snapshot) > GameSnapshot.maximumStock - SupplyCatalog.definition(for: supply).unitsPerPurchase {
            return GameStrings.text("action.inventoryFull")
        }
        if let limit, count(in: snapshot) >= limit { return GameStrings.format("shop.furnitureLimit", limit) }
        if (snapshot?.player.level ?? 1) < unlockLevel { return GameStrings.format("career.unlock", unlockLevel) }
        if (snapshot?.player.gold ?? 0) < price { return GameStrings.text("action.insufficientGold") }
        if case .supply = kind { return GameStrings.format("shop.owned", count(in: snapshot)) + " · " + GameStrings.text(detailKey) }
        return GameStrings.text(detailKey)
    }

    func purchaseIdentifier(prefix: String = "shopBuy_") -> String {
        switch kind {
        case .supply(let supply): supply.buyID
        case .equipment, .furniture: prefix + id
        }
    }

    @MainActor func purchase(in store: GameStore) {
        switch kind {
        case .supply(let supply): store.buySupply(supply)
        case .equipment: store.buyEquipment(itemID: id)
        case .furniture: store.buyFurniture(offerID: id)
        }
    }

}
