import Foundation

/// Shared rules for the crafting systems, used by the engine actions and the hooks in other systems.
public enum CraftRules {
    /// Outing stamina after the worn handmade bonus (rounded up, never below 1).
    public static func outingStaminaCost(in state: GameSnapshot) -> Int {
        WorkQuote.discount(OutingCatalog.staminaCost, by: state.craft.bonus(.outingStamina))
    }
    /// A shift's wage with the worn handmade bonus (advanced pieces only roll it).
    public static func wage(_ base: Int, in state: GameSnapshot) -> Int {
        let percent = state.craft.bonus(.workGold)
        return percent > 0 ? base + base * percent / 100 : base
    }
    /// The café nap's effect with the worn handmade bonus.
    public static func napEffect(in state: GameSnapshot) -> RecoveryEffect {
        let percent = state.craft.bonus(.napRecovery)
        let base = CafeCatalog.napEffect
        guard percent > 0 else { return base }
        return RecoveryEffect(stamina: base.stamina + base.stamina * percent / 100, mood: base.mood + base.mood * percent / 100)
    }

    /// Adds to the bag up to its cap; returns what was actually added.
    @discardableResult
    static func add(_ material: CraftMaterial, _ amount: Int, to craft: inout CraftState) -> Int {
        let current = craft.count(of: material)
        let added = max(0, min(amount, CraftCatalog.maximumMaterial - current))
        craft.materials[material.rawValue] = current + added
        return added
    }

    struct CopyGrant { let usesBefore: Int; let usesAfter: Int; let overflowStardust: Int; let isNew: Bool }

    /// One more copy: its uses are added up to two copies' worth. When `convertsOverflow`, uses above
    /// the cap become stardust (10 per whole copy, rounded up).
    static func grantCopy(_ definition: BlueprintDefinition, to craft: inout CraftState, at timestamp: Date,
                          convertsOverflow: Bool = true) -> CopyGrant {
        let isNew = craft.blueprints[definition.id] == nil
        var record = craft.blueprints[definition.id] ?? BlueprintRecord(usesLeft: 0, firstLearnedAt: timestamp)
        let before = record.usesLeft
        let total = before + definition.tier.usesPerCopy
        record.usesLeft = min(definition.tier.maximumUses, total)
        craft.blueprints[definition.id] = record
        let overflow = total - record.usesLeft
        var stardust = 0
        if convertsOverflow, overflow > 0 {
            let per = definition.tier.usesPerCopy
            stardust = add(.stardust, (overflow * CraftCatalog.overflowStardustPerCopy + per - 1) / per, to: &craft)
        }
        return CopyGrant(usesBefore: before, usesAfter: record.usesLeft, overflowStardust: stardust, isNew: isNew)
    }

    /// A route's first copy, given once, with a "学会了新蓝图" notice.
    static func grantFirstCopy(_ definition: BlueprintDefinition, in state: inout GameSnapshot, at timestamp: Date) {
        guard !state.craft.grantedSources.contains(definition.id) else { return }
        state.craft.grantedSources.append(definition.id)
        _ = grantCopy(definition, to: &state.craft, at: timestamp)
        state.craft.grants.removeAll { $0.blueprintID == definition.id }
        state.craft.grants.append(BlueprintGrant(blueprintID: definition.id, at: timestamp, seen: false))
    }

    /// Milestones that can be read from the save. Runs on every sync, so saves from before 3.0 receive
    /// the blueprints their existing progress (keepsakes, neighbours, letters) has already earned.
    static func grantEarnedBlueprints(_ state: inout GameSnapshot, at timestamp: Date) {
        if !state.craft.legacyChecked {
            state.craft.legacyChecked = true
            // Players who walked the garden before 3.0 get the garden hat their walks would have earned.
            if state.outing.totalDepartures > 0, let hat = CraftCatalog.blueprints.first(where: { $0.source == .gardenWalk }) {
                grantFirstCopy(hat, in: &state, at: timestamp)
            }
        }
        for definition in CraftCatalog.blueprints where !state.craft.grantedSources.contains(definition.id) {
            if isEarned(definition.source, in: state) { grantFirstCopy(definition, in: &state, at: timestamp) }
        }
    }

    static func isEarned(_ source: BlueprintSource, in state: GameSnapshot) -> Bool {
        switch source {
        case .keepsake(let id): return state.outing.keepsakes[id] != nil
        case .friendship(let neighborID, let stage): return state.community.relationship(for: neighborID).stage.level >= stage
        case .cafeNaps(let count): return state.craft.cafeNaps >= count
        case .townEvent(let id): return state.community.events.letters.contains { $0.eventID == id }
        case .craftLevel(let level): return state.craft.skillLevel.level >= level
        // Granted where they happen (the outing's settlement), or not yet open.
        case .gardenWalk, .rainyOuting, .bazaarTrades, .shares, .shopShelf, .luck: return false
        }
    }

    /// Called when an outing is settled: a full walk and meeting the drizzle each teach a blueprint.
    static func grantOutingBlueprints(_ state: inout GameSnapshot, trip: OutingTrip, at timestamp: Date) -> [String] {
        var learned: [String] = []
        for definition in CraftCatalog.blueprints where !state.craft.grantedSources.contains(definition.id) {
            let earned = switch definition.source {
            case .gardenWalk: trip.footprintsUsed >= OutingCatalog.footprints
            case .rainyOuting: trip.seenEventIDs.contains("drizzle")
            default: false
            }
            if earned { grantFirstCopy(definition, in: &state, at: timestamp); learned.append(definition.id) }
        }
        return learned
    }

    /// A finished shift may bring home a piece of fabric, decided by the shift's own ID.
    static func workFabric(shiftID: String, in state: inout GameSnapshot) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in shiftID.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        var random = OutingRandom(seed: hash, step: 0)
        guard random.percent() < CraftCatalog.workFabricChance else { return 0 }
        return add(.fabric, 1, to: &state.craft)
    }

    /// A footprint may also turn up its spot's material, rolled on its own stream so every other
    /// outcome of the step stays the same.
    static func outingMaterial(_ trip: inout OutingTrip, spot: OutingSpot, in state: inout GameSnapshot) {
        var random = OutingRandom(seed: trip.seed ^ 0xC4AF_7E15_3A7E_0001, step: trip.step)
        guard random.percent() < CraftCatalog.outingMaterialChance else { return }
        let material = CraftCatalog.material(at: spot)
        let added = add(material, 1, to: &state.craft)
        guard added > 0 else { return }
        var finds = trip.craftFinds ?? [:]
        finds[material.rawValue, default: 0] += added
        trip.craftFinds = finds
    }

    /// The wheel's slice for a 0...99 roll.
    static func slice(for roll: Int) -> WheelSlice {
        var total = 0
        for slice in CraftCatalog.wheel {
            total += slice.percent
            if roll < total { return slice }
        }
        return CraftCatalog.wheel[0]
    }
}

extension GameEngine {
    /// One turn of the wheel: the day's free turn first, then up to two paid ones. Every turn gives something.
    public static func spinWheel(_ state: inout GameSnapshot, seed: UInt64 = .random(in: .min ... .max),
                                 now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let today = state.tasks.dailyDayKey else { return .init(failure: .gameInvalidState) }
        var wheel = state.craft.wheel
        if wheel.dayKey != today { wheel = WheelDay(); wheel.dayKey = today }
        let free = wheel.freeLeft(today: today) > 0
        if !free {
            guard wheel.paidLeft(today: today) > 0 else { return .init(failure: .wheelDailyLimit) }
            guard state.player.gold >= CraftCatalog.wheelSpinPrice else {
                return .init(failure: .shopGoldRequired, amount: CraftCatalog.wheelSpinPrice)
            }
        }
        let timestamp = effectiveTime(state, now: now)
        var candidate = state
        let goldBefore = candidate.player.gold
        if free { wheel.freeUsed += 1 } else { wheel.paidUsed += 1; candidate.player.gold -= CraftCatalog.wheelSpinPrice }
        candidate.craft.wheel = wheel
        var random = OutingRandom(seed: seed, step: 0)
        let slice = CraftRules.slice(for: random.percent())
        let id = "spin-\(today)-\(wheel.freeUsed + wheel.paidUsed)"
        let result: WheelSpinResult
        if let material = slice.prize.material {
            let before = candidate.craft.count(of: material)
            let added = CraftRules.add(material, slice.count, to: &candidate.craft)
            result = WheelSpinResult(id: id, prize: slice.prize, count: added, paidGold: free ? 0 : CraftCatalog.wheelSpinPrice,
                                     goldBefore: goldBefore, goldAfter: candidate.player.gold, materialBefore: before,
                                     materialAfter: before + added, blueprintID: nil, usesBefore: 0, usesAfter: 0,
                                     overflowStardust: 0, isNewBlueprint: false)
        } else {
            // Blueprints with room for more uses first; once every one is full, any (the extra becomes stardust).
            let craftable = CraftCatalog.craftableBlueprints
            let open = craftable.filter { candidate.craft.usesLeft($0.id) < $0.tier.maximumUses }
            guard let definition = random.pick(open.isEmpty ? craftable : open) else { return .init(failure: .gameInvalidState) }
            let grant = CraftRules.grantCopy(definition, to: &candidate.craft, at: timestamp)
            result = WheelSpinResult(id: id, prize: .blueprint, count: 1, paidGold: free ? 0 : CraftCatalog.wheelSpinPrice,
                                     goldBefore: goldBefore, goldAfter: candidate.player.gold, materialBefore: 0, materialAfter: 0,
                                     blueprintID: definition.id, usesBefore: grant.usesBefore, usesAfter: grant.usesAfter,
                                     overflowStardust: grant.overflowStardust, isNewBlueprint: grant.isNew)
        }
        candidate.craft.lastSpin = result
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .wheelSpun)
    }

    /// Stardust buys a chosen blueprint copy, priced by tier. Uses stop at the cap (no stardust back).
    public static func exchangeStardust(_ state: inout GameSnapshot, blueprintID: String, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let definition = CraftCatalog.blueprint(id: blueprintID) else { return .init(failure: .craftBlueprintMissing) }
        guard definition.isCraftable else { return .init(failure: .craftNotOpen) }
        guard state.craft.usesLeft(blueprintID) < definition.tier.maximumUses else { return .init(failure: .craftUsesFull) }
        let price = definition.tier.stardustPrice
        let have = state.craft.count(of: .stardust)
        guard have >= price else { return .init(failure: .craftStardustRequired, amount: price - have) }
        var candidate = state
        candidate.craft.materials[CraftMaterial.stardust.rawValue] = have - price
        _ = CraftRules.grantCopy(definition, to: &candidate.craft, at: effectiveTime(state, now: now), convertsOverflow: false)
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .stardustExchanged)
    }

    /// One try at a blueprint. Success uses the materials and one use and makes a piece with a rolled
    /// quality and attributes. Failure hands back half of each material (rounded up), keeps the use,
    /// and makes the next try of the same blueprint 5% likelier. Both raise the craft skill.
    public static func craft(_ state: inout GameSnapshot, blueprintID: String, seed: UInt64 = .random(in: .min ... .max),
                             now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let definition = CraftCatalog.blueprint(id: blueprintID) else { return .init(failure: .craftBlueprintMissing) }
        switch state.craft.readiness(for: definition) {
        case .ready: break
        case .notYetOpen: return .init(failure: .craftNotOpen)
        case .neverHeld: return .init(failure: .craftBlueprintMissing)
        case .usedUp: return .init(failure: .craftUsedUp)
        case .skillTooLow(let level): return .init(failure: .craftSkillRequired, amount: level)
        case .lacksMaterials: return .init(failure: .craftMaterialsRequired)
        }
        guard state.craft.handmade.count < CraftCatalog.maximumHandmade else { return .init(failure: .craftInventoryFull) }
        let timestamp = effectiveTime(state, now: now)
        var candidate = state
        var craft = candidate.craft
        guard var record = craft.blueprints[definition.id] else { return .init(failure: .craftBlueprintMissing) }
        let serial = craft.nextSerial
        var random = OutingRandom(seed: seed, step: serial)
        let percent = craft.successPercent(for: definition)
        let experienceBefore = craft.experience
        let usesBefore = record.usesLeft
        let succeeded = random.percent() < percent
        var spent: [String: Int] = [:]
        var refunded: [String: Int] = [:]
        var itemID: String?
        if succeeded {
            for cost in definition.costs {
                craft.materials[cost.material.rawValue] = craft.count(of: cost.material) - cost.count
                spent[cost.material.rawValue] = cost.count
            }
            record.usesLeft -= 1
            record.craftedCount += 1
            record.failureStreak = 0
            craft.experience = min(CraftCatalog.maximumExperience, craft.experience + definition.tier.successExperience)
            let odds = CraftCatalog.qualityOdds(tier: definition.tier, skillLevel: CraftCatalog.skillLevel(experience: experienceBefore).level)
            let qualityRoll = random.percent()
            let common = odds[.common] ?? 0, fine = odds[.fine] ?? 0
            let quality: OutingDecorQuality = qualityRoll < common ? .common : qualityRoll < common + fine ? .fine : .treasured
            var pool = CraftCatalog.attributes(for: definition.tier)
            var attributes: [HandmadeAttributeRoll] = []
            for _ in 0..<CraftCatalog.attributeCount(tier: definition.tier, quality: quality) {
                guard let attribute = random.pick(pool) else { break }
                pool.removeAll { $0 == attribute }
                attributes.append(HandmadeAttributeRoll(attribute: attribute, value: random.int(attribute.range(for: quality))))
            }
            let id = "handmade-\(serial)"
            craft.handmade.append(HandmadeItem(id: id, blueprintID: definition.id, quality: quality,
                                               attributes: attributes, madeAt: timestamp))
            itemID = id
        } else {
            for cost in definition.costs {
                let back = (cost.count + 1) / 2
                let used = cost.count - back
                craft.materials[cost.material.rawValue] = craft.count(of: cost.material) - used
                if used > 0 { spent[cost.material.rawValue] = used }
                refunded[cost.material.rawValue] = back
            }
            record.failureStreak = min(CraftCatalog.maximumFailureStreak, record.failureStreak + 1)
            craft.experience = min(CraftCatalog.maximumExperience, craft.experience + definition.tier.failureExperience)
        }
        craft.nextSerial = min(CraftCatalog.maximumExperience, serial + 1)
        craft.blueprints[definition.id] = record
        candidate.craft = craft
        // A new skill level may teach a blueprint right away.
        let heldBefore = Set(candidate.craft.grantedSources)
        CraftRules.grantEarnedBlueprints(&candidate, at: timestamp)
        let learned = candidate.craft.grantedSources.filter { !heldBefore.contains($0) }
        // The result card names them, so the cottage doesn't announce them again.
        candidate.craft.markGrantsSeen(learned)
        candidate.craft.lastAttempt = CraftAttemptResult(
            id: "attempt-\(serial)", blueprintID: definition.id, succeeded: succeeded, successPercent: percent, itemID: itemID,
            spent: spent, refunded: refunded, experienceBefore: experienceBefore, experienceAfter: candidate.craft.experience,
            usesBefore: usesBefore, usesAfter: record.usesLeft,
            nextSuccessPercent: candidate.craft.successPercent(for: definition), learnedBlueprintIDs: learned)
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: succeeded ? .crafted : .craftMissed)
    }

    /// The blueprint the cottage keeps track of (nil clears it).
    public static func setCraftGoal(_ state: inout GameSnapshot, blueprintID: String?, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        if let blueprintID, CraftCatalog.blueprint(id: blueprintID) == nil { return .init(failure: .craftBlueprintMissing) }
        guard state.craft.goalBlueprintID != blueprintID else { return ActionOutcome() }
        state.craft.goalBlueprintID = blueprintID
        return .init(success: .craftGoalSet)
    }

    /// Wear a handmade piece in its appearance slot, or clear the slot. Work gear and its bonuses never change.
    public static func setAppearance(_ state: inout GameSnapshot, slot: EquipmentSlot, itemID: String?,
                                     now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        if let itemID {
            guard let item = state.craft.item(id: itemID) else { return .init(failure: .craftItemMissing) }
            guard item.blueprint?.product.slot == slot else { return .init(failure: .craftSlotMismatch) }
        }
        guard state.craft.appearance[slot] != itemID else { return ActionOutcome() }
        var candidate = state
        candidate.craft.appearance[slot] = itemID
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: itemID == nil ? .appearanceCleared : .appearanceWorn)
    }

    public static func setShowsWorkGearWhenEmpty(_ state: inout GameSnapshot, _ value: Bool, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard state.craft.showsWorkGearWhenEmpty != value else { return ActionOutcome() }
        state.craft.showsWorkGearWhenEmpty = value
        return .init(success: .appearanceSettingSaved)
    }

    /// The "学会了新蓝图" notices have been shown.
    public static func markBlueprintGrantsSeen(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard !state.craft.unseenGrants.isEmpty else { return ActionOutcome() }
        for index in state.craft.grants.indices { state.craft.grants[index].seen = true }
        return .init(success: .blueprintGrantsSeen)
    }
}
