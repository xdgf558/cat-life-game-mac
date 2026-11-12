import Foundation
import Observation
import CatGameCore

/// Presentation history is local UI preference, separate from the game save.
@MainActor
@Observable
final class GameAdoptionReminderCenter {
    static let presentedIDsKey = "catlife.adoptionReminder.presentedOfferIDs.v1"
    private var pendingIDs: [String] = []
    @ObservationIgnored private var presentedIDs: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        presentedIDs = Set(defaults.stringArray(forKey: Self.presentedIDsKey) ?? [])
    }

    var pendingOffer: CatAdoptionOffer? {
        pendingIDs.first.flatMap { CatCatalog.adoptionOffer(catID: $0) }
    }

    /// Recheck saved eligibility so interrupted or previously unaffordable offers can return.
    func consider(_ snapshot: GameSnapshot) {
        pendingIDs.removeAll { id in
            guard let offer = CatCatalog.adoptionOffer(catID: id) else { return true }
            return !eligible(offer, in: snapshot)
        }
        for offer in CatCatalog.adoptionOffers where !presentedIDs.contains(offer.id)
            && !pendingIDs.contains(offer.id) && eligible(offer, in: snapshot) {
            pendingIDs.append(offer.id)
        }
    }

    func markPresented(_ id: String) {
        guard pendingOffer?.id == id, presentedIDs.insert(id).inserted else { return }
        defaults.set(presentedIDs.sorted(), forKey: Self.presentedIDsKey)
    }

    func dismiss(_ id: String) { pendingIDs.removeAll { $0 == id } }

    func clearPending() { pendingIDs.removeAll() }

    private func eligible(_ offer: CatAdoptionOffer, in snapshot: GameSnapshot) -> Bool {
        !snapshot.cats.contains { $0.id == offer.id }
            && snapshot.player.level >= offer.requiredPlayerLevel
            && snapshot.home.roomLevel >= offer.requiredRoomLevel
            && snapshot.player.gold >= offer.price
    }
}
