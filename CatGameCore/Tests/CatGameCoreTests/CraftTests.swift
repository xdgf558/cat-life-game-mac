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
