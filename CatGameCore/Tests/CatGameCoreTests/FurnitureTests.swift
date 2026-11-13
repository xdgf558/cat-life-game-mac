import Foundation
import Testing
@testable import CatGameCore

@Suite("Furniture ownership and room layouts")
struct FurnitureTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func freshRoomOwnsNineDistinctItemsAndPlacesEachOnce() {
        let state = GameSnapshot.fresh(now: now)
        #expect(state.isValid)
        #expect(state.inventory.furniture.count == 9)
        #expect(state.home.furniture.count == 9)
        #expect(Set(state.inventory.furniture.map(\.id)) == Set(state.home.furniture.map(\.itemID)))
        #expect(state.inventory.furniture.filter { $0.kind == .plant }.map(\.id) == ["plantLarge", "plantSmall"])
        #expect(FurnitureCatalog.all.count == FurnitureKind.allCases.count)
        #expect(Set(FurnitureCatalog.all.filter(\.isWall).map(\.kind)) == [.wallFlower, .wallCat, .wallSunrise, .wallTownMemory])
        #expect(FurnitureCatalog.all.allSatisfy { !$0.assetName.isEmpty && $0.nameKey == "furniture.\($0.kind.rawValue)" })
        #expect(!state.inventory.furniture.contains { $0.id == "bowl" })
    }

    @Test func storingAndReplacingFurnitureChangesOnlyTheCompleteLayout() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        let stored = state.home.furniture.filter { $0.itemID != "cabinet" }
        let newBowl = NormalizedPoint(x: 0.67, y: 0.74)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: newBowl, furniture: stored, now: now).kind == .layout)
        var expected = original
        expected.home.bowlPosition = newBowl
        expected.home.furniture = stored
        #expect(state == expected)
        #expect(state.inventory.furniture.count == 9)

        let replaced = stored + [FurniturePlacement(itemID: "cabinet", position: .init(x: 0.41, y: 0.58))]
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: newBowl, furniture: replaced, now: now).succeeded)
        expected.home.furniture = replaced
        #expect(state == expected)
        #expect(state.inventory == original.inventory)
        #expect(state.player == original.player)
    }

    @Test func invalidLayoutNeverPartiallyCommitsTheBowlOrFurniture() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        let invalidPositions: [NormalizedPoint] = [
            .init(x: .nan, y: 0.5), .init(x: 0.5, y: .infinity),
            .init(x: -0.001, y: 0.5), .init(x: 0.5, y: -0.001),
            .init(x: 1.001, y: 0.5), .init(x: 0.5, y: 1.001)
        ]
        for position in invalidPositions {
            #expect(!GameEngine.setRoomLayout(&state, bowlPosition: position, furniture: [], now: now).succeeded)
            #expect(state == original)
            let invalidFurniture = [FurniturePlacement(itemID: "cabinet", position: position)]
            #expect(!GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.2, y: 0.3),
                                             furniture: invalidFurniture, now: now).succeeded)
            #expect(state == original)
        }
        let item = original.home.furniture[0]
        for placements in [[item, item], [.init(itemID: "unowned", position: .init(x: 0.5, y: 0.5))]] {
            #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.2, y: 0.3),
                                            furniture: placements, now: now).messageKey == "room.invalidFurnitureLayout")
            #expect(state == original)
        }
        #expect(!GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.2, y: 0.3), furniture: [],
                                         now: Date(timeIntervalSince1970: .infinity)).succeeded)
        #expect(state == original)
    }

    @Test func snapshotRejectsDuplicateOwnershipAndDanglingPlacementReferences() {
        let fresh = GameSnapshot.fresh(now: now)
        var duplicateOwned = fresh
        duplicateOwned.inventory.furniture.append(fresh.inventory.furniture[0])
        var blankOwned = fresh
        blankOwned.inventory.furniture.append(.init(id: " \n", kind: .plant))
        var unownedPlacement = fresh
        unownedPlacement.inventory.furniture.removeAll { $0.id == "cabinet" }
        var duplicatePlacement = fresh
        duplicatePlacement.home.furniture.append(fresh.home.furniture[0])
        var invalidPosition = fresh
        invalidPosition.home.furniture[0].position.x = .infinity
        for state in [duplicateOwned, blankOwned, unownedPlacement, duplicatePlacement, invalidPosition] {
            #expect(!state.isValid)
        }
        var empty = fresh
        empty.inventory.furniture = []
        empty.home.furniture = []
        #expect(empty.isValid)
    }

    @Test func legacySchemaOneMigratesWithoutOverwritingExistingProgress() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var expected = try await repository.loadOrCreate(now: now)
        expected.inventory.food = 11
        expected.inventory.litter = 7
        expected.inventory.toys = 5
        expected.player.gold = 125
        expected.player.completedWorkCount = 9
        expected.player.activeWork = ActiveWork(id: "existing-work", startedAt: now,
                                               endsAt: now.addingTimeInterval(120), goldReward: 60)
        expected.home.bowlPosition = .init(x: 0.53, y: 0.68)
        expected.home.comfortScore = 43
        expected.cats.append(CatState(id: "existing-kitten", name: "小白", now: now))
        try await repository.save(expected)
        let legacy = try removingFurnitureFields(from: Data(contentsOf: repository.saveURL), in: ["inventory", "home"])
        try legacy.write(to: repository.saveURL)

        let reopened = FileSaveRepository(directory: folder)
        let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(60))
        #expect(loaded == expected)
        #expect(loaded.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(await reopened.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
        try await reopened.save(loaded)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == expected)
    }

    @Test func explicitlyStoredEmptyRoomSurvivesSavingAndColdReload() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        let owned = state.inventory.furniture
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.4, y: 0.7), furniture: [], now: now).succeeded)
        try await repository.save(state)
        let loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(loaded == state)
        #expect(loaded.home.furniture.isEmpty)
        #expect(loaded.inventory.furniture == owned)
    }

    @Test func missingOwnershipFieldDoesNotRepopulateExplicitlyEmptyRoom() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.home.furniture = []
        try await repository.save(state)
        let legacyOwnership = try removingFurnitureFields(from: Data(contentsOf: repository.saveURL), in: ["inventory"])
        try legacyOwnership.write(to: repository.saveURL)
        let loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(loaded.inventory.furniture == FurnitureCatalog.defaultItems)
        #expect(loaded.home.furniture.isEmpty)
        #expect(loaded == state)
    }

    @Test func storedFurnitureCanBePlacedAgainAfterReloadWithoutDuplication() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        let owned = state.inventory.furniture
        let gold = state.player.gold
        let placed = state.home.furniture.filter { !["catBed", "plantLarge"].contains($0.itemID) }
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition, furniture: placed, now: now).succeeded)
        try await repository.save(state)
        var restored = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(restored.home.furniture.count == 7)
        let replacement = FurniturePlacement(itemID: "catBed", position: .init(x: 0.57, y: 0.72))
        #expect(GameEngine.setRoomLayout(&restored, bowlPosition: restored.home.bowlPosition,
                                        furniture: restored.home.furniture + [replacement], now: now).succeeded)
        try await repository.save(restored)
        let reloaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(reloaded.inventory.furniture == owned)
        #expect(reloaded.home.furniture.count == 8)
        #expect(reloaded.home.furniture.first { $0.itemID == "catBed" } == replacement)
        #expect(!reloaded.home.furniture.contains { $0.itemID == "plantLarge" })
        #expect(reloaded.player.gold == gold)
    }

    @Test func malformedFurnitureFieldsDoNotSilentlyBecomeDefaults() throws {
        let data = try JSONEncoder().encode(GameSnapshot.fresh(now: now))
        for containerName in ["inventory", "home"] {
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var container = try #require(object[containerName] as? [String: Any])
            container["furniture"] = NSNull()
            object[containerName] = container
            let malformed = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameSnapshot.self, from: malformed) }
        }
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var inventory = try #require(object["inventory"] as? [String: Any])
        inventory["furniture"] = [["id": "unknown", "kind": "unsupported-kind"]]
        object["inventory"] = inventory
        let malformedKind = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameSnapshot.self, from: malformedKind) }
    }

    @Test func invalidFurnitureCannotReplaceTheLastValidSave() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = try await repository.loadOrCreate(now: now)
        let savedData = try Data(contentsOf: repository.saveURL)
        var invalid = original
        invalid.home.furniture.append(.init(itemID: "not-owned", position: .init(x: 0.5, y: 0.5)))
        await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid) }
        #expect(try Data(contentsOf: repository.saveURL) == savedData)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == original)
    }

    private func directory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatFurnitureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func removingFurnitureFields(from data: Data, in containers: [String]) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 14
        for name in containers {
            var container = try #require(object[name] as? [String: Any])
            container.removeValue(forKey: "furniture")
            object[name] = container
        }
        return try snapshotFixtureData(object, options: [.sortedKeys])
    }
}
