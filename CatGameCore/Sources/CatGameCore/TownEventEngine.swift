import Foundation

extension GameEngine {
    public static func resolveTownEvent(_ state: inout GameSnapshot, eventID: String, choiceID: String,
                                        dayKey: String, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        if let failure = TownEventCatalog.eligibility(eventID: eventID, choiceID: choiceID, dayKey: dayKey, in: state) {
            return .init(failure: failure)
        }
        guard let event = TownEventCatalog.event(id: eventID),
              let choice = event.choices.first(where: { $0.id == choiceID }) else { return .init(failure: .townEventMissing) }
        var candidate = state
        candidate.player.stamina -= choice.staminaCost
        if let kind = choice.supplyCost { candidate.inventory[keyPath: kind.stock] -= choice.supplyCount }
        if let id = choice.giftID { candidate.inventory.gifts[id, default: 0] -= 1 }
        // Capture after spending so a traded item is never subtracted from the displayed reward.
        let beforeRewards = candidate
        candidate.player.gold += min(choice.rewards.gold, GameSnapshot.maximumGold - candidate.player.gold)
        candidate.inventory.food += min(choice.rewards.food, GameSnapshot.maximumStock - candidate.inventory.food)
        candidate.inventory.litter += min(choice.rewards.litter, GameSnapshot.maximumStock - candidate.inventory.litter)
        candidate.inventory.toys += min(choice.rewards.toys, GameSnapshot.maximumStock - candidate.inventory.toys)
        candidate.inventory.premiumFood += min(choice.rewards.premiumFood, GameSnapshot.maximumStock - candidate.inventory.premiumFood)
        candidate.inventory.premiumLitter += min(choice.rewards.premiumLitter, GameSnapshot.maximumStock - candidate.inventory.premiumLitter)
        var relationship = candidate.community.relationship(for: event.neighborID)
        let previousStage = relationship.stage.level
        let gained = applyFriendship(choice.friendshipReward, to: &relationship, in: &candidate)
        candidate.community.relationships[event.neighborID] = relationship
        let actual = TownEventRewards(gold: candidate.player.gold - beforeRewards.player.gold,
            food: candidate.inventory.food - beforeRewards.inventory.food,
            litter: candidate.inventory.litter - beforeRewards.inventory.litter,
            toys: candidate.inventory.toys - beforeRewards.inventory.toys,
            premiumFood: candidate.inventory.premiumFood - beforeRewards.inventory.premiumFood,
            premiumLitter: candidate.inventory.premiumLitter - beforeRewards.inventory.premiumLitter)
        let receipt = TownEventReceipt(dayKey: dayKey, eventID: eventID, choiceID: choiceID, neighborID: event.neighborID,
            completedAt: candidate.meta.lastSyncAt, friendshipGained: gained,
            stageBefore: previousStage, stageAfter: relationship.stage.level, rewards: actual)
        candidate.community.events.totalCompleted = min(GameSnapshot.maximumGold, candidate.community.events.totalCompleted + 1)
        candidate.community.events.letters = Array(candidate.community.events.letters.suffix(63)) + [receipt]
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .townEventCompleted, amount: gained)
    }

    public static func claimTownMilestone(_ state: inout GameSnapshot, milestoneID: String,
                                         now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        if let failure = TownEventCatalog.milestoneEligibility(id: milestoneID, in: state) { return .init(failure: failure) }
        guard let milestone = TownEventCatalog.milestone(id: milestoneID) else { return .init(failure: .townEventMissing) }
        var candidate = state
        if !candidate.inventory.furniture.contains(where: { $0.id == milestone.itemID }) {
            candidate.inventory.furniture.append(.init(id: milestone.itemID, kind: milestone.furnitureKind))
        }
        candidate.community.events.claimedMilestoneIDs.append(milestone.id)
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .townMilestoneClaimed)
    }
}
