import Foundation
import CatGameCore

/// 3.0 magic cottage actions. Each is one persisted transaction: the wheel's prize, a craft's result
/// and a change of clothes are durable before the UI shows them, and reloading can't re-roll them.
extension GameStore {
    var craft: CraftState? { snapshot?.craft }

    @discardableResult
    func spinWheel() async -> Bool {
        await performCraft { GameEngine.spinWheel(&$0, now: $1) }
    }

    @discardableResult
    func exchangeStardust(blueprintID: String) async -> Bool {
        await performCraft(showsNotice: true) { GameEngine.exchangeStardust(&$0, blueprintID: blueprintID, now: $1) }
    }

    @discardableResult
    func craftBlueprint(_ blueprintID: String) async -> Bool {
        await performCraft { GameEngine.craft(&$0, blueprintID: blueprintID, now: $1) }
    }

    @discardableResult
    func setCraftGoal(_ blueprintID: String?) async -> Bool {
        await performCraft(showsNotice: true) { GameEngine.setCraftGoal(&$0, blueprintID: blueprintID, now: $1) }
    }

    @discardableResult
    func setAppearance(slot: EquipmentSlot, itemID: String?) async -> Bool {
        await performCraft(showsNotice: true) { GameEngine.setAppearance(&$0, slot: slot, itemID: itemID, now: $1) }
    }

    @discardableResult
    func setShowsWorkGearWhenEmpty(_ value: Bool) async -> Bool {
        await performCraft { GameEngine.setShowsWorkGearWhenEmpty(&$0, value, now: $1) }
    }

    @discardableResult
    func markBlueprintGrantsSeen() async -> Bool {
        guard snapshot?.craft.unseenGrants.isEmpty == false else { return true }
        return await performCraft { GameEngine.markBlueprintGrantsSeen(&$0, now: $1) }
    }

    /// 3.1: mend a handmade piece.
    @discardableResult
    func repairHandmade(_ itemID: String) async -> Bool {
        await performCraft(showsNotice: true) { GameEngine.repairHandmade(&$0, itemID: itemID, now: $1) }
    }

    /// 3.1: the goodbye card was read, or (nil) this morning's "about to break" notice was shown.
    @discardableResult
    func acknowledgeHandmadeNotices(farewellID: String?) async -> Bool {
        await performCraft { GameEngine.acknowledgeHandmadeNotices(&$0, farewellID: farewellID, now: $1) }
    }

    /// 3.2: swap a handmade piece with a neighbour, or sell it to the shop.
    @discardableResult
    func tradeHandmade(neighborID: String, itemID: String) async -> Bool {
        await performCraft(showsNotice: true) { GameEngine.tradeHandmade(&$0, neighborID: neighborID, itemID: itemID, now: $1) }
    }

    @discardableResult
    func sellHandmade(_ itemID: String) async -> Bool {
        await performCraft(showsNotice: true) { GameEngine.sellHandmade(&$0, itemID: itemID, now: $1) }
    }

    private func performCraft(showsNotice: Bool = false, _ action: (inout GameSnapshot, Date) -> ActionOutcome) async -> Bool {
        let generation = saveSceneGeneration
        let succeeded = await performPersistedAction(playsSound: false, showsSuccessNotice: showsNotice, action)
        if succeeded, generation == saveSceneGeneration { playNavigationSound() }
        return succeeded && generation == saveSceneGeneration
    }
}
