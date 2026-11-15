import Foundation
import CatGameCore

/// 2.0 outing actions. Each one is a single persisted transaction: costs, finds and choices are
/// durable before the UI shows them, so quitting mid-trip never loses or repeats a step.
extension GameStore {
    var outing: OutingState? { snapshot?.outing }
    var outingTrip: OutingTrip? { snapshot?.outing.trip }

    @discardableResult
    func startOuting(catID: String) async -> Bool {
        await performOuting { GameEngine.startOuting(&$0, catID: catID, now: $1) }
    }

    @discardableResult
    func exploreOuting(spot: OutingSpot) async -> Bool {
        await performOuting { GameEngine.exploreOuting(&$0, spot: spot, now: $1) }
    }

    @discardableResult
    func chooseOutingEvent(optionID: String) async -> Bool {
        await performOuting { GameEngine.chooseOutingEvent(&$0, optionID: optionID, now: $1) }
    }

    @discardableResult
    func endOuting() async -> Bool {
        await performOuting { GameEngine.endOuting(&$0, now: $1) }
    }

    @discardableResult
    func acknowledgeOutingSettlement() async -> Bool {
        guard snapshot?.outing.unacknowledgedSettlement != nil else { return true }
        return await performOuting { GameEngine.acknowledgeOutingSettlement(&$0, now: $1) }
    }

    @discardableResult
    func resolveDecorDuplicate(decorID: String, keepNew: Bool) async -> Bool {
        let succeeded = await performOuting { GameEngine.resolveDecorDuplicate(&$0, decorID: decorID, keepNew: keepNew, now: $1) }
        if succeeded { showNotice(GameStrings.format("outing.compare.done", OutingCatalog.duplicateDecorGold)) }
        return succeeded
    }

    @discardableResult
    func setKeepsakeOnShelf(keepsakeID: String, onShelf: Bool) async -> Bool {
        await performOuting { GameEngine.setKeepsakeOnShelf(&$0, keepsakeID: keepsakeID, onShelf: onShelf, now: $1) }
    }

    private func performOuting(_ action: (inout GameSnapshot, Date) -> ActionOutcome) async -> Bool {
        let generation = saveSceneGeneration
        let succeeded = await performPersistedAction(playsSound: false, showsSuccessNotice: false, action)
        if succeeded, generation == saveSceneGeneration { playNavigationSound() }
        return succeeded && generation == saveSceneGeneration
    }
}
