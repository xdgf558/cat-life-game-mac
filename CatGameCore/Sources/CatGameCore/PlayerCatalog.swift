import Foundation

public enum AvatarGender: String, Codable, CaseIterable, Sendable {
    case male, female
}

/// Appearance is cosmetic: neither gender nor avatar participates in work rules.
public struct PlayerAvatar: Identifiable, Equatable, Sendable {
    public let id: String
    public let gender: AvatarGender
    public var nameKey: String { "avatars.\(id).name" }
    public var detailKey: String { "avatars.\(id).detail" }
    public var assetName: String { "player-" + id.replacingOccurrences(of: "_", with: "-") }
}

public enum EquipmentSlot: String, Codable, CaseIterable, Sendable {
    case head, body, feet, accessory
}

public struct EquipmentBonuses: Codable, Equatable, Sendable {
    public let durationReductionPercent: Int
    public let staminaReductionPercent: Int
    public let moodReductionPercent: Int

    /// Clamp each additive category so future catalog entries cannot eliminate
    /// all work time or costs. Saved values are independently validated on load.
    public init(durationReductionPercent: Int = 0, staminaReductionPercent: Int = 0,
                moodReductionPercent: Int = 0) {
        self.durationReductionPercent = min(50, max(0, durationReductionPercent))
        self.staminaReductionPercent = min(50, max(0, staminaReductionPercent))
        self.moodReductionPercent = min(50, max(0, moodReductionPercent))
    }

    public func adding(_ other: EquipmentBonuses) -> EquipmentBonuses {
        func sum(_ left: Int, _ right: Int) -> Int {
            min(50, max(0, left)) + min(50, max(0, right))
        }
        return .init(durationReductionPercent: sum(durationReductionPercent, other.durationReductionPercent),
                     staminaReductionPercent: sum(staminaReductionPercent, other.staminaReductionPercent),
                     moodReductionPercent: sum(moodReductionPercent, other.moodReductionPercent))
    }

    var isValid: Bool {
        [durationReductionPercent, staminaReductionPercent, moodReductionPercent]
            .allSatisfy { (0...50).contains($0) }
    }
}

public struct EquipmentItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let slot: EquipmentSlot
    public let bonuses: EquipmentBonuses
    public var nameKey: String { "equipment.\(id).name" }
    public var detailKey: String { "equipment.\(id).detail" }
    public var assetName: String { "gear-" + id.replacingOccurrences(of: "_", with: "-") }
}

public struct PlayerProfile: Codable, Equatable, Sendable {
    /// nil uses the localized default; a custom name is player-authored text.
    public var name: String?
    public var avatarID: String?
    public var ownedEquipmentIDs: [String]
    public var equipped: [EquipmentSlot: String]

    public init(avatarID: String? = nil,
                ownedEquipmentIDs: [String] = PlayerCatalog.starterEquipmentIDs,
                equipped: [EquipmentSlot: String] = [:], name: String? = nil) {
        self.name = name
        self.avatarID = avatarID
        self.ownedEquipmentIDs = ownedEquipmentIDs
        self.equipped = equipped
    }

    private enum CodingKeys: String, CodingKey { case name, avatarID, ownedEquipmentIDs, equipped }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // A malformed cosmetic name must not restore an older backup and lose
        // progress. Avatar and equipment decoding retain their strict rules.
        name = (try? values.decode(String.self, forKey: .name)).flatMap(PlayerNameRules.normalized)
        avatarID = try values.decodeIfPresent(String.self, forKey: .avatarID)
        // The entire absent profile migrates in PlayerState. A present profile
        // never receives another gift because its inventory is absent or empty.
        ownedEquipmentIDs = try values.decode([String].self, forKey: .ownedEquipmentIDs)
        let slots = try values.decode([String: String].self, forKey: .equipped)
        var equipped: [EquipmentSlot: String] = [:]
        for (key, itemID) in slots {
            guard let slot = EquipmentSlot(rawValue: key) else {
                throw DecodingError.dataCorruptedError(forKey: .equipped, in: values,
                    debugDescription: "Unknown equipment slot")
            }
            equipped[slot] = itemID
        }
        self.equipped = equipped
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(name, forKey: .name)
        try values.encodeIfPresent(avatarID, forKey: .avatarID)
        try values.encode(ownedEquipmentIDs, forKey: .ownedEquipmentIDs)
        try values.encode(Dictionary(uniqueKeysWithValues: equipped.map { ($0.key.rawValue, $0.value) }),
                          forKey: .equipped)
    }

    var isValid: Bool {
        guard name.map({ PlayerNameRules.normalized($0) == $0 }) ?? true,
              avatarID.map({ PlayerCatalog.avatar(id: $0) != nil }) ?? true,
              Set(ownedEquipmentIDs).count == ownedEquipmentIDs.count,
              ownedEquipmentIDs.allSatisfy({ PlayerCatalog.item(id: $0) != nil }),
              Set(equipped.values).count == equipped.count else { return false }
        return equipped.allSatisfy { slot, id in
            ownedEquipmentIDs.contains(id) && PlayerCatalog.item(id: id)?.slot == slot
        }
    }
}

/// A saved contract for one shift. Its captured base values and reductions do
/// not depend on the current outfit or future changes to catalog balancing.
public struct WorkQuote: Codable, Equatable, Sendable {
    public let jobID: String
    public let baseDurationSeconds: Int
    public let durationSeconds: Int
    public let baseStaminaCost: Int
    public let staminaCost: Int
    public let baseMoodCost: Int
    public let moodCost: Int
    public let bonuses: EquipmentBonuses
    public let equipmentIDs: [String]

    init(job: WorkJob, profile: PlayerProfile) {
        jobID = job.id
        baseDurationSeconds = job.durationMinutes * 60
        baseStaminaCost = job.staminaCost
        baseMoodCost = job.moodCost
        bonuses = PlayerCatalog.bonuses(for: profile)
        equipmentIDs = EquipmentSlot.allCases.compactMap { profile.equipped[$0] }
        durationSeconds = Self.discount(baseDurationSeconds, by: bonuses.durationReductionPercent)
        staminaCost = Self.discount(baseStaminaCost, by: bonuses.staminaReductionPercent)
        moodCost = Self.discount(baseMoodCost, by: bonuses.moodReductionPercent)
    }

    /// Integer arithmetic rounds a reduced cost up, never below one for a
    /// positive base. All callers validate bounded base values before use.
    static func discount(_ base: Int, by percentage: Int) -> Int {
        guard base > 0 else { return 0 }
        return max(1, (base * (100 - percentage) + 99) / 100)
    }

    var isValid: Bool {
        guard !jobID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...315_360_000).contains(baseDurationSeconds),
              (0...100).contains(baseStaminaCost), (0...100).contains(baseMoodCost),
              bonuses.isValid,
              equipmentIDs.count <= EquipmentSlot.allCases.count,
              equipmentIDs.count == Set(equipmentIDs).count,
              equipmentIDs.allSatisfy({ PlayerCatalog.item(id: $0) != nil }) else { return false }
        let slots = equipmentIDs.compactMap { PlayerCatalog.item(id: $0)?.slot }
        guard Set(slots).count == slots.count else { return false }
        return durationSeconds == Self.discount(baseDurationSeconds, by: bonuses.durationReductionPercent)
            && staminaCost == Self.discount(baseStaminaCost, by: bonuses.staminaReductionPercent)
            && moodCost == Self.discount(baseMoodCost, by: bonuses.moodReductionPercent)
    }
}

public enum PlayerCatalog {
    public static let avatars: [PlayerAvatar] = [
        .init(id: "male_sunny", gender: .male),
        .init(id: "male_forest", gender: .male),
        .init(id: "male_scholarly", gender: .male),
        .init(id: "female_sunny", gender: .female),
        .init(id: "female_forest", gender: .female),
        .init(id: "female_scholarly", gender: .female)
    ]

    public static let equipment: [EquipmentItem] = [
        .init(id: "starter_cap", slot: .head, bonuses: .init(moodReductionPercent: 20)),
        .init(id: "starter_jacket", slot: .body, bonuses: .init(staminaReductionPercent: 15)),
        .init(id: "starter_sneakers", slot: .feet, bonuses: .init(durationReductionPercent: 10)),
        .init(id: "starter_charm", slot: .accessory, bonuses: .init(durationReductionPercent: 5)),
        .init(id: "advanced_cap", slot: .head, bonuses: .init(moodReductionPercent: 30)),
        .init(id: "advanced_jacket", slot: .body, bonuses: .init(staminaReductionPercent: 25)),
        .init(id: "advanced_sneakers", slot: .feet, bonuses: .init(durationReductionPercent: 20)),
        .init(id: "advanced_charm", slot: .accessory, bonuses: .init(durationReductionPercent: 10))
    ]

    /// Keep this explicit when new purchasable items are added to the catalog.
    public static let starterEquipmentIDs = [
        "starter_cap", "starter_jacket", "starter_sneakers", "starter_charm"
    ]

    public static func avatar(id: String) -> PlayerAvatar? { avatars.first { $0.id == id } }
    public static func item(id: String) -> EquipmentItem? { equipment.first { $0.id == id } }

    public static func bonuses(for profile: PlayerProfile) -> EquipmentBonuses {
        EquipmentSlot.allCases.reduce(EquipmentBonuses()) { accumulated, slot in
            guard let id = profile.equipped[slot], profile.ownedEquipmentIDs.contains(id),
                  let item = item(id: id), item.slot == slot else { return accumulated }
            return accumulated.adding(item.bonuses)
        }
    }
}
