import Foundation

public enum NativeSaveTransferError: Error, Equatable, Sendable {
    case invalidArchive
    case unsupportedArchiveVersion(Int)
    case fileTooLarge
    case futureProgress
}

/// A validated, immutable preview; selecting a file never mutates the game.
public struct NativeSaveArchive: Equatable, Sendable {
    public let snapshot: GameSnapshot
    public let exportedAt: Date
}

public enum NativeSaveTransfer {
    public static let maximumFileSize = 5 * 1024 * 1024
    private static let identifier = "com.stationcat.catlife.native.save"
    private static let currentFormatVersion = 1

    /// Check again when confirming: the device clock may have changed after preview.
    /// Export remains available so a clock error never traps the original progress.
    public static func validateImportTime(_ archive: NativeSaveArchive, now: Date = Date()) throws {
        guard now.timeIntervalSince1970.isFinite else { throw NativeSaveTransferError.invalidArchive }
        let growthDates = archive.snapshot.cats.compactMap(\.growthState).flatMap {
            [$0.recordedSince] + [$0.adoptedAt].compactMap { $0 }
        }
        let eventDates = archive.snapshot.community.events.letters.map(\.completedAt)
        let habitDates = archive.snapshot.cats.flatMap {
            $0.habits.memories.map(\.createdAt) + [$0.habits.lastRestObservation?.completedAt, $0.habits.lastPlayObservation?.observedAt].compactMap { $0 }
        }
        let playDates = [archive.snapshot.catPlay.activeSession?.openedAt, archive.snapshot.catPlay.activeSession?.paidAt,
                         archive.snapshot.catPlay.lastResult?.endedAt].compactMap { $0 }
        guard ([archive.snapshot.meta.lastSyncAt] + growthDates + eventDates + habitDates + playDates).allSatisfy({ $0.timeIntervalSince(now) <= 24 * 60 * 60 }) else {
            throw NativeSaveTransferError.futureProgress
        }
    }

    private struct Envelope: Codable {
        let format: String
        let formatVersion: Int
        let exportedAt: Date
        let snapshot: GameSnapshot

        private enum CodingKeys: String, CodingKey {
            case format, formatVersion, exportedAt, snapshot
        }

        init(snapshot: GameSnapshot, exportedAt: Date) {
            format = identifier
            formatVersion = currentFormatVersion
            self.exportedAt = exportedAt
            self.snapshot = snapshot
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            format = try values.decode(String.self, forKey: .format)
            guard format == identifier else { throw NativeSaveTransferError.invalidArchive }
            formatVersion = try values.decode(Int.self, forKey: .formatVersion)
            guard formatVersion == currentFormatVersion else {
                throw NativeSaveTransferError.unsupportedArchiveVersion(formatVersion)
            }
            exportedAt = try values.decode(Date.self, forKey: .exportedAt)
            snapshot = try values.decode(GameSnapshot.self, forKey: .snapshot)
        }
    }

    public static func encode(snapshot: GameSnapshot, exportedAt: Date = Date()) throws -> Data {
        guard snapshot.schemaVersion == GameSnapshot.currentSchemaVersion else {
            throw SaveRepositoryError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        guard snapshot.isValid, exportedAt.timeIntervalSince1970.isFinite else {
            throw NativeSaveTransferError.invalidArchive
        }
        let data = try NativeSaveCodec.encoder().encode(Envelope(snapshot: snapshot, exportedAt: exportedAt))
        // ISO date formatting and the entire schema must survive a read-back.
        _ = try decode(data, now: exportedAt)
        return data
    }

    /// Preserve unknown fields and number precision when exporting a newer save.
    static func encodePreservedSnapshot(_ snapshotData: Data, exportedAt: Date) throws -> Data {
        guard snapshotData.count <= maximumFileSize else { throw NativeSaveTransferError.fileTooLarge }
        _ = try rawSnapshotSchema(snapshotData)
        guard exportedAt.timeIntervalSince1970.isFinite else { throw NativeSaveTransferError.invalidArchive }
        let encodedDate = try NativeSaveCodec.encoder().encode(exportedAt)
        guard (try? NativeSaveCodec.decoder().decode(Date.self, from: encodedDate)) != nil else {
            throw NativeSaveTransferError.invalidArchive
        }
        var data = Data("{\"format\":\"\(identifier)\",\"formatVersion\":\(currentFormatVersion),\"exportedAt\":".utf8)
        data.append(encodedDate)
        data.append(Data(",\"snapshot\":".utf8))
        data.append(snapshotData)
        data.append(Data("}".utf8))
        guard data.count <= maximumFileSize else { throw NativeSaveTransferError.fileTooLarge }
        return data
    }

    static func rawSnapshotSchema(_ data: Data) throws -> Int {
        struct Header: Decodable { let schemaVersion: Int }
        guard String(data: data, encoding: .utf8) != nil,
              let header = try? JSONDecoder().decode(Header.self, from: data), header.schemaVersion > 0 else {
            throw NativeSaveTransferError.invalidArchive
        }
        return header.schemaVersion
    }

    public static func decode(_ data: Data, now: Date = Date()) throws -> NativeSaveArchive {
        guard data.count <= maximumFileSize else { throw NativeSaveTransferError.fileTooLarge }
        guard now.timeIntervalSince1970.isFinite else { throw NativeSaveTransferError.invalidArchive }
        do {
            let envelope = try NativeSaveCodec.decoder().decode(Envelope.self, from: data)
            let snapshot = try NativeSaveCodec.validated(envelope.snapshot, migrationDate: now)
            return NativeSaveArchive(snapshot: snapshot, exportedAt: envelope.exportedAt)
        } catch let error as NativeSaveTransferError {
            throw error
        } catch let error as SaveRepositoryError {
            throw error
        } catch {
            throw NativeSaveTransferError.invalidArchive
        }
    }
}

/// Disk saves and shared archives use one date codec and migration boundary.
enum NativeSaveCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return decoder
    }

    static func decodeSnapshot(_ data: Data, now: Date) throws -> GameSnapshot {
        try validated(decoder().decode(GameSnapshot.self, from: data), migrationDate: now)
    }

    static func validated(_ snapshot: GameSnapshot, migrationDate: Date) throws -> GameSnapshot {
        guard migrationDate.timeIntervalSince1970.isFinite else { throw SaveRepositoryError.invalidSnapshot }
        var snapshot = snapshot
        // Only pre-health schemas can reach this boundary without a health object.
        // Start protection now, never by retroactively evaluating old neglect.
        for index in snapshot.cats.indices where snapshot.cats[index].healthState == nil {
            snapshot.cats[index].healthState = CatHealthState(now: migrationDate)
        }
        for index in snapshot.cats.indices where snapshot.cats[index].growthState == nil {
            snapshot.cats[index].growthState = .legacy(appearance: snapshot.cats[index].appearance, now: migrationDate,
                                                     isPregnant: snapshot.cats[index].isPregnant)
        }
        guard snapshot.isValid else { throw SaveRepositoryError.invalidSnapshot }
        return snapshot
    }
}
