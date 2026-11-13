import Foundation

/// The first five careers retain the web game's base values; higher tiers are
/// native additions. Random events and need-dependent modifiers are separate.
public struct WorkJob: Identifiable, Equatable, Sendable {
    public let id: String
    public let unlockLevel: Int
    public let durationMinutes: Int
    public let staminaCost: Int
    public let moodCost: Int
    public let goldReward: Int
    public let expReward: Int
}

public enum WorkCatalog {
    public static let all: [WorkJob] = [
        .init(id: "job_flyer", unlockLevel: 1, durationMinutes: 2,
              staminaCost: 10, moodCost: 5, goldReward: 60, expReward: 22),
        .init(id: "job_store", unlockLevel: 2, durationMinutes: 3,
              staminaCost: 15, moodCost: 8, goldReward: 100, expReward: 35),
        .init(id: "job_petshop", unlockLevel: 4, durationMinutes: 4,
              staminaCost: 20, moodCost: 12, goldReward: 160, expReward: 52),
        .init(id: "job_it_engineer", unlockLevel: 6, durationMinutes: 10,
              staminaCost: 30, moodCost: 12, goldReward: 400, expReward: 100),
        .init(id: "job_cat_cafe_manager", unlockLevel: 10, durationMinutes: 30,
              staminaCost: 50, moodCost: 20, goldReward: 800, expReward: 200),
        .init(id: "job_pet_photographer", unlockLevel: 15, durationMinutes: 45,
              staminaCost: 65, moodCost: 24, goldReward: 1_400, expReward: 320),
        .init(id: "job_pet_brand_designer", unlockLevel: 20, durationMinutes: 60,
              staminaCost: 80, moodCost: 28, goldReward: 2_000, expReward: 450)
    ]

    public static func job(id: String) -> WorkJob? {
        all.first { $0.id == id }
    }

    /// Returns zero for an unrepresentable level rather than overflowing.
    public static func requiredExperience(forLevel level: Int) -> Int {
        guard level > 0 else { return 0 }
        let (required, overflow) = level.multipliedReportingOverflow(by: 100)
        return overflow ? 0 : required
    }

    static func validProgress(level: Int, exp: Int) -> Bool {
        let needed = requiredExperience(forLevel: level)
        return needed > 0 && exp >= 0 && exp < needed
    }

    /// Apply points across level boundaries without constructing a potentially
    /// overflowing total. There is no artificial gameplay level cap.
    static func progress(level: Int, exp: Int, adding reward: Int) -> (level: Int, exp: Int)? {
        guard validProgress(level: level, exp: exp), reward >= 0 else { return nil }
        var level = level
        var exp = exp
        var remaining = reward
        while remaining > 0 {
            let needed = requiredExperience(forLevel: level) - exp
            if remaining < needed {
                exp += remaining
                remaining = 0
            } else {
                remaining -= needed
                level += 1 // Valid levels are at most Int.max / 100.
                exp = 0
                guard requiredExperience(forLevel: level) > 0 else { return nil }
            }
        }
        return (level, exp)
    }
}

/// A durable receipt, not an unclaimed reward. Gold and experience have already
/// been applied in the same save that creates this result.
public struct WorkResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var jobID: String
    public var completedAt: Date
    public var goldReward: Int
    public var expReward: Int
    public var levelBefore: Int
    public var levelAfter: Int
    public var expAfter: Int

    public init(id: String, jobID: String, completedAt: Date,
                goldReward: Int, expReward: Int, levelBefore: Int,
                levelAfter: Int, expAfter: Int) {
        self.id = id
        self.jobID = jobID
        self.completedAt = completedAt
        self.goldReward = goldReward
        self.expReward = expReward
        self.levelBefore = levelBefore
        self.levelAfter = levelAfter
        self.expAfter = expAfter
    }

    public var newlyUnlockedJobIDs: [String] {
        WorkCatalog.all.filter { $0.unlockLevel > levelBefore && $0.unlockLevel <= levelAfter }.map(\.id)
    }
}
