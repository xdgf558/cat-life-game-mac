import Foundation
import CatGameCore

enum SaveTransferError: Error, Equatable, Sendable {
    case busy, invalidFile, fileTooLarge, unsupportedVersion, readFailed, writeFailed, currentSaveReadable, futureProgress

    static func reason(for error: Error) -> SaveTransferError {
        let reason: SaveTransferError
        if let error = error as? SaveTransferError { reason = error }
        else if let error = error as? NativeSaveTransferError {
            switch error {
            case .invalidArchive: reason = .invalidFile
            case .unsupportedArchiveVersion: reason = .unsupportedVersion
            case .fileTooLarge: reason = .fileTooLarge
            case .futureProgress: reason = .futureProgress
            }
        } else if let error = error as? SaveRepositoryError {
            switch error {
            case .unsupportedSchemaVersion: reason = .unsupportedVersion
            case .invalidSnapshot, .unreadableSave: reason = .invalidFile
            case .currentSaveReadable: reason = .currentSaveReadable
            }
        } else { reason = .readFailed }
        return reason
    }

    static func messageKey(for error: Error) -> String {
        switch reason(for: error) {
        case .busy: return "saveTransfer.busy"
        case .invalidFile: return "saveTransfer.invalidFile"
        case .fileTooLarge: return "saveTransfer.fileTooLarge"
        case .unsupportedVersion: return "saveTransfer.unsupportedVersion"
        case .readFailed: return "saveTransfer.readFailed"
        case .writeFailed: return "saveTransfer.writeFailed"
        case .currentSaveReadable: return "saveTransfer.currentSaveReadable"
        case .futureProgress: return "saveTransfer.futureProgress"
        }
    }
}

/// Only repositories that can preserve a durable recovery point accept replacement.
protocol GameSaveTransferRepository: GameSaveRepository {
    func importSnapshot(_ state: GameSnapshot) async throws
    func restoreSnapshotAfterLoadFailure(_ state: GameSnapshot) async throws
    func loadImportRecovery() async throws -> GameSnapshot?
}

extension FileSaveRepository: GameSaveTransferRepository {}

protocol GamePreservedSaveRepository: GameSaveRepository {
    func preservedNewerSaves() async throws -> [PreservedNewerSave]
    func exportPreservedNewerSave(id: String, exportedAt: Date) async throws -> Data
}

extension FileSaveRepository: GamePreservedSaveRepository {}
