import Foundation

/// An original kept independently of the bounded corrupt-file evidence.
public struct PreservedNewerSave: Identifiable, Equatable, Sendable {
    public let id: String
    public let savedAt: Date
    public let schemaVersion: Int
    public let byteCount: Int

    public init(id: String, savedAt: Date, schemaVersion: Int, byteCount: Int) {
        self.id = id
        self.savedAt = savedAt
        self.schemaVersion = schemaVersion
        self.byteCount = byteCount
    }
}

extension FileSaveRepository {
    public func preservedNewerSaves() throws -> [PreservedNewerSave] {
        let files = PreservedNewerSaveFiles(directory: directory)
        try files.promoteLegacyFiles()
        return try files.list()
    }

    public func exportPreservedNewerSave(id: String, exportedAt: Date = Date()) throws -> Data {
        let files = PreservedNewerSaveFiles(directory: directory)
        let original = try files.read(id: id)
        return try NativeSaveTransfer.encodePreservedSnapshot(original, exportedAt: exportedAt)
    }
}

struct PreservedNewerSaveFiles {
    let directory: URL
    private let prefix = "newer-save-"

    func list() throws -> [PreservedNewerSave] {
        try urls(prefix: prefix).map { url in
            let attributes = try regularAttributes(at: url)
            let data = try Data(contentsOf: url)
            return PreservedNewerSave(id: url.lastPathComponent,
                savedAt: attributes[.modificationDate] as? Date ?? .distantPast,
                schemaVersion: try NativeSaveTransfer.rawSnapshotSchema(data), byteCount: data.count)
        }.sorted {
            if $0.savedAt == $1.savedAt { return $0.id < $1.id }
            return $0.savedAt > $1.savedAt
        }
    }

    func read(id: String) throws -> Data {
        guard validName(id, prefix: prefix) else { throw NativeSaveTransferError.invalidArchive }
        let url = directory.appendingPathComponent(id)
        let attributes = try regularAttributes(at: url)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= NativeSaveTransfer.maximumFileSize else {
            throw NativeSaveTransferError.fileTooLarge
        }
        return try Data(contentsOf: url)
    }

    func preserve(_ data: Data) throws -> URL {
        for url in try urls(prefix: prefix) {
            _ = try regularAttributes(at: url)
            if try Data(contentsOf: url) == data { return url }
        }
        let url = directory.appendingPathComponent("\(prefix)\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func promoteLegacyFiles() throws {
        for url in try urls(prefix: "unreadable-save-") {
            _ = try regularAttributes(at: url)
            let data = try Data(contentsOf: url)
            guard let schema = try? NativeSaveTransfer.rawSnapshotSchema(data),
                  schema > GameSnapshot.currentSchemaVersion
                    || (try? NativeSaveCodec.decodeSnapshot(data, now: Date())) != nil else { continue }
            _ = try preserve(data)
            // Remove only after an exact copy is safely outside automatic cleanup.
            try FileManager.default.removeItem(at: url)
        }
    }

    private func urls(prefix: String) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { validName($0.lastPathComponent, prefix: prefix) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    }

    private func validName(_ name: String, prefix: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix(".json")
            && UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(5))) != nil
    }

    private func regularAttributes(at url: URL) throws -> [FileAttributeKey: Any] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadUnknown) }
        return attributes
    }
}
