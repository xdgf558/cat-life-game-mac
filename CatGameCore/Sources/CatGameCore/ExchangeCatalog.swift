import Foundation

public enum ExchangeItem: Hashable, Sendable {
    case supply(SupplyKind), gift(String)

    public var nameKey: String {
        switch self {
        case .supply(let kind): SupplyCatalog.definition(for: kind).nameKey
        case .gift(let id): CommunityCatalog.gift(id: id)?.nameKey ?? "community.giftMissing"
        }
    }
    public var assetName: String {
        switch self {
        case .supply(let kind): SupplyCatalog.definition(for: kind).assetName
        case .gift(let id): CommunityCatalog.gift(id: id)?.assetName ?? ""
        }
    }
    public var symbol: String {
        switch self {
        case .supply(let kind): SupplyCatalog.definition(for: kind).symbol
        case .gift(let id): CommunityCatalog.gift(id: id)?.symbol ?? "gift.fill"
        }
    }
    public func count(in inventory: InventoryState) -> Int {
        switch self {
        case .supply(let kind): inventory.count(kind)
        case .gift(let id): inventory.giftCount(id)
        }
    }

    func add(_ quantity: Int, to inventory: inout InventoryState) {
        switch self {
        case .supply(let kind): inventory[keyPath: kind.stock] += quantity
        case .gift(let id): inventory.gifts[id, default: 0] += quantity
        }
    }
}

public struct ExchangeStack: Equatable, Sendable {
    public let item: ExchangeItem
    public let quantity: Int
}

public struct ExchangeOffer: Identifiable, Equatable, Sendable {
    public let id: String
    public let neighborID: String
    public let requiredStage: Int
    public let inputs: [ExchangeStack]
    public let outputs: [ExchangeStack]
    public var nameKey: String { "market.offer.\(id)" }
}

public enum ExchangeCatalog {
    public static let dailyLimit = 2
    public static let friendship = 2
    public static let offers: [ExchangeOffer] = [
        .init(id: "mira_food", neighborID: "neighbor_mira", requiredStage: 1,
              inputs: [.init(item: .supply(.food), quantity: 2)],
              outputs: [.init(item: .supply(.premiumFood), quantity: 1)]),
        .init(id: "mira_feast", neighborID: "neighbor_mira", requiredStage: 3,
              inputs: [.init(item: .gift("flower"), quantity: 1), .init(item: .supply(.food), quantity: 1)],
              outputs: [.init(item: .supply(.premiumFood), quantity: 2)]),
        .init(id: "ken_toy", neighborID: "neighbor_ken", requiredStage: 1,
              inputs: [.init(item: .gift("drink"), quantity: 1)],
              outputs: [.init(item: .supply(.toy), quantity: 6)]),
        .init(id: "ken_picnic", neighborID: "neighbor_ken", requiredStage: 3,
              inputs: [.init(item: .supply(.toy), quantity: 6), .init(item: .gift("cat_snack"), quantity: 1)],
              outputs: [.init(item: .supply(.premiumFood), quantity: 2)]),
        .init(id: "luna_litter", neighborID: "neighbor_luna", requiredStage: 1,
              inputs: [.init(item: .supply(.litter), quantity: 2)],
              outputs: [.init(item: .supply(.premiumLitter), quantity: 1)]),
        .init(id: "luna_fresh", neighborID: "neighbor_luna", requiredStage: 3,
              inputs: [.init(item: .gift("dessert"), quantity: 1), .init(item: .supply(.litter), quantity: 1)],
              outputs: [.init(item: .supply(.premiumLitter), quantity: 2)]),
        .init(id: "grace_pantry", neighborID: "neighbor_grace", requiredStage: 1,
              inputs: [.init(item: .gift("cat_snack"), quantity: 1)],
              outputs: [.init(item: .supply(.food), quantity: 2)]),
        .init(id: "grace_care", neighborID: "neighbor_grace", requiredStage: 3,
              inputs: [.init(item: .gift("flower"), quantity: 1), .init(item: .gift("drink"), quantity: 1)],
              outputs: [.init(item: .supply(.premiumFood), quantity: 1), .init(item: .supply(.premiumLitter), quantity: 1)])
    ]

    public static func offer(id: String) -> ExchangeOffer? { offers.first { $0.id == id } }

    /// The UI and engine use the same current inventory and per-neighbor ledger.
    public static func eligibility(of offer: ExchangeOffer, in state: GameSnapshot) -> ActionFailure? {
        guard self.offer(id: offer.id) == offer,
              CommunityCatalog.neighbor(id: offer.neighborID) != nil else { return .exchangeMissing }
        guard state.community.relationship(for: offer.neighborID).stage.level >= offer.requiredStage else {
            return .exchangeStageRequired
        }
        guard state.community.exchangeCount(for: offer.neighborID).remainingToday > 0 else { return .exchangeDailyLimit }
        var inventory = state.inventory
        for stack in offer.inputs {
            guard stack.item.count(in: inventory) >= stack.quantity else { return .exchangeMaterialsRequired }
            stack.item.add(-stack.quantity, to: &inventory)
        }
        for stack in offer.outputs {
            guard stack.item.count(in: inventory) <= GameSnapshot.maximumStock - stack.quantity else {
                return .shopInventoryFull
            }
            stack.item.add(stack.quantity, to: &inventory)
        }
        return nil
    }
}

extension GameEngine {
    public static func exchange(_ state: inout GameSnapshot, offerID: String,
                                now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let offer = ExchangeCatalog.offer(id: offerID) else { return .init(failure: .exchangeMissing) }
        if let failure = ExchangeCatalog.eligibility(of: offer, in: state) {
            return .init(failure: failure, amount: failure == .exchangeStageRequired ? offer.requiredStage : 0)
        }
        var candidate = state
        for stack in offer.inputs { stack.item.add(-stack.quantity, to: &candidate.inventory) }
        for stack in offer.outputs { stack.item.add(stack.quantity, to: &candidate.inventory) }
        var count = candidate.community.exchangeCount(for: offer.neighborID)
        count.today += 1
        count.total = min(GameSnapshot.maximumGold, count.total + 1)
        candidate.community.exchangeCounts[offer.neighborID] = count
        var relationship = candidate.community.relationship(for: offer.neighborID)
        let gained = applyFriendship(ExchangeCatalog.friendship, to: &relationship, in: &candidate)
        candidate.community.relationships[offer.neighborID] = relationship
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .exchanged, amount: gained)
    }
}
