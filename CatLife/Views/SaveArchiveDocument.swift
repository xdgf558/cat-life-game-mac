import SwiftUI
import UniformTypeIdentifiers
import CatGameCore

struct SaveArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw SaveTransferError.invalidFile
        }
        _ = try NativeSaveTransfer.decode(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SaveArchiveSelection: Sendable {
    let archive: NativeSaveArchive
    let filename: String
    let byteCount: Int
}

enum SaveArchiveFiles {
    static func backupFilename(exportedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "CatLife-Backup-" + formatter.string(from: exportedAt)
    }

    static func read(_ url: URL) throws -> NativeSaveArchive {
        try readSelection(url).archive
    }

    /// Read outside the main actor, with the same cap as the archive decoder.
    static func readSelection(_ url: URL) throws -> SaveArchiveSelection {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // File providers may need to materialize or coordinate the selected item.
        // Keep both the security scope and the bounded read inside that access.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<SaveArchiveSelection, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            result = Result {
                let data = try readCoordinatedFile(coordinatedURL)
                return SaveArchiveSelection(archive: try NativeSaveTransfer.decode(data),
                                            filename: url.lastPathComponent, byteCount: data.count)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw SaveTransferError.readFailed }
        return try result.get()
    }

    private static func readCoordinatedFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= NativeSaveTransfer.maximumFileSize {
            let limit = min(65_536, NativeSaveTransfer.maximumFileSize + 1 - data.count)
            guard let chunk = try handle.read(upToCount: limit), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= NativeSaveTransfer.maximumFileSize else {
            throw SaveTransferError.fileTooLarge
        }
        return data
    }

    static func prepareShareFile(_ data: Data, filename: String) throws -> URL {
        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SaveExports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename).appendingPathExtension("json")
            try data.write(to: url, options: .atomic)
            // Keep one prepared attachment; saved Files exports are outside this cache.
            for previous in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                where previous != url && previous.lastPathComponent.hasPrefix("CatLife-Backup") && previous.pathExtension == "json" {
                try? FileManager.default.removeItem(at: previous)
            }
            return url
        } catch { throw SaveTransferError.writeFailed }
    }
}
