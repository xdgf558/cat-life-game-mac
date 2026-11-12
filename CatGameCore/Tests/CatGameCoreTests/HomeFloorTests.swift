import Foundation
import Testing
@testable import CatGameCore

@Suite("Two-floor homes preserve layouts and legacy progress")
struct HomeFloorTests {
    let now = Date(timeIntervalSince1970: 1_793_600_000)

    private func state(level: Int = 6) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 20
        state.player.gold = 30_000
        state.home = HomeState(roomLevel: level)
        return state
    }

    private func object(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: NativeSaveCodec.encoder().encode(state)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try NativeSaveCodec.decodeSnapshot(snapshotFixtureData(object), now: now)
    }

    @Test func capacitiesArePerFloorAndDoNotShrinkExistingRooms() throws {
        #expect(HomeCatalog.all.map(\.level) == Array(1...8))
        #expect(HomeCatalog.all.map(\.floorCapacity) == [9, 12, 16, 20, 24, 24, 28, 32])
        #expect(HomeCatalog.all.prefix(3).map(\.upgradeCost) == [0, 450, 900])
        #expect(HomeCatalog.all.prefix(3).map(\.requiredPlayerLevel) == [1, 2, 4])
        for room in HomeCatalog.all {
            #expect(room.capacity == room.floorCapacity * room.floors.count)
            #expect(room.floors == (room.level < 6 ? [.ground] : [.ground, .upper]))
            #expect(room.capacity(on: .ground) == room.floorCapacity)
            #expect(room.capacity(on: .upper) == (room.level < 6 ? 0 : room.floorCapacity))
            #expect(room.worldScale(on: .upper) == (room.level < 6 ? nil : room.worldScale))
        }
        #expect(try #require(HomeCatalog.level(5)).worldScale == HomeCatalog.level(6)?.worldScale)
    }

    @Test func allLegacySchemasKeepTheirMovedGroundLayoutAndBowl() throws {
        var expected = state(level: 3)
        expected.home.bowlPosition = .init(x: 0.6, y: 0.8)
        expected.home.furniture.removeLast()
        expected.home.furniture[0].position = .init(x: 0.3, y: 0.4)
        expected.inventory.furniture[0].orientation = .left
        for schema in 1...9 {
            var old = try object(expected)
            old["schemaVersion"] = schema
            var home = try #require(old["home"] as? [String: Any])
            home.removeValue(forKey: "upperBowlPosition")
            home["furniture"] = try #require(home["furniture"] as? [[String: Any]]).map { placement in
                var placement = placement
                placement.removeValue(forKey: "floor")
                return placement
            }
            old["home"] = home
            let migrated = try decode(old)
            #expect(migrated == (try expectedLegacyFootprintMigration(expected)))
            #expect(migrated.home.availableFloors == [.ground] && migrated.home.upperBowlPosition == nil)
            #expect(migrated.home.furniture.allSatisfy { $0.floor == .ground })
            #expect(try NativeSaveCodec.decodeSnapshot(NativeSaveCodec.encoder().encode(migrated), now: now) == migrated)
        }
    }

    @Test func damagedCurrentFloorFieldsAndLockedUpperDataAreRejected() throws {
        for roomLevel in [1, 5, 6, 8] {
            let original = try object(state(level: roomLevel))
            for invalidFloor: Any? in [nil, NSNull(), "attic", 1] {
                var invalid = original
                var home = try #require(invalid["home"] as? [String: Any])
                var furniture = try #require(home["furniture"] as? [[String: Any]])
                furniture[0]["floor"] = invalidFloor
                home["furniture"] = furniture
                invalid["home"] = home
                #expect(throws: (any Error).self) { try decode(invalid) }
            }
        }
        for level in 1...5 {
            var invalid = state(level: level)
            invalid.home.upperBowlPosition = .init(x: 0.4, y: 0.6)
            #expect(!invalid.isValid)
            #expect(throws: (any Error).self) { try decode(object(invalid)) }
            invalid.home.upperBowlPosition = nil
            invalid.home.furniture[0].floor = .upper
            #expect(!invalid.isValid)
            #expect(throws: (any Error).self) { try decode(object(invalid)) }
        }
        for invalidBowl: NormalizedPoint? in [nil, .init(x: .nan, y: 0.4), .init(x: 0.3, y: .infinity), .init(x: 1.1, y: 0)] {
            var invalid = state()
            invalid.home.upperBowlPosition = invalidBowl
            #expect(!invalid.isValid)
        }
        var old = try object(state(level: 4))
        old["schemaVersion"] = 9
        #expect(throws: SaveRepositoryError.invalidSnapshot) { try decode(old) }
    }

    @Test func sixthLevelAddsOnlyAnEmptyUpperFloorAndRepeatedUpgradeNeverCharges() {
        var value = state(level: 5)
        value.home.bowlPosition = .init(x: 0.55, y: 0.66)
        value.home.furniture[0].position = .init(x: 0.44, y: 0.5)
        let original = value
        #expect(GameEngine.upgradeHome(&value, toLevel: 6, now: now).succeeded)
        #expect(value.home.placements(on: .ground) == original.home.furniture)
        #expect(value.home.bowlPosition == original.home.bowlPosition)
        #expect(value.home.placements(on: .upper).isEmpty)
        #expect(value.home.upperBowlPosition == HomeState.defaultBowlPosition)
        #expect(value.inventory == original.inventory && value.cats == original.cats)
        #expect(value.player.gold == original.player.gold - 3_600)
        let upgraded = value
        #expect(GameEngine.upgradeHome(&value, toLevel: 6, now: now).failure == .homeUpgradeUnavailable)
        #expect(value == upgraded && value.isValid)
    }

    @Test func eachFloorCommitsIndependentlyAndAnItemMustBeStoredBeforeChangingFloors() throws {
        var value = state()
        let original = value
        let cabinet = try #require(value.home.furniture.first { $0.itemID == "cabinet" })
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.3, y: 0.7),
            furniture: [cabinet], floor: .upper, now: now).failure == .roomInvalidFurnitureLayout)
        #expect(value == original)
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: value.home.bowlPosition,
            furniture: value.home.placements(on: .ground).filter { $0.itemID != cabinet.itemID }, now: now).succeeded)
        let ground = value.home.placements(on: .ground)
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.3, y: 0.7),
            furniture: [cabinet], orientations: [cabinet.itemID: .left], floor: .upper, now: now).succeeded)
        #expect(value.home.placements(on: .ground) == ground)
        #expect(value.home.bowlPosition == original.home.bowlPosition)
        #expect(value.home.placements(on: .upper).first?.floor == .upper)
        #expect(value.home.upperBowlPosition == .init(x: 0.3, y: 0.7))
        let bothFloors = value
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.6, y: 0.8),
            furniture: ground, orientations: [cabinet.itemID: .front], now: now).failure == .roomInvalidFurnitureLayout)
        #expect(value == bothFloors)
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.6, y: 0.8),
            furniture: [], now: now).succeeded)
        #expect(value.home.placements(on: .upper) == bothFloors.home.placements(on: .upper))
        #expect(value.home.upperBowlPosition == bothFloors.home.upperBowlPosition)
        #expect(value.home.placements(on: .ground).isEmpty && value.inventory == bothFloors.inventory)
    }

    @Test func lockedFloorAndOverfullFloorCannotPartiallyCommit() {
        var locked = state(level: 5)
        let original = locked
        #expect(GameEngine.setBowlPosition(&locked, .init(x: 0.4, y: 0.7), floor: .upper, now: now).failure == .roomInvalidFurnitureLayout)
        #expect(GameEngine.setRoomLayout(&locked, bowlPosition: .init(x: 0.4, y: 0.7),
            furniture: [], floor: .upper, now: now).failure == .roomInvalidFurnitureLayout)
        #expect(locked == original)
        var value = state()
        let upper = (0..<25).map { index in
            let id = "extra-\(index)"
            value.inventory.furniture.append(FurnitureItem(id: id, kind: .plant))
            return FurniturePlacement(itemID: id, position: .init(x: 0.5, y: 0.6), floor: .upper)
        }
        let before = value
        let denied = GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.5, y: 0.8),
            furniture: upper, floor: .upper, now: now)
        #expect(denied.failure == .roomCapacityReached && denied.amount == 24)
        #expect(value == before, "Whole-home capacity does not let one floor exceed its own limit.")
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.5, y: 0.8),
            furniture: Array(upper.prefix(24)), floor: .upper, now: now).succeeded)
        #expect(value.home.placements(on: .upper).count == 24 && value.home.placements(on: .ground) == before.home.furniture)
        let bothFloors = value
        #expect(!GameEngine.setBowlPosition(&value, .init(x: .nan, y: 0.7), floor: .upper, now: now).succeeded)
        #expect(value == bothFloors)
    }

    @Test func bothFloorsAndTheirOrientationsSurviveBackupAndRepositoryImport() async throws {
        var value = state(level: 8)
        value.home.furniture[0].floor = .upper
        value.home.furniture[0].position = .init(x: 0.3, y: 0.45)
        value.home.upperBowlPosition = .init(x: 0.6, y: 0.8)
        value.inventory.furniture[0].orientation = .left
        let encoded = try NativeSaveTransfer.encode(snapshot: value, exportedAt: now)
        let archive = try NativeSaveTransfer.decode(encoded, now: now)
        #expect(archive.snapshot == value)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HomeFloors-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = try await repository.loadOrCreate(now: now)
        try await repository.importSnapshot(archive.snapshot)
        #expect(try await repository.loadOrCreate(now: now) == value)
        #expect(try await repository.loadImportRecovery() == original)
    }
}
