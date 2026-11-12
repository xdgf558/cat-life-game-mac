import Foundation

public enum CatIllness: String, Codable, CaseIterable, Sendable {
    case cold, stomachache, skinProblem
}

public struct CatIllnessDefinition: Equatable, Sendable {
    public let nameKey: String
    public let detailKey: String
    public let treatmentCost: Int
}

public enum CatHealthCatalog {
    public static let evaluationInterval: TimeInterval = 30 * 60
    public static let protectionDuration: TimeInterval = 24 * 60 * 60
    public static let maximumCatchUpInterval: TimeInterval = 6 * 60 * 60
    public static let illnessRiskThreshold = 8
    public static let lowNeedThreshold = 30
    public static let minimumIllnessHealth = 25
    public static let treatedHealth = 80

    public static func definition(for illness: CatIllness) -> CatIllnessDefinition {
        let cost: Int
        switch illness {
        case .cold: cost = 120
        case .stomachache: cost = 180
        case .skinProblem: cost = 260
        }
        return CatIllnessDefinition(nameKey: "health.illness.\(illness.rawValue).name",
            detailKey: "health.illness.\(illness.rawValue).detail", treatmentCost: cost)
    }
}

public struct CatHealthState: Codable, Equatable, Sendable {
    public var illness: CatIllness?
    public var riskPoints: Int
    public var lastEvaluatedAt: Date
    public var protectedUntil: Date

    public init(illness: CatIllness? = nil, riskPoints: Int = 0,
                lastEvaluatedAt: Date, protectedUntil: Date) {
        self.illness = illness
        self.riskPoints = riskPoints
        self.lastEvaluatedAt = lastEvaluatedAt
        self.protectedUntil = protectedUntil
    }

    public init(now: Date) {
        self.init(lastEvaluatedAt: now,
                  protectedUntil: now.addingTimeInterval(CatHealthCatalog.protectionDuration))
    }

    private enum CodingKeys: String, CodingKey { case illness, riskPoints, lastEvaluatedAt, protectedUntil }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Explicit null means healthy; a missing receipt must not silently erase an illness.
        guard values.contains(.illness) else {
            throw DecodingError.keyNotFound(CodingKeys.illness,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing cat illness state"))
        }
        illness = try values.decodeIfPresent(CatIllness.self, forKey: .illness)
        riskPoints = try values.decode(Int.self, forKey: .riskPoints)
        lastEvaluatedAt = try values.decode(Date.self, forKey: .lastEvaluatedAt)
        protectedUntil = try values.decode(Date.self, forKey: .protectedUntil)
        guard isValid else { throw SaveRepositoryError.invalidSnapshot }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(illness, forKey: .illness)
        try values.encode(riskPoints, forKey: .riskPoints)
        try values.encode(lastEvaluatedAt, forKey: .lastEvaluatedAt)
        try values.encode(protectedUntil, forKey: .protectedUntil)
    }

    var isValid: Bool {
        (0...CatHealthCatalog.illnessRiskThreshold).contains(riskPoints)
            && [lastEvaluatedAt, protectedUntil].allSatisfy { $0.timeIntervalSince1970.isFinite }
    }
}

enum CatHealthEngine {
    static func synchronize(_ cat: inout CatState, now: Date) {
        guard var health = cat.healthState else {
            // Existing saves begin here, never at their pre-upgrade last-played date.
            cat.healthState = CatHealthState(now: now)
            return
        }
        let cursor = max(health.lastEvaluatedAt, health.protectedUntil)
        let elapsed = now.timeIntervalSince(cursor)
        let interval = CatHealthCatalog.evaluationInterval
        guard elapsed >= interval else { return }
        guard elapsed.isFinite else {
            health.lastEvaluatedAt = now
            cat.healthState = health
            return
        }
        let count = Int(min(CatHealthCatalog.maximumCatchUpInterval / interval, floor(elapsed / interval)))
        // Advance needs at fixed checkpoints, including rest credits, before assessing risk.
        for step in 1...count {
            cat.healthState = health
            GameEngine.settleCatNeeds(&cat, now: cursor.addingTimeInterval(Double(step) * interval))
            health = cat.healthState ?? health
            if health.illness != nil {
                if cat.health > CatHealthCatalog.minimumIllnessHealth {
                    cat.health = max(CatHealthCatalog.minimumIllnessHealth, cat.health - 2)
                }
            } else {
                let needs: [(CatIllness, Int)] = [(.stomachache, cat.satiety),
                                                (.skinProblem, cat.cleanliness), (.cold, cat.energy)]
                let lowest = needs.min { $0.1 < $1.1 }!
                health.riskPoints = lowest.1 < CatHealthCatalog.lowNeedThreshold
                    ? min(CatHealthCatalog.illnessRiskThreshold, health.riskPoints + 1)
                    : max(0, health.riskPoints - 1)
                if health.riskPoints == CatHealthCatalog.illnessRiskThreshold { health.illness = lowest.0 }
            }
        }
        // Discard excess absence once while preserving the next fractional interval.
        health.lastEvaluatedAt = now.addingTimeInterval(-elapsed.truncatingRemainder(dividingBy: interval))
        cat.healthState = health
    }

    static func relieveRisk(_ cat: inout CatState, caringFor need: KeyPath<CatState, Int>, points: Int) {
        let value = cat[keyPath: need]
        guard var health = cat.healthState, health.illness == nil,
              value < CatHealthCatalog.lowNeedThreshold,
              value <= min(cat.satiety, min(cat.cleanliness, cat.energy)) else { return }
        health.riskPoints = max(0, health.riskPoints - points)
        cat.healthState = health
    }
}
