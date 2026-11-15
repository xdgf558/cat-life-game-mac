import Foundation

/// 2.0 cat outing: one cat walks the Cat Town garden with the player. Numbers here are the
/// rules; the UI only shows what these tables and the engine actually return.
public enum OutingSpot: String, Codable, CaseIterable, Sendable, Identifiable {
    case flowerBed, treeShade, path
    public var id: String { rawValue }
    public var titleKey: String { "outing.spot.\(rawValue)" }
    /// The personality that notices more here (raises the find chance, changes the reaction).
    public var favoredStyle: CatBehaviorStyle {
        switch self {
        case .flowerBed: .quiet
        case .treeShade: .curious
        case .path: .playful
        }
    }
}

/// A habit an event option can ask for. Personality is innate for catalog cats; play rhythm and
/// rest preference count only once the player has confirmed them at home.
public enum OutingHabit: Equatable, Sendable {
    case style(CatBehaviorStyle), play(CatPlayRhythm), rest(CatRestPreference)

    public var key: String {
        switch self {
        case .style(let value): "style.\(value.rawValue)"
        case .play(let value): "play.\(value.rawValue)"
        case .rest(let value): "rest.\(value.rawValue)"
        }
    }

    public func isKnown(for cat: CatState) -> Bool {
        guard let definition = CatHabitCatalog.definition(for: cat.id) else { return false }
        switch self {
        case .style(let value): return definition.style == value
        case .play(let value): return definition.play == value && cat.habits.playConfirmed
        case .rest(let value): return definition.rest == value && cat.habits.restConfirmed
        }
    }
}

public struct OutingKeepsakeDefinition: Equatable, Sendable, Identifiable {
    public let id: String
    public let spot: OutingSpot
    public let symbol: String
    public var nameKey: String { "outing.keepsake.\(id)" }
    public var storyKey: String { "outing.keepsake.\(id).story" }
}

public enum OutingDecorPlacement: String, Sendable { case wall, floor }

public struct OutingDecorDefinition: Equatable, Sendable, Identifiable {
    public let id: String
    public let spot: OutingSpot
    public let kind: FurnitureKind
    public let symbol: String
    public var placement: OutingDecorPlacement { FurnitureCatalog.metadata(for: kind).isWall ? .wall : .floor }
    public var itemID: String { "outing-decor-\(id)" }
    public var nameKey: String { "furniture.\(kind.rawValue)" }
}

public enum OutingDecorQuality: String, Codable, CaseIterable, Comparable, Sendable {
    case common, fine, treasured
    public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    public var titleKey: String { "outing.quality.\(rawValue)" }
}

public enum OutingDecorAttribute: String, Codable, CaseIterable, Sendable {
    /// Every cat's mood per hour at home. Player stamina per hour at home.
    /// Extra energy (percent of the rest) when a cat finishes a rest. Extra bond (percent) from play.
    /// One extra footprint per outing (treasured only).
    case catMood, playerStamina, catEnergy, bond, footprint
    public var titleKey: String { "outing.attribute.\(rawValue)" }
    /// The whole range any quality can roll, for the attribute bar.
    public var range: ClosedRange<Int> {
        switch self {
        case .catMood: 1...3
        case .playerStamina: 1...2
        case .catEnergy: 5...10
        case .bond: 3...8
        case .footprint: 1...1
        }
    }
    func range(for quality: OutingDecorQuality) -> ClosedRange<Int> {
        switch (self, quality) {
        case (.catMood, .common): 1...1
        case (.catMood, .fine): 2...2
        case (.catMood, .treasured): 3...3
        case (.playerStamina, .treasured): 2...2
        case (.playerStamina, _): 1...1
        case (.catEnergy, .common): 5...6
        case (.catEnergy, .fine): 7...8
        case (.catEnergy, .treasured): 9...10
        case (.bond, .common): 3...4
        case (.bond, .fine): 5...6
        case (.bond, .treasured): 7...8
        case (.footprint, _): 1...1
        }
    }
}

/// What an event option gives. Amounts are the rule; the result card shows the actual values.
public struct OutingEffect: Equatable, Sendable {
    public var catMood = 0
    public var bond = 0
    public var friendship = 0
    public var neighborID: String?
    public var gold = 0
    /// The option leaves this spot alone, so the footprint spent on it comes back.
    public var refundsFootprint = false

    public init(catMood: Int = 0, bond: Int = 0, friendship: Int = 0, neighborID: String? = nil,
                gold: Int = 0, refundsFootprint: Bool = false) {
        self.catMood = catMood; self.bond = bond; self.friendship = friendship
        self.neighborID = neighborID; self.gold = gold; self.refundsFootprint = refundsFootprint
    }

    /// Rough hints for the option button (mood / bond / neighbour / no footprint), never numbers.
    public var hintKeys: [String] {
        var keys: [String] = []
        if catMood > 0 { keys.append("outing.hint.mood") }
        if bond > 0 { keys.append("outing.hint.bond") }
        if friendship > 0 { keys.append("outing.hint.neighbor") }
        if gold > 0 { keys.append("outing.hint.gold") }
        if refundsFootprint { keys.append("outing.hint.noFootprint") }
        return keys
    }
}

public struct OutingEventOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let effect: OutingEffect
    /// Only shown when the cat's habit is known; never the only way to a good result.
    public let habit: OutingHabit?
}

public struct OutingEventDefinition: Equatable, Sendable, Identifiable {
    public let id: String
    /// nil: can happen at any spot.
    public let spot: OutingSpot?
    public let symbol: String
    public let options: [OutingEventOption]
    public var titleKey: String { "outing.event.\(id).title" }
    public var bodyKey: String { "outing.event.\(id).body" }
    public func optionKey(_ option: OutingEventOption) -> String { "outing.event.\(id).\(option.id)" }
    public func resultKey(_ option: OutingEventOption) -> String { "outing.event.\(id).\(option.id).result" }
    public func options(for cat: CatState) -> [OutingEventOption] {
        options.filter { $0.habit.map { $0.isKnown(for: cat) } ?? true }
    }
}

public enum OutingCatalog {
    // Departure and trip rules.
    public static let staminaCost = 20
    public static let energyCost = 25
    public static let minimumSatiety = 30
    public static let minimumEnergy = 25
    public static let footprints = 6
    public static let dailyDepartures = 2
    public static let duplicateKeepsakeGold = 20
    public static let duplicateDecorGold = 60
    public static let nothingMood = 2
    public static let maximumActiveDecor = 3
    public static let keepsakeShelfThreshold = 3
    public static let shelfSlots = 6
    public static let shelfItemID = "keepsake-shelf"

    // Exploration odds, in percent.
    static let eventChance = 28
    static let findChance = 50
    static let favoredFindBonus = 15
    static let keepsakeShare = 55
    static let decorShare = 25
    static let goldRange = 10...25

    public static let keepsakes: [OutingKeepsakeDefinition] = [
        .init(id: "pressedFlower", spot: .flowerBed, symbol: "bookmark.fill"),
        .init(id: "dandelion", spot: .flowerBed, symbol: "aqi.medium"),
        .init(id: "ladybugPin", spot: .flowerBed, symbol: "ladybug.fill"),
        .init(id: "oldTrowel", spot: .flowerBed, symbol: "hammer.fill"),
        .init(id: "acorn", spot: .treeShade, symbol: "circle.hexagongrid.fill"),
        .init(id: "blueFeather", spot: .treeShade, symbol: "leaf.fill"),
        .init(id: "goldenLeaf", spot: .treeShade, symbol: "leaf.circle.fill"),
        .init(id: "butterflyCard", spot: .treeShade, symbol: "rectangle.portrait.fill"),
        .init(id: "pebble", spot: .path, symbol: "oval.fill"),
        .init(id: "clover", spot: .path, symbol: "suit.club.fill"),
        .init(id: "rustyKey", spot: .path, symbol: "key.fill"),
        .init(id: "marble", spot: .path, symbol: "circle.circle.fill")
    ]

    public static let decor: [OutingDecorDefinition] = [
        .init(id: "windChime", spot: .path, kind: .gardenWindChime, symbol: "bell.fill"),
        .init(id: "clayPot", spot: .flowerBed, kind: .gardenClayPot, symbol: "camera.macro"),
        .init(id: "leafWreath", spot: .treeShade, kind: .gardenLeafWreath, symbol: "laurel.leading"),
        .init(id: "pebbleLamp", spot: .path, kind: .gardenPebbleLamp, symbol: "lamp.floor.fill"),
        .init(id: "picnicBasket", spot: .flowerBed, kind: .gardenPicnicBasket, symbol: "basket.fill"),
        .init(id: "birdhouse", spot: .treeShade, kind: .gardenBirdhouse, symbol: "house.lodge.fill")
    ]

    public static let events: [OutingEventDefinition] = [
        .init(id: "fallingLeaf", spot: .treeShade, symbol: "leaf.fill", options: [
            .init(id: "chase", effect: .init(catMood: 5), habit: nil),
            .init(id: "carry", effect: .init(bond: 3), habit: nil),
            .init(id: "sway", effect: .init(catMood: 5, bond: 3), habit: .play(.moveAndPause))]),
        .init(id: "dirtTreasure", spot: .flowerBed, symbol: "circle.dotted", options: [
            .init(id: "dig", effect: .init(catMood: 3, gold: 8), habit: nil),
            .init(id: "wait", effect: .init(bond: 3), habit: nil),
            .init(id: "watch", effect: .init(bond: 4, gold: 12), habit: .play(.slowMove))]),
        .init(id: "meetMira", spot: .path, symbol: "person.fill", options: [
            .init(id: "chat", effect: .init(friendship: 3, neighborID: "neighbor_mira"), habit: nil),
            .init(id: "nod", effect: .init(catMood: 2), habit: nil),
            .init(id: "sniff", effect: .init(bond: 2, friendship: 4, neighborID: "neighbor_mira"), habit: .style(.quiet))]),
        .init(id: "butterfly", spot: .flowerBed, symbol: "sparkles", options: [
            .init(id: "stay", effect: .init(bond: 4), habit: nil),
            .init(id: "shoo", effect: .init(catMood: 2), habit: nil)]),
        .init(id: "hollow", spot: .treeShade, symbol: "tree.fill", options: [
            .init(id: "approach", effect: .init(catMood: 4), habit: nil),
            .init(id: "leave", effect: .init(refundsFootprint: true), habit: nil),
            .init(id: "peek", effect: .init(catMood: 4, gold: 12), habit: .style(.curious))]),
        .init(id: "puddle", spot: .path, symbol: "drop.fill", options: [
            .init(id: "carry", effect: .init(bond: 4), habit: nil),
            .init(id: "detour", effect: .init(refundsFootprint: true), habit: nil),
            .init(id: "splash", effect: .init(catMood: 6, bond: 1), habit: .style(.curious))]),
        .init(id: "woolHat", spot: .treeShade, symbol: "hat.widebrim.fill", options: [
            .init(id: "handIn", effect: .init(friendship: 3, neighborID: "neighbor_grace"), habit: nil),
            .init(id: "putBack", effect: .init(catMood: 2), habit: nil)]),
        .init(id: "strayCat", spot: .path, symbol: "cat.fill", options: [
            .init(id: "wait", effect: .init(catMood: 2, bond: 2), habit: nil),
            .init(id: "leave", effect: .init(refundsFootprint: true), habit: nil),
            .init(id: "share", effect: .init(catMood: 4, bond: 3), habit: .style(.playful))]),
        .init(id: "drizzle", spot: nil, symbol: "cloud.drizzle.fill", options: [
            .init(id: "shelter", effect: .init(bond: 3), habit: nil),
            .init(id: "runBack", effect: .init(refundsFootprint: true), habit: nil)]),
        .init(id: "sunnyBench", spot: .treeShade, symbol: "sun.max.fill", options: [
            .init(id: "sit", effect: .init(catMood: 2, bond: 3), habit: nil),
            .init(id: "keepGoing", effect: .init(refundsFootprint: true), habit: nil),
            .init(id: "curl", effect: .init(catMood: 3, bond: 5), habit: .rest(.bed))])
    ]

    public static func keepsake(id: String) -> OutingKeepsakeDefinition? { keepsakes.first { $0.id == id } }
    public static func decor(id: String) -> OutingDecorDefinition? { decor.first { $0.id == id } }
    public static func decor(itemID: String) -> OutingDecorDefinition? { decor.first { $0.itemID == itemID } }
    public static func decor(kind: FurnitureKind) -> OutingDecorDefinition? { decor.first { $0.kind == kind } }
    public static func event(id: String) -> OutingEventDefinition? { events.first { $0.id == id } }
    public static func keepsakes(at spot: OutingSpot) -> [OutingKeepsakeDefinition] { keepsakes.filter { $0.spot == spot } }
    public static func decor(at spot: OutingSpot) -> [OutingDecorDefinition] { decor.filter { $0.spot == spot } }
}

/// Why a cat can't leave right now; the prep screen greys the cat out with this reason.
public enum OutingCatBlocker: String, Sendable {
    case sick, hungry, tired, playing
    public var messageKey: String { "outing.blocker.\(rawValue)" }
}

extension OutingCatalog {
    public static func blocker(for cat: CatState, in state: GameSnapshot) -> OutingCatBlocker? {
        if cat.healthState?.illness != nil { return .sick }
        if cat.satiety < minimumSatiety { return .hungry }
        if cat.energy < minimumEnergy { return .tired }
        if state.catPlay.activeSession?.catID == cat.id { return .playing }
        return nil
    }
}
