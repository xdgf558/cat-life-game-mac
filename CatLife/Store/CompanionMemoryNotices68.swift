import Foundation
import Observation
import CatGameCore

struct CompanionMemoryNotice68: Identifiable, Equatable, Sendable {
    let id = UUID()
    let catID: String
    let memory: CatMemory
    let generation: UUID
}

/// Display receipts come only from successful commits, never from loading a snapshot.
@MainActor @Observable
final class CompanionMemoryNotices68 {
    private(set) var pending: [CompanionMemoryNotice68] = []
    var current: CompanionMemoryNotice68? { pending.first }
    var hasPending: Bool { !pending.isEmpty }

    func record(from previous: GameSnapshot, to current: GameSnapshot, generation: UUID) {
        for cat in current.cats {
            guard let old = previous.cats.first(where: { $0.id == cat.id }) else { continue }
            for memory in cat.habits.memories where !old.habits.memories.contains(where: { $0.kind == memory.kind }) {
                guard !pending.contains(where: { $0.catID == cat.id && $0.memory.kind == memory.kind && $0.generation == generation }) else { continue }
                pending.append(.init(catID: cat.id, memory: memory, generation: generation))
            }
        }
    }

    func acknowledge(catID: String, kind: CatMemoryKind, generation: UUID) {
        pending.removeAll { $0.catID == catID && $0.memory.kind == kind && $0.generation == generation }
    }

    func dismiss(_ id: UUID) { pending.removeAll { $0.id == id } }
    func clear() { pending.removeAll() }
}
