import Foundation
import Observation
import CatGameCore

enum GameOnboardingStep: String, CaseIterable, Codable {
    case care, work, supplies, tasks, town
}

/// The tour is a local presentation preference, never a gameplay reward or save migration.
@MainActor
@Observable
final class GameOnboardingCenter {
    static let progressKey = "catlife.onboarding.progress.v1"
    private(set) var step: GameOnboardingStep?
    var isPresented = false
    var isActive: Bool { step != nil }
    var stepIndex: Int { step.flatMap { GameOnboardingStep.allCases.firstIndex(of: $0) } ?? 0 }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveCreatedAt: String?

    private struct Progress: Codable {
        let saveCreatedAt: String
        let step: GameOnboardingStep?
        let completed: Bool
        var isValid: Bool { !saveCreatedAt.isEmpty && completed == (step == nil) }
    }

    init(defaults: UserDefaults) { self.defaults = defaults }

    func prepare(snapshot: GameSnapshot, disposition: SaveLoadDisposition) {
        isPresented = false
        saveCreatedAt = identity(for: snapshot)
        if case .created = disposition {
            step = .care
        } else if let data = defaults.data(forKey: Self.progressKey),
                  let progress = try? JSONDecoder().decode(Progress.self, from: data),
                  progress.isValid, progress.saveCreatedAt == saveCreatedAt {
            step = progress.step
        } else {
            // Existing progress without a matching tour record belongs to an established player.
            step = nil
        }
        persist()
    }

    func show() {
        guard isActive else { return }
        isPresented = true
    }

    func restart(snapshot: GameSnapshot) {
        saveCreatedAt = identity(for: snapshot)
        step = .care
        isPresented = true
        persist()
    }

    func next() {
        guard isActive else { return }
        let nextIndex = stepIndex + 1
        guard nextIndex < GameOnboardingStep.allCases.count else { finish(); return }
        step = GameOnboardingStep.allCases[nextIndex]
        persist()
    }

    func previous() {
        guard isActive, stepIndex > 0 else { return }
        step = GameOnboardingStep.allCases[stepIndex - 1]
        persist()
    }

    func finish() {
        step = nil
        isPresented = false
        persist()
    }

    func didImport(snapshot: GameSnapshot) {
        saveCreatedAt = identity(for: snapshot)
        finish()
    }

    private func persist() {
        guard let saveCreatedAt,
              let data = try? JSONEncoder().encode(Progress(saveCreatedAt: saveCreatedAt,
                  step: step, completed: step == nil)) else { return }
        defaults.set(data, forKey: Self.progressKey)
    }

    private func identity(for snapshot: GameSnapshot) -> String {
        // Match the disk codec's precision so first-create microseconds survive a cold launch.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: snapshot.meta.createdAt)
    }
}
