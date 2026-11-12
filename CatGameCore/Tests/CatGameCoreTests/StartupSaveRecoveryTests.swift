import Foundation
import Testing
@testable import CatGameCore

@Suite("Explicit recovery after startup failure")
struct StartupSaveRecoveryTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StartupSaveRecovery-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func evidence(in directory: URL, prefix: String = "unreadable-save-") throws -> [Data] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .map { try Data(contentsOf: $0) }
    }

    @Test func damagedPrimaryAndBackupArePreservedAndImportRecoveryIsUntouched() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let primary = Data("{broken primary".utf8)
        let backup = Data("broken backup".utf8)
        let importRecovery = try NativeSaveCodec.encoder().encode(GameSnapshot.fresh(now: now))
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        try importRecovery.write(to: repository.importRecoveryURL)
        await #expect(throws: SaveRepositoryError.unreadableSave) { try await repository.loadOrCreate(now: now) }

        var replacement = GameSnapshot.fresh(now: now)
        replacement.player.gold = 687
        try await repository.restoreSnapshotAfterLoadFailure(replacement)
        #expect(try await repository.loadOrCreate(now: now) == replacement)
        #expect(try evidence(in: folder).contains(primary))
        #expect(try evidence(in: folder).contains(backup))
        #expect(!FileManager.default.fileExists(atPath: repository.backupURL.path))
        #expect(try Data(contentsOf: repository.importRecoveryURL) == importRecovery)
        try await repository.checkWritable()
    }

    @Test func futurePrimaryAndBackupArePreservedAndDoNotBlockSubsequentSaves() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let primary = Data("{\"schemaVersion\":99,\"futureOnlyData\":[1,2,3]}".utf8)
        let backup = Data("{\"schemaVersion\":98,\"futureOnlyData\":\"backup\"}".utf8)
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            try await repository.loadOrCreate(now: now)
        }
        var replacement = GameSnapshot.fresh(now: now)
        try await repository.restoreSnapshotAfterLoadFailure(replacement)
        #expect(try evidence(in: folder, prefix: "newer-save-").contains(primary))
        #expect(try evidence(in: folder, prefix: "newer-save-").contains(backup))
        try await repository.checkWritable()
        replacement.player.gold = 888
        try await repository.save(replacement, now: now)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == replacement)
        #expect(try NativeSaveCodec.decodeSnapshot(Data(contentsOf: repository.backupURL), now: now).player.gold == 200)
    }

    @Test func aValidAutomaticBackupRemainsAvailableAndBothOriginalsArePreserved() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let primary = Data("{\"schemaVersion\":99}".utf8)
        var previous = GameSnapshot.fresh(now: now)
        previous.player.gold = 321
        let backup = try NativeSaveCodec.encoder().encode(previous)
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(try evidence(in: folder, prefix: "newer-save-").contains(primary))
        #expect(try evidence(in: folder, prefix: "newer-save-").contains(backup))
        try await repository.checkWritable()
    }

    @Test func missingPrimaryCanBeRestoredWhileUnreadableBackupStillBlocksReplacement() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let brokenBackup = Data("broken backup".utf8)
        try brokenBackup.write(to: repository.backupURL)
        let replacement = GameSnapshot.fresh(now: now)
        try await repository.restoreSnapshotAfterLoadFailure(replacement)
        #expect(try await repository.loadOrCreate(now: now) == replacement)
        #expect(try evidence(in: folder).contains(brokenBackup))

        let primary = try Data(contentsOf: repository.saveURL)
        try FileManager.default.createDirectory(at: repository.backupURL, withIntermediateDirectories: false)
        var other = replacement
        other.player.gold = 999
        await #expect(throws: (any Error).self) { try await repository.restoreSnapshotAfterLoadFailure(other) }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try evidence(in: folder) == [brokenBackup])
    }

    @Test func invalidCandidateCannotAlterOriginalsOrCreateEvidence() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let primary = Data("broken primary".utf8)
        let backup = Data("broken backup".utf8)
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        var invalid = GameSnapshot.fresh(now: now)
        invalid.player.gold = -1
        await #expect(throws: SaveRepositoryError.invalidSnapshot) {
            try await repository.restoreSnapshotAfterLoadFailure(invalid)
        }
        invalid = .fresh(now: now)
        invalid.schemaVersion = 99
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            try await repository.restoreSnapshotAfterLoadFailure(invalid)
        }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(try evidence(in: folder).isEmpty)
    }

    @Test func evidenceCleanupKeepsBothCurrentOriginalsAndBoundsOlderFiles() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        for index in 0..<5 {
            let url = folder.appendingPathComponent("unreadable-save-\(UUID()).json")
            try Data("old evidence \(index)".utf8).write(to: url)
        }
        let primary = Data("new damaged primary".utf8)
        let backup = Data("new damaged backup".utf8)
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        let remaining = try evidence(in: folder)
        #expect(remaining.count == FileSaveRepository.maximumRecoveryFiles)
        #expect(remaining.contains(primary) && remaining.contains(backup))
    }

    #if os(macOS)
    @Test func failureToPreserveEvidenceCannotReplacePrimaryOrRemoveBackup() async throws {
        let folder = try directory()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let repository = FileSaveRepository(directory: folder)
        let primary = Data("broken primary".utf8)
        let backup = Data("broken backup".utf8)
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        // Exercise a real filesystem rejection, without a runtime failure hook.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: folder.path)
        await #expect(throws: (any Error).self) {
            try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(try evidence(in: folder).isEmpty)
    }

    @Test func failedFinalPrimaryWriteKeepsOriginalAndCannotCommitThroughAutomaticBackup() async throws {
        let folder = try directory()
        let repository = FileSaveRepository(directory: folder)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: repository.saveURL.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let primary = Data("broken primary".utf8)
        let backup = Data("{\"schemaVersion\":99}".utf8)
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: repository.saveURL.path)
        await #expect(throws: (any Error).self) {
            try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try evidence(in: folder).contains(primary))
        #expect(try evidence(in: folder, prefix: "newer-save-").contains(backup))
        #expect(!FileManager.default.fileExists(atPath: repository.backupURL.path))
        await #expect(throws: SaveRepositoryError.unreadableSave) { try await repository.loadOrCreate(now: now) }
    }
    #endif
}
