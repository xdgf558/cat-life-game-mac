import Foundation

public enum HomeFloor: String, Codable, CaseIterable, Hashable, Sendable {
    case ground, upper
}

/// Runtime layout limits are chosen by the host app, never stored in a backup.
public enum HomeLayoutRules: Equatable, Sendable {
    case standard, macDesktop

    var extraSlotsPerFloor: Int { self == .macDesktop ? 7 : 0 }
}

public struct HomeLevel: Identifiable, Equatable, Sendable {
    public let level: Int
    /// Total furniture capacity across all unlocked floors. Bowls do not count.
    public let capacity: Int
    public let worldScale: Double
    /// Gold required to enter this level; the initial room costs nothing.
    public let upgradeCost: Int
    public let requiredPlayerLevel: Int
    public var id: Int { level }
    public var floors: [HomeFloor] { level >= 6 ? [.ground, .upper] : [.ground] }
    public var floorCapacity: Int { capacity / floors.count }

    public func floorCapacity(using rules: HomeLayoutRules) -> Int { floorCapacity + rules.extraSlotsPerFloor }
    public func capacity(using rules: HomeLayoutRules) -> Int { floorCapacity(using: rules) * floors.count }
    public func capacity(on floor: HomeFloor, rules: HomeLayoutRules = .standard) -> Int {
        floors.contains(floor) ? floorCapacity(using: rules) : 0
    }
    public func worldScale(on floor: HomeFloor) -> Double? { floors.contains(floor) ? worldScale : nil }
}

public enum HomeCatalog {
    public static let all: [HomeLevel] = [
        .init(level: 1, capacity: 9, worldScale: 1, upgradeCost: 0, requiredPlayerLevel: 1),
        .init(level: 2, capacity: 12, worldScale: 1.25, upgradeCost: 450, requiredPlayerLevel: 2),
        .init(level: 3, capacity: 16, worldScale: 1.5, upgradeCost: 900, requiredPlayerLevel: 4),
        .init(level: 4, capacity: 20, worldScale: 1.65, upgradeCost: 1_600, requiredPlayerLevel: 6),
        .init(level: 5, capacity: 24, worldScale: 1.8, upgradeCost: 2_400, requiredPlayerLevel: 8),
        .init(level: 6, capacity: 48, worldScale: 1.8, upgradeCost: 3_600, requiredPlayerLevel: 10),
        .init(level: 7, capacity: 56, worldScale: 1.9, upgradeCost: 5_000, requiredPlayerLevel: 13),
        .init(level: 8, capacity: 64, worldScale: 2, upgradeCost: 7_000, requiredPlayerLevel: 16)
    ]

    public static func level(_ level: Int) -> HomeLevel? { all.first { $0.level == level } }

    public static func nextLevel(after current: Int) -> HomeLevel? {
        guard let index = all.firstIndex(where: { $0.level == current }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// Preserve pre-upgrade saves that already contain more items than today's
    /// limit. They can still be moved or put away; only new placements are gated.
    static func allowsLayout(_ proposed: [FurniturePlacement], replacing previous: [FurniturePlacement],
                             roomLevel: Int, rules: HomeLayoutRules = .standard) -> Bool {
        guard let room = level(roomLevel) else { return false }
        guard proposed.allSatisfy({ room.floors.contains($0.floor) }) else { return false }
        func allows(_ proposed: [FurniturePlacement], _ previous: [FurniturePlacement], limit: Int) -> Bool {
            if proposed.count <= limit { return true }
            let previousIDs = Set(previous.map(\.itemID))
            return proposed.allSatisfy { previousIDs.contains($0.itemID) }
        }
        guard allows(proposed, previous, limit: room.capacity(using: rules)) else { return false }
        return room.floors.allSatisfy { floor in
            allows(proposed.filter { $0.floor == floor }, previous.filter { $0.floor == floor },
                   limit: room.capacity(on: floor, rules: rules))
        }
    }
}
