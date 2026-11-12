import Foundation
import CatGameCore

/// The app serializes commits; the repository provides atomic durable storage.
protocol GameSaveRepository: Sendable {
    var lastLoadDisposition: SaveLoadDisposition { get async }
    func loadOrCreate(now: Date) async throws -> GameSnapshot
    func save(_ state: GameSnapshot) async throws
    func checkWritable() async throws
}

extension FileSaveRepository: GameSaveRepository {}

/// A short retry burst is followed by low-frequency recovery probes.
/// Manual actions always remain available and report their own write failure.
struct SaveRetryState {
    private(set) var failures = 0
    private(set) var nextAttempt = Date.distantPast
    private(set) var hasReportedFailure = false
    static let maximumAutomaticAttempts = 3

    func permitsAutomaticAttempt(at date: Date) -> Bool {
        date >= nextAttempt
    }

    mutating func failed(at date: Date) -> Bool {
        failures = min(Self.maximumAutomaticAttempts, failures + 1)
        nextAttempt = date.addingTimeInterval(failures == 1 ? 2 : (failures == 2 ? 5 : 60))
        let shouldReport = !hasReportedFailure
        hasReportedFailure = true
        return shouldReport
    }

    mutating func succeeded() { self = Self() }
}

/// A full stamina clock has no saved effect until work consumes stamina; that
/// action already anchors regeneration at its own start time.
func requiresDurableSave(_ candidate: GameSnapshot, comparedTo original: GameSnapshot) -> Bool {
    var comparable = candidate
    comparable.meta.lastSyncAt = original.meta.lastSyncAt
    if comparable.player.stamina == 100, original.player.stamina == 100,
       comparable.player.activeSleep == nil, original.player.activeSleep == nil {
        comparable.player.staminaUpdatedAt = original.player.staminaUpdatedAt
    }
    return comparable != original
}
