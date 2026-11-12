import Foundation
import Testing
@testable import CatGameCore

@Suite("Siamese and silver shaded adoption")
struct SiameseSilverAdoptionTests {
    private let now = Date(timeIntervalSince1970: 1_793_600_000)

    private func eligibleSnapshot() -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 8
        state.player.gold = 5_000
        state.home.roomLevel = 3
        return state
    }

    @Test(arguments: [CatCatalog.siameseCatID, CatCatalog.silverCatID])
    func eachRequirementIsCheckedBeforeAnyPurchase(catID: String) throws {
        let offer = try #require(CatCatalog.adoptionOffer(catID: catID))
        #expect(offer.appearance == (catID == CatCatalog.siameseCatID ? .siamese : .silver))
        #expect(offer.price == (offer.appearance == .siamese ? 900 : 1_200))
        #expect(offer.requiredPlayerLevel == (offer.appearance == .siamese ? 6 : 8))
        #expect(offer.requiredRoomLevel == 3)
        for (level, room, gold, expected) in [
            (offer.requiredPlayerLevel - 1, 3, 5_000, ActionFailure.catPlayerLevelRequired),
            (8, 2, 5_000, .catRoomLevelRequired),
            (8, 3, offer.price - 1, .shopGoldRequired)
        ] {
            var state = eligibleSnapshot()
            state.player.level = level
            state.home.roomLevel = room
            state.player.gold = gold
            let before = state
            #expect(GameEngine.adoptCat(&state, catID: catID, now: now).failure == expected)
            #expect(state == before)
        }
    }

    @Test(arguments: [CatCatalog.siameseCatID, CatCatalog.silverCatID])
    func independentAdoptionDeductsOnceAndKeepsOldCompanion(catID: String) throws {
        var state = eligibleSnapshot()
        let offer = try #require(CatCatalog.adoptionOffer(catID: catID))
        state.player.gold = offer.price
        let original = state
        #expect(GameEngine.adoptCat(&state, catID: catID, now: now).success == .catAdopted)
        #expect(state.player.gold == 0)
        #expect(state.cats.count == 2 && state.cats[0] == original.cats[0])
        #expect(state.activeCatID == original.activeCatID)
        #expect(state.cats[1].appearance == offer.appearance)
        #expect(state.cats[1].healthState == CatHealthState(now: now))
        let once = state
        #expect(GameEngine.adoptCat(&state, catID: catID, now: now).failure == .catAlreadyOwned)
        #expect(state == once)
    }

    @Test func allFiveCatsKeepIndependentNamesHealthCareAndCompanionAfterRoundTrip() throws {
        var state = eligibleSnapshot()
        for offer in CatCatalog.adoptionOffers {
            #expect(GameEngine.adoptCat(&state, catID: offer.id, now: now).succeeded)
        }
        #expect(state.cats.map(\.appearance) == CatAppearance.allCases)
        #expect(state.player.gold == 2_000)
        let previous = Array(state.cats.prefix(3))
        for id in [CatCatalog.siameseCatID, CatCatalog.silverCatID] {
            #expect(GameEngine.selectCompanion(&state, catID: id, now: now).succeeded)
            #expect(GameEngine.feed(&state, catID: id, now: now).succeeded)
            #expect(GameEngine.clean(&state, catID: id, now: now).succeeded)
        }
        state.cats[3].customName = "Cocoa🐾"
        state.cats[4].customName = "雪团"
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: encoded)
        #expect(decoded == state && decoded.isValid)
        #expect(decoded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(Array(decoded.cats.prefix(3)) == previous)
        #expect(decoded.activeCat?.appearance == .silver)
        #expect(decoded.cats[3].customName == "Cocoa🐾" && decoded.cats[4].customName == "雪团")
    }

    @Test func schemaSixKeepsExistingThreeCatsWithoutAutoAdoptingNewBreeds() throws {
        var original = eligibleSnapshot()
        for id in [CatCatalog.cowCatID, CatCatalog.blueCatID] {
            #expect(GameEngine.adoptCat(&original, catID: id, now: now).succeeded)
        }
        original.cats[1].customName = "奶糖"
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["schemaVersion"] = 6
        object.removeValue(forKey: "community")
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
        #expect(decoded.cats == original.cats && decoded.player == original.player)
        #expect(decoded.home == original.home && decoded.inventory == original.inventory)
        #expect(decoded.cats.map(\.appearance) == [.orange, .cow, .blue])
        #expect(decoded.schemaVersion == GameSnapshot.currentSchemaVersion && decoded.isValid)
    }
}
