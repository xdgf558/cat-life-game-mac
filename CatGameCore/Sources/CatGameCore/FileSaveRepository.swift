import Foundation

public enum SaveRepositoryError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidSnapshot
    /// Neither the primary nor a validated backup can be loaded. Nothing is reset.
    case unreadableSave
    /// A transient load failure has cleared; retry loading instead of replacing progress.
    case currentSaveReadable
}

public enum SaveLoadDisposition: Sendable {
    case created, loaded, recoveredBackup
}

/// One actor serializes access to a native JSON save and a validated checkpoint.
/// Frequent saves retain the checkpoint for five minutes instead of replacing it
/// with a nearly identical copy on every tick. File metadata preserves this window
/// across repository instances without adding fields to the game save schema.
/// The caller owns the Application Support location; no browser storage is touched.
public actor FileSaveRepository {
    static let backupInterval: TimeInterval = 5 * 60
    static let maximumRecoveryFiles = 3
    public nonisolated let directory: URL
    public nonisolated let saveURL: URL
    public nonisolated let backupURL: URL
    public nonisolated let importRecoveryURL: URL
    public private(set) var lastLoadDisposition: SaveLoadDisposition = .loaded

    public init(directory: URL) {
        self.directory = directory
        saveURL = directory.appendingPathComponent("cat-life-native-v1.json")
        backupURL = directory.appendingPathComponent("cat-life-native-v1.backup.json")
        importRecoveryURL = directory.appendingPathComponent("cat-life-before-import.json")
    }

    public func loadOrCreate(now: Date = Date()) async throws -> GameSnapshot {
        try ensureDirectory()
        // An inaccessible historical diagnostic must not block a valid primary.
        try? PreservedNewerSaveFiles(directory: directory).promoteLegacyFiles()
        let manager = FileManager.default
        if manager.fileExists(atPath: saveURL.path) {
            // A read-permission/I/O failure propagates instead of silently replacing a file.
            let primaryData = try Data(contentsOf: saveURL)
            do {
                let state = try decode(primaryData, now: now)
                lastLoadDisposition = .loaded
                return state
            } catch SaveRepositoryError.unsupportedSchemaVersion(let version) {
                // Never downgrade a future native save by restoring an older backup.
                throw SaveRepositoryError.unsupportedSchemaVersion(version)
            } catch {
                return try recoverBackup(preserving: primaryData, now: now)
            }
        }
        if manager.fileExists(atPath: backupURL.path) {
            return try recoverBackup(preserving: nil, now: now)
        }
        guard now.timeIntervalSince1970.isFinite else { throw SaveRepositoryError.invalidSnapshot }
        let fresh = GameSnapshot.fresh(now: now)
        try await save(fresh)
        lastLoadDisposition = .created
        return fresh
    }

    public func save(_ state: GameSnapshot) async throws {
        try await save(state, now: Date())
    }

    /// Probe the same storage directory without rewriting gameplay or rotating its checkpoint.
    public func checkWritable() throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: saveURL.path) {
            _ = try decode(Data(contentsOf: saveURL))
        }
        _ = try shouldRotateBackup(now: Date())
        let probe = directory.appendingPathComponent(".cat-life-save-check-\(UUID().uuidString).tmp")
        let data = Data("CatLife save check".utf8)
        defer { try? FileManager.default.removeItem(at: probe) }
        try data.write(to: probe, options: .atomic)
        guard try Data(contentsOf: probe) == data else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.removeItem(at: probe)
    }

    /// The explicit clock makes checkpoint rotation deterministic in durability tests.
    public func save(_ state: GameSnapshot, now: Date) async throws {
        guard now.timeIntervalSince1970.isFinite else { throw SaveRepositoryError.invalidSnapshot }
        guard state.schemaVersion == GameSnapshot.currentSchemaVersion else {
            throw SaveRepositoryError.unsupportedSchemaVersion(state.schemaVersion)
        }
        guard state.isValid else { throw SaveRepositoryError.invalidSnapshot }
        let candidate = try encode(state)
        // Validate serialization before touching existing durable files.
        _ = try decode(candidate)
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: saveURL.path) {
            let previous = try Data(contentsOf: saveURL)
            // Do not rotate corrupt data over the last known-good backup or replace a
            // newer-schema file merely because the caller has an in-memory snapshot.
            _ = try decode(previous)
            if previous == candidate { return }
            if try shouldRotateBackup(now: now) {
                try previous.write(to: backupURL, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: backupURL.path)
            }
        }
        try candidate.write(to: saveURL, options: .atomic)
    }


    /// Explicit replacement keeps a separate, durable undo point. Unlike the
    /// rolling automatic checkpoint, ordinary saves never overwrite this file.
    public func importSnapshot(_ state: GameSnapshot) async throws {
        guard state.schemaVersion == GameSnapshot.currentSchemaVersion else {
            throw SaveRepositoryError.unsupportedSchemaVersion(state.schemaVersion)
        }
        guard state.isValid else { throw SaveRepositoryError.invalidSnapshot }
        let candidate = try encode(state)
        _ = try decode(candidate)
        try ensureDirectory()
        // A missing, unreadable or corrupt current save is never silently replaced.
        let previous = try Data(contentsOf: saveURL)
        _ = try decode(previous)
        guard previous != candidate else { return }
        try previous.write(to: importRecoveryURL, options: .atomic)
        // Last throwing operation: an error cannot report failure after committing.
        // The regular checkpoint retains its normal previous-progress semantics.
        try candidate.write(to: saveURL, options: .atomic)
    }

    public func loadImportRecovery() async throws -> GameSnapshot? {
        guard FileManager.default.fileExists(atPath: importRecoveryURL.path) else { return nil }
        return try decode(Data(contentsOf: importRecoveryURL))
    }

    /// The welcome-page recovery is explicit: preserve unreadable/newer files
    /// before replacing them, without weakening ordinary import's valid-save guard.
    public func restoreSnapshotAfterLoadFailure(_ state: GameSnapshot) async throws {
        guard state.schemaVersion == GameSnapshot.currentSchemaVersion else {
            throw SaveRepositoryError.unsupportedSchemaVersion(state.schemaVersion)
        }
        guard state.isValid else { throw SaveRepositoryError.invalidSnapshot }
        let candidate = try encode(state)
        _ = try decode(candidate)
        try ensureDirectory()
        // Read both first. Permission/I/O failures are not missing or corrupt data.
        let primary = try existingData(at: saveURL)
        let backup = try existingData(at: backupURL)
        if let primary, (try? decode(primary)) != nil {
            throw SaveRepositoryError.currentSaveReadable
        }
        if primary == nil, let backup, (try? decode(backup)) != nil {
            throw SaveRepositoryError.currentSaveReadable
        }
        try PreservedNewerSaveFiles(directory: directory).promoteLegacyFiles()
        var preserved = Set<URL>()
        if let primary { preserved.insert(try preserveRecoveryData(primary)) }
        if let backup { preserved.insert(try preserveRecoveryData(backup)) }
        if let backup {
            let backupIsUsable: Bool
            do { _ = try decode(backup); backupIsUsable = true }
            catch { backupIsUsable = false }
            // A future checkpoint would reject the next normal save. Its exact
            // bytes already exist in recovery evidence before this removal.
            if !backupIsUsable { try FileManager.default.removeItem(at: backupURL) }
        }
        // Never stage the candidate as an automatic backup: a failed primary
        // write must not silently import that candidate on the next launch.
        try candidate.write(to: saveURL, options: .atomic)
        lastLoadDisposition = .loaded
        cleanUpRecoveryFiles(preserving: preserved)
    }

    private func existingData(at url: URL) throws -> Data? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw CocoaError(.fileReadUnknown)
            }
            return try Data(contentsOf: url)
        }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func shouldRotateBackup(now: Date) throws -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: backupURL.path) else { return true }
        // Permission/I/O failures must not be treated as a corrupt file that can
        // be overwritten. A malformed backup can be repaired from the valid primary.
        let backupData = try Data(contentsOf: backupURL)
        do {
            _ = try decode(backupData)
        } catch SaveRepositoryError.unsupportedSchemaVersion(let version) {
            throw SaveRepositoryError.unsupportedSchemaVersion(version)
        } catch {
            return true
        }
        let attributes = try manager.attributesOfItem(atPath: backupURL.path)
        guard let checkpointAt = attributes[.modificationDate] as? Date else { return true }
        // Clock rollback keeps the existing known-good checkpoint until time catches up.
        return now.timeIntervalSince(checkpointAt) >= Self.backupInterval
    }

    private func recoverBackup(preserving corruptData: Data?, now: Date) throws -> GameSnapshot {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw SaveRepositoryError.unreadableSave
        }
        let backupData = try Data(contentsOf: backupURL)
        let recovered: GameSnapshot
        do {
            recovered = try decode(backupData, now: now)
        } catch SaveRepositoryError.unsupportedSchemaVersion(let version) {
            throw SaveRepositoryError.unsupportedSchemaVersion(version)
        } catch {
            throw SaveRepositoryError.unreadableSave
        }
        var preserved = Set<URL>()
        if let corruptData { preserved.insert(try preserveRecoveryData(corruptData)) }
        try backupData.write(to: saveURL, options: .atomic)
        lastLoadDisposition = .recoveredBackup
        cleanUpRecoveryFiles(preserving: preserved)
        return recovered
    }

    private func preserveRecoveryData(_ data: Data) throws -> URL {
        if let schema = try? NativeSaveTransfer.rawSnapshotSchema(data), schema > GameSnapshot.currentSchemaVersion {
            return try PreservedNewerSaveFiles(directory: directory).preserve(data)
        }
        // Retrying a failed restore must not produce unlimited identical evidence.
        if let existing = try recoveryFiles().first(where: { (try? Data(contentsOf: $0)) == data }) {
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: existing.path)
            return existing
        }
        let url = directory.appendingPathComponent("unreadable-save-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func cleanUpRecoveryFiles(preserving protected: Set<URL>) {
        // Cleanup cannot turn a successfully restored save into a load failure.
        // Keep this recovery's originals plus recent evidence, up to three files.
        do { try PreservedNewerSaveFiles(directory: directory).promoteLegacyFiles() }
        catch { return }
        if let files = try? recoveryFiles() {
            // Directory enumeration can resolve a symlinked save directory;
            // match the unique evidence filename rather than URL representation.
            let protectedNames = Set(protected.map(\.lastPathComponent))
                .intersection(files.map(\.lastPathComponent))
            var remaining = max(0, Self.maximumRecoveryFiles - protectedNames.count)
            for url in files where !protectedNames.contains(url.lastPathComponent) {
                if remaining > 0 { remaining -= 1 }
                else { try? FileManager.default.removeItem(at: url) }
            }
        }
    }

    private func recoveryFiles() throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.compactMap { url -> (URL, Date)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("unreadable-save-"), name.hasSuffix(".json"),
                  UUID(uuidString: String(name.dropFirst("unreadable-save-".count).dropLast(5))) != nil,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
            return (url, attributes[.modificationDate] as? Date ?? .distantPast)
        }.sorted {
            if $0.1 == $1.1 { return $0.0.lastPathComponent < $1.0.lastPathComponent }
            return $0.1 > $1.1
        }.map(\.0)
    }

    private func encode(_ snapshot: GameSnapshot) throws -> Data {
        try NativeSaveCodec.encoder().encode(snapshot)
    }

    private func decode(_ data: Data, now: Date = Date()) throws -> GameSnapshot {
        try NativeSaveCodec.decodeSnapshot(data, now: now)
    }
}
