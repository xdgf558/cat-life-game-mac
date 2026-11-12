import CatGameCore

extension GameStore {
    func openTownBoard() {
        guard !isBusy, !isDecorating, snapshot != nil else { return }
        inspectedCatID = nil
        isShowingSettings = false
        activeSheet = .town
        catCollectionFilter = nil
        adoptionCatID = nil
        isShowingNeighbors = false
        isShowingMarket = false
        isShowingTownBoard = true
        playNavigationSound()
    }

    @discardableResult
    func resolveTownEvent(eventID: String, choiceID: String, dayKey: String,
        presentResult: (@MainActor (TownEventReceipt) -> Bool)? = nil) async -> TownEventReceipt? {
        let generation = saveSceneGeneration
        var receipt: TownEventReceipt?
        let succeeded = await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
            let outcome = GameEngine.resolveTownEvent(&$0, eventID: eventID, choiceID: choiceID, dayKey: dayKey, now: $1)
            if outcome.success == .townEventCompleted { receipt = $0.community.events.todayReceipt }
            return outcome
        }
        guard succeeded, let receipt, generation == saveSceneGeneration else { return nil }
        if canPresentTownEventResult { playFeedback(.claim) }
        if !canPresentTownEventResult || presentResult?(receipt) != true {
            showNotice(townEventNotice(receipt))
        }
        return receipt
    }

    @discardableResult
    func claimTownMilestone(milestoneID: String) async -> Bool {
        let generation = saveSceneGeneration
        let succeeded = await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
            GameEngine.claimTownMilestone(&$0, milestoneID: milestoneID, now: $1)
        }
        guard succeeded, generation == saveSceneGeneration else { return false }
        if canPresentTownEventResult { playFeedback(.claim) }
        showNotice(GameStrings.text("townEvents.milestone.claimed"))
        return true
    }

    private func townEventNotice(_ receipt: TownEventReceipt) -> String {
        let rewards = receipt.rewards
        let lines = [("friendship", receipt.friendshipGained), ("gold", rewards.gold),
                     ("food", rewards.food), ("litter", rewards.litter), ("toys", rewards.toys),
                     ("premiumFood", rewards.premiumFood), ("premiumLitter", rewards.premiumLitter)]
            .filter { $0.1 > 0 }.map { GameStrings.format("townEvents.reward." + $0.0, $0.1) }
        return GameStrings.text("townEvents.completedNotice") + (lines.isEmpty ? "" : "\n" + lines.joined(separator: " · "))
    }
}
