#if os(macOS)
import Foundation
import CatGameCore

struct MacCatUrgencySample: Equatable {
    let id: String
    let hungry: Bool
    let ill: Bool

    init(id: String, hungry: Bool, ill: Bool) { self.id = id; self.hungry = hungry; self.ill = ill }
    init(cat: CatState) {
        id = cat.id
        // Use the same hunger threshold as the room bubble, independently of higher-priority illness.
        hungry = CatNeed.current(satiety: cat.satiety, cleanliness: 100, mood: 100, hasFood: true) == .food
        ill = CatNeed.current(satiety: 100, cleanliness: 100, mood: 100, hasFood: true,
                              isIll: cat.healthState?.illness != nil) == .hospital
    }
}

struct MacCatUrgencyState: Equatable {
    let generation: UUID
    let cats: [MacCatUrgencySample]
    var isRestoring = false

    init(generation: UUID, cats: [MacCatUrgencySample], isRestoring: Bool = false) {
        self.generation = generation; self.cats = cats; self.isRestoring = isRestoring
    }
    init(snapshot: GameSnapshot?, generation: UUID, isRestoring: Bool) {
        self.init(generation: generation, cats: snapshot?.cats.map(MacCatUrgencySample.init(cat:)) ?? [],
                  isRestoring: isRestoring || snapshot == nil)
    }
}

struct MacCatUrgencyNotice: Equatable {
    enum Kind: String { case illness, hunger }
    let catID: String
    let kind: Kind
    var titleKey: String { "mac.notifications.cat.title" }
    var bodyKey: String { "mac.notifications.cat." + kind.rawValue }
    func identifier(generation: UUID) -> String { "catlife.catUrgency.\(generation.uuidString).\(catID).\(kind.rawValue)" }
}

/// Observe committed snapshots only. Display and permission changes never replay old needs.
struct MacCatUrgencyTracker {
    private var previous: MacCatUrgencyState?
    mutating func reset(_ state: MacCatUrgencyState) { previous = state }
    mutating func observe(_ state: MacCatUrgencyState, isInBackground: Bool,
                          notificationsEnabled: Bool) -> [MacCatUrgencyNotice] {
        defer { previous = state }
        guard let previous, previous.generation == state.generation,
              !previous.isRestoring, !state.isRestoring, isInBackground, notificationsEnabled else { return [] }
        let oldCats = Dictionary(previous.cats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return state.cats.compactMap { cat in
            guard let old = oldCats[cat.id] else { return nil }
            if cat.ill && !old.ill { return MacCatUrgencyNotice(catID: cat.id, kind: .illness) }
            if cat.hungry && !old.hungry { return MacCatUrgencyNotice(catID: cat.id, kind: .hunger) }
            return nil
        }
    }
}
#endif
