import Foundation

public enum ActionKind: String, Codable, Sendable {
    case feed, clean, play, purchase, workStarted, workFinished, layout, none
    case sleepStarted, sleepEnded, catRestStarted, catRestEnded
}

public enum ActionFailure: String, Equatable, Sendable {
    case habitCatUnavailable = "catHabits.error.catUnavailable"
    case habitPlayBusy = "catHabits.error.busy"
    case habitPlaySessionEnded = "catHabits.error.sessionEnded"
    case habitInputInvalid = "catHabits.error.input"
    case habitCornerUnavailable = "catHabits.error.corner"
    case townEventMissing = "townEvents.error.missing"
    case townEventDayChanged = "townEvents.error.dayChanged"
    case townEventCompleted = "townEvents.error.completed"
    case townEventStaminaRequired = "townEvents.error.stamina"
    case townEventBusy = "townEvents.error.busy"
    case townEventSuppliesRequired = "townEvents.error.supplies"
    case townMilestoneClaimed = "townEvents.error.milestoneClaimed"
    case townMilestoneIncomplete = "townEvents.error.milestoneIncomplete"
    case exchangeMissing = "market.error.missing"
    case exchangeStageRequired = "market.error.stage"
    case exchangeDailyLimit = "market.error.limit"
    case exchangeMaterialsRequired = "market.error.materials"
    case careSupplyInvalid = "care.supplyInvalid"
    case carePremiumFoodRequired = "care.premiumFoodRequired"
    case carePremiumLitterRequired = "care.premiumLitterRequired"
    case neighborMissing = "community.neighborMissing"
    case communityGiftMissing = "community.giftMissing"
    case communityGiftRequired = "community.giftRequired"
    case communityGiftLimit = "community.giftLimit"
    case hospitalHealthy = "hospital.healthy"
    case hospitalGoldRequired = "hospital.goldRequired"
    case taskMissing = "tasks.error.unknown"
    case taskLevelRequired = "tasks.error.levelRequired"
    case taskAlreadyClaimed = "tasks.error.alreadyClaimed"
    case taskIncomplete = "tasks.error.incomplete"
    case taskDayChanged = "tasks.error.dayChanged"
    case taskProgressLimit = "tasks.error.progressLimit"
    case catAdoptionMissing = "cat.adoptionMissing"
    case catAlreadyOwned = "cat.alreadyOwned"
    case catPlayerLevelRequired = "cat.playerLevelRequired"
    case catRoomLevelRequired = "cat.roomLevelRequired"
    case careCatMissing = "care.catMissing"
    case careFoodRequired = "care.foodRequired"
    case careLitterRequired = "care.litterRequired"
    case careToyRequired = "care.toyRequired"
    case equipmentItemMissing = "equipment.itemMissing"
    case equipmentNotOwned = "equipment.notOwned"
    case gameInvalidState = "game.invalidState"
    case playerAvatarMissing = "player.avatarMissing"
    case restInvalidFurniture = "rest.invalidFurniture"
    case restInvalidSession = "rest.invalidSession"
    case roomInvalidFurnitureLayout = "room.invalidFurnitureLayout"
    case roomInvalidPosition = "room.invalidPosition"
    case shopGoldRequired = "shop.goldRequired"
    case shopInvalidQuantity = "shop.invalidQuantity"
    case shopInventoryFull = "shop.inventoryFull"
    case shopItemMissing = "shop.itemMissing"
    case shopAlreadyOwned = "shop.alreadyOwned"
    case shopLevelRequired = "shop.levelRequired"
    case shopFurnitureLimit = "shop.furnitureLimit"
    case homeUpgradeUnavailable = "home.upgradeUnavailable"
    case homeLevelRequired = "home.levelRequired"
    case roomCapacityReached = "room.capacityReached"
    case sleepWorkActive = "sleep.workActive"
    case workAlreadyActive = "work.alreadyActive"
    case workJobMissing = "work.jobMissing"
    case workLevelRequired = "work.levelRequired"
    case workProgressLimit = "work.progressLimit"
    case workSleeping = "work.sleeping"
    case workStaminaRequired = "work.staminaRequired"
}

public enum ActionSuccess: String, Equatable, Sendable {
    case habitPlayOpened = "catHabits.playOpened"
    case habitPlayUpdated = "catHabits.playUpdated"
    case habitPlayEnded = "catHabits.playEnded"
    case habitCornerSelected = "catHabits.cornerSelected"
    case townEventCompleted = "townEvents.completedNotice"
    case townMilestoneClaimed = "townEvents.milestoneClaimedNotice"
    case exchanged = "market.exchanged"
    case supplyPurchased = "shop.supplyPurchased"
    case neighborVisited = "community.visited"
    case neighborChatted = "community.chatted"
    case neighborGifted = "community.gifted"
    case communityGiftPurchased = "community.giftPurchased"
    case catTreated = "hospital.treated"
    case taskClaimed = "tasks.claimedNotice"
    case catAdopted = "cat.adopted"
    case companionSelected = "cat.companionSelected"
    case avatarSaved = "player.avatarSaved"
    case equipped = "equipment.equipped"
    case unequipped = "equipment.unequipped"
    case starterEquipped = "equipment.starterEquipped"
    case sleepStarted = "sleep.started"
    case sleepEnded = "sleep.ended"
    case catRestStarted = "rest.started"
    case catRestEnded = "rest.ended"
    case fed = "care.fed"
    case cleaned = "care.cleaned"
    case played = "care.played"
    case equipmentPurchased = "shop.equipmentPurchased"
    case furniturePurchased = "shop.furniturePurchased"
    case homeUpgraded = "home.upgraded"
    case workCancelled = "mac.work.cancelled"
    case workStarted = "work.started"
    case workFinished = "work.finished"
    case layoutSaved = "room.layoutSaved"
    case foodPurchased = "shop.foodPurchased"
    case litterPurchased = "shop.litterPurchased"
    case toyPurchased = "shop.toyPurchased"

    public var kind: ActionKind {
        switch self {
        case .catAdopted, .equipmentPurchased, .furniturePurchased, .homeUpgraded,
             .foodPurchased, .litterPurchased, .toyPurchased, .communityGiftPurchased, .supplyPurchased, .exchanged: return .purchase
        case .companionSelected, .avatarSaved, .equipped, .unequipped, .starterEquipped,
             .taskClaimed, .catTreated, .neighborVisited, .neighborChatted, .neighborGifted,
              .townEventCompleted, .townMilestoneClaimed: return .none
        case .habitPlayOpened, .habitPlayUpdated, .habitPlayEnded, .habitCornerSelected, .workCancelled: return .none
        case .sleepStarted: return .sleepStarted
        case .sleepEnded: return .sleepEnded
        case .catRestStarted: return .catRestStarted
        case .catRestEnded: return .catRestEnded
        case .fed: return .feed
        case .cleaned: return .clean
        case .played: return .play
        case .workStarted: return .workStarted
        case .workFinished: return .workFinished
        case .layoutSaved: return .layout
        }
    }
}

public struct ActionOutcome: Equatable, Sendable {
    public let success: ActionSuccess?
    public let failure: ActionFailure?
    public var kind: ActionKind { success?.kind ?? .none }
    public var succeeded: Bool { failure == nil }
    public var messageKey: String { failure?.rawValue ?? success?.rawValue ?? "" }
    /// Resource units consumed/granted, or gold paid out for completed work.
    public let amount: Int

    /// Synchronization or an already-completed action can succeed without a notice.
    public init() {
        success = nil
        failure = nil
        amount = 0
    }

    public init(success: ActionSuccess, amount: Int = 0) {
        self.success = success
        failure = nil
        self.amount = amount
    }

    public init(failure: ActionFailure, amount: Int = 0) {
        success = nil
        self.failure = failure
        self.amount = amount
    }
}
