import Foundation

/// A blueprint the player has held at least once. `usesLeft` 0 is "用完了": kept for the book.
public struct BlueprintRecord: Codable, Equatable, Sendable {
    public var usesLeft: Int
    public var craftedCount: Int
    /// Successful-or-not tries in a row that failed; each adds to the next try's chance.
    public var failureStreak: Int
    public var firstLearnedAt: Date

    public init(usesLeft: Int, craftedCount: Int = 0, failureStreak: Int = 0, firstLearnedAt: Date) {
        self.usesLeft = usesLeft; self.craftedCount = craftedCount
        self.failureStreak = failureStreak; self.firstLearnedAt = firstLearnedAt
    }

    func isValid(for definition: BlueprintDefinition) -> Bool {
        (0...definition.tier.maximumUses).contains(usesLeft) && (0...CraftCatalog.maximumExperience).contains(craftedCount)
            && (0...CraftCatalog.maximumFailureStreak).contains(failureStreak) && firstLearnedAt.timeIntervalSince1970.isFinite
    }
}

/// One handmade piece: each is its own copy with its own quality and attributes.
public struct HandmadeItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let blueprintID: String
    public let quality: OutingDecorQuality
    public let attributes: [HandmadeAttributeRoll]
    public let madeAt: Date
    /// 3.1: days of wear left, and the most it can hold (lowered by each repair).
    public var durability: Int
    public var durabilityCap: Int
    public var repairs: Int
    /// Mornings it was worn on.
    public var daysWorn: Int

    public init(id: String, blueprintID: String, quality: OutingDecorQuality, attributes: [HandmadeAttributeRoll],
                madeAt: Date, durability: Int, durabilityCap: Int, repairs: Int = 0, daysWorn: Int = 0) {
        self.id = id; self.blueprintID = blueprintID; self.quality = quality; self.attributes = attributes; self.madeAt = madeAt
        self.durability = durability; self.durabilityCap = durabilityCap; self.repairs = repairs; self.daysWorn = daysWorn
    }

    private enum CodingKeys: String, CodingKey {
        case id, blueprintID, quality, attributes, madeAt, durability, durabilityCap, repairs, daysWorn
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        blueprintID = try values.decode(String.self, forKey: .blueprintID)
        let decodedQuality = try values.decode(OutingDecorQuality.self, forKey: .quality)
        quality = decodedQuality
        attributes = try values.decode([HandmadeAttributeRoll].self, forKey: .attributes)
        madeAt = try values.decode(Date.self, forKey: .madeAt)
        // Pieces made in 3.0 start 3.1 like new, at the top of their range.
        let full = CraftCatalog.blueprint(id: blueprintID)
            .map { CraftCatalog.durabilityRange(tier: $0.tier, quality: decodedQuality).upperBound } ?? CraftCatalog.minimumDurabilityCap
        let decodedCap = try values.decodeIfPresent(Int.self, forKey: .durabilityCap) ?? full
        durabilityCap = decodedCap
        durability = try values.decodeIfPresent(Int.self, forKey: .durability) ?? decodedCap
        repairs = try values.decodeIfPresent(Int.self, forKey: .repairs) ?? 0
        daysWorn = try values.decodeIfPresent(Int.self, forKey: .daysWorn) ?? 0
    }

    public var blueprint: BlueprintDefinition? { CraftCatalog.blueprint(id: blueprintID) }
    public var stage: DurabilityStage { .of(durability: durability, cap: durabilityCap) }
    /// Where a repair would bring it: about two thirds of the cap it would have afterwards.
    public func repairTarget(skillLevel: Int) -> (durability: Int, cap: Int) {
        let cap = skillLevel >= CraftCatalog.repairMasterLevel ? durabilityCap
            : max(CraftCatalog.minimumDurabilityCap, durabilityCap - CraftCatalog.repairCapLoss)
        return (min(cap, max(durability, (cap * 2 + 2) / 3)), cap)
    }

    var isValid: Bool {
        guard let blueprint, OutingState.validID(id), madeAt.timeIntervalSince1970.isFinite,
              (1...2).contains(attributes.count), Set(attributes.map(\.attribute)).count == attributes.count,
              (CraftCatalog.minimumDurabilityCap...CraftCatalog.maximumDurability).contains(durabilityCap),
              (1...durabilityCap).contains(durability), (0...CraftCatalog.maximumRepairs).contains(repairs),
              (0...CraftCatalog.maximumExperience).contains(daysWorn) else { return false }
        return attributes.allSatisfy { $0.isValid && CraftCatalog.attributes(for: blueprint.tier).contains($0.attribute) }
    }
}

/// 3.1: a worn piece that reached zero on a new morning. The goodbye card reads this; the piece is gone.
public struct HandmadeFarewell: Codable, Equatable, Sendable, Identifiable {
    /// The piece's own ID.
    public let id: String
    public let blueprintID: String
    public let quality: OutingDecorQuality
    public let attributes: [HandmadeAttributeRoll]
    public let madeAt: Date
    public let daysWorn: Int
    public let repairs: Int
    /// The one material handed back, if the bag had room.
    public let refunded: CraftMaterial?
    /// The blueprint's uses that morning.
    public let usesLeft: Int
    public let brokeAt: Date

    var isValid: Bool {
        CraftCatalog.blueprint(id: blueprintID) != nil && OutingState.validID(id) && madeAt.timeIntervalSince1970.isFinite
            && brokeAt.timeIntervalSince1970.isFinite && (0...CraftCatalog.maximumExperience).contains(daysWorn)
            && (0...CraftCatalog.maximumRepairs).contains(repairs) && attributes.count <= 2 && usesLeft >= 0
    }
}

/// Today's wheel turns. A new day (after sleeping into it) starts again.
public struct WheelDay: Codable, Equatable, Sendable {
    public var dayKey: String?
    public var freeUsed: Int
    public var paidUsed: Int
    public init() { dayKey = nil; freeUsed = 0; paidUsed = 0 }

    public func freeLeft(today: String?) -> Int { dayKey == today ? max(0, CraftCatalog.wheelFreeSpins - freeUsed) : CraftCatalog.wheelFreeSpins }
    public func paidLeft(today: String?) -> Int { dayKey == today ? max(0, CraftCatalog.wheelPaidSpins - paidUsed) : CraftCatalog.wheelPaidSpins }

    var isValid: Bool {
        (0...CraftCatalog.wheelFreeSpins).contains(freeUsed) && (0...CraftCatalog.wheelPaidSpins).contains(paidUsed)
            && (dayKey.map { TownEventState.date(for: $0) != nil } ?? (freeUsed == 0 && paidUsed == 0))
    }
}

/// What the last spin gave, with the before / after numbers the result card shows.
public struct WheelSpinResult: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let prize: WheelPrize
    public let count: Int
    public let paidGold: Int
    public let goldBefore: Int
    public let goldAfter: Int
    /// For a material (or stardust) prize: the bag before and after.
    public let materialBefore: Int
    public let materialAfter: Int
    /// For a blueprint prize.
    public let blueprintID: String?
    public let usesBefore: Int
    public let usesAfter: Int
    /// Stardust that uses above the cap turned into.
    public let overflowStardust: Int
    public let isNewBlueprint: Bool
}

/// What the last craft attempt did, for the success and failure cards.
public struct CraftAttemptResult: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let blueprintID: String
    public let succeeded: Bool
    public let successPercent: Int
    /// The handmade piece made (success only).
    public let itemID: String?
    /// Materials used up, and those handed back after a failure.
    public let spent: [String: Int]
    public let refunded: [String: Int]
    public let experienceBefore: Int
    public let experienceAfter: Int
    public let usesBefore: Int
    public let usesAfter: Int
    /// The same blueprint's chance for the next try.
    public let nextSuccessPercent: Int
    /// Blueprints a new skill level taught.
    public let learnedBlueprintIDs: [String]
}

/// A first copy granted by a milestone, so the game can say "学会了新蓝图" once.
public struct BlueprintGrant: Codable, Equatable, Sendable, Identifiable {
    public let blueprintID: String
    public let at: Date
    public var seen: Bool
    public var id: String { blueprintID }
}

public struct CraftState: Codable, Equatable, Sendable {
    public var materials: [String: Int]
    public var blueprints: [String: BlueprintRecord]
    /// Blueprints whose milestone first copy has been given (each route gives one copy, once).
    public var grantedSources: [String]
    public var experience: Int
    public var wheel: WheelDay
    public var goalBlueprintID: String?
    public var handmade: [HandmadeItem]
    /// Appearance slots (handmade item IDs). Independent of work gear.
    public var appearance: [EquipmentSlot: String]
    /// An empty appearance slot shows the work gear there; off shows the avatar's own clothes.
    public var showsWorkGearWhenEmpty: Bool
    public var nextSerial: Int
    /// Café naps taken since 3.0, for the chalkboard blueprint.
    public var cafeNaps: Int
    public var lastSpin: WheelSpinResult?
    public var lastAttempt: CraftAttemptResult?
    public var grants: [BlueprintGrant]
    /// Saves from before 3.0 are checked once for blueprints their earlier walks earned.
    public var legacyChecked: Bool
    /// 3.1: goodbye cards for pieces that broke, oldest first, and pieces that became fragile this morning.
    public var farewells: [HandmadeFarewell]
    public var fragileNotices: [String]

    public init() {
        materials = [:]; blueprints = [:]; grantedSources = []; experience = 0; wheel = WheelDay()
        goalBlueprintID = nil; handmade = []; appearance = [:]; showsWorkGearWhenEmpty = true
        nextSerial = 1; cafeNaps = 0; lastSpin = nil; lastAttempt = nil; grants = []; legacyChecked = false
        farewells = []; fragileNotices = []
    }

    private enum CodingKeys: String, CodingKey {
        case materials, blueprints, grantedSources, experience, wheel, goalBlueprintID, handmade, appearance
        case showsWorkGearWhenEmpty, nextSerial, cafeNaps, lastSpin, lastAttempt, grants, legacyChecked
        case farewells, fragileNotices
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        materials = try values.decodeIfPresent([String: Int].self, forKey: .materials) ?? [:]
        blueprints = try values.decodeIfPresent([String: BlueprintRecord].self, forKey: .blueprints) ?? [:]
        grantedSources = try values.decodeIfPresent([String].self, forKey: .grantedSources) ?? []
        experience = try values.decodeIfPresent(Int.self, forKey: .experience) ?? 0
        wheel = try values.decodeIfPresent(WheelDay.self, forKey: .wheel) ?? WheelDay()
        goalBlueprintID = try values.decodeIfPresent(String.self, forKey: .goalBlueprintID)
        handmade = try values.decodeIfPresent([HandmadeItem].self, forKey: .handmade) ?? []
        var appearance: [EquipmentSlot: String] = [:]
        for (key, itemID) in try values.decodeIfPresent([String: String].self, forKey: .appearance) ?? [:] {
            guard let slot = EquipmentSlot(rawValue: key) else {
                throw DecodingError.dataCorruptedError(forKey: .appearance, in: values, debugDescription: "Unknown appearance slot")
            }
            appearance[slot] = itemID
        }
        self.appearance = appearance
        showsWorkGearWhenEmpty = try values.decodeIfPresent(Bool.self, forKey: .showsWorkGearWhenEmpty) ?? true
        nextSerial = try values.decodeIfPresent(Int.self, forKey: .nextSerial) ?? 1
        cafeNaps = try values.decodeIfPresent(Int.self, forKey: .cafeNaps) ?? 0
        // Result cards are presentational: a damaged one is dropped rather than failing the save.
        lastSpin = try? values.decodeIfPresent(WheelSpinResult.self, forKey: .lastSpin)
        lastAttempt = try? values.decodeIfPresent(CraftAttemptResult.self, forKey: .lastAttempt)
        grants = try values.decodeIfPresent([BlueprintGrant].self, forKey: .grants) ?? []
        legacyChecked = try values.decodeIfPresent(Bool.self, forKey: .legacyChecked) ?? false
        farewells = try values.decodeIfPresent([HandmadeFarewell].self, forKey: .farewells) ?? []
        fragileNotices = try values.decodeIfPresent([String].self, forKey: .fragileNotices) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(materials, forKey: .materials)
        try values.encode(blueprints, forKey: .blueprints)
        try values.encode(grantedSources, forKey: .grantedSources)
        try values.encode(experience, forKey: .experience)
        try values.encode(wheel, forKey: .wheel)
        try values.encodeIfPresent(goalBlueprintID, forKey: .goalBlueprintID)
        try values.encode(handmade, forKey: .handmade)
        try values.encode(Dictionary(uniqueKeysWithValues: appearance.map { ($0.key.rawValue, $0.value) }), forKey: .appearance)
        try values.encode(showsWorkGearWhenEmpty, forKey: .showsWorkGearWhenEmpty)
        try values.encode(nextSerial, forKey: .nextSerial)
        try values.encode(cafeNaps, forKey: .cafeNaps)
        try values.encodeIfPresent(lastSpin, forKey: .lastSpin)
        try values.encodeIfPresent(lastAttempt, forKey: .lastAttempt)
        try values.encode(grants, forKey: .grants)
        try values.encode(legacyChecked, forKey: .legacyChecked)
        try values.encode(farewells, forKey: .farewells)
        try values.encode(fragileNotices, forKey: .fragileNotices)
    }

    // MARK: Reading

    public func count(of material: CraftMaterial) -> Int { materials[material.rawValue] ?? 0 }
    public func usesLeft(_ blueprintID: String) -> Int { blueprints[blueprintID]?.usesLeft ?? 0 }
    public func hasEverHeld(_ blueprintID: String) -> Bool { blueprints[blueprintID] != nil }
    public var skillLevel: CraftSkillLevel { CraftCatalog.skillLevel(experience: experience) }
    public func item(id: String) -> HandmadeItem? { handmade.first { $0.id == id } }
    public func isWorn(_ itemID: String) -> Bool { appearance.values.contains(itemID) }
    public var unseenGrants: [BlueprintGrant] { grants.filter { !$0.seen } }
    /// Marks these blueprints' grant notices as shown (a result card or a settlement already told the player).
    public mutating func markGrantsSeen(_ blueprintIDs: [String]) {
        let ids = Set(blueprintIDs)
        for index in grants.indices where ids.contains(grants[index].blueprintID) { grants[index].seen = true }
    }

    /// Every material a blueprint still lacks (empty when it can be made).
    public func shortfall(for definition: BlueprintDefinition) -> [CraftCost] {
        definition.costs.compactMap { cost in
            let missing = cost.count - count(of: cost.material)
            return missing > 0 ? CraftCost(material: cost.material, count: missing) : nil
        }
    }

    /// The chance shown on the button: base + skill + failures in a row, capped.
    public func successPercent(for definition: BlueprintDefinition) -> Int {
        let streak = blueprints[definition.id]?.failureStreak ?? 0
        return min(CraftCatalog.maximumSuccessPercent,
                   definition.tier.baseSuccessPercent + skillLevel.successBonus + streak * CraftCatalog.failureBonusPercent)
    }

    public enum Readiness: Equatable, Sendable {
        case ready, lacksMaterials, usedUp, neverHeld, skillTooLow(Int), notYetOpen
    }
    public func readiness(for definition: BlueprintDefinition) -> Readiness {
        guard definition.isCraftable else { return .notYetOpen }
        guard let record = blueprints[definition.id] else { return .neverHeld }
        guard record.usesLeft > 0 else { return .usedUp }
        guard skillLevel.level >= definition.tier.requiredSkillLevel else { return .skillTooLow(definition.tier.requiredSkillLevel) }
        return shortfall(for: definition).isEmpty ? .ready : .lacksMaterials
    }
    public var readyCount: Int { CraftCatalog.blueprints.filter { readiness(for: $0) == .ready }.count }

    /// Worn handmade pieces: per attribute only the best value counts.
    public var activeBonuses: [HandmadeAttribute: Int] {
        var best: [HandmadeAttribute: Int] = [:]
        for itemID in appearance.values {
            guard let item = item(id: itemID) else { continue }
            for roll in item.attributes { best[roll.attribute] = max(best[roll.attribute] ?? 0, roll.value) }
        }
        return best
    }
    public func bonus(_ attribute: HandmadeAttribute) -> Int { activeBonuses[attribute] ?? 0 }

    var isValid: Bool {
        guard materials.count <= CraftMaterial.allCases.count,
              materials.allSatisfy({ CraftMaterial(rawValue: $0.key) != nil && (0...CraftCatalog.maximumMaterial).contains($0.value) }),
              blueprints.allSatisfy({ id, record in CraftCatalog.blueprint(id: id).map(record.isValid(for:)) ?? false }),
              grantedSources.count <= CraftCatalog.blueprints.count, Set(grantedSources).count == grantedSources.count,
              grantedSources.allSatisfy({ CraftCatalog.blueprint(id: $0) != nil }),
              (0...CraftCatalog.maximumExperience).contains(experience), wheel.isValid,
              goalBlueprintID.map({ CraftCatalog.blueprint(id: $0) != nil }) ?? true,
              handmade.count <= CraftCatalog.maximumHandmade, handmade.allSatisfy(\.isValid),
              Set(handmade.map(\.id)).count == handmade.count,
              Set(appearance.values).count == appearance.count,
              (1...CraftCatalog.maximumExperience).contains(nextSerial),
              (0...CraftCatalog.maximumExperience).contains(cafeNaps),
              grants.count <= CraftCatalog.blueprints.count, Set(grants.map(\.blueprintID)).count == grants.count,
              grants.allSatisfy({ CraftCatalog.blueprint(id: $0.blueprintID) != nil && $0.at.timeIntervalSince1970.isFinite }),
              farewells.count <= CraftCatalog.maximumFarewells, farewells.allSatisfy(\.isValid),
              Set(farewells.map(\.id)).count == farewells.count,
              fragileNotices.count <= CraftCatalog.maximumHandmade, Set(fragileNotices).count == fragileNotices.count,
              fragileNotices.allSatisfy({ item(id: $0) != nil })
        else { return false }
        return appearance.allSatisfy { slot, itemID in item(id: itemID)?.blueprint?.product.slot == slot }
    }
}
