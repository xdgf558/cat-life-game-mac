#if os(macOS)
import XCTest
import CatGameCore
@testable import CatLifeMac

@MainActor
final class MacRoomSaveRepairTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_600_000)

    private func plan(_ original: GameSnapshot, placements: [FurniturePlacement]? = nil) -> MacRoomLayoutRepair.Plan {
        let placements = placements ?? original.home.furniture
        let previous = Dictionary(uniqueKeysWithValues: original.home.furniture.map { ($0.itemID, $0) })
        return .init(placements: placements,
                     bowlPositions: Dictionary(uniqueKeysWithValues: original.home.availableFloors.map { ($0, original.home.bowlPosition(on: $0)!) }),
                     movedIDs: Set(placements.filter { previous[$0.itemID] != $0 }.map(\.itemID)),
                     storedIDs: Set(previous.keys).subtracting(placements.map(\.itemID)))
    }

    private func makeStore(_ repository: RepairMemoryRepository) throws -> GameStore {
        let suite = "MacRoomSaveRepairTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return GameStore(repository: repository, reminderDefaults: defaults)
    }

    private func source(now: Date) -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.settings.audio.musicEnabled = false
        state.settings.audio.effectsEnabled = false
        state.settings.audio.catEnabled = false
        state.settings.audio.haptics = false
        return state
    }

    private func needingRepair(now: Date) -> GameSnapshot {
        var state = source(now: now)
        for index in state.home.furniture.indices { state.home.furniture[index].position = .init(x: 0, y: 0) }
        return state
    }

    func testNewHomeSeedUsesOnlyTheExistingOwnedFurnitureAndDoesNotInventHistory() async throws {
        let original = source(now: date)
        let result = try await MacRoomSaveRepair.prepare(original, now: date, isNewHome: true)
        XCTAssertEqual(result.inventory, original.inventory)
        XCTAssertEqual(Set(result.home.furniture.map(\.itemID)), Set(original.home.furniture.map(\.itemID)))
        XCTAssertTrue(result.cats[0].habits.memories.isEmpty)
        XCTAssertTrue(result.cats[0].habits.restLocations.values.allSatisfy { !$0.visited })
        XCTAssertNil(result.cats[0].habits.lastRestObservation)
        XCTAssertEqual(result.player.gold, original.player.gold)
    }

    func testUnchangedPlanReturnsTheExactOriginalWithoutSettlingClocksOrRest() throws {
        var original = source(now: date)
        let bed = try XCTUnwrap(original.inventory.furniture.first { $0.kind == .catBed })
        XCTAssertTrue(GameEngine.startCatRest(&original, catID: original.activeCatID,
            furnitureID: bed.id, sessionID: "unchanged-rest", now: date).succeeded)
        let result = try MacRoomSaveRepair.applying(plan(original), to: original, now: date.addingTimeInterval(600))
        XCTAssertEqual(result, original)
    }

    func testIncompleteTwoFloorPlanIsRejectedRatherThanPublishingHalfARepair() throws {
        var original = source(now: date)
        original.home = HomeState(roomLevel: 6)
        var placements = original.home.furniture
        placements[0].position = .init(x: 0.6, y: 0.7)
        let incomplete = MacRoomLayoutRepair.Plan(placements: placements,
            bowlPositions: [.ground: original.home.bowlPosition], movedIDs: [placements[0].itemID], storedIDs: [])
        XCTAssertThrowsError(try MacRoomSaveRepair.applying(incomplete, to: original, now: date))
        XCTAssertNotEqual(original.home.furniture[0].position, placements[0].position)
    }

    func testAutomaticMoveUpdatesOnlyExistingReferencesAndNeverInventsAVisitOrMemory() throws {
        var original = source(now: date)
        let bed = try XCTUnwrap(original.inventory.furniture.first { $0.kind == .catBed })
        let cushion = try XCTUnwrap(original.inventory.furniture.first { $0.kind == .floorCushion })
        original.cats[0].habits.restLocations[bed.id]?.visited = true
        original.cats[0].habits.restLocations[cushion.id]?.visited = false
        original.cats[0].habits.cornerFurnitureID = cushion.id
        original.cats[0].energy = 30
        XCTAssertTrue(GameEngine.startCatRest(&original, catID: original.activeCatID,
            furnitureID: bed.id, sessionID: "interrupted-rest", now: date).succeeded)
        var placements = original.home.furniture.filter { $0.itemID != cushion.id }
        let index = try XCTUnwrap(placements.firstIndex { $0.itemID == bed.id })
        placements[index].position = .init(x: 0.65, y: 0.75)
        let result = try MacRoomSaveRepair.applying(plan(original, placements: placements), to: original,
                                                  now: date.addingTimeInterval(1))
        XCTAssertNil(result.cats[0].activeRest)
        XCTAssertNil(result.cats[0].habits.cornerFurnitureID)
        XCTAssertEqual(result.cats[0].habits.restLocations[bed.id]?.reference.position, placements[index].position)
        XCTAssertEqual(result.cats[0].habits.restLocations[bed.id]?.visited, true)
        XCTAssertEqual(result.cats[0].habits.restLocations[cushion.id], original.cats[0].habits.restLocations[cushion.id])
        XCTAssertEqual(result.cats[0].habits.memories, original.cats[0].habits.memories)
        XCTAssertEqual(result.cats[0].habits.restClueSessionIDs, original.cats[0].habits.restClueSessionIDs)
        XCTAssertEqual(result.inventory, original.inventory)
        let restored = try NativeSaveTransfer.decode(
            NativeSaveTransfer.encode(snapshot: result, exportedAt: result.meta.lastSyncAt), now: result.meta.lastSyncAt)
        XCTAssertEqual(restored.snapshot, result)
    }

    func testMovedLegacyFootprintStaysFrozenAndStoredLegacyItemUsesNormalCoreStorageRule() throws {
        var original = source(now: date)
        for kind in [FurnitureKind.cabinet, .catBed] {
            let index = try XCTUnwrap(original.inventory.furniture.firstIndex { $0.kind == kind })
            let item = original.inventory.furniture[index]
            let data = try JSONSerialization.data(withJSONObject: ["id": item.id, "kind": kind.rawValue,
                "orientation": "left", "usesLegacyFootprint": true])
            original.inventory.furniture[index] = try JSONDecoder().decode(FurnitureItem.self, from: data)
        }
        let cabinet = try XCTUnwrap(original.inventory.furniture.first { $0.kind == .cabinet })
        let bed = try XCTUnwrap(original.inventory.furniture.first { $0.kind == .catBed })
        var placements = original.home.furniture.filter { $0.itemID != bed.id }
        let index = try XCTUnwrap(placements.firstIndex { $0.itemID == cabinet.id })
        placements[index].position = .init(x: 0.6, y: 0.7)
        let result = try MacRoomSaveRepair.applying(plan(original, placements: placements), to: original, now: date)
        XCTAssertEqual(result.inventory.furniture.first { $0.id == cabinet.id }, cabinet)
        XCTAssertEqual(result.inventory.furniture.first { $0.id == bed.id }?.orientation, .left)
        XCTAssertEqual(result.inventory.furniture.first { $0.id == bed.id }?.usesLegacyFootprint, false)
        XCTAssertEqual(result.inventory.furniture.count, original.inventory.furniture.count)
        let restored = try NativeSaveTransfer.decode(
            NativeSaveTransfer.encode(snapshot: result, exportedAt: result.meta.lastSyncAt), now: result.meta.lastSyncAt)
        XCTAssertEqual(restored.snapshot, result)
    }

    func testRepairSaveFailureDoesNotPublishOrChangeTheOldSaveAndRetryCanComplete() async throws {
        let original = needingRepair(now: Date())
        let repository = RepairMemoryRepository(original)
        await repository.setFailing(true)
        let store = try makeStore(repository)
        await store.load()
        XCTAssertTrue(store.loadFailed && store.macRoomRepairFailed)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isBusy || store.isLoading)
        let unchanged = await repository.saved
        let attempts = await repository.saveAttempts
        XCTAssertEqual(unchanged, original)
        XCTAssertGreaterThan(attempts, 0, "The real planner must produce a candidate before persistence fails.")
        await repository.setFailing(false)
        await store.load()
        let repaired = try XCTUnwrap(store.snapshot)
        XCTAssertFalse(store.loadFailed || store.macRoomRepairFailed)
        XCTAssertNotEqual(repaired.home, original.home)
        XCTAssertEqual(repaired.inventory.furniture.map(\.id), original.inventory.furniture.map(\.id))
        XCTAssertEqual(store.macPreviousSaveAt, original.meta.lastSyncAt)
        let repeated = try await MacRoomSaveRepair.prepare(repaired, now: Date().addingTimeInterval(1))
        XCTAssertEqual(repeated, repaired, "A repaired layout is idempotent and does not trigger another save.")
    }

    func testNewHomeRepairRetryKeepsItsSeedAfterTheRepositoryReadsBackEncodedDates() async throws {
        let original = source(now: Date())
        let expected = try await MacRoomSaveRepair.prepare(original, now: Date(), isNewHome: true)
        let repository = RepairMemoryRepository(original, createsFirstLoad: true)
        await repository.setFailing(true)
        let store = try makeStore(repository)
        await store.load()
        XCTAssertTrue(store.macRoomRepairFailed)
        XCTAssertNil(store.snapshot)
        await repository.setFailing(false)
        await store.load()
        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(store.snapshot?.home, expected.home)
    }

    func testImportFailureLeavesPublishedAndDurableProgressThenSuccessfulImportUsesRepairedLayout() async throws {
        let repository = RepairMemoryRepository(source(now: Date()))
        let store = try makeStore(repository)
        await store.load()
        let before = try XCTUnwrap(store.snapshot)
        var incoming = needingRepair(now: Date())
        incoming.player.gold = 587
        let archive = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: incoming))
        await repository.setFailing(true)
        do {
            try await store.importSaveArchive(archive)
            XCTFail("A failed durable import must not report success.")
        } catch { XCTAssertEqual(error as? SaveTransferError, .writeFailed) }
        XCTAssertEqual(store.snapshot, before)
        let unchanged = await repository.saved
        XCTAssertEqual(unchanged, before)
        await repository.setFailing(false)
        try await store.importSaveArchive(archive)
        let imported = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(imported.player.gold, incoming.player.gold)
        XCTAssertNotEqual(imported.home, incoming.home)
        XCTAssertEqual(imported.inventory.furniture.map(\.id), incoming.inventory.furniture.map(\.id))
        let disk = await repository.saved
        let recovery = await repository.recovery
        XCTAssertEqual(disk, imported)
        XCTAssertEqual(recovery, before)
    }
}

private actor RepairMemoryRepository: GameSaveTransferRepository {
    var saved: GameSnapshot
    var recovery: GameSnapshot?
    var saveAttempts = 0
    var failing = false
    var lastLoadDisposition = SaveLoadDisposition.loaded
    var readCount = 0
    let createsFirstLoad: Bool
    init(_ state: GameSnapshot, createsFirstLoad: Bool = false) {
        saved = state
        self.createsFirstLoad = createsFirstLoad
    }
    func setFailing(_ value: Bool) { failing = value }
    func loadOrCreate(now: Date) throws -> GameSnapshot {
        readCount += 1
        lastLoadDisposition = createsFirstLoad && readCount == 1 ? .created : .loaded
        if createsFirstLoad && readCount > 1 {
            return try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: saved, exportedAt: now), now: now).snapshot
        }
        return saved
    }
    func checkWritable() throws { if failing { throw CocoaError(.fileWriteOutOfSpace) } }
    func save(_ state: GameSnapshot) throws {
        saveAttempts += 1
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
        saved = state
    }
    func importSnapshot(_ state: GameSnapshot) throws {
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
        recovery = saved
        saved = state
    }
    func restoreSnapshotAfterLoadFailure(_ state: GameSnapshot) throws { try importSnapshot(state) }
    func loadImportRecovery() -> GameSnapshot? { recovery }
}
#endif
