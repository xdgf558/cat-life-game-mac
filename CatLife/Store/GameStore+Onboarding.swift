import Foundation
import CatGameCore

extension GameStore {
    func replayOnboarding() {
        guard let snapshot, hasEnteredHome, !isLoading, !isBusy,
              !saveTransferInProgress, !isDecorating else { return }
        inspectedCatID = nil
        onboarding.restart(snapshot: snapshot)
    }

    /// A guide shortcut only navigates; the normal page owns every gameplay action.
    func exploreOnboarding(_ step: GameOnboardingStep) {
        guard snapshot != nil, hasEnteredHome, !isLoading, !isBusy,
              !saveTransferInProgress, !isDecorating else { return }
        inspectedCatID = nil
        isInspectingHealth = false
        isShowingSettings = false
        catCollectionFilter = nil
        adoptionCatID = nil
        isShowingNeighbors = false
        isShowingMarket = false
        switch step {
        case .care: activeSheet = nil
        case .work: activeSheet = .work
        case .supplies:
            shopCategory = .supplies
            activeSheet = .shop
        case .tasks: activeSheet = .tasks
        case .town: activeSheet = .town
        }
        onboarding.isPresented = false
    }
}
