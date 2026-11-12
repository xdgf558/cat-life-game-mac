import Foundation

extension GameEngine {
    public static func claimTask(_ state: inout GameSnapshot, id: String,
                                 expectedDayKey: String? = nil, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let task = GameTaskCatalog.task(id: id) else { return ActionOutcome(failure: .taskMissing) }
        guard GameTaskCatalog.isUnlocked(task, in: state) else {
            return ActionOutcome(failure: .taskLevelRequired, amount: task.requiredLevel)
        }
        if task.category == .daily,
           expectedDayKey == nil || expectedDayKey != state.tasks.dailyDayKey {
            return ActionOutcome(failure: .taskDayChanged)
        }
        guard !GameTaskCatalog.isClaimed(task, in: state) else { return ActionOutcome(failure: .taskAlreadyClaimed) }
        guard GameTaskCatalog.isClaimable(task, in: state) else { return ActionOutcome(failure: .taskIncomplete) }
        guard let progress = WorkCatalog.progress(level: state.player.level, exp: state.player.exp,
                                                  adding: task.expReward) else {
            return ActionOutcome(failure: .taskProgressLimit)
        }
        var candidate = state
        let goldAwarded = min(task.goldReward, GameSnapshot.maximumGold - candidate.player.gold)
        candidate.player.gold += goldAwarded
        candidate.player.level = progress.level
        candidate.player.exp = progress.exp
        if task.category == .daily { candidate.tasks.dailyClaimedTaskIDs.append(task.id) }
        else { candidate.tasks.claimedTaskIDs.append(task.id) }
        guard candidate.isValid else { return ActionOutcome(failure: .gameInvalidState) }
        state = candidate
        return ActionOutcome(success: .taskClaimed, amount: goldAwarded)
    }
}

extension GameTaskState {
    static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, (1...9999).contains(year),
              let month = parts.month, let day = parts.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    mutating func advanceDay(to date: Date) {
        guard let next = Self.dayKey(for: date), dailyDayKey == nil || next > dailyDayKey! else { return }
        dailyDayKey = next
        dailyWorkCount = 0
        dailyFeedCount = 0
        dailyPlayCount = 0
        dailyCleanCount = 0
        dailyClaimedTaskIDs = []
    }

    mutating func recordWork(completedAt date: Date) {
        guard dailyDayKey != nil, Self.dayKey(for: date) == dailyDayKey else { return }
        dailyWorkCount = min(GameSnapshot.maximumGold, dailyWorkCount + 1)
    }

    // Immediate care follows synchronization and belongs to the open ledger, even after westward travel.
    mutating func recordFeed() {
        totalFeedCount = min(GameSnapshot.maximumGold, totalFeedCount + 1)
        if dailyDayKey != nil {
            dailyFeedCount = min(GameSnapshot.maximumGold, dailyFeedCount + 1)
        }
    }

    mutating func recordClean() {
        totalCleanCount = min(GameSnapshot.maximumGold, totalCleanCount + 1)
        if dailyDayKey != nil {
            dailyCleanCount = min(GameSnapshot.maximumGold, dailyCleanCount + 1)
        }
    }

    mutating func recordPlay() {
        if dailyDayKey != nil {
            dailyPlayCount = min(GameSnapshot.maximumGold, dailyPlayCount + 1)
        }
    }

    mutating func recordFurniturePurchase() {
        furniturePurchaseCount = min(GameSnapshot.maximumGold, furniturePurchaseCount + 1)
    }

    mutating func restoreFurniturePurchaseHistory(from furniture: [FurnitureItem]) {
        // Exact shop instances prove earlier purchases; starter gifts and arbitrary IDs do not.
        let purchasedInstances = Set(ShopCatalog.furnitureOffers.flatMap { offer in
            (1...offer.maxOwned).map { FurnitureItem(id: offer.instanceID($0), kind: offer.kind) }
        })
        // Purchase evidence is the stable ID and kind, independent of the saved artwork direction.
        let ownedInstances = Set(furniture.map { FurnitureItem(id: $0.id, kind: $0.kind) })
        furniturePurchaseCount = max(furniturePurchaseCount, ownedInstances.intersection(purchasedInstances).count)
    }
}
