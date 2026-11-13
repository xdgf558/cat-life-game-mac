import Foundation

public enum SupplyKind: String, Codable, CaseIterable, Hashable, Sendable {
    case food, litter, toy, premiumFood, premiumLitter
}

public struct SupplyDefinition: Identifiable, Equatable, Sendable {
    public let kind: SupplyKind
    public let price: Int
    public let unlockLevel: Int
    public let unitsPerPurchase: Int
    public let assetName: String
    public let symbol: String
    public var id: SupplyKind { kind }
    public var nameKey: String { "supply.\(kind.rawValue).name" }
    public var detailKey: String { "supply.\(kind.rawValue).detail" }
}

public enum SupplyCatalog {
    public static func definition(for kind: SupplyKind) -> SupplyDefinition {
        switch kind {
        case .food: .init(kind: kind, price: GameEngine.foodPrice, unlockLevel: 1,
                         unitsPerPurchase: 1, assetName: "bowl-full", symbol: "takeoutbag.and.cup.and.straw.fill")
        case .litter: .init(kind: kind, price: GameEngine.litterPrice, unlockLevel: 1,
                           unitsPerPurchase: 1, assetName: "icon-clean", symbol: "sparkles")
        case .toy: .init(kind: kind, price: GameEngine.toyPrice, unlockLevel: 1,
                        unitsPerPurchase: GameEngine.toyUsesPerPurchase, assetName: "icon-play", symbol: "baseball.fill")
        case .premiumFood: .init(kind: kind, price: 40, unlockLevel: 2,
                                unitsPerPurchase: 1, assetName: "supply-premium-food", symbol: "fish.fill")
        case .premiumLitter: .init(kind: kind, price: 45, unlockLevel: 3,
                                  unitsPerPurchase: 1, assetName: "supply-premium-litter", symbol: "sparkles")
        }
    }
}

extension InventoryState {
    public func count(_ kind: SupplyKind) -> Int { self[keyPath: kind.stock] }
}

extension SupplyKind {
    var stock: WritableKeyPath<InventoryState, Int> {
        switch self {
        case .food: \.food
        case .litter: \.litter
        case .toy: \.toys
        case .premiumFood: \.premiumFood
        case .premiumLitter: \.premiumLitter
        }
    }
}

extension GameEngine {
    public static func buySupply(_ state: inout GameSnapshot, kind: SupplyKind, quantity: Int = 1,
                                 now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard (1...999).contains(quantity) else { return .init(failure: .shopInvalidQuantity) }
        let supply = SupplyCatalog.definition(for: kind)
        guard state.player.level >= supply.unlockLevel else {
            return .init(failure: .shopLevelRequired, amount: supply.unlockLevel)
        }
        let cost = supply.price * quantity
        let units = supply.unitsPerPurchase * quantity
        guard state.player.gold >= cost else { return .init(failure: .shopGoldRequired, amount: cost) }
        guard state.inventory.count(kind) <= GameSnapshot.maximumStock - units else {
            return .init(failure: .shopInventoryFull)
        }
        state.player.gold -= cost
        state.inventory[keyPath: kind.stock] += units
        let success: ActionSuccess
        switch kind {
        case .food: success = .foodPurchased
        case .litter: success = .litterPurchased
        case .toy: success = .toyPurchased
        case .premiumFood, .premiumLitter: success = .supplyPurchased
        }
        return .init(success: success, amount: units)
    }
}
