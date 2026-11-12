import CatGameCore

struct TaskClaimReceipt: Equatable {
    let taskID: String
    let goldAwarded: Int
    let experienceAwarded: Int
}

extension GameStore {
    func goToTaskDestination(_ destination: GameTaskDestination) {
        guard !isBusy, !isDecorating else { return }
        isShowingSettings = false
        switch destination {
        case .work: activeSheet = .work
        case .care: activeSheet = nil
        case .furnitureShop:
            shopCategory = .furniture
            activeSheet = .shop
        case .upgrade: openHomeUpgrade()
        case .neighbors: openNeighbors()
        case .market: openExchangeMarket()
        }
    }
}
