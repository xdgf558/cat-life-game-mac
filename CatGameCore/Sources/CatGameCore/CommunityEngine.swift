import Foundation

extension GameEngine {
    public static func visitNeighbor(_ state: inout GameSnapshot, neighborID: String,
                                     now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard CommunityCatalog.neighbor(id: neighborID) != nil else { return .init(failure: .neighborMissing) }
        var relationship = state.community.relationship(for: neighborID)
        guard !relationship.visitedToday else { return .init(success: .neighborChatted) }
        var candidate = state
        relationship.visitedToday = true
        relationship.totalVisitCount = min(GameSnapshot.maximumGold, relationship.totalVisitCount + 1)
        let gained = applyFriendship(CommunityCatalog.visitFriendship, to: &relationship, in: &candidate)
        candidate.community.relationships[neighborID] = relationship
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .neighborVisited, amount: gained)
    }

    public static func giveNeighborGift(_ state: inout GameSnapshot, neighborID: String, giftID: String,
                                       now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard CommunityCatalog.neighbor(id: neighborID) != nil else { return .init(failure: .neighborMissing) }
        guard CommunityCatalog.gift(id: giftID) != nil else { return .init(failure: .communityGiftMissing) }
        var relationship = state.community.relationship(for: neighborID)
        guard relationship.remainingGiftsToday > 0 else { return .init(failure: .communityGiftLimit) }
        guard state.inventory.giftCount(giftID) > 0 else { return .init(failure: .communityGiftRequired) }
        var candidate = state
        candidate.inventory.gifts[giftID, default: 0] -= 1
        relationship.giftsGivenToday += 1
        relationship.totalGiftCount = min(GameSnapshot.maximumGold, relationship.totalGiftCount + 1)
        let gained = applyFriendship(CommunityCatalog.giftFriendship(neighborID: neighborID, giftID: giftID),
                                     to: &relationship, in: &candidate)
        candidate.community.relationships[neighborID] = relationship
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .neighborGifted, amount: gained)
    }

    public static func buyCommunityGift(_ state: inout GameSnapshot, giftID: String, quantity: Int = 1,
                                       now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let gift = CommunityCatalog.gift(id: giftID) else { return .init(failure: .communityGiftMissing) }
        guard (1...999).contains(quantity) else { return .init(failure: .shopInvalidQuantity) }
        let count = state.inventory.giftCount(giftID)
        guard count <= GameSnapshot.maximumStock - quantity else { return .init(failure: .shopInventoryFull) }
        let price = gift.price * quantity
        guard state.player.gold >= price else { return .init(failure: .shopGoldRequired, amount: price) }
        var candidate = state
        candidate.player.gold -= price
        candidate.inventory.gifts[giftID] = count + quantity
        guard candidate.isValid else { return .init(failure: .gameInvalidState) }
        state = candidate
        return .init(success: .communityGiftPurchased, amount: price)
    }

    static func applyFriendship(_ points: Int, to relationship: inout NeighborRelationship,
                                        in state: inout GameSnapshot) -> Int {
        let gained = min(points, 100 - relationship.friendship)
        relationship.friendship += gained
        for stage in CommunityCatalog.stages where stage.level > 1
            && stage.minimumPoints <= relationship.friendship
            && !relationship.rewardedStageLevels.contains(stage.level) {
            state.player.gold += min(stage.goldReward, GameSnapshot.maximumGold - state.player.gold)
            state.inventory.food += min(stage.foodReward, GameSnapshot.maximumStock - state.inventory.food)
            state.inventory.litter += min(stage.litterReward, GameSnapshot.maximumStock - state.inventory.litter)
            state.inventory.toys += min(stage.toyUsesReward, GameSnapshot.maximumStock - state.inventory.toys)
            relationship.rewardedStageLevels.append(stage.level)
        }
        return gained
    }
}
