import Foundation

/// 3.2 猫町集市: handmade clothes can be swapped with a neighbour (one deal per neighbour a day) or
/// sold to the shop for gold. Requests are worked out from the day and the neighbour, so they are the
/// same all day and on every launch; the save only keeps who has already traded today and the totals.

/// What a neighbour is looking for today.
public enum BazaarWant: Equatable, Sendable {
    case slot(EquipmentSlot)
    case theme(CraftTheme)
    /// Any piece about to break (under 20%): Grace mends old things.
    case fragile

    /// Strings: `bazaar.want.slot.<slot>`, `bazaar.want.theme.<theme>`, `bazaar.want.fragile`.
    public var key: String {
        switch self {
        case .slot(let slot): "bazaar.want.slot.\(slot.rawValue)"
        case .theme(let theme): "bazaar.want.theme.\(theme.rawValue)"
        case .fragile: "bazaar.want.fragile"
        }
    }

    /// Only a piece that fits; most neighbours turn down one that is about to break.
    public func accepts(_ item: HandmadeItem) -> Bool {
        guard let blueprint = item.blueprint, let slot = blueprint.product.slot else { return false }
        switch self {
        case .slot(let wanted): return slot == wanted && item.stage != .fragile
        case .theme(let theme): return blueprint.theme == theme && item.stage != .fragile
        case .fragile: return item.stage == .fragile
        }
    }
}

/// One neighbour's request for the day.
public struct BazaarRequest: Equatable, Sendable, Identifiable {
    public let neighborID: String
    public let want: BazaarWant
    public let gold: Int
    public let materials: [CraftCost]
    /// Now and then a neighbour hands over a blueprint copy as well.
    public let blueprintID: String?
    public var id: String { neighborID }
    /// The neighbour's own words for this kind of request.
    public var lineKey: String { "bazaar.line.\(neighborID).\(want.key)" }
}

/// What a neighbour gives for one particular piece: the request adjusted by tier, quality and wear.
public struct BazaarDeal: Equatable, Sendable {
    public let gold: Int
    public let materials: [CraftCost]
    public let blueprintID: String?
    /// Against the request as posted: extra (or, for a worn piece, less) gold and extra material.
    public let goldChange: Int
    public let materialChange: Int
}

/// The shop's price, line by line as the sell page shows it.
public struct BazaarSaleQuote: Equatable, Sendable {
    public let basePrice: Int
    /// 100, 130 or 180.
    public let qualityPercent: Int
    public let attributeBonus: Int
    /// 50–100: half a price plus half for the durability left.
    public let durabilityPercent: Int
    /// A piece about to break is only worth half its materials.
    public let isFragile: Bool
    public let materialValue: Int
    public let price: Int
}

/// Why a piece can't go to the bazaar.
public enum BazaarBlocker: Equatable, Sendable {
    case worn, notTradable
}

public struct BazaarState: Codable, Equatable, Sendable {
    /// The day `tradedToday` belongs to.
    public var dayKey: String?
    /// Neighbours already traded with on `dayKey`.
    public var tradedToday: [String]
    public var totalTrades: Int
    public var totalSold: Int

    public init() { dayKey = nil; tradedToday = []; totalTrades = 0; totalSold = 0 }

    private enum CodingKeys: String, CodingKey { case dayKey, tradedToday, totalTrades, totalSold }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try values.decodeIfPresent(String.self, forKey: .dayKey)
        tradedToday = try values.decodeIfPresent([String].self, forKey: .tradedToday) ?? []
        totalTrades = try values.decodeIfPresent(Int.self, forKey: .totalTrades) ?? 0
        totalSold = try values.decodeIfPresent(Int.self, forKey: .totalSold) ?? 0
    }

    public func hasTraded(_ neighborID: String, today: String?) -> Bool {
        dayKey == today && tradedToday.contains(neighborID)
    }
    public func tradesToday(_ today: String?) -> Int { dayKey == today ? tradedToday.count : 0 }

    var isValid: Bool {
        (0...GameSnapshot.maximumGold).contains(totalTrades) && (0...GameSnapshot.maximumGold).contains(totalSold)
            && tradedToday.count <= CommunityCatalog.neighbors.count && Set(tradedToday).count == tradedToday.count
            && tradedToday.allSatisfy { CommunityCatalog.neighbor(id: $0) != nil }
            && tradedToday.count <= totalTrades
            && (dayKey.map { TownEventState.date(for: $0) != nil } ?? tradedToday.isEmpty)
    }
}

public enum BazaarCatalog {
    /// Each trade makes the neighbour like you this much more.
    public static let tradeFriendship = 1
    /// Shop base price by tier, and the gold each attribute adds.
    public static func basePrice(_ tier: CraftTier) -> Int { switch tier { case .basic: 60; case .mid: 110; case .advanced: 200 } }
    public static let attributePrice = 12
    public static func qualityPercent(_ quality: OutingDecorQuality) -> Int {
        switch quality { case .common: 100; case .fine: 130; case .treasured: 180 }
    }
    /// What one of each material is worth to the shop (for pieces about to break).
    public static func materialValue(_ material: CraftMaterial) -> Int {
        switch material { case .fabric: 8; case .thread: 6; case .wood: 6; case .dye: 10; case .stardust: 12 }
    }

    // MARK: Requests

    /// Each neighbour's taste: what they may ask for and what they tend to give.
    private struct Taste {
        let wants: [BazaarWant]
        let materials: [CraftMaterial]
        let materialCount: ClosedRange<Int>
        let gold: ClosedRange<Int>
        /// A second gift of stardust.
        let stardust: ClosedRange<Int>?
        /// Percent of days a blueprint copy comes too.
        let blueprintChance: Int
    }

    private static func taste(_ neighborID: String) -> Taste? {
        switch neighborID {
        case "neighbor_mira":
            Taste(wants: [.slot(.body), .slot(.accessory), .slot(.head)], materials: [.wood, .fabric],
                  materialCount: 3...4, gold: 40...60, stardust: nil, blueprintChance: 0)
        case "neighbor_ken":
            Taste(wants: [.theme(.cafe), .theme(.bazaar), .theme(.winter), .theme(.garden)], materials: [.dye],
                  materialCount: 2...3, gold: 0...0, stardust: 3...5, blueprintChance: 0)
        case "neighbor_luna":
            Taste(wants: [.theme(.rainy), .theme(.starMoon), .slot(.feet)], materials: [.stardust],
                  materialCount: 5...8, gold: 0...20, stardust: nil, blueprintChance: 25)
        case "neighbor_grace":
            Taste(wants: [.fragile, .fragile, .slot(.accessory)], materials: [.thread],
                  materialCount: 2...3, gold: 20...30, stardust: nil, blueprintChance: 0)
        default: nil
        }
    }

    public static func requests(day: String) -> [BazaarRequest] {
        CommunityCatalog.neighbors.compactMap { request(for: $0.id, day: day) }
    }

    public static func request(for neighborID: String, day: String) -> BazaarRequest? {
        guard let taste = taste(neighborID) else { return nil }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "bazaar|\(day)|\(neighborID)".utf8 { hash = (hash ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        var random = OutingRandom(seed: hash, step: 0)
        let want = random.pick(taste.wants) ?? taste.wants[0]
        let material = random.pick(taste.materials) ?? taste.materials[0]
        var materials = [CraftCost(material: material, count: random.int(taste.materialCount))]
        if let stardust = taste.stardust { materials.append(CraftCost(material: .stardust, count: random.int(stardust))) }
        // Gold comes in fives.
        let gold = random.int(taste.gold) / 5 * 5
        var blueprintID: String?
        if taste.blueprintChance > 0, random.percent() < taste.blueprintChance {
            blueprintID = random.pick(CraftCatalog.craftableBlueprints.map(\.id))
        }
        return BazaarRequest(neighborID: neighborID, want: want, gold: gold, materials: materials, blueprintID: blueprintID)
    }

    // MARK: Prices

    /// Better and newer pieces earn more: higher tiers and quality add gold and one more of the
    /// first material; a fresh piece adds a little, a worn one takes a little off.
    public static func deal(_ request: BazaarRequest, for item: HandmadeItem) -> BazaarDeal {
        let tier = item.blueprint?.tier ?? .basic
        var goldChange = switch tier { case .basic: 0; case .mid: 10; case .advanced: 25 }
        var materialChange = 0
        switch item.quality {
        case .common: break
        case .fine: goldChange += 10; materialChange += 1
        case .treasured: goldChange += 20; materialChange += 1
        }
        switch item.stage {
        case .fresh: goldChange += 10
        case .handy, .fragile: break
        case .worn: goldChange -= 10
        }
        let gold = max(0, request.gold + goldChange)
        var materials = request.materials
        if materialChange > 0, let first = materials.first {
            materials[0] = CraftCost(material: first.material, count: first.count + materialChange)
        }
        return BazaarDeal(gold: gold, materials: materials, blueprintID: request.blueprintID,
                          goldChange: gold - request.gold, materialChange: materialChange)
    }

    /// Price = (base × quality + attributes × 12) × (50% + 50% × durability left). A piece about to
    /// break is only worth half of what its materials cost.
    public static func saleQuote(for item: HandmadeItem) -> BazaarSaleQuote {
        let definition = item.blueprint
        let base = basePrice(definition?.tier ?? .basic)
        let quality = qualityPercent(item.quality)
        let attributes = item.attributes.count * attributePrice
        let durability = item.durabilityCap > 0 ? 50 + 50 * item.durability / item.durabilityCap : 50
        let materials = definition?.costs.reduce(0) { $0 + $1.count * materialValue($1.material) } ?? 0
        let fragile = item.stage == .fragile
        let price = fragile ? max(1, materials / 2) : (base * quality / 100 + attributes) * durability / 100
        return BazaarSaleQuote(basePrice: base, qualityPercent: quality, attributeBonus: attributes,
                               durabilityPercent: durability, isFragile: fragile, materialValue: materials, price: price)
    }

    /// Worn pieces must be taken off first; only handmade clothes can be traded or sold.
    public static func blocker(_ item: HandmadeItem, in craft: CraftState) -> BazaarBlocker? {
        guard item.blueprint?.product.slot != nil else { return .notTradable }
        return craft.isWorn(item.id) ? .worn : nil
    }
}

extension GameEngine {
    /// Swap one handmade piece with a neighbour for what they offer today. The piece is gone for good.
    public static func tradeHandmade(_ state: inout GameSnapshot, neighborID: String, itemID: String,
                                     now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let today = state.tasks.dailyDayKey else { return .init(failure: .gameInvalidState) }
        guard let request = BazaarCatalog.request(for: neighborID, day: today) else { return .init(failure: .neighborMissing) }
        guard !state.craft.bazaar.hasTraded(neighborID, today: today) else { return .init(failure: .bazaarTradedToday) }
        guard let item = state.craft.item(id: itemID) else { return .init(failure: .craftItemMissing) }
        if let blocker = BazaarCatalog.blocker(item, in: state.craft) {
            return .init(failure: blocker == .worn ? .bazaarWorn : .bazaarNotTradable)
        }
        guard request.want.accepts(item) else { return .init(failure: .bazaarNotWanted) }
        let deal = BazaarCatalog.deal(request, for: item)
        let timestamp = effectiveTime(state, now: now)
        var candidate = state
        remove(itemID, from: &candidate.craft)
        candidate.player.gold += min(deal.gold, GameSnapshot.maximumGold - candidate.player.gold)
        for cost in deal.materials { CraftRules.add(cost.material, cost.count, to: &candidate.craft) }
        if let blueprintID = deal.blueprintID, let definition = CraftCatalog.blueprint(id: blueprintID) {
            _ = CraftRules.grantCopy(definition, to: &candidate.craft, at: timestamp)
        }
        var bazaar = candidate.craft.bazaar
        if bazaar.dayKey != today { bazaar.dayKey = today; bazaar.tradedToday = [] }
        bazaar.tradedToday.append(neighborID)
        bazaar.totalTrades = min(GameSnapshot.maximumGold, bazaar.totalTrades + 1)
        candidate.craft.bazaar = bazaar
        var relationship = candidate.community.relationship(for: neighborID)
        _ = applyFriendship(BazaarCatalog.tradeFriendship, to: &relationship, in: &candidate)
        candidate.community.relationships[neighborID] = relationship
        // Five trades teach the lucky charm.
        CraftRules.grantEarnedBlueprints(&candidate, at: timestamp)
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .bazaarTraded)
    }

    /// Sell one handmade piece to the shop. It never comes back on the shelves.
    public static func sellHandmade(_ state: inout GameSnapshot, itemID: String, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let item = state.craft.item(id: itemID) else { return .init(failure: .craftItemMissing) }
        if let blocker = BazaarCatalog.blocker(item, in: state.craft) {
            return .init(failure: blocker == .worn ? .bazaarWorn : .bazaarNotTradable)
        }
        let quote = BazaarCatalog.saleQuote(for: item)
        var candidate = state
        remove(itemID, from: &candidate.craft)
        candidate.player.gold += min(quote.price, GameSnapshot.maximumGold - candidate.player.gold)
        candidate.craft.bazaar.totalSold = min(GameSnapshot.maximumGold, candidate.craft.bazaar.totalSold + 1)
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .bazaarSold, amount: quote.price)
    }

    private static func remove(_ itemID: String, from craft: inout CraftState) {
        craft.handmade.removeAll { $0.id == itemID }
        for (slot, id) in craft.appearance where id == itemID { craft.appearance[slot] = nil }
        craft.fragileNotices.removeAll { $0 == itemID }
    }
}
