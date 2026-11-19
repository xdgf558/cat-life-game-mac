import Foundation
import Testing
@testable import CatGameCore

@Suite("Magic cottage crafting, wheel and stardust")
struct CraftTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    @Test func saveWithoutCraftDecodesToAnEmptyCottage() throws {
        let original = GameSnapshot.fresh(now: now)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["schemaVersion"] = 18
        object.removeValue(forKey: "craft")
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
        #expect(decoded.craft == CraftState())
        #expect(decoded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(decoded.isValid)
    }

    @Test func stardustStopsAtTheCapWithoutRefund() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic })
        var state = GameSnapshot.fresh(now: now)
        state.craft.blueprints[hat.id] = BlueprintRecord(usesLeft: hat.tier.maximumUses - 1, firstLearnedAt: now)
        state.craft.materials[CraftMaterial.stardust.rawValue] = hat.tier.stardustPrice
        #expect(GameEngine.exchangeStardust(&state, blueprintID: hat.id, now: now).succeeded)
        #expect(state.craft.usesLeft(hat.id) == hat.tier.maximumUses)
        #expect(state.craft.count(of: .stardust) == 0)
        // Full now: a second exchange is refused and costs nothing.
        state.craft.materials[CraftMaterial.stardust.rawValue] = hat.tier.stardustPrice
        #expect(!GameEngine.exchangeStardust(&state, blueprintID: hat.id, now: now).succeeded)
        #expect(state.craft.count(of: .stardust) == hat.tier.stardustPrice)
    }

    @Test func aCopyPastTheCapBecomesStardust() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic })
        var craft = CraftState()
        craft.blueprints[hat.id] = BlueprintRecord(usesLeft: hat.tier.maximumUses, firstLearnedAt: now)
        let grant = CraftRules.grantCopy(hat, to: &craft, at: now)
        #expect(grant.usesAfter == hat.tier.maximumUses)
        #expect(grant.overflowStardust == CraftCatalog.overflowStardustPerCopy)
        #expect(craft.count(of: .stardust) == CraftCatalog.overflowStardustPerCopy)
    }

    @Test func aMissReturnsHalfTheMaterialsAndRaisesTheNextChance() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic })
        let start = ready(hat)
        var state = start
        var seed: UInt64 = 0
        // 90% succeed, so look for a seed that misses.
        while seed < 500 {
            state = start
            #expect(GameEngine.craft(&state, blueprintID: hat.id, seed: seed, now: now).succeeded)
            if state.craft.lastAttempt?.succeeded == false { break }
            seed += 1
        }
        let attempt = try #require(state.craft.lastAttempt)
        #expect(!attempt.succeeded)
        for cost in hat.costs {
            #expect(state.craft.count(of: cost.material) == (cost.count + 1) / 2)
        }
        #expect(state.craft.usesLeft(hat.id) == hat.tier.usesPerCopy)
        #expect(state.craft.blueprints[hat.id]?.failureStreak == 1)
        #expect(attempt.nextSuccessPercent == attempt.successPercent + CraftCatalog.failureBonusPercent)
        #expect(state.craft.experience == hat.tier.failureExperience)
    }

    @Test func aSuccessUsesOneCopyAndMakesAPiece() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic })
        let start = ready(hat)
        var state = start
        var seed: UInt64 = 0
        while seed < 50 {
            state = start
            _ = GameEngine.craft(&state, blueprintID: hat.id, seed: seed, now: now)
            if state.craft.lastAttempt?.succeeded == true { break }
            seed += 1
        }
        let attempt = try #require(state.craft.lastAttempt)
        #expect(attempt.succeeded)
        #expect(state.craft.usesLeft(hat.id) == hat.tier.usesPerCopy - 1)
        #expect(state.craft.handmade.count == 1)
        for cost in hat.costs { #expect(state.craft.count(of: cost.material) == 0) }
    }

    @Test func reachingCraftLevelTwoTeachesItsBlueprintWithoutASecondNotice() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic })
        let taught = try #require(CraftCatalog.blueprints.first { $0.source == .craftLevel(2) })
        let levelTwo = try #require(CraftCatalog.skillLevels.first { $0.level == 2 })
        var state = ready(hat)
        // Either outcome (+10 or +5) crosses the threshold.
        state.craft.experience = levelTwo.minimumExperience - hat.tier.failureExperience
        #expect(GameEngine.craft(&state, blueprintID: hat.id, seed: 1, now: now).succeeded)
        #expect(state.craft.skillLevel.level >= 2)
        #expect(state.craft.lastAttempt?.learnedBlueprintIDs.contains(taught.id) == true)
        #expect(state.craft.hasEverHeld(taught.id))
        #expect(!state.craft.unseenGrants.contains { $0.blueprintID == taught.id })
    }

    @Test func invalidGrantsMakeTheCottageInvalid() {
        var craft = CraftState()
        craft.grants = [BlueprintGrant(blueprintID: "noSuchBlueprint", at: now, seen: false)]
        #expect(!craft.isValid)
    }

    // MARK: 3.1 durability

    @Test func aMadePieceGetsDurabilityFromItsTierAndQuality() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic })
        let item = try #require(madePiece(hat).craft.handmade.first)
        let range = CraftCatalog.durabilityRange(tier: hat.tier, quality: item.quality)
        #expect(range.contains(item.durability) && item.durability == item.durabilityCap && item.stage == .fresh)
    }

    @Test func aPieceFromThreePointZeroDecodesLikeNew() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic })
        let json = #"{"id":"handmade-1","blueprintID":"\#(hat.id)","quality":"fine","attributes":[{"attribute":"bond","value":5},{"attribute":"dailyMood","value":3}],"madeAt":0}"#
        let item = try JSONDecoder().decode(HandmadeItem.self, from: Data(json.utf8))
        #expect(item.durabilityCap == CraftCatalog.durabilityRange(tier: hat.tier, quality: .fine).upperBound)
        #expect(item.durability == item.durabilityCap && item.repairs == 0 && item.isValid)
    }

    @Test func onlyWornPiecesLoseADayEachMorning() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic && $0.product.slot != nil })
        var state = madePiece(hat)
        let slot = try #require(hat.product.slot)
        let item = try #require(state.craft.handmade.first)
        // A second piece stays in the closet.
        state.craft.handmade.append(HandmadeItem(id: "handmade-99", blueprintID: hat.id, quality: .common,
            attributes: item.attributes.prefix(1).map { $0 }, madeAt: now, durability: 10, durabilityCap: 10))
        state.craft.appearance[slot] = item.id
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400))
        #expect(state.craft.item(id: item.id)?.durability == item.durability - 1)
        #expect(state.craft.item(id: item.id)?.daysWorn == 1)
        #expect(state.craft.item(id: "handmade-99")?.durability == 10)
        // Away for a week: still one day.
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400 * 8))
        #expect(state.craft.item(id: item.id)?.durability == item.durability - 2)
        #expect(state.isValid)
    }

    @Test func aPieceThatBecomesFragileIsAnnouncedOnce() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic && $0.product.slot != nil })
        var state = madePiece(hat)
        let slot = try #require(hat.product.slot)
        let id = try #require(state.craft.handmade.first?.id)
        state.craft.handmade[0].durabilityCap = 20
        state.craft.handmade[0].durability = 4
        state.craft.appearance[slot] = id
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400))
        #expect(state.craft.fragileNotices == [id])
        #expect(GameEngine.acknowledgeHandmadeNotices(&state, farewellID: nil, now: now.addingTimeInterval(86_400)).succeeded)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400 * 2))
        #expect(state.craft.fragileNotices.isEmpty)
    }

    @Test func aWornOutPieceLeavesAGoodbyeCardAndAMaterial() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic && $0.product.slot != nil })
        var state = madePiece(hat)
        let slot = try #require(hat.product.slot)
        let id = try #require(state.craft.handmade.first?.id)
        let usesBefore = state.craft.usesLeft(hat.id)
        let material = try #require(CraftCatalog.repairCosts(for: hat).first?.material)
        let bagBefore = state.craft.count(of: material)
        state.craft.handmade[0].durability = 1
        state.craft.appearance[slot] = id
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(86_400))
        #expect(state.craft.item(id: id) == nil && state.craft.appearance[slot] == nil)
        let farewell = try #require(state.craft.farewells.first)
        #expect(farewell.id == id && farewell.refunded == material && farewell.usesLeft == usesBefore)
        #expect(state.craft.count(of: material) == bagBefore + 1 && state.craft.usesLeft(hat.id) == usesBefore)
        #expect(state.isValid)
        #expect(GameEngine.acknowledgeHandmadeNotices(&state, farewellID: id, now: now.addingTimeInterval(86_400)).succeeded)
        #expect(state.craft.farewells.isEmpty)
    }

    @Test func mendingRestoresTwoThirdsAndLowersTheCap() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic && $0.product.slot != nil })
        var state = madePiece(hat)
        state.craft.handmade[0].durabilityCap = 30
        state.craft.handmade[0].durability = 3
        let attributes = state.craft.handmade[0].attributes
        // No materials yet.
        #expect(GameEngine.repairHandmade(&state, itemID: state.craft.handmade[0].id, now: now).failure == .craftRepairMaterials)
        for cost in CraftCatalog.repairCosts(for: hat) { state.craft.materials[cost.material.rawValue] = cost.count }
        #expect(GameEngine.repairHandmade(&state, itemID: state.craft.handmade[0].id, now: now).succeeded)
        let item = state.craft.handmade[0]
        #expect(item.durabilityCap == 26 && item.durability == 18 && item.repairs == 1 && item.attributes == attributes)
        for cost in CraftCatalog.repairCosts(for: hat) { #expect(state.craft.count(of: cost.material) == 0) }
        // Already above two thirds: nothing to mend.
        #expect(GameEngine.repairHandmade(&state, itemID: item.id, now: now).failure == .craftRepairNotNeeded)
    }

    @Test func aMasterMendsWithoutLoweringTheCap() throws {
        let hat = try #require(CraftCatalog.craftableBlueprints.first { $0.tier == .basic && $0.product.slot != nil })
        var state = madePiece(hat)
        let master = try #require(CraftCatalog.skillLevels.first { $0.level == CraftCatalog.repairMasterLevel })
        state.craft.experience = master.minimumExperience
        state.craft.handmade[0].durabilityCap = 30
        state.craft.handmade[0].durability = 3
        for cost in CraftCatalog.repairCosts(for: hat) { state.craft.materials[cost.material.rawValue] = cost.count }
        #expect(GameEngine.repairHandmade(&state, itemID: state.craft.handmade[0].id, now: now).succeeded)
        #expect(state.craft.handmade[0].durabilityCap == 30 && state.craft.handmade[0].durability == 20)
    }

    /// A save holding one freshly made piece of `definition`.
    private func madePiece(_ definition: BlueprintDefinition) -> GameSnapshot {
        let start = ready(definition)
        var state = start
        var seed: UInt64 = 0
        while seed < 50 {
            state = start
            _ = GameEngine.craft(&state, blueprintID: definition.id, seed: seed, now: now)
            if state.craft.lastAttempt?.succeeded == true { break }
            seed += 1
        }
        return state
    }

    /// A fresh save holding one copy of `definition` and exactly the materials it needs.
    private func ready(_ definition: BlueprintDefinition) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.synchronize(&state, now: now)
        state.craft = CraftState()
        state.craft.legacyChecked = true
        state.craft.blueprints[definition.id] = BlueprintRecord(usesLeft: definition.tier.usesPerCopy, firstLearnedAt: now)
        for cost in definition.costs { state.craft.materials[cost.material.rawValue] = cost.count }
        return state
    }
}
