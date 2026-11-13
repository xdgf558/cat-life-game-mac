import Foundation
import Testing
@testable import CatGameCore

@Suite("Native save sharing and explicit recovery")
struct NativeSaveTransferTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NativeSaveTransfer-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func changedArchive(_ transform: (inout [String: Any]) throws -> Void) throws -> Data {
        let data = try NativeSaveTransfer.encode(snapshot: .fresh(now: now), exportedAt: now)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try transform(&object)
        return try snapshotFixtureData(object)
    }

    @Test func roundTripPreservesProgressNamesSettingsLayoutAndReceipts() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.profile.name = "Milo 🐱"
        state.home.name = "Sunny room"
        state.settings.language = .traditionalChinese
        state.home.bowlPosition = .init(x: 0.58, y: 0.72)
        #expect(GameEngine.feed(&state, catID: state.activeCatID, now: now).succeeded)
        #expect(GameEngine.claimTask(&state, id: "tutorial_feed", now: now).succeeded)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let data = try NativeSaveTransfer.encode(snapshot: state, exportedAt: now)
        let archive = try NativeSaveTransfer.decode(data, now: now)
        #expect(archive.snapshot == state)
        #expect(archive.exportedAt == now)
    }

    @Test func importTimeRejectsMoreThanOneDayAheadButDoesNotBlockExport() throws {
        let ahead = now.addingTimeInterval(86_401)
        let state = GameSnapshot.fresh(now: ahead)
        let data = try NativeSaveTransfer.encode(snapshot: state, exportedAt: now)
        let archive = try NativeSaveTransfer.decode(data, now: now)
        #expect(archive.snapshot == state, "Preserve the complete progress for exporting after a clock correction.")
        #expect(throws: NativeSaveTransferError.futureProgress) {
            try NativeSaveTransfer.validateImportTime(archive, now: now)
        }
        try NativeSaveTransfer.validateImportTime(archive, now: now.addingTimeInterval(1))
        try NativeSaveTransfer.validateImportTime(archive, now: ahead)
        #expect(throws: NativeSaveTransferError.invalidArchive) {
            try NativeSaveTransfer.validateImportTime(archive, now: Date(timeIntervalSince1970: .infinity))
        }
        // A preview accepted before a device-clock correction needs a fresh check at commit.
        #expect(throws: NativeSaveTransferError.futureProgress) {
            try NativeSaveTransfer.validateImportTime(archive, now: now.addingTimeInterval(-60))
        }
    }

    @Test func rejectsForeignMalformedOversizedAndFutureArchivesBeforeBusinessDecoding() throws {
        #expect(throws: NativeSaveTransferError.invalidArchive) {
            try NativeSaveTransfer.decode(Data("not JSON".utf8), now: now)
        }
        #expect(throws: NativeSaveTransferError.invalidArchive) {
            try NativeSaveTransfer.decode(NativeSaveCodec.encoder().encode(GameSnapshot.fresh(now: now)), now: now)
        }
        #expect(throws: NativeSaveTransferError.fileTooLarge) {
            try NativeSaveTransfer.decode(Data(repeating: 32, count: NativeSaveTransfer.maximumFileSize + 1), now: now)
        }
        let foreign = try changedArchive { $0["format"] = "another-game" }
        #expect(throws: NativeSaveTransferError.invalidArchive) { try NativeSaveTransfer.decode(foreign, now: now) }
        let futureEnvelope = try changedArchive {
            $0["formatVersion"] = 2
            $0.removeValue(forKey: "snapshot")
        }
        #expect(throws: NativeSaveTransferError.unsupportedArchiveVersion(2)) {
            try NativeSaveTransfer.decode(futureEnvelope, now: now)
        }
        let futureSchema = try changedArchive { $0["snapshot"] = ["schemaVersion": 99] }
        #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            try NativeSaveTransfer.decode(futureSchema, now: now)
        }
    }

    @Test func rejectsInvalidDatesAndDamagedCurrentHealthBeforeImport() throws {
        let invalidDate = try changedArchive { $0["exportedAt"] = "tomorrow" }
        #expect(throws: NativeSaveTransferError.invalidArchive) { try NativeSaveTransfer.decode(invalidDate, now: now) }
        let invalidHealth = try changedArchive {
            var snapshot = try #require($0["snapshot"] as? [String: Any])
            var cats = try #require(snapshot["cats"] as? [[String: Any]])
            cats[0].removeValue(forKey: "healthState")
            snapshot["cats"] = cats
            $0["snapshot"] = snapshot
        }
        #expect(throws: SaveRepositoryError.invalidSnapshot) {
            try NativeSaveTransfer.decode(invalidHealth, now: now)
        }
        var invalid = GameSnapshot.fresh(now: now)
        invalid.player.gold = -1
        #expect(throws: NativeSaveTransferError.invalidArchive) {
            try NativeSaveTransfer.encode(snapshot: invalid, exportedAt: now)
        }
        #expect(throws: NativeSaveTransferError.invalidArchive) {
            try NativeSaveTransfer.encode(snapshot: .fresh(now: now), exportedAt: Date(timeIntervalSince1970: .infinity))
        }
    }

    @Test func oldSchemaHealthMigrationIsImmediatelyWritableWithoutBackdatedIllness() async throws {
        let old = try changedArchive {
            var snapshot = try #require($0["snapshot"] as? [String: Any])
            snapshot["schemaVersion"] = 4
            var cats = try #require(snapshot["cats"] as? [[String: Any]])
            cats[0].removeValue(forKey: "healthState")
            snapshot["cats"] = cats
            $0["snapshot"] = snapshot
        }
        let importedAt = now.addingTimeInterval(20 * 86400)
        let archive = try NativeSaveTransfer.decode(old, now: importedAt)
        #expect(archive.snapshot.cats[0].healthState == CatHealthState(now: importedAt))
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        _ = try await repository.loadOrCreate(now: now)
        try await repository.importSnapshot(archive.snapshot)
        #expect(try await repository.loadOrCreate(now: importedAt) == archive.snapshot)
    }

    @Test func importPreservesDurableRecoveryAcrossAutosavesAndRestoreCanBeUndone() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var old = try await repository.loadOrCreate(now: now)
        #expect(try await repository.loadImportRecovery() == nil)
        old.player.gold = 350
        try await repository.save(old, now: now)
        let checkpoint = try Data(contentsOf: repository.backupURL)
        var imported = old
        imported.player.gold = 900
        try await repository.importSnapshot(imported)
        #expect(try await repository.loadOrCreate(now: now) == imported)
        #expect(try await repository.loadImportRecovery() == old)
        #expect(try Data(contentsOf: repository.backupURL) == checkpoint)

        try await repository.importSnapshot(imported)
        #expect(try await repository.loadImportRecovery() == old)
        imported.player.gold = 950
        try await repository.save(imported, now: now.addingTimeInterval(600))
        let reopened = FileSaveRepository(directory: folder)
        let recovery = try #require(try await reopened.loadImportRecovery())
        #expect(recovery == old)
        try await reopened.importSnapshot(recovery)
        #expect(try await reopened.loadOrCreate(now: now) == old)
        #expect(try await reopened.loadImportRecovery() == imported)
    }

    @Test func invalidImportAndRecoveryWriteFailureLeavePrimaryAndAutomaticBackupUntouched() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.gold = 350
        try await repository.save(state, now: now)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        state.player.gold = -1
        await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.importSnapshot(state) }
        #expect(!FileManager.default.fileExists(atPath: repository.importRecoveryURL.path))
        state.player.gold = 999
        try FileManager.default.createDirectory(at: repository.importRecoveryURL, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await repository.importSnapshot(state) }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(try await repository.loadOrCreate(now: now).player.gold == 350)
    }

    @Test func unreadableOrFutureCurrentSaveCannotBeOverwrittenByImport() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = try await repository.loadOrCreate(now: now)
        let future = Data("{\"schemaVersion\":99}".utf8)
        try future.write(to: repository.saveURL)
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            try await repository.importSnapshot(original)
        }
        #expect(try Data(contentsOf: repository.saveURL) == future)
        #expect(!FileManager.default.fileExists(atPath: repository.importRecoveryURL.path))
        try FileManager.default.removeItem(at: repository.saveURL)
        try FileManager.default.createDirectory(at: repository.saveURL, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await repository.importSnapshot(original) }
        #expect(!FileManager.default.fileExists(atPath: repository.importRecoveryURL.path))
    }

    @Test func repeatedImportReplacesInsteadOfAddingRewardsAndKeepsTaskReceipts() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        #expect(GameEngine.feed(&state, catID: state.activeCatID, now: now).succeeded)
        #expect(GameEngine.claimTask(&state, id: "tutorial_feed", now: now).succeeded)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let workEnd = try #require(state.player.activeWork?.endsAt)
        let data = try NativeSaveTransfer.encode(snapshot: state, exportedAt: now)
        var final: GameSnapshot?
        for _ in 0..<2 {
            var candidate = try NativeSaveTransfer.decode(data, now: workEnd).snapshot
            #expect(GameEngine.synchronize(&candidate, now: workEnd).succeeded)
            try await repository.importSnapshot(candidate)
            var loaded = try await repository.loadOrCreate(now: workEnd)
            let gold = loaded.player.gold
            #expect(GameEngine.claimTask(&loaded, id: "tutorial_feed", now: workEnd).failure == .taskAlreadyClaimed)
            _ = GameEngine.synchronize(&loaded, now: workEnd)
            #expect(loaded.player.gold == gold)
            if let final { #expect(loaded == final) }
            final = loaded
        }
    }

    #if os(macOS)
    @Test func failedFinalImportWritePreservesCurrentGameAndReplacesOlderUndoPoint() async throws {
        let folder = try directory()
        let repository = FileSaveRepository(directory: folder)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: repository.saveURL.path)
            try? FileManager.default.removeItem(at: folder)
        }
        var current = try await repository.loadOrCreate(now: now)
        current.player.gold = 350
        try await repository.save(current, now: now)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        var oldUndo = current
        oldUndo.player.gold = 120
        let oldUndoData = try NativeSaveCodec.encoder().encode(oldUndo)
        try oldUndoData.write(to: repository.importRecoveryURL)
        var incoming = current
        incoming.player.gold = 900
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: repository.saveURL.path)

        await #expect(throws: (any Error).self) { try await repository.importSnapshot(incoming) }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        // Preparing the undo point succeeds before the final primary rename fails.
        // It now preserves the current game, not the older import's undo history.
        #expect(try Data(contentsOf: repository.importRecoveryURL) == primary)
        #expect(try Data(contentsOf: repository.importRecoveryURL) != oldUndoData)
        #expect(try await repository.loadImportRecovery() == current)
        #expect(try await repository.loadOrCreate(now: now) == current)
    }
    #endif
}
