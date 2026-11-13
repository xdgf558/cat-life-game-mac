import Foundation
import Observation
import CatGameCore

/// Work, action and recovery messages from the same moment stay visible together.
@MainActor
@Observable
final class GameNoticeCenter {
    private(set) var toast: String?
    private(set) var startupNotice: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func show(_ message: String, ready: Bool) {
        guard !message.isEmpty else { return }
        let previous = ready ? toast : startupNotice
        let combined = ((previous.map { [$0] } ?? []) + [message])
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [String]()) { lines, message in
                lines.removeAll { $0 == message }
                lines.append(message)
            }
            .suffix(3)
            .joined(separator: "\n")
        guard !combined.isEmpty else { return }
        guard ready else { startupNotice = combined; return }
        task?.cancel()
        toast = combined
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.toast = nil
        }
    }

    func enterHome() {
        guard let notice = startupNotice else { return }
        startupNotice = nil
        show(notice, ready: true)
    }
}

@MainActor
enum GameActionNotice {
    static func message(for outcome: ActionOutcome, snapshot: GameSnapshot?) -> String {
        if outcome.succeeded {
            guard let success = outcome.success else { return "" }
            switch success {
            case .fed: return GameStrings.text("action.feed")
            case .cleaned: return GameStrings.text("action.clean")
            case .played: return GameStrings.text("action.play")
            case .foodPurchased, .litterPurchased, .toyPurchased, .supplyPurchased:
                return GameStrings.text("action.purchase")
            case .catAdopted, .equipmentPurchased, .furniturePurchased, .homeUpgraded,
                 .companionSelected, .avatarSaved, .equipped, .unequipped, .starterEquipped,
                 .sleepStarted, .sleepEnded, .catRestStarted, .catRestEnded, .catTreated:
                return GameStrings.text(success.rawValue)
            case .workStarted:
                if let active = snapshot?.player.activeWork, let job = WorkCatalog.job(id: active.jobID) {
                    if let quote = active.quote, quote.durationSeconds != quote.baseDurationSeconds {
                        return GameStrings.text("work.benefitsApplied") + " · "
                            + GameStrings.format("work.durationSeconds", quote.durationSeconds / 60, quote.durationSeconds % 60)
                    }
                    return GameStrings.format("career.started", GameStrings.text("jobs.\(job.id).name"), job.durationMinutes)
                }
                return GameStrings.text("action.workStarted")
            case .workFinished: return GameStrings.format("action.workFinished", outcome.amount)
            case .taskClaimed: return GameStrings.format("tasks.claimedNotice", outcome.amount)
            case .neighborVisited, .neighborGifted: return GameStrings.format(success.rawValue, outcome.amount)
            case .exchanged:
                return outcome.amount > 0 ? GameStrings.format("market.completedWithFriendship", outcome.amount)
                    : GameStrings.text(success.rawValue)
            case .neighborChatted, .communityGiftPurchased, .townEventCompleted, .townMilestoneClaimed:
                return GameStrings.text(success.rawValue)
            case .habitPlayOpened, .habitPlayUpdated, .habitPlayEnded, .habitCornerSelected:
                return GameStrings.text(success.rawValue)
            case .workCancelled: return GameStrings.text(success.rawValue)
            case .layoutSaved: return GameStrings.text("layout.saved")
            }
        }
        switch outcome.failure {
        case .taskMissing, .taskAlreadyClaimed, .taskIncomplete, .taskDayChanged, .taskProgressLimit,
             .playerAvatarMissing, .equipmentItemMissing, .equipmentNotOwned,
             .sleepWorkActive, .workSleeping, .restInvalidFurniture,
             .workJobMissing, .workLevelRequired, .workProgressLimit,
             .shopItemMissing, .shopAlreadyOwned, .homeUpgradeUnavailable,
             .catAdoptionMissing, .catAlreadyOwned, .hospitalHealthy,
             .neighborMissing, .communityGiftMissing, .communityGiftRequired, .communityGiftLimit,
             .exchangeMissing, .exchangeStageRequired, .exchangeDailyLimit, .exchangeMaterialsRequired,
             .careSupplyInvalid, .carePremiumFoodRequired, .carePremiumLitterRequired,
             .townEventMissing, .townEventDayChanged, .townEventCompleted, .townEventStaminaRequired,
              .townEventSuppliesRequired, .townMilestoneClaimed, .townMilestoneIncomplete, .townEventBusy,
              .habitCatUnavailable, .habitPlayBusy, .habitPlaySessionEnded, .habitInputInvalid, .habitCornerUnavailable:
            return GameStrings.text(outcome.messageKey)
        case .taskLevelRequired, .shopLevelRequired, .shopFurnitureLimit, .homeLevelRequired,
             .catPlayerLevelRequired, .catRoomLevelRequired, .hospitalGoldRequired:
            return GameStrings.format(outcome.messageKey, outcome.amount)
        case .roomCapacityReached:
            let canUpgrade = HomeCatalog.nextLevel(after: snapshot?.home.roomLevel ?? 1) != nil
            return GameStrings.format(canUpgrade ? outcome.messageKey : "room.capacityReachedMax", outcome.amount)
        case .roomInvalidPosition, .roomInvalidFurnitureLayout: return GameStrings.text("layout.invalid")
        case .shopGoldRequired: return GameStrings.text("action.insufficientGold")
        case .workStaminaRequired: return GameStrings.text("action.insufficientStamina")
        case .careFoodRequired: return GameStrings.text("care.needFood")
        case .careLitterRequired: return GameStrings.text("care.needLitter")
        case .careToyRequired: return GameStrings.text("care.needToy")
        case .shopInventoryFull: return GameStrings.text("action.inventoryFull")
        case .careCatMissing, .gameInvalidState, .restInvalidSession, .shopInvalidQuantity, .workAlreadyActive, nil:
            return GameStrings.text("action.failed")
        }
    }
}
