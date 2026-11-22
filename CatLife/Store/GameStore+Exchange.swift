import CatGameCore

extension GameStore {
    /// `neighborID` opens on that neighbour's stall (the Mac bazaar's supplies tab).
    func openExchangeMarket(neighborID: String? = nil) {
        guard !isBusy, !isDecorating, snapshot != nil else { return }
        inspectedCatID = nil
        isShowingSettings = false
        activeSheet = .town
        catCollectionFilter = nil
        adoptionCatID = nil
        isShowingNeighbors = false
        isShowingTownBoard = false
        marketNeighborID = neighborID
        isShowingMarket = true
    }

    @discardableResult
    func exchange(offerID: String,
        presentResult: (@MainActor (NeighborActionReceipt) -> Bool)? = nil) async -> NeighborActionReceipt? {
        let offer = ExchangeCatalog.offer(id: offerID)
        return await performNeighborAction(id: offer?.neighborID ?? "", exchanging: offer,
                                           presentResult: presentResult) {
            GameEngine.exchange(&$0, offerID: offerID, now: $1)
        }
    }
}
