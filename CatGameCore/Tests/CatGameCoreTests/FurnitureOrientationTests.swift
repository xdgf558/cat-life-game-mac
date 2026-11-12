import Foundation
import Testing
@testable import CatGameCore

@Suite("Furniture orientation is durable instance state")
struct FurnitureOrientationTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func json(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: snapshotFixtureData(object))
    }

    @Test func onlyFloorKindsSupportRotationAndEveryLegacyItemKeepsItsOriginalDirection() throws {
        #expect(Set(FurnitureKind.allCases.filter(\.supportsRotation)) ==
            [.cabinet, .catTree, .catBed, .plant, .floorCushion, .flowerStool, .bookcase, .rattanChair, .sideTable])
        let original = GameSnapshot.fresh(now: now)
        for version in 1...5 {
            var object = try json(original)
            object["schemaVersion"] = version
            var inventory = try #require(object["inventory"] as? [String: Any])
            var items = try #require(inventory["furniture"] as? [[String: Any]])
            for index in items.indices { items[index].removeValue(forKey: "orientation") }
            inventory["furniture"] = items
            object["inventory"] = inventory
            let loaded = try decode(object)
            #expect(loaded == original && loaded.isValid)
            #expect(loaded.inventory.furniture.allSatisfy { $0.orientation == .front })
        }
    }

    @Test func malformedOrUnsupportedDirectionsAreRejectedInsteadOfReset() throws {
        let original = GameSnapshot.fresh(now: now)
        for invalid in [NSNull(), "upsideDown", 1, false] as [Any] {
            var object = try json(original)
            var inventory = try #require(object["inventory"] as? [String: Any])
            var items = try #require(inventory["furniture"] as? [[String: Any]])
            items[0]["orientation"] = invalid
            inventory["furniture"] = items
            object["inventory"] = inventory
            #expect(throws: (any Error).self) { try decode(object) }
        }
        for kind in [FurnitureKind.wallCat, .wallFlower] {
            var state = original
            let index = try #require(state.inventory.furniture.firstIndex { $0.kind == kind })
            state.inventory.furniture[index].orientation = .left
            #expect(!state.isValid)
            #expect(throws: SaveRepositoryError.invalidSnapshot) { try decode(json(state)) }
        }
    }

    @Test func orientationAndLayoutCommitTogetherWithoutChangingOwnershipOrRewards() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        let orientations = Dictionary(uniqueKeysWithValues: state.inventory.furniture
            .filter { $0.kind.supportsRotation }.map { ($0.id, FurnitureOrientation.left) })
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: original.home.bowlPosition,
            furniture: original.home.furniture, orientations: orientations, now: now).succeeded)
        var expected = original
        for index in expected.inventory.furniture.indices where expected.inventory.furniture[index].kind.supportsRotation {
            expected.inventory.furniture[index].orientation = .left
        }
        #expect(state == expected && state.isValid)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture, now: now).succeeded)
        #expect(state == expected)
    }

    @Test func invalidOrientationOrLayoutCannotCommitAnyPartOfTheDraft() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        let invalidOrientations: [[String: FurnitureOrientation]] = [
            ["catBed": .left, "wallCat": .left],
            ["catBed": .left, "not-owned": .front],
            ["bowl": .left]
        ]
        for orientations in invalidOrientations {
            #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.6, y: 0.7),
                furniture: [], orientations: orientations, now: now).failure == .roomInvalidFurnitureLayout)
            #expect(state == original)
        }
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: .infinity, y: 0.7),
            furniture: [], orientations: ["catBed": .left], now: now).failure == .roomInvalidPosition)
        #expect(state == original)

        state.inventory.furniture.append(.init(id: "extra", kind: .plant))
        let beforeCapacityCheck = state
        let crowded = state.home.furniture + [FurniturePlacement(itemID: "extra", position: .init(x: 0.5, y: 0.7))]
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.6, y: 0.7),
            furniture: crowded, orientations: ["catBed": .left], now: now).failure == .roomCapacityReached)
        #expect(state == beforeCapacityCheck)
    }

    @Test func storingReloadingReplacingAndUpgradingPreservePerInstanceDirections() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FurnitureOrientation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 4
        state.player.gold = 5_000
        let placement = state.home.furniture.first { $0.itemID == "catBed" }!
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture, orientations: ["catBed": .left], now: now).succeeded)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture.filter { $0.itemID != "catBed" }, now: now).succeeded)
        try await FileSaveRepository(directory: folder).save(state, now: now)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(loaded == state)
        #expect(loaded.inventory.furniture.first { $0.id == "catBed" }?.orientation == .left)
        #expect(GameEngine.setRoomLayout(&loaded, bowlPosition: loaded.home.bowlPosition,
            furniture: loaded.home.furniture + [placement], now: now).succeeded)
        for level in 2...3 { #expect(GameEngine.upgradeHome(&loaded, toLevel: level, now: now).succeeded) }
        #expect(loaded.inventory.furniture == state.inventory.furniture)
        #expect(loaded.home.furniture.contains(placement))
        #expect(loaded.tasks == state.tasks)
        try await FileSaveRepository(directory: folder).save(loaded, now: now)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == loaded)
    }

    @Test func turningPlacedFurnitureSettlesRestButUnchangedOrStoredDirectionsDoNotInterruptIt() throws {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.furniture.append(.init(id: "stored", kind: .plant))
        state.cats[0].energy = 20
        #expect(GameEngine.startCatRest(&state, catID: state.activeCatID, furnitureID: "catBed",
            sessionID: "turning-rest", now: now).succeeded)
        let restingCat = state.cats[0]
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture, orientations: ["catBed": .front, "stored": .left], now: now).succeeded)
        #expect(state.cats[0] == restingCat)
        let reward = try #require(state.cats[0].activeRest?.energyReward)
        let halfway = now.addingTimeInterval(6)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture, orientations: ["catBed": .left], now: halfway).succeeded)
        #expect(state.cats[0].activeRest == nil && state.cats[0].energy == 20 + reward / 2)
        let settled = state
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture, orientations: ["catBed": .left], now: halfway).succeeded)
        #expect(state == settled)
    }

    @Test func turnedPurchasedFurnitureStillRestoresHistoryWithoutCountingGiftsOrWrongKinds() throws {
        var state = GameSnapshot.fresh(now: now)
        state.inventory.furniture += [
            .init(id: "shop_potted_plant_1", kind: .plant, orientation: .left),
            .init(id: "shop_cozy_cushion_10", kind: .floorCushion, orientation: .left),
            .init(id: "gift_plant", kind: .plant, orientation: .left),
            .init(id: "shop_potted_plant_2", kind: .catBed, orientation: .left),
            .init(id: "shop_cozy_cushion_11", kind: .floorCushion, orientation: .left)
        ]
        var expected = state
        expected.tasks.furniturePurchaseCount = 2
        let loaded = try decode(json(state))
        #expect(loaded == expected)
        #expect(try decode(json(loaded)) == loaded)
    }
}
