import Foundation
import CoreGraphics
import Testing
@testable import CatGameCore

@Suite("Schema 15 four-way furniture and rotated floor geometry")
struct FourWayFurnitureTests {
    private let now = Date(timeIntervalSince1970: 1_794_500_000)

    private func object(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    // Intentionally bypass the fixture writer: malformed legacy vocabulary must
    // reach the production decoder unchanged in these boundary tests.
    private func decode(_ object: [String: Any]) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func changingOrientation(_ object: [String: Any], to value: Any?, item: Int = 0) throws -> [String: Any] {
        var object = object
        var inventory = try #require(object["inventory"] as? [String: Any])
        var items = try #require(inventory["furniture"] as? [[String: Any]])
        items[item]["orientation"] = value
        inventory["furniture"] = items
        object["inventory"] = inventory
        return object
    }

    private func legacyObject(_ state: GameSnapshot, schema: Int) throws -> [String: Any] {
        var object = try object(state)
        object["schemaVersion"] = schema
        return try #require(JSONSerialization.jsonObject(with: snapshotFixtureData(object)) as? [String: Any])
    }

    @Test func fourTurnsReturnToStartAndContactAxesMatchTheFacingLabels() {
        #expect(FurnitureOrientation.allCases == [.front, .left, .back, .right])
        #expect(FurnitureOrientation.front.turnedRight == .right)
        #expect(FurnitureOrientation.front.turnedLeft == .left)
        let front = CGPoint(x: 0, y: -1)
        let directions: [FurnitureOrientation: CGPoint] = [
            .front: front, .left: CGPoint(x: -1, y: 0),
            .back: CGPoint(x: 0, y: 1), .right: CGPoint(x: 1, y: 0)
        ]
        for orientation in FurnitureOrientation.allCases {
            #expect(orientation.turnedLeft.turnedRight == orientation)
            #expect(orientation.turnedRight.turnedLeft == orientation)
            #expect(orientation.turnedLeft.turnedLeft.turnedLeft.turnedLeft == orientation)
            #expect(orientation.turnedRight.turnedRight.turnedRight.turnedRight == orientation)
            #expect(orientation.rotatedOffset(front) == directions[orientation])
            let offset = CGPoint(x: 0.4, y: -0.7)
            let turned = orientation.rotatedOffset(offset)
            #expect(abs(hypot(turned.x, turned.y) - hypot(offset.x, offset.y)) < 0.000_001)
        }
    }

    @Test func gridMetadataFreezesEveryFrontCollisionSizeAndRotatesOnlyFloorItems() {
        let frontSizes: [FurnitureKind: CGSize] = [
            .cabinet: CGSize(width: 186, height: 78), .catTree: CGSize(width: 160, height: 82),
            .catBed: CGSize(width: 292, height: 144), .plant: CGSize(width: 70, height: 42),
            .floorCushion: CGSize(width: 154, height: 80), .flowerStool: CGSize(width: 126, height: 68),
            .bookcase: CGSize(width: 190, height: 76), .rattanChair: CGSize(width: 158, height: 88),
            .sideTable: CGSize(width: 136, height: 72), .wallFlower: CGSize(width: 110, height: 170),
            .wallCat: CGSize(width: 108, height: 148), .wallSunrise: CGSize(width: 104, height: 178),
            .wallTownMemory: CGSize(width: 132, height: 126)
        ]
        for kind in FurnitureKind.allCases {
            let metadata = FurnitureCatalog.metadata(for: kind)
            #expect(metadata.footprint.artworkSize == frontSizes[kind])
            #expect(metadata.footprint.width > 0 && metadata.footprint.depth > 0)
            #expect(metadata.isWall == !kind.supportsRotation)
            #expect(metadata.height == 0 || (metadata.height.isFinite && metadata.height > 0))
            for direction in FurnitureOrientation.allCases {
                let footprint = metadata.footprint(for: direction)
                if kind.supportsRotation && direction.swapsFootprintAxes {
                    #expect(footprint.width == metadata.footprint.depth)
                    #expect(footprint.depth == metadata.footprint.width)
                } else { #expect(footprint == metadata.footprint) }
            }
        }
        let small = FurnitureCatalog.footprint(for: .init(id: "plantSmall", kind: .plant, orientation: .left))
        let large = FurnitureCatalog.footprint(for: .init(id: "plantLarge", kind: .plant, orientation: .left))
        #expect(small.width == large.width * 0.78 && small.depth == large.depth * 0.78)
        let square = FurnitureFootprint(width: 2, depth: 2)
        #expect(FurnitureOrientation.allCases.allSatisfy { square.rotated(for: $0) == square })
    }

    @Test func rotatedRectanglesDriveBoundaryCollisionsAndSweptNavigation() {
        let floor = [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0),
                     CGPoint(x: 400, y: 300), CGPoint(x: 0, y: 300)]
        let footprint = FurnitureFootprint(width: 2, depth: 1)
        for direction in FurnitureOrientation.allCases {
            let size = footprint.rotated(for: direction).artworkSize
            let navigation = RoomNavigation(floor: floor, obstacles: [], footprint: size, precomputeGrid: false)
            #expect(navigation.isWalkable(CGPoint(x: 200, y: 150)))
            #expect(navigation.isWalkable(CGPoint(x: 80, y: 150)) == direction.swapsFootprintAxes)
            #expect(navigation.isWalkable(CGPoint(x: 200, y: 50)) == !direction.swapsFootprintAxes)
            let obstacle = CGRect(x: 320, y: 145, width: 5, height: 10)
            let collision = RoomNavigation(floor: floor, obstacles: [obstacle], footprint: size, precomputeGrid: false)
            #expect(collision.isWalkable(CGPoint(x: 200, y: 150)) == direction.swapsFootprintAxes)
            let barrier = RoomNavigation(floor: floor,
                obstacles: [CGRect(x: 199.995, y: 0, width: 0.01, height: 300)],
                footprint: CGSize(width: size.width / 4, height: size.height / 4), precomputeGrid: false)
            let start = CGPoint(x: 80, y: 150), end = CGPoint(x: 320, y: 150)
            #expect(barrier.isWalkable(start) && barrier.isWalkable(end))
            #expect(!barrier.segmentIsWalkable(from: start, to: end))
        }
    }

    @Test func allLegacySchemasChangeOnlyTheDirectionVocabularyAndExistingVersionMigrations() throws {
        for schema in 1...14 {
            var original = GameSnapshot.fresh(now: now)
            original.home.furniture[0].position = .init(x: 0.44, y: 0.57)
            original.inventory.furniture[0].orientation = .left
            original.inventory.food = 17
            original.player.gold = 1234
            original.player.profile.name = "Milo"
            original.cats[0].customName = "豆豆"
            original.cats[0].energy = 20
            original.cats[0].habits.cornerFurnitureID = "catBed"
            #expect(GameEngine.startCatRest(&original, catID: original.activeCatID,
                furnitureID: "catBed", sessionID: "legacy-rest-\(schema)", now: now).succeeded)
            if schema >= 10 {
                original.home = HomeState(furniture: original.home.furniture, roomLevel: 6)
                original.home.furniture[0].floor = .upper
            }
            let expected = try expectedLegacyFootprintMigration(schema < 14 ? expectedCompanionMigration(original) : original)
            let loaded = try decode(legacyObject(original, schema: schema))
            #expect(loaded == expected && loaded.isValid)
            #expect(loaded.home == original.home && loaded.cats[0].activeRest == original.cats[0].activeRest)
            #expect(loaded.cats[0].habits.cornerFurnitureID == "catBed")
            #expect(try decode(object(loaded)) == loaded)
        }
    }

    @Test func schema14KeepsItsCompanionLedgerAndDurableRestsThroughReloadImportAndNextSave() async throws {
        var original = GameSnapshot.fresh(now: now)
        original.inventory.furniture[0].orientation = .left
        original.cats[0].energy = 20
        #expect(GameEngine.startCatRest(&original, catID: original.activeCatID,
            furnitureID: "catBed", sessionID: "v14-kept-rest", now: now).succeeded)
        original.cats[0].habits.pinnedHintCollapsed = true
        original.cats[0].habits.pinnedMemory = .littleCorner
        original.cats[0].habits.responseFinishIndex = 1
        original.cats[0].habits.cornerFurnitureID = "catBed"
        original.cats[0].habits.restClueSessionIDs = ["v14-bed-observation"]
        original.cats[0].habits.playClueSessionIDs = ["v14-play-observation"]
        original.cats[0].habits.memories = [.init(kind: .firstResponse, createdAt: now)]
        original.cats[0].habits.restLocations["catBed"] = .init(
            reference: .init(floor: .ground, position: .init(x: 0.28, y: 0.63)), visited: true)
        original.cats[0].habits.restLocations["stored-v14-bed"] = .init(
            reference: .init(floor: .ground, position: .init(x: 0.4, y: 0.7)), visited: true)
        try #require(original.isValid)
        var saved = try #require(JSONSerialization.jsonObject(with: NativeSaveCodec.encoder().encode(original)) as? [String: Any])
        saved["schemaVersion"] = 14
        let bytes = try snapshotFixtureData(saved)
        let expected = try expectedLegacyFootprintMigration(original)
        var envelope = try #require(JSONSerialization.jsonObject(with:
            NativeSaveTransfer.encode(snapshot: original, exportedAt: now)) as? [String: Any])
        envelope["snapshot"] = try JSONSerialization.jsonObject(with: bytes)
        let oldArchive = try JSONSerialization.data(withJSONObject: envelope)
        #expect(try NativeSaveTransfer.decode(oldArchive, now: now).snapshot == expected)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FourWayFurniture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let repository = FileSaveRepository(directory: folder)
        try bytes.write(to: repository.saveURL)
        let loaded = try await repository.loadOrCreate(now: now)
        #expect(loaded == expected)
        #expect(try Data(contentsOf: repository.saveURL) == bytes)
        #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: loaded, exportedAt: now), now: now).snapshot == expected)
        try await repository.save(loaded, now: now)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == expected)
        let newObject = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        #expect(newObject["schemaVersion"] as? Int == 15)
        let inventory = try #require(newObject["inventory"] as? [String: Any])
        let items = try #require(inventory["furniture"] as? [[String: Any]])
        #expect(items.first?["orientation"] as? String == "left")
    }

    @Test func oldSchemasRejectNewOrMalformedVocabularyAndOnlyPreSixCanOmitDirections() throws {
        let original = GameSnapshot.fresh(now: now)
        for schema in 1...14 {
            let saved = try legacyObject(original, schema: schema)
            for bad in [NSNull(), "front", "left", "back", "right", "", "normal ", 1, false] as [Any] {
                #expect(throws: (any Error).self) { try decode(changingOrientation(saved, to: bad)) }
            }
            let missing = try changingOrientation(saved, to: nil)
            if schema < 6 { #expect(try decode(missing) == original) }
            else { #expect(throws: (any Error).self) { try decode(missing) } }
        }
    }

    @Test func currentSchemaRequiresTheEntireFurnitureLayoutAndOnlyFourCurrentDirections() throws {
        let saved = try object(GameSnapshot.fresh(now: now))
        for bad in [nil, NSNull(), "normal", "mirrored", "Front", "upsideDown", 1, false] as [Any?] {
            #expect(throws: (any Error).self) { try decode(changingOrientation(saved, to: bad)) }
        }
        for (containerKey, field) in [("inventory", "furniture"), ("home", "furniture"), ("home", "roomLevel")] {
            for bad in [nil, NSNull()] as [Any?] {
                var malformed = saved
                var container = try #require(malformed[containerKey] as? [String: Any])
                container[field] = bad
                malformed[containerKey] = container
                #expect(throws: (any Error).self) { try decode(malformed) }
            }
        }
    }

    @Test func eachDirectionCommitsAndRoundTripsWithoutChangingCoordinatesOwnershipOrRewards() throws {
        for direction in FurnitureOrientation.allCases {
            var state = GameSnapshot.fresh(now: now)
            let previous = state
            #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                furniture: state.home.furniture, orientations: ["cabinet": direction], now: now).succeeded)
            var expected = previous
            expected.inventory.furniture[0].orientation = direction
            #expect(state == expected)
            #expect(try decode(object(state)) == expected)
            #expect(try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: now), now: now).snapshot == expected)
        }
    }

    @Test func bothWallSidesKeepNormalizedCoordinatesButEveryNonFrontWallDirectionFailsAtomically() throws {
        for x in [0.24, 0.7] {
            var state = GameSnapshot.fresh(now: now)
            let placements = [FurniturePlacement(itemID: "wallCat", position: .init(x: x, y: 0.3))]
            #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                furniture: placements, orientations: ["wallCat": .front], now: now).succeeded)
            #expect(state.home.furniture == placements)
            let previous = state
            for direction in [FurnitureOrientation.left, .back, .right] {
                #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.6, y: 0.7),
                    furniture: [], orientations: ["wallCat": direction], now: now).failure == .roomInvalidFurnitureLayout)
                #expect(state == previous)
                var badSnapshot = state
                let wall = try #require(badSnapshot.inventory.furniture.firstIndex { $0.id == "wallCat" })
                badSnapshot.inventory.furniture[wall].orientation = direction
                #expect(throws: (any Error).self) { try decode(object(badSnapshot)) }
            }
        }
    }
}
