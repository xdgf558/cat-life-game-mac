import Foundation

public enum CatSex: String, Codable, CaseIterable, Sendable {
    case male, female
}

public enum CatGrowthStage: String, CaseIterable, Sendable {
    case kitten, junior, adult

    public var minimumAgeDays: Int {
        switch self {
        case .kitten: 0
        case .junior: 180
        case .adult: 365
        }
    }

    public var next: Self? {
        switch self {
        case .kitten: .junior
        case .junior: .adult
        case .adult: nil
        }
    }
}

public enum CatBondStage: String, CaseIterable, Sendable {
    case newFriend, familiar, trusted, close

    public static func stage(for intimacy: Int) -> Self {
        allCases.last(where: { intimacy >= $0.minimumIntimacy }) ?? .newFriend
    }

    public var minimumIntimacy: Int {
        switch self {
        case .newFriend: 0
        case .familiar: 25
        case .trusted: 50
        case .close: 75
        }
    }

    public var next: Self? {
        switch self {
        case .newFriend: .familiar
        case .familiar: .trusted
        case .trusted: .close
        case .close: nil
        }
    }
}

/// Catalog ages are game settings, never inferred birthdays or adoption dates.
public enum CatGrowthCatalog {
    public static let ageMultiplier = 10

    public static func initialAgeDays(for appearance: CatAppearance) -> Int {
        switch appearance {
        case .orange, .silver: 90
        case .cow, .siamese: 180
        case .blue: 365
        }
    }

    public static func sex(for appearance: CatAppearance) -> CatSex {
        switch appearance {
        case .orange, .blue, .siamese: .male
        case .cow, .silver: .female
        }
    }
}

/// Immutable anchors avoid additional save writes as age and companionship advance.
public struct CatGrowthState: Codable, Equatable, Sendable {
    static let maximumTrackedDays = 1_000_000_000
    public let recordedSince: Date
    public let adoptedAt: Date?
    public let initialAgeDays: Int
    public let sex: CatSex
    public let isLegacyRecord: Bool

    public init(recordedSince: Date, adoptedAt: Date?, initialAgeDays: Int, sex: CatSex) {
        self.recordedSince = recordedSince
        self.adoptedAt = adoptedAt
        self.initialAgeDays = initialAgeDays
        self.sex = sex
        self.isLegacyRecord = adoptedAt == nil
    }

    public static func adopted(appearance: CatAppearance, now: Date) -> Self {
        Self(recordedSince: now, adoptedAt: now,
             initialAgeDays: CatGrowthCatalog.initialAgeDays(for: appearance),
             sex: CatGrowthCatalog.sex(for: appearance))
    }

    public static func legacy(appearance: CatAppearance, now: Date, isPregnant: Bool = false) -> Self {
        Self(recordedSince: now, adoptedAt: nil,
             initialAgeDays: CatGrowthCatalog.initialAgeDays(for: appearance),
             // Pre-growth saves had pregnancy but no sex; preserve that established state.
             sex: isPregnant ? .female : CatGrowthCatalog.sex(for: appearance))
    }

    /// Pass the snapshot's monotonic lastSyncAt, not the device clock.
    public func ageDays(at date: Date) -> Int {
        let elapsed = days(since: recordedSince, at: date, multiplier: CatGrowthCatalog.ageMultiplier)
        let initial = min(Self.maximumTrackedDays, max(0, initialAgeDays))
        return min(Self.maximumTrackedDays, initial + elapsed)
    }

    public func stage(at date: Date) -> CatGrowthStage {
        let age = ageDays(at: date)
        return CatGrowthStage.allCases.last(where: { age >= $0.minimumAgeDays }) ?? .kitten
    }

    public func companionshipDays(at date: Date) -> Int {
        days(since: adoptedAt ?? recordedSince, at: date)
    }

    var isValid: Bool {
        recordedSince.timeIntervalSince1970.isFinite && (0...36_500).contains(initialAgeDays)
            && isLegacyRecord == (adoptedAt == nil)
            && (adoptedAt.map { $0.timeIntervalSince1970.isFinite && $0 <= recordedSince } ?? true)
    }

    private func days(since start: Date, at date: Date, multiplier: Int = 1) -> Int {
        let elapsed = date.timeIntervalSince(start)
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        return Int(min(Double(Self.maximumTrackedDays), (elapsed / 86_400 * Double(multiplier)).rounded(.down)))
    }
}
