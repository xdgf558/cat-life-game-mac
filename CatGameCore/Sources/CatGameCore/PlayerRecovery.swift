import Foundation

/// Stamina and mood gained from one recovery. Interfaces only read these values.
public struct RecoveryEffect: Equatable, Sendable {
    public let stamina: Int
    public let mood: Int
    public init(stamina: Int = 0, mood: Int = 0) { self.stamina = stamina; self.mood = mood }

    /// Points actually gained without passing 100, per attribute.
    public func applied(to player: PlayerState) -> RecoveryEffect {
        RecoveryEffect(stamina: min(stamina, max(0, 100 - player.stamina)), mood: min(mood, max(0, 100 - player.mood)))
    }
    /// A recovery is useful while any attribute it raises is below 100.
    public func isUseful(for player: PlayerState) -> Bool {
        let gained = applied(to: player)
        return gained.stamina > 0 || gained.mood > 0
    }
    public var total: Int { stamina + mood }
}

/// Carried snacks the player eats; separate from the cats' food and litter.
public enum PlayerSupplyKind: String, Codable, CaseIterable, Hashable, Sendable {
    case riceBall, flowerTea, dessert
}

public struct PlayerSupplyDefinition: Identifiable, Equatable, Sendable {
    public let kind: PlayerSupplyKind
    public let price: Int
    public let effect: RecoveryEffect
    public let symbol: String
    public var id: PlayerSupplyKind { kind }
    public var nameKey: String { "supply.player.\(kind.rawValue).name" }
    public var detailKey: String { "supply.player.\(kind.rawValue).detail" }
    public var assetName: String { "supply-player-\(kind.rawValue)" }
    /// Tea is drunk; the others are eaten.
    public var isDrink: Bool { kind == .flowerTea }
}

/// Dine-in café items: they count toward the daily supply limit but cannot be carried home.
public enum CafeItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case latte, pancake
}

public struct CafeMenuItem: Identifiable, Equatable, Sendable {
    public let kind: CafeItemKind
    public let price: Int
    public let effect: RecoveryEffect
    public let symbol: String
    public var id: CafeItemKind { kind }
    public var nameKey: String { "cafe.menu.\(kind.rawValue).name" }
    public var detailKey: String { "cafe.menu.\(kind.rawValue).detail" }
    public var assetName: String { "cafe-\(kind.rawValue)" }
    public var isDrink: Bool { kind == .latte }
}

/// Recovery tuning lives here (handoff values are suggestions); views never hard-code numbers.
public enum PlayerSupplyCatalog {
    public static let all: [PlayerSupplyDefinition] = [
        .init(kind: .riceBall, price: 120, effect: .init(stamina: 25), symbol: "triangle.fill"),
        .init(kind: .flowerTea, price: 90, effect: .init(mood: 20), symbol: "cup.and.saucer.fill"),
        .init(kind: .dessert, price: 110, effect: .init(stamina: 10, mood: 12), symbol: "birthday.cake.fill"),
    ]
    public static let maxCarried = 5
    /// Shared by carried supplies and café dine-in items; resets with the real calendar day.
    public static let dailyLimit = 3

    public static func definition(_ kind: PlayerSupplyKind) -> PlayerSupplyDefinition {
        all.first { $0.kind == kind }!
    }
}

public enum CafeCatalog {
    public static let menu: [CafeMenuItem] = [
        .init(kind: .latte, price: 60, effect: .init(mood: 15), symbol: "mug.fill"),
        .init(kind: .pancake, price: 80, effect: .init(stamina: 12, mood: 8), symbol: "pawprint.fill"),
    ]
    public static let napPrice = 50
    public static let napDuration: TimeInterval = 15 * 60
    public static let napEffect = RecoveryEffect(stamina: 30, mood: 10)
    public static let napsPerDay = 1
    /// Opening hours in the player's local time: [openHour, closeHour).
    public static let openHour = 10
    public static let closeHour = 22

    public static func item(_ kind: CafeItemKind) -> CafeMenuItem { menu.first { $0.kind == kind }! }
    public static func isOpen(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= openHour && hour < closeHour
    }
}

/// Today's recovery usage; stale days read as zero, so no reset write is needed.
public struct PlayerRecoveryDay: Codable, Equatable, Sendable {
    public var dayKey: String?
    public var suppliesUsed: Int
    public var napUsed: Bool
    public init(dayKey: String? = nil, suppliesUsed: Int = 0, napUsed: Bool = false) {
        self.dayKey = dayKey; self.suppliesUsed = suppliesUsed; self.napUsed = napUsed
    }
}

public struct PlayerNap: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var startedAt: Date
    public var endsAt: Date
    public var effect: RecoveryEffectRecord
    public init(id: String = UUID().uuidString, startedAt: Date, endsAt: Date, effect: RecoveryEffectRecord) {
        self.id = id; self.startedAt = startedAt; self.endsAt = endsAt; self.effect = effect
    }
    public var duration: TimeInterval { endsAt.timeIntervalSince(startedAt) }
}

/// Codable copy of an effect, so later catalog tuning never rewrites a nap already in progress.
public struct RecoveryEffectRecord: Codable, Equatable, Sendable {
    public var stamina: Int
    public var mood: Int
    public init(_ effect: RecoveryEffect) { stamina = effect.stamina; mood = effect.mood }
    public var effect: RecoveryEffect { RecoveryEffect(stamina: stamina, mood: mood) }
}

/// The last finished nap, for the café's "awake" card. Purely presentational history.
public struct PlayerNapResult: Codable, Equatable, Sendable {
    public var napID: String
    public var finishedAt: Date
    public var gained: RecoveryEffectRecord
    public var early: Bool
}

/// Receipt for one supply or café order: only the points that item granted, after the
/// transaction's own synchronization, so natural regeneration is never credited to it.
public struct PlayerRecoveryReceipt: Codable, Equatable, Sendable {
    public var id: String
    /// `supply.<kind>` or `cafe.<kind>`.
    public var source: String
    public var gained: RecoveryEffectRecord
    public var at: Date
    public init(id: String = UUID().uuidString, source: String, gained: RecoveryEffect, at: Date) {
        self.id = id; self.source = source; self.gained = RecoveryEffectRecord(gained); self.at = at
    }
    public static func source(_ kind: PlayerSupplyKind) -> String { "supply.\(kind.rawValue)" }
    public static func source(_ kind: CafeItemKind) -> String { "cafe.\(kind.rawValue)" }
}

extension PlayerState {
    public func carried(_ kind: PlayerSupplyKind) -> Int { supplies[kind.rawValue] ?? 0 }
}

extension GameSnapshot {
    /// Supplies and dine-in items eaten today (zero once the real day has changed).
    public var suppliesUsedToday: Int {
        player.recoveryDay.dayKey == tasks.dailyDayKey ? player.recoveryDay.suppliesUsed : 0
    }
    public var napUsedToday: Bool {
        player.recoveryDay.dayKey == tasks.dailyDayKey && player.recoveryDay.napUsed
    }
    public var suppliesLeftToday: Int { max(0, PlayerSupplyCatalog.dailyLimit - suppliesUsedToday) }

    mutating func recordRecovery(supply: Bool = false, nap: Bool = false) {
        if player.recoveryDay.dayKey != tasks.dailyDayKey {
            player.recoveryDay = PlayerRecoveryDay(dayKey: tasks.dailyDayKey)
        }
        if supply { player.recoveryDay.suppliesUsed += 1 }
        if nap { player.recoveryDay.napUsed = true }
    }

    var playerRecoveryIsValid: Bool {
        guard player.supplies.allSatisfy({ PlayerSupplyKind(rawValue: $0.key) != nil && (0...PlayerSupplyCatalog.maxCarried).contains($0.value) }),
              (0...PlayerSupplyCatalog.dailyLimit).contains(player.recoveryDay.suppliesUsed),
              player.recoveryDay.dayKey != nil || (player.recoveryDay.suppliesUsed == 0 && !player.recoveryDay.napUsed)
        else { return false }
        if let nap = player.activeNap {
            guard player.activeWork == nil, player.activeSleep == nil,
                  [nap.startedAt, nap.endsAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
                  nap.endsAt > nap.startedAt, nap.duration <= 24 * 3600,
                  (0...100).contains(nap.effect.stamina), (0...100).contains(nap.effect.mood) else { return false }
        }
        return true
    }
}

extension GameEngine {
    public static func buyPlayerSupply(_ state: inout GameSnapshot, kind: PlayerSupplyKind, quantity: Int = 1,
                                       now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard (1...PlayerSupplyCatalog.maxCarried).contains(quantity) else { return .init(failure: .shopInvalidQuantity) }
        let supply = PlayerSupplyCatalog.definition(kind)
        guard state.player.carried(kind) + quantity <= PlayerSupplyCatalog.maxCarried else {
            return .init(failure: .supplyCarryLimit, amount: PlayerSupplyCatalog.maxCarried)
        }
        let cost = supply.price * quantity
        guard state.player.gold >= cost else { return .init(failure: .shopGoldRequired, amount: cost) }
        state.player.gold -= cost
        state.player.supplies[kind.rawValue] = state.player.carried(kind) + quantity
        return .init(success: .playerSupplyPurchased, amount: quantity)
    }

    /// Full attributes never waste an item or a daily portion. Overflow needs `allowingWaste`, checked
    /// against the synchronized state, so regeneration landing at the same moment can't slip past the confirm.
    public static func usePlayerSupply(_ state: inout GameSnapshot, kind: PlayerSupplyKind, allowingWaste: Bool = false,
                                       now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard state.player.carried(kind) > 0 else { return .init(failure: .supplyNone) }
        guard state.suppliesLeftToday > 0 else { return .init(failure: .recoveryDailyLimit) }
        let effect = PlayerSupplyCatalog.definition(kind).effect
        guard effect.isUseful(for: state.player) else { return .init(failure: .recoveryFull) }
        let gained = effect.applied(to: state.player)
        let waste = effect.total - gained.total
        guard waste == 0 || allowingWaste else { return .init(failure: .recoveryWouldWaste, amount: waste) }
        let timestamp = effectiveTime(state, now: now)
        apply(gained, to: &state, at: timestamp)
        state.player.supplies[kind.rawValue] = state.player.carried(kind) - 1
        state.recordRecovery(supply: true)
        state.player.lastRecoveryReceipt = PlayerRecoveryReceipt(source: PlayerRecoveryReceipt.source(kind), gained: gained, at: timestamp)
        return .init(success: .playerSupplyUsed, amount: gained.total)
    }

    public static func orderCafeItem(_ state: inout GameSnapshot, kind: CafeItemKind, allowingWaste: Bool = false,
                                     now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        let timestamp = effectiveTime(state, now: now)
        guard CafeCatalog.isOpen(at: timestamp) else { return .init(failure: .cafeClosed) }
        guard state.suppliesLeftToday > 0 else { return .init(failure: .recoveryDailyLimit) }
        let item = CafeCatalog.item(kind)
        guard item.effect.isUseful(for: state.player) else { return .init(failure: .recoveryFull) }
        guard state.player.gold >= item.price else { return .init(failure: .shopGoldRequired, amount: item.price) }
        let gained = item.effect.applied(to: state.player)
        let waste = item.effect.total - gained.total
        guard waste == 0 || allowingWaste else { return .init(failure: .recoveryWouldWaste, amount: waste) }
        state.player.gold -= item.price
        apply(gained, to: &state, at: timestamp)
        state.recordRecovery(supply: true)
        state.player.lastRecoveryReceipt = PlayerRecoveryReceipt(source: PlayerRecoveryReceipt.source(kind), gained: gained, at: timestamp)
        return .init(success: .cafeOrdered, amount: gained.total)
    }

    public static func startCafeNap(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        let timestamp = effectiveTime(state, now: now)
        guard state.player.activeNap == nil else { return .init(failure: .cafeNapActive) }
        guard CafeCatalog.isOpen(at: timestamp) else { return .init(failure: .cafeClosed) }
        guard state.player.activeWork == nil else { return .init(failure: .cafeNapWorking) }
        guard state.player.activeSleep == nil else { return .init(failure: .cafeNapSleeping) }
        guard !state.napUsedToday else { return .init(failure: .cafeNapUsed) }
        guard CafeCatalog.napEffect.isUseful(for: state.player) else { return .init(failure: .recoveryFull) }
        guard state.player.gold >= CafeCatalog.napPrice else { return .init(failure: .shopGoldRequired, amount: CafeCatalog.napPrice) }
        state.player.gold -= CafeCatalog.napPrice
        state.player.activeNap = PlayerNap(startedAt: timestamp, endsAt: timestamp.addingTimeInterval(CafeCatalog.napDuration),
                                           effect: RecoveryEffectRecord(CafeCatalog.napEffect))
        state.recordRecovery(nap: true)
        return .init(success: .cafeNapStarted)
    }

    /// Waking early grants the elapsed share (rounded down); the seat fee and today's nap stay used.
    public static func wakeFromCafeNap(_ state: inout GameSnapshot, now: Date = Date()) -> ActionOutcome {
        let synchronized = synchronize(&state, now: now)
        guard synchronized.succeeded else { return synchronized }
        guard let nap = state.player.activeNap else { return synchronized }
        settleNap(&state, nap: nap, at: effectiveTime(state, now: now), early: true)
        return .init(success: .cafeNapEnded, amount: state.player.lastNapResult?.gained.effect.total ?? 0)
    }

    /// Gain so far for a nap at `date` (full gain once due). Used by the café's live preview.
    public static func napGain(_ nap: PlayerNap, at date: Date) -> RecoveryEffect {
        let share = nap.duration > 0 ? min(1, max(0, date.timeIntervalSince(nap.startedAt) / nap.duration)) : 1
        return RecoveryEffect(stamina: Int(floor(Double(nap.effect.stamina) * share)),
                              mood: Int(floor(Double(nap.effect.mood) * share)))
    }

    /// Called from synchronize: a due nap completes with its full gain.
    static func settleDueNap(_ state: inout GameSnapshot, at timestamp: Date) {
        guard let nap = state.player.activeNap, timestamp >= nap.endsAt else { return }
        settleNap(&state, nap: nap, at: nap.endsAt, early: false)
    }

    private static func settleNap(_ state: inout GameSnapshot, nap: PlayerNap, at date: Date, early: Bool) {
        let gained = napGain(nap, at: date).applied(to: state.player)
        apply(gained, to: &state, at: date)
        state.player.activeNap = nil
        state.player.lastNapResult = PlayerNapResult(napID: nap.id, finishedAt: date,
                                                     gained: RecoveryEffectRecord(gained), early: early && date < nap.endsAt)
    }

    private static func apply(_ gained: RecoveryEffect, to state: inout GameSnapshot, at timestamp: Date) {
        let wasFull = state.player.stamina >= 100
        state.player.stamina = min(100, state.player.stamina + gained.stamina)
        state.player.mood = min(100, state.player.mood + gained.mood)
        // Natural regeneration restarts its hour from a refilled bar, as after work.
        if !wasFull, state.player.stamina >= 100 { state.player.staminaUpdatedAt = max(state.player.staminaUpdatedAt, timestamp) }
    }
}
