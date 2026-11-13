import SwiftUI
import CatGameCore

/// Map coordinates are presentation only; they never enter a game save.
enum TownMapLayout {
    static let size = CGSize(width: 390, height: 1820)
    static let readingOrder: [TownPlace] = [.work, .shop, .plaza, .board, .market, .street,
                                           .home, .hospital, .adoption, .cafe, .lot1, .lot2]
    static func frame(for place: TownPlace) -> CGRect {
        let values: (CGFloat, CGFloat, CGFloat)
        switch place {
        case .work: values = (14, 196, 156)
        case .shop: values = (220, 200, 156)
        case .plaza: values = (106, 500, 178)
        case .board: values = (4, 714, 134)
        case .market: values = (234, 714, 152)
        case .street: values = (4, 910, 164)
        case .hospital: values = (234, 910, 152)
        case .home: values = (118, 1200, 170)
        case .adoption: values = (12, 1420, 150)
        case .cafe: values = (166, 1620, 150)
        case .lot1: values = (258, 1420, 128)
        case .lot2: values = (4, 1620, 128)
        }
        return CGRect(x: values.0, y: values.1, width: values.2, height: values.2 + 24)
    }
    static func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour < 7 || hour >= 19
    }
}

@MainActor
struct TownMapStatus {
    let snapshot: GameSnapshot?
    var hasNewTownActivity: Bool {
        guard let snapshot else { return false }
        return snapshot.community.events.todayReceipt == nil && TownEventCatalog.current(in: snapshot) != nil
    }
    var sickCount: Int { snapshot?.cats.filter { $0.healthState?.illness != nil }.count ?? 0 }
    var availableAdoptions: [CatAdoptionOffer] {
        guard let snapshot else { return [] }
        return CatCatalog.adoptionOffers.filter { offer in
            !snapshot.cats.contains { $0.id == offer.id }
                && snapshot.player.level >= offer.requiredPlayerLevel
                && snapshot.home.roomLevel >= offer.requiredRoomLevel
                && snapshot.player.gold >= offer.price
        }
    }
    var unvisitedNeighbors: [NeighborDefinition] {
        guard let snapshot else { return [] }
        return CommunityCatalog.neighbors.filter { !snapshot.community.relationship(for: $0.id).visitedToday }
    }
    var availableExchanges: Int {
        guard let snapshot else { return 0 }
        return ExchangeCatalog.offers.filter { ExchangeCatalog.eligibility(of: $0, in: snapshot) == nil }.count
    }
    var exhaustedExchanges: Bool {
        guard let snapshot else { return false }
        return CommunityCatalog.neighbors.allSatisfy { snapshot.community.exchangeCount(for: $0.id).remainingToday == 0 }
    }
    func badge(for place: TownPlace, now: Date) -> String? {
        if place.isFuture { return GameStrings.text("town.comingSoon") }
        switch place {
        case .plaza, .board:
            guard let snapshot else { return nil }
            if snapshot.community.events.todayReceipt != nil { return GameStrings.text("townEvents.completed") }
            return TownEventCatalog.current(in: snapshot) == nil ? nil : GameStrings.text("townEvents.available")
        case .hospital where sickCount > 0: return GameStrings.format("town.sickCount", sickCount)
        case .street where !unvisitedNeighbors.isEmpty: return GameStrings.format("townMap.visitCount", unvisitedNeighbors.count)
        case .adoption where !availableAdoptions.isEmpty: return GameStrings.format("townMap.adoptionCount", availableAdoptions.count)
        case .market:
            if availableExchanges > 0 { return GameStrings.format("market.availableCount", availableExchanges) }
            return exhaustedExchanges ? GameStrings.text("townMap.exchangedToday") : nil
        case .work:
            guard let active = snapshot?.player.activeWork else { return nil }
            let remaining = max(0, Int(ceil(active.endsAt.timeIntervalSince(max(now, snapshot?.meta.lastSyncAt ?? now)))))
            if remaining == 0 { return GameStrings.text("townMap.workReady") }
            return GameStrings.format("townMap.working", String(format: "%02d:%02d", remaining / 60, remaining % 60))
        default: return nil
        }
    }
    func badgeTint(for place: TownPlace) -> Color {
        if place.isFuture { return RoomTheme.lilac }
        switch place {
        case .plaza, .board: return snapshot?.community.events.todayReceipt == nil ? RoomTheme.friendship : RoomTheme.secondary
        case .hospital: return RoomTheme.coral
        case .street: return RoomTheme.friendship
        case .work: return RoomTheme.gold
        case .market where exhaustedExchanges: return RoomTheme.secondary
        default: return RoomTheme.mint
        }
    }
}
