import Foundation

/// 3.0 魔法小屋与手作工坊 (built to the 3.1 crafting rules): materials, blueprints with uses, a craft
/// skill, success rates, and handmade clothes with a quality and random attributes. Numbers here are
/// the rules; every screen shows what these tables and `CraftEngine` actually use.
public enum CraftMaterial: String, Codable, CaseIterable, Sendable, Identifiable {
    case fabric, thread, wood, dye, stardust
    public var id: String { rawValue }
    public var titleKey: String { "craft.material.\(rawValue)" }
    public var symbol: String {
        switch self {
        case .fabric: "scissors"
        case .thread: "circle.hexagongrid.fill"
        case .wood: "tree.fill"
        case .dye: "paintpalette.fill"
        case .stardust: "sparkles"
        }
    }
}

public enum CraftTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case garden, cafe, starMoon, rainy, winter, bazaar
    public var id: String { rawValue }
    public var titleKey: String { "craft.theme.\(rawValue)" }
}

public enum CraftTier: String, Codable, CaseIterable, Comparable, Sendable {
    case basic, mid, advanced
    public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    public var titleKey: String { "craft.tier.\(rawValue)" }
    public var baseSuccessPercent: Int { switch self { case .basic: 90; case .mid: 75; case .advanced: 55 } }
    /// Uses one blueprint copy brings; holding is capped at two copies.
    public var usesPerCopy: Int { switch self { case .basic: 8; case .mid: 5; case .advanced: 3 } }
    public var maximumUses: Int { usesPerCopy * 2 }
    public var successExperience: Int { switch self { case .basic: 10; case .mid: 20; case .advanced: 35 } }
    public var failureExperience: Int { switch self { case .basic: 5; case .mid: 10; case .advanced: 17 } }
    public var requiredSkillLevel: Int { switch self { case .basic: 1; case .mid: 2; case .advanced: 4 } }
    public var stardustPrice: Int { switch self { case .basic: 15; case .mid: 30; case .advanced: 50 } }
}

/// What a blueprint makes: clothes for one appearance slot, or a cottage decoration.
public enum CraftProduct: Equatable, Sendable {
    case wear(EquipmentSlot)
    case decor
    public var slot: EquipmentSlot? { if case .wear(let slot) = self { slot } else { nil } }
}

/// The first copy's route. Later copies come from the wheel and the stardust exchange.
public enum BlueprintSource: Equatable, Sendable {
    /// First outing that walks every footprint of the garden.
    case gardenWalk
    case keepsake(String)
    case friendship(neighborID: String, stage: Int)
    case cafeNaps(Int)
    case townEvent(String)
    /// An outing that meets the drizzle.
    case rainyOuting
    case craftLevel(Int)
    /// Routes that open with later updates (the bazaar, shares, the shop's daily shelf).
    case bazaarTrades(Int), shares(Int), shopShelf
    /// Only the wheel and the stardust exchange.
    case luck

    public var key: String {
        switch self {
        case .gardenWalk: "gardenWalk"
        case .keepsake: "keepsake"
        case .friendship: "friendship"
        case .cafeNaps: "cafeNaps"
        case .townEvent: "townEvent"
        case .rainyOuting: "rainyOuting"
        case .craftLevel: "craftLevel"
        case .bazaarTrades: "bazaarTrades"
        case .shares: "shares"
        case .shopShelf: "shopShelf"
        case .luck: "luck"
        }
    }
    /// Routes the game can grant today.
    public var isAvailable: Bool {
        switch self {
        case .shares, .shopShelf: false
        default: true
        }
    }
}

public struct CraftCost: Equatable, Sendable, Identifiable {
    public let material: CraftMaterial
    public let count: Int
    public var id: String { material.rawValue }
}

public struct BlueprintDefinition: Equatable, Sendable, Identifiable {
    public let id: String
    public let theme: CraftTheme
    public let product: CraftProduct
    public let tier: CraftTier
    public let costs: [CraftCost]
    public let source: BlueprintSource
    public let symbol: String
    public var nameKey: String { "craft.blueprint.\(id)" }
    public var detailKey: String { "craft.blueprint.\(id).detail" }
    /// Decorations need room art and footprints first, so they open with a later update.
    public var isCraftable: Bool { product != .decor }
    public func cost(of material: CraftMaterial) -> Int { costs.first { $0.material == material }?.count ?? 0 }
}

/// Handmade clothes give small life bonuses; work gear keeps the work bonuses.
public enum HandmadeAttribute: String, Codable, CaseIterable, Sendable {
    /// Extra footprints per outing. Less stamina spent leaving on an outing (percent).
    /// Player mood each new day. More bond from play (percent). More from a café nap (percent).
    /// More gold from work (percent, advanced blueprints only).
    case footprint, outingStamina, dailyMood, bond, napRecovery, workGold
    public var titleKey: String { "craft.attribute.\(rawValue)" }
    public var range: ClosedRange<Int> {
        switch self {
        case .footprint: 1...1
        case .outingStamina: 5...15
        case .dailyMood: 2...6
        case .bond: 3...8
        case .napRecovery: 10...20
        case .workGold: 2...5
        }
    }
    public var isPercent: Bool { ![.footprint, .dailyMood].contains(self) }
    /// Reductions read as minus; everything else as plus.
    public var isReduction: Bool { self == .outingStamina }

    /// Common rolls the lower half, fine the whole range, treasured the top third.
    func range(for quality: OutingDecorQuality) -> ClosedRange<Int> {
        let low = range.lowerBound, high = range.upperBound
        guard high > low else { return range }
        switch quality {
        case .common: return low...max(low, (low + high) / 2)
        case .fine: return range
        case .treasured: return max(low, high - (high - low) / 3)...high
        }
    }
}

public struct HandmadeAttributeRoll: Codable, Equatable, Sendable {
    public let attribute: HandmadeAttribute
    public let value: Int
    var isValid: Bool { attribute.range.contains(value) }
}

public struct CraftSkillLevel: Equatable, Sendable, Identifiable {
    public let level: Int
    /// Total proficiency needed to reach this level.
    public let minimumExperience: Int
    public let successBonus: Int
    public var id: Int { level }
    public var titleKey: String { "craft.skill.\(level)" }
    public var unlockKey: String { "craft.skill.\(level).unlock" }
}

/// One wedge of the magic wheel. `blueprint` hands out a random wearable blueprint copy.
public enum WheelPrize: String, Codable, CaseIterable, Sendable {
    case fabric, thread, wood, dye, stardust, blueprint
    public var material: CraftMaterial? { CraftMaterial(rawValue: rawValue) }
}

public struct WheelSlice: Equatable, Sendable, Identifiable {
    public let prize: WheelPrize
    public let count: Int
    public let percent: Int
    public var id: String { prize.rawValue }
}

public enum CraftCatalog {
    public static let blueprints: [BlueprintDefinition] = [
        // Garden
        .init(id: "gardenHat", theme: .garden, product: .wear(.head), tier: .basic,
              costs: [.init(material: .fabric, count: 2), .init(material: .thread, count: 2), .init(material: .wood, count: 2)],
              source: .gardenWalk, symbol: "hat.widebrim.fill"),
        .init(id: "butterflyBrooch", theme: .garden, product: .wear(.accessory), tier: .basic,
              costs: [.init(material: .thread, count: 1), .init(material: .dye, count: 2)],
              source: .keepsake("butterflyCard"), symbol: "leaf.fill"),
        .init(id: "flowerCart", theme: .garden, product: .decor, tier: .mid,
              costs: [.init(material: .wood, count: 4), .init(material: .dye, count: 1)],
              source: .luck, symbol: "cart.fill"),
        // Café
        .init(id: "baristaApron", theme: .cafe, product: .wear(.body), tier: .basic,
              costs: [.init(material: .fabric, count: 3), .init(material: .thread, count: 1)],
              source: .friendship(neighborID: "neighbor_mira", stage: 2), symbol: "cup.and.saucer.fill"),
        .init(id: "catEarBand", theme: .cafe, product: .wear(.head), tier: .basic,
              costs: [.init(material: .fabric, count: 1), .init(material: .thread, count: 2)],
              source: .luck, symbol: "cat.fill"),
        .init(id: "cafeChalkboard", theme: .cafe, product: .decor, tier: .mid,
              costs: [.init(material: .wood, count: 3), .init(material: .dye, count: 1)],
              source: .cafeNaps(5), symbol: "list.bullet.rectangle.fill"),
        // Star & moon
        .init(id: "starBoots", theme: .starMoon, product: .wear(.feet), tier: .mid,
              costs: [.init(material: .fabric, count: 2), .init(material: .thread, count: 1), .init(material: .stardust, count: 3)],
              source: .luck, symbol: "star.fill"),
        .init(id: "moonCape", theme: .starMoon, product: .wear(.body), tier: .advanced,
              costs: [.init(material: .fabric, count: 5), .init(material: .dye, count: 2), .init(material: .stardust, count: 5)],
              source: .luck, symbol: "moon.stars.fill"),
        .init(id: "moonLamp", theme: .starMoon, product: .decor, tier: .advanced,
              costs: [.init(material: .wood, count: 2), .init(material: .stardust, count: 8)],
              source: .townEvent("luna_stargaze"), symbol: "moon.fill"),
        // Rainy day
        .init(id: "rainHat", theme: .rainy, product: .wear(.head), tier: .basic,
              costs: [.init(material: .fabric, count: 2), .init(material: .dye, count: 1)],
              source: .rainyOuting, symbol: "umbrella.fill"),
        .init(id: "duckBoots", theme: .rainy, product: .wear(.feet), tier: .mid,
              costs: [.init(material: .fabric, count: 2), .init(material: .thread, count: 2), .init(material: .dye, count: 1)],
              source: .shopShelf, symbol: "shoeprints.fill"),
        .init(id: "umbrellaStand", theme: .rainy, product: .decor, tier: .basic,
              costs: [.init(material: .wood, count: 3)],
              source: .luck, symbol: "umbrella"),
        // Winter
        .init(id: "woolScarf", theme: .winter, product: .wear(.accessory), tier: .basic,
              costs: [.init(material: .thread, count: 4)],
              source: .craftLevel(2), symbol: "wind"),
        .init(id: "fleeceCoat", theme: .winter, product: .wear(.body), tier: .mid,
              costs: [.init(material: .fabric, count: 5), .init(material: .thread, count: 3)],
              source: .friendship(neighborID: "neighbor_grace", stage: 2), symbol: "snowflake"),
        .init(id: "smallStove", theme: .winter, product: .decor, tier: .advanced,
              costs: [.init(material: .wood, count: 5), .init(material: .dye, count: 2), .init(material: .stardust, count: 6)],
              source: .craftLevel(4), symbol: "flame.fill"),
        // Bazaar
        .init(id: "luckyCharm", theme: .bazaar, product: .wear(.accessory), tier: .mid,
              costs: [.init(material: .thread, count: 2), .init(material: .stardust, count: 4)],
              source: .bazaarTrades(5), symbol: "suit.club.fill"),
        .init(id: "stallSign", theme: .bazaar, product: .decor, tier: .mid,
              costs: [.init(material: .wood, count: 4), .init(material: .dye, count: 2)],
              source: .shopShelf, symbol: "signpost.right.fill"),
        .init(id: "merchantOveralls", theme: .bazaar, product: .wear(.body), tier: .advanced,
              costs: [.init(material: .fabric, count: 6), .init(material: .thread, count: 3), .init(material: .stardust, count: 6)],
              source: .shares(10), symbol: "bag.fill")
    ]

    /// Level 3 shows 140 / 200 in the design; levels 4 and 5 follow the same steps.
    public static let skillLevels: [CraftSkillLevel] = [
        .init(level: 1, minimumExperience: 0, successBonus: 0),
        .init(level: 2, minimumExperience: 60, successBonus: 0),
        .init(level: 3, minimumExperience: 140, successBonus: 6),
        .init(level: 4, minimumExperience: 200, successBonus: 6),
        .init(level: 5, minimumExperience: 360, successBonus: 10)
    ]
    public static let maximumExperience = 1_000_000
    public static let maximumSuccessPercent = 98
    /// Each failure in a row adds this to the same blueprint's next try; a success clears it.
    public static let failureBonusPercent = 5
    public static let maximumFailureStreak = 20
    public static let maximumMaterial = 9_999
    public static let maximumHandmade = 200
    /// Uses above the cap become stardust, at this much per whole copy (rounded up).
    public static let overflowStardustPerCopy = 10

    // Magic wheel.
    public static let wheelFreeSpins = 1
    public static let wheelPaidSpins = 2
    public static let wheelSpinPrice = 100
    /// The 3.0 table's 4% theme decoration opens with the decorations; until then it is stardust.
    public static let wheel: [WheelSlice] = [
        .init(prize: .fabric, count: 2, percent: 25),
        .init(prize: .thread, count: 2, percent: 20),
        .init(prize: .wood, count: 2, percent: 20),
        .init(prize: .dye, count: 1, percent: 15),
        .init(prize: .stardust, count: 3, percent: 12),
        .init(prize: .blueprint, count: 1, percent: 8)
    ]

    // Where materials come from besides the wheel.
    /// Chance (percent) that an outing footprint also turns up its spot's material.
    public static let outingMaterialChance = 45
    /// Chance (percent) that a finished shift brings home a piece of fabric.
    public static let workFabricChance = 50

    public static func blueprint(id: String) -> BlueprintDefinition? { blueprints.first { $0.id == id } }
    public static func blueprints(in theme: CraftTheme) -> [BlueprintDefinition] { blueprints.filter { $0.theme == theme } }
    public static var craftableBlueprints: [BlueprintDefinition] { blueprints.filter(\.isCraftable) }
    public static func material(at spot: OutingSpot) -> CraftMaterial {
        switch spot {
        case .flowerBed: .thread
        case .treeShade: .wood
        case .path: .dye
        }
    }

    public static func skillLevel(experience: Int) -> CraftSkillLevel {
        skillLevels.last { experience >= $0.minimumExperience } ?? skillLevels[0]
    }
    public static func nextSkillLevel(experience: Int) -> CraftSkillLevel? {
        skillLevels.first { experience < $0.minimumExperience }
    }

    /// Quality odds (common, fine, treasured) in percent. From skill level 3 fine comes more often.
    public static func qualityOdds(tier: CraftTier, skillLevel: Int) -> [OutingDecorQuality: Int] {
        let skilled = skillLevel >= 3
        switch tier {
        case .basic: return [.common: skilled ? 70 : 75, .fine: skilled ? 25 : 20, .treasured: 5]
        case .mid: return [.common: skilled ? 60 : 65, .fine: skilled ? 32 : 27, .treasured: 8]
        case .advanced: return [.common: skilled ? 45 : 50, .fine: skilled ? 35 : 30, .treasured: 20]
        }
    }
    /// Advanced pieces always carry two attributes.
    public static func attributeCount(tier: CraftTier, quality: OutingDecorQuality) -> Int {
        tier == .advanced ? 2 : quality == .common ? 1 : 2
    }
    public static func attributes(for tier: CraftTier) -> [HandmadeAttribute] {
        HandmadeAttribute.allCases.filter { $0 != .workGold || tier == .advanced }
    }

    // MARK: 3.1 durability

    /// Days of wear a new piece has, by tier and quality. Mid is the design's table; basic is
    /// about four days shorter; advanced spreads 30–50 over the three qualities.
    public static func durabilityRange(tier: CraftTier, quality: OutingDecorQuality) -> ClosedRange<Int> {
        switch (tier, quality) {
        case (.basic, .common): 16...22
        case (.basic, .fine): 23...30
        case (.basic, .treasured): 31...36
        case (.mid, .common): 20...26
        case (.mid, .fine): 27...34
        case (.mid, .treasured): 35...40
        case (.advanced, .common): 30...36
        case (.advanced, .fine): 37...44
        case (.advanced, .treasured): 45...50
        }
    }
    public static let maximumDurability = 50
    /// Each repair lowers the cap by this much, until the craft skill reaches `repairMasterLevel`.
    public static let repairCapLoss = 4
    public static let repairMasterLevel = 5
    /// A cap never drops below this, so an often-mended piece can still be worn for a while.
    public static let minimumDurabilityCap = 8
    /// Morning goodbye cards waiting to be read are kept to this many.
    public static let maximumFarewells = 12
    public static let maximumRepairs = 99

    /// What a repair uses: one each of the first two non-stardust materials of the blueprint.
    public static func repairCosts(for definition: BlueprintDefinition) -> [CraftCost] {
        definition.costs.filter { $0.material != .stardust }.prefix(2).map { CraftCost(material: $0.material, count: 1) }
    }
}

/// How worn a handmade piece looks. Attributes keep their full value until it breaks.
public enum DurabilityStage: String, CaseIterable, Sendable {
    case fresh, handy, worn, fragile
    public var titleKey: String { "gear.stage.\(rawValue)" }
    /// 80% and up is like new, 50–80% handy, 20–50% worn, under 20% about to break.
    public static func of(durability: Int, cap: Int) -> Self {
        let percent = cap > 0 ? durability * 100 / cap : 0
        return percent >= 80 ? .fresh : percent >= 50 ? .handy : percent >= 20 ? .worn : .fragile
    }
}
