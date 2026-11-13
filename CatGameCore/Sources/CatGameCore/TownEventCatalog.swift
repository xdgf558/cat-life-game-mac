import Foundation

public struct TownEventRewards: Codable, Equatable, Sendable {
    public var gold: Int
    public var food: Int
    public var litter: Int
    public var toys: Int
    public var premiumFood: Int
    public var premiumLitter: Int

    public init(gold: Int = 0, food: Int = 0, litter: Int = 0, toys: Int = 0,
                premiumFood: Int = 0, premiumLitter: Int = 0) {
        self.gold = gold; self.food = food; self.litter = litter; self.toys = toys
        self.premiumFood = premiumFood; self.premiumLitter = premiumLitter
    }

    var isValid: Bool {
        (0...GameSnapshot.maximumGold).contains(gold)
            && [food, litter, toys, premiumFood, premiumLitter].allSatisfy {
                (0...GameSnapshot.maximumStock).contains($0)
            }
    }
}

public struct TownEventChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let eventID: String
    public let staminaCost: Int
    public let supplyCost: SupplyKind?
    public let supplyCount: Int
    public let giftID: String?
    public let friendshipReward: Int
    public let rewards: TownEventRewards
    public var titleKey: String { "townEvents.event.\(eventID).\(id).title" }
    public var responseKey: String { "townEvents.event.\(eventID).\(id).reply" }
}

public struct TownEventDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let neighborID: String
    public let choices: [TownEventChoice]
    public var titleKey: String { "townEvents.event.\(id).title" }
    public var bodyKey: String { "townEvents.event.\(id).body" }
    public var assetName: String { CommunityCatalog.neighbor(id: neighborID)?.portraitAssetName ?? "town-board-cartoon" }
}

public struct TownEventMilestone: Identifiable, Equatable, Sendable {
    public let id: String
    public let target: Int
    public let furnitureKind: FurnitureKind
    public let itemID: String
    public var titleKey: String { "townEvents.milestone.\(id).title" }
    public var bodyKey: String { "townEvents.milestone.\(id).body" }
}

/// Stable content IDs are retained in letters. Retired content remains readable, but cannot be replayed.
public enum TownEventCatalog {
    public static let all: [TownEventDefinition] = [
        event("mira_tidy", "neighbor_mira", stamina: 8, help: .init(litter: 1), supply: .litter, output: .init(food: 1)),
        event("ken_repair", "neighbor_ken", stamina: 10, help: .init(toys: 2), supply: .toy, count: 2, output: .init(food: 1)),
        event("luna_reading", "neighbor_luna", stamina: 6, help: .init(toys: 1), gift: "drink", output: .init(premiumLitter: 1)),
        event("grace_picnic", "neighbor_grace", stamina: 8, help: .init(food: 1), gift: "dessert", output: .init(premiumFood: 1)),
        event("mira_garden", "neighbor_mira", stamina: 8, help: .init(litter: 1), gift: "flower", output: .init(toys: 3)),
        event("ken_colors", "neighbor_ken", stamina: 10, help: .init(toys: 2), gift: "drink", output: .init(premiumFood: 1)),
        event("luna_stargaze", "neighbor_luna", stamina: 6, help: .init(food: 1), gift: "flower", output: .init(premiumLitter: 1)),
        event("grace_welcome", "neighbor_grace", stamina: 8, help: .init(food: 1), supply: .food, output: .init(litter: 1))
    ]
    public static let milestones: [TownEventMilestone] = [
        .init(id: "town_memory_7", target: 7, furnitureKind: .wallTownMemory, itemID: "town-event-memory")
    ]

    public static func event(id: String) -> TownEventDefinition? { all.first { $0.id == id } }
    public static func milestone(id: String) -> TownEventMilestone? { milestones.first { $0.id == id } }
    public static func current(in state: GameSnapshot) -> TownEventDefinition? {
        state.community.events.eventID.flatMap(event(id:))
    }

    public static func eligibility(eventID: String, choiceID: String, dayKey: String,
                                   in state: GameSnapshot) -> ActionFailure? {
        guard state.community.events.dayKey == dayKey, state.tasks.dailyDayKey == dayKey else { return .townEventDayChanged }
        guard state.community.events.todayReceipt == nil else { return .townEventCompleted }
        guard state.community.events.eventID == eventID, let event = event(id: eventID),
              let choice = event.choices.first(where: { $0.id == choiceID }),
              CommunityCatalog.neighbor(id: event.neighborID) != nil else { return .townEventMissing }
        if choice.staminaCost > 0 {
            if state.player.activeSleep != nil || state.player.activeWork != nil { return .townEventBusy }
            if state.player.stamina < choice.staminaCost { return .townEventStaminaRequired }
        }
        if let kind = choice.supplyCost, state.inventory.count(kind) < choice.supplyCount { return .townEventSuppliesRequired }
        if let id = choice.giftID, state.inventory.giftCount(id) < 1 { return .townEventSuppliesRequired }
        return nil
    }

    public static func milestoneEligibility(id: String, in state: GameSnapshot) -> ActionFailure? {
        guard let milestone = milestone(id: id) else { return .townEventMissing }
        guard !state.community.events.claimedMilestoneIDs.contains(id) else { return .townMilestoneClaimed }
        guard state.community.events.totalCompleted >= milestone.target else { return .townMilestoneIncomplete }
        if let owned = state.inventory.furniture.first(where: { $0.id == milestone.itemID }), owned.kind != milestone.furnitureKind {
            return .gameInvalidState
        }
        return nil
    }

    static func eventID(for dayKey: String) -> String? {
        guard !all.isEmpty, let date = TownEventState.date(for: dayKey) else { return nil }
        let day = Int(floor(date.timeIntervalSince1970 / 86_400))
        return all[((day % all.count) + all.count) % all.count].id
    }

    private static func event(_ id: String, _ neighbor: String, stamina: Int, help: TownEventRewards,
                              supply: SupplyKind? = nil, count: Int = 1, gift: String? = nil,
                              output: TownEventRewards) -> TownEventDefinition {
        .init(id: id, neighborID: neighbor, choices: [
            .init(id: "help", eventID: id, staminaCost: stamina, supplyCost: nil, supplyCount: 0,
                  giftID: nil, friendshipReward: 4, rewards: help),
            .init(id: "supply", eventID: id, staminaCost: 0, supplyCost: supply,
                  supplyCount: supply == nil ? 0 : count, giftID: gift, friendshipReward: 6, rewards: output)
        ])
    }
}
