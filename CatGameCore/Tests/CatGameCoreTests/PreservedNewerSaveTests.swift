import Foundation
import Testing
@testable import CatGameCore

@Suite("Recoverable original save files")
struct PreservedNewerSaveTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)
    let future = Data("{\"schemaVersion\":99,\"unknown\":{\"large\":18446744073709551615,\"precise\":9007199254740993}}".utf8)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PreservedNewerSave-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func contents(_ directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    @Test func readablePrimaryAfterFailedLoadRejectsReplacementWithoutAnyMutation() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try Data("damaged".utf8).write(to: repository.saveURL)
        await #expect(throws: SaveRepositoryError.unreadableSave) { try await repository.loadOrCreate(now: now) }
        var current = GameSnapshot.fresh(now: now)
        current.player.gold = 999
        let bytes = try NativeSaveCodec.encoder().encode(current)
        try bytes.write(to: repository.saveURL)
        try bytes.write(to: repository.backupURL)
        try bytes.write(to: repository.importRecoveryURL)
        try future.write(to: folder.appendingPathComponent("unreadable-save-\(UUID()).json"))
        let before = try contents(folder)
        await #expect(throws: SaveRepositoryError.currentSaveReadable) {
            try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        }
        #expect(try contents(folder) == before)
        #expect(try await repository.loadOrCreate(now: now) == current)
    }

    @Test func missingPrimaryWithReadableBackupRequiresRetry() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try NativeSaveCodec.encoder().encode(GameSnapshot.fresh(now: now)).write(to: repository.backupURL)
        let before = try contents(folder)
        await #expect(throws: SaveRepositoryError.currentSaveReadable) {
            try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        }
        #expect(try contents(folder) == before)
    }

    @Test func futureOriginalsSurviveRepeatedOrdinaryRecoveryAndDeduplicate() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let second = Data("{\"schemaVersion\":98,\"original\":2}".utf8)
        try future.write(to: repository.saveURL)
        try second.write(to: repository.backupURL)
        try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        let originals = try await repository.preservedNewerSaves()
        #expect(originals.count == 2)
        for index in 0..<6 {
            try Data("damaged \(index)".utf8).write(to: repository.saveURL)
            try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        }
        try future.write(to: repository.saveURL)
        try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        #expect(try await repository.preservedNewerSaves() == originals)
        let remaining = try contents(folder)
        #expect(remaining.filter { $0.key.hasPrefix("unreadable-save-") }.count == 3)
        #expect(remaining.values.contains(future) && remaining.values.contains(second))
    }

    @Test func legacyFutureAndNowSupportedOriginalsArePromotedBeforeLoadAndCleanup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let compatible = try NativeSaveCodec.encoder().encode(GameSnapshot.fresh(now: now))
        let legacy = folder.appendingPathComponent("unreadable-save-\(UUID()).json")
        let duplicate = folder.appendingPathComponent("unreadable-save-\(UUID()).json")
        let supported = folder.appendingPathComponent("unreadable-save-\(UUID()).json")
        try future.write(to: legacy)
        try future.write(to: duplicate)
        try compatible.write(to: supported)
        try compatible.write(to: repository.saveURL)
        _ = try await repository.loadOrCreate(now: now)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: duplicate.path))
        #expect(!FileManager.default.fileExists(atPath: supported.path))
        let originals = try await repository.preservedNewerSaves()
        #expect(originals.count == 2)
        #expect(Set(originals.map(\.schemaVersion)) == [99, GameSnapshot.currentSchemaVersion])
        for original in originals {
            let archive = try await repository.exportPreservedNewerSave(id: original.id, exportedAt: now)
            if original.schemaVersion == GameSnapshot.currentSchemaVersion {
                #expect(try NativeSaveTransfer.decode(archive, now: now).snapshot == .fresh(now: now))
            } else {
                #expect(archive.range(of: future) != nil)
            }
        }
    }

    @Test func exportPreservesUnknownFieldsAndExactNumbersInStandardEnvelope() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try future.write(to: repository.saveURL)
        try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        let original = try #require(try await repository.preservedNewerSaves().first)
        #expect(original.byteCount == future.count && original.schemaVersion == 99)
        let archive = try await repository.exportPreservedNewerSave(id: original.id, exportedAt: now)
        #expect(archive.range(of: future) != nil)
        let envelope = try #require(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        #expect(envelope["format"] as? String == "com.stationcat.catlife.native.save")
        #expect(envelope["formatVersion"] as? Int == 1)
        #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            try NativeSaveTransfer.decode(archive, now: now)
        }
        #expect(try Data(contentsOf: folder.appendingPathComponent(original.id)) == future)
    }

    @Test func compatibleOriginalCanBeImportedUsingNormalBackupDecoder() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = GameSnapshot.fresh(now: now)
        state.player.gold = 4321
        let raw = try NativeSaveCodec.encoder().encode(state)
        let id = "newer-save-\(UUID()).json"
        try raw.write(to: folder.appendingPathComponent(id))
        let archive = try await repository.exportPreservedNewerSave(id: id, exportedAt: now)
        #expect(archive.range(of: raw) != nil)
        let decoded = try NativeSaveTransfer.decode(archive, now: now)
        #expect(decoded.snapshot == state && decoded.exportedAt == now)
        #expect(try Data(contentsOf: folder.appendingPathComponent(id)) == raw)
    }

    @Test func exportRejectsTraversalSymlinksDirectoriesAndInvalidRawJSON() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let id = "newer-save-\(UUID()).json"
        let url = folder.appendingPathComponent(id)
        try future.write(to: repository.saveURL)
        for invalid in ["../cat-life-native-v1.json", "../\(id)", "", "newer-save-no-uuid.json"] {
            await #expect(throws: NativeSaveTransferError.invalidArchive) {
                try await repository.exportPreservedNewerSave(id: invalid, exportedAt: now)
            }
        }
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: repository.saveURL)
        await #expect(throws: (any Error).self) { try await repository.exportPreservedNewerSave(id: id) }
        await #expect(throws: (any Error).self) { try await repository.preservedNewerSaves() }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await repository.exportPreservedNewerSave(id: id) }
        try FileManager.default.removeItem(at: url)
        try Data("{broken".utf8).write(to: url)
        await #expect(throws: NativeSaveTransferError.invalidArchive) { try await repository.exportPreservedNewerSave(id: id) }
        #expect(try Data(contentsOf: repository.saveURL) == future)
    }

    @Test func inaccessibleLegacyEvidenceCannotBlockValidLoadOrBePruned() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let expected = GameSnapshot.fresh(now: now)
        let raw = try NativeSaveCodec.encoder().encode(expected)
        try raw.write(to: repository.saveURL)
        try raw.write(to: repository.backupURL)
        let legacy = folder.appendingPathComponent("unreadable-save-\(UUID()).json")
        try FileManager.default.createSymbolicLink(at: legacy, withDestinationURL: repository.saveURL)
        #expect(try await repository.loadOrCreate(now: now) == expected)
        for index in 0..<5 {
            try Data("evidence \(index)".utf8).write(to: folder.appendingPathComponent("unreadable-save-\(UUID()).json"))
        }
        try Data("broken primary".utf8).write(to: repository.saveURL)
        #expect(try await repository.loadOrCreate(now: now) == expected)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(files.filter { $0.lastPathComponent.hasPrefix("unreadable-save-") }.count == 7)
    }

    @Test func rawExportValidatesJSONDateAndFinalArchiveSize() throws {
        let invalidJSON = [Data("[]".utf8), Data("{}".utf8), Data("{\"schemaVersion\":true}".utf8),
            Data("{\"schemaVersion\":0}".utf8), Data("{\"schemaVersion\":99}{}".utf8), Data([0xff])]
        for invalid in invalidJSON {
            #expect(throws: NativeSaveTransferError.invalidArchive) {
                try NativeSaveTransfer.encodePreservedSnapshot(invalid, exportedAt: now)
            }
        }
        #expect(throws: NativeSaveTransferError.invalidArchive) {
            try NativeSaveTransfer.encodePreservedSnapshot(future, exportedAt: Date(timeIntervalSince1970: .infinity))
        }
        var oversized = future
        oversized.append(Data(repeating: 32, count: NativeSaveTransfer.maximumFileSize - future.count))
        #expect(throws: NativeSaveTransferError.fileTooLarge) {
            try NativeSaveTransfer.encodePreservedSnapshot(oversized, exportedAt: now)
        }
    }

    #if os(macOS)
    @Test func failureToPreserveFutureOriginalDoesNotReplaceEitherSave() async throws {
        let folder = try directory()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let repository = FileSaveRepository(directory: folder)
        let backup = Data("broken backup".utf8)
        try future.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        let before = try contents(folder)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: folder.path)
        await #expect(throws: (any Error).self) {
            try await repository.restoreSnapshotAfterLoadFailure(.fresh(now: now))
        }
        #expect(try contents(folder) == before)
    }
    #endif
}
