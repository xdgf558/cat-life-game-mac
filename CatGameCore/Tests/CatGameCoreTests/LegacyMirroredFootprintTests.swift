import Foundation
import CoreGraphics
import Testing
@testable import CatGameCore

@Suite("Released mirrored furniture keeps its collision footprint")
struct LegacyMirroredFootprintTests {
    private let now = Date(timeIntervalSince1970: 1_794_500_000)
    // Released sizes, independent of the new rotated footprint implementation.
    private let legacySizes: [FurnitureKind: CGSize] = [
        .cabinet: .init(width: 186, height: 78), .catTree: .init(width: 160, height: 82),
        .catBed: .init(width: 292, height: 144), .plant: .init(width: 70, height: 42),
        .floorCushion: .init(width: 154, height: 80), .flowerStool: .init(width: 126, height: 68),
        .bookcase: .init(width: 190, height: 76), .rattanChair: .init(width: 158, height: 88),
        .sideTable: .init(width: 136, height: 72)
    ]

    private func object(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func changingItem(_ object: [String: Any], id: String = "cabinet",
                              edit: (inout [String: Any]) -> Void) throws -> [String: Any] {
        var object = object
        var inventory = try #require(object["inventory"] as? [String: Any])
        var items = try #require(inventory["furniture"] as? [[String: Any]])
        let index = try #require(items.firstIndex { $0["id"] as? String == id })
        edit(&items[index])
        inventory["furniture"] = items
        object["inventory"] = inventory
        return object
    }

    private func legacyObject(_ original: GameSnapshot) throws -> [String: Any] {
        var result = try object(original)
        result["schemaVersion"] = 14
        // The fixture writer emits actual released normal/mirrored strings and no new key.
        return try #require(JSONSerialization.jsonObject(with: snapshotFixtureData(result)) as? [String: Any])
    }

    private func mirroredCabinet(floor: HomeFloor = .ground) throws -> GameSnapshot {
        var original = GameSnapshot.fresh(now: now)
        original.inventory.furniture[0].orientation = .left
        if floor == .upper {
            original.home = HomeState(furniture: original.home.furniture, roomLevel: 6)
            original.home.furniture[0].floor = .upper
        }
        return try decode(legacyObject(original))
    }

    private func cabinet(_ state: GameSnapshot) throws -> FurnitureItem {
        try #require(state.inventory.furniture.first { $0.id == "cabinet" })
    }

    @Test func eachReleasedMirroredKindKeepsItsFrozenSizeOnBothFloorsAndRoundTrips() throws {
        for (kind, expectedSize) in legacySizes {
            for floor in HomeFloor.allCases {
                for small in (kind == .plant ? [false, true] : [false]) {
                    var original = GameSnapshot.fresh(now: now)
                    let id = small ? "plantSmall" : "fixture-\(kind.rawValue)"
                    original.inventory.furniture = [.init(id: id, kind: kind, orientation: .left)]
                    original.home = HomeState(furniture: [.init(itemID: id,
                        position: .init(x: 0.33, y: 0.61), floor: floor)], roomLevel: 6)
                    original.player.gold = 1234
                    original.cats[0].customName = "Milo"
                    let fixture = try legacyObject(original)
                    let oldInventory = try #require(fixture["inventory"] as? [String: Any])
                    let oldItems = try #require(oldInventory["furniture"] as? [[String: Any]])
                    #expect(oldItems[0]["orientation"] as? String == "mirrored")
                    #expect(oldItems[0]["usesLegacyFootprint"] == nil)
                    let migrated = try decode(fixture)
                    let item = try #require(migrated.inventory.furniture.first)
                    #expect(item.orientation == .left && item.usesLegacyFootprint)
                    let factor = small ? 0.78 : 1.0
                    #expect(FurnitureCatalog.footprint(for: item).artworkSize ==
                        CGSize(width: expectedSize.width * factor, height: expectedSize.height * factor))
                    #expect(migrated.isValid && migrated.home == original.home)
                    #expect(migrated.player == original.player && migrated.cats == original.cats)
                    #expect(try decode(object(migrated)) == migrated)
                    #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: migrated,
                        exportedAt: now), now: now).snapshot == migrated)
                }
            }
        }
    }

    @Test func storedLegacyItemsUseCurrentGeometryAndOldUnknownKeysCannotOverrideInference() throws {
        var original = GameSnapshot.fresh(now: now)
        original.inventory.furniture[0].orientation = .left
        original.home.furniture.removeAll { $0.itemID == "cabinet" }
        let stored = try decode(legacyObject(original))
        #expect(try cabinet(stored).orientation == .left)
        #expect(try !cabinet(stored).usesLegacyFootprint)
        for value in [false, NSNull(), "not a bool"] as [Any] {
            var placed = original
            placed.home.furniture.append(.init(itemID: "cabinet", position: .init(x: 0.4, y: 0.6)))
            let mirrored = try changingItem(legacyObject(placed)) { $0["usesLegacyFootprint"] = value }
            #expect(try cabinet(decode(mirrored)).usesLegacyFootprint)
        }
        let normal = try changingItem(legacyObject(GameSnapshot.fresh(now: now))) {
            $0["usesLegacyFootprint"] = true
        }
        #expect(try !cabinet(decode(normal)).usesLegacyFootprint)
    }

    @Test func currentFormatRequiresEveryBooleanAndRejectsImpossibleMarkers() throws {
        let original = GameSnapshot.fresh(now: now)
        let saved = try object(original)
        let inventory = try #require(saved["inventory"] as? [String: Any])
        let items = try #require(inventory["furniture"] as? [[String: Any]])
        #expect(items.allSatisfy { $0["usesLegacyFootprint"] as? Bool == false })
        for value in [nil, NSNull(), "true", 1] as [Any?] {
            let damaged = try changingItem(saved) { $0["usesLegacyFootprint"] = value }
            #expect(throws: (any Error).self) { try decode(damaged) }
        }
        for direction in ["front", "back", "right"] {
            let damaged = try changingItem(saved) {
                $0["orientation"] = direction; $0["usesLegacyFootprint"] = true
            }
            #expect(throws: (any Error).self) { try decode(damaged) }
        }
        let badWall = try changingItem(saved, id: "wallCat") {
            $0["orientation"] = "left"; $0["usesLegacyFootprint"] = true
        }
        #expect(throws: (any Error).self) { try decode(badWall) }
        var unplaced = try mirroredCabinet()
        unplaced.home.furniture.removeAll { $0.itemID == "cabinet" }
        #expect(!unplaced.isValid)
        #expect(throws: (any Error).self) { try decode(object(unplaced)) }
        #expect(throws: (any Error).self) { try NativeSaveTransfer.encode(snapshot: unplaced, exportedAt: now) }
    }

    @Test func unchangedLayoutBowlOnlyAndAnotherItemOrFloorKeepTheMarker() throws {
        var state = try mirroredCabinet(floor: .upper)
        let previousItem = try cabinet(state)
        let otherFloor = state.home.placements(on: .upper)
        var ground = state.home.placements(on: .ground)
        ground[0].position.x += 0.03
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.72, y: 0.8),
            furniture: ground, now: now).succeeded)
        #expect(try cabinet(state) == previousItem)
        #expect(state.home.placements(on: .upper) == otherFloor)
        let upperBowl = try #require(state.home.bowlPosition(on: .upper))
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: upperBowl,
            furniture: otherFloor, floor: .upper, now: now).succeeded)
        #expect(try cabinet(state) == previousItem)
        #expect(GameEngine.setBowlPosition(&state, .init(x: 0.7, y: 0.7), floor: .upper, now: now).succeeded)
        #expect(try cabinet(state) == previousItem)
    }

    @Test func realMovePutAwayAndExplicitTurnReleaseOnlyTheChangedInstance() throws {
        let original = try mirroredCabinet()
        for operation in 0...2 {
            var state = original
            var placements = state.home.furniture
            let index = try #require(placements.firstIndex { $0.itemID == "cabinet" })
            if operation == 0 { placements[index].position.x += 0.01 }
            if operation == 1 { placements.remove(at: index) }
            #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                furniture: placements, orientations: operation == 2 ? ["cabinet": .left] : [:], now: now).succeeded)
            let item = try cabinet(state)
            #expect(item.orientation == .left && !item.usesLegacyFootprint)
            #expect(FurnitureCatalog.footprint(for: item) == FurnitureCatalog.metadata(for: .cabinet).footprint(for: .left))
            #expect(try decode(object(state)) == state)
        }
        var item = try cabinet(original)
        for _ in 0..<4 { item.orientation = item.orientation.turnedRight }
        #expect(item.orientation == .left && !item.usesLegacyFootprint)
    }

    @Test func placementToleranceKeepsFloatRoundTripsWithoutChangingSavedCoordinates() throws {
        let state = try mirroredCabinet()
        let item = try cabinet(state)
        let previous = try #require(state.home.furniture.first { $0.itemID == item.id })
        var tiny = previous
        tiny.position.x += 0.000_000_5
        tiny.position.y -= 0.000_000_5
        #expect(item.applyingPlacement(from: previous, to: tiny) == item)
        var saved = state
        var placements = state.home.furniture
        let index = try #require(placements.firstIndex { $0.itemID == item.id })
        placements[index] = tiny
        #expect(GameEngine.setRoomLayout(&saved, bowlPosition: state.home.bowlPosition,
            furniture: placements, now: now).succeeded)
        #expect(try cabinet(saved) == item)
        #expect(saved.home.furniture[index].position == tiny.position)
        var moved = previous
        moved.position.x += 0.000_002
        #expect(!item.applyingPlacement(from: previous, to: moved).usesLegacyFootprint)
        moved = previous; moved.floor = .upper
        #expect(!item.applyingPlacement(from: previous, to: moved).usesLegacyFootprint)
        moved = previous; moved.itemID = "another-instance"
        #expect(!item.applyingPlacement(from: previous, to: moved).usesLegacyFootprint)
        #expect(!item.applyingPlacement(from: previous, to: nil).usesLegacyFootprint)
        #expect(!item.applyingPlacement(from: nil, to: previous).usesLegacyFootprint)
    }

    @Test func sameLeftAssignmentEndsRestAndOtherFloorGeometryChangesFailAtomically() throws {
        var state = try mirroredCabinet()
        state.cats[0].energy = 20
        #expect(GameEngine.startCatRest(&state, catID: state.activeCatID,
            furnitureID: "catBed", sessionID: "same-left-rest", now: now).succeeded)
        #expect(state.cats[0].activeRest != nil)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: state.home.furniture, orientations: ["cabinet": .left], now: now).succeeded)
        #expect(state.cats[0].activeRest == nil)
        #expect(try !cabinet(state).usesLegacyFootprint)
        var otherFloorState = try mirroredCabinet(floor: .upper)
        let previous = otherFloorState
        #expect(GameEngine.setRoomLayout(&otherFloorState, bowlPosition: previous.home.bowlPosition,
            furniture: previous.home.placements(on: .ground), orientations: ["cabinet": .left], now: now)
            .failure == .roomInvalidFurnitureLayout)
        #expect(otherFloorState == previous)
        var invalid = previous.home.placements(on: .upper)
        invalid[0].position.x = 2
        #expect(GameEngine.setRoomLayout(&otherFloorState, bowlPosition: .init(x: 0.5, y: 0.5),
            furniture: invalid, floor: .upper, now: now).failure == .roomInvalidFurnitureLayout)
        #expect(otherFloorState == previous)
    }

    @Test func durableSaveAutomaticBackupAndArchiveRetainTheMarker() async throws {
        let migrated = try mirroredCabinet()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyMirrored-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(migrated, now: now)
        var changed = migrated
        changed.player.gold += 10
        try await repository.save(changed, now: now.addingTimeInterval(301))
        #expect(try await repository.loadOrCreate(now: now) == changed)
        let backup = try NativeSaveCodec.decoder().decode(GameSnapshot.self,
            from: Data(contentsOf: repository.backupURL))
        #expect(backup == migrated && backup.inventory.furniture[0].usesLegacyFootprint)
        let archive = try NativeSaveTransfer.encode(snapshot: changed, exportedAt: now)
        #expect(try NativeSaveTransfer.decode(archive, now: now).snapshot == changed)
        let importedFolder = folder.appendingPathComponent("imported")
        let imported = FileSaveRepository(directory: importedFolder)
        _ = try await imported.loadOrCreate(now: now)
        try await imported.importSnapshot(NativeSaveTransfer.decode(archive, now: now).snapshot)
        #expect(try await imported.loadOrCreate(now: now) == changed)
        let recovery = try await imported.loadImportRecovery()
        #expect(recovery == GameSnapshot.fresh(now: now))
    }
}
