import Foundation

public enum CatBehaviorStyle: String, Codable, CaseIterable, Sendable {
    case playful, curious, quiet
}

public enum CatRestPreference: String, Codable, CaseIterable, Sendable {
    case bed, cushion
    public var furnitureKind: FurnitureKind { self == .bed ? .catBed : .floorCushion }
    public init?(kind: FurnitureKind) {
        switch kind { case .catBed: self = .bed; case .floorCushion: self = .cushion; default: return nil }
    }
}

public enum CatPlayRhythm: String, Codable, CaseIterable, Sendable {
    case slowMove, moveAndPause
}

public struct CatHabitDefinition: Equatable, Sendable, Identifiable {
    public let id: String
    public let style: CatBehaviorStyle
    public let rest: CatRestPreference
    public let play: CatPlayRhythm
}

public enum CatHabitCatalog {
    public static let all: [CatHabitDefinition] = [
        .init(id: CatCatalog.initialCatID, style: .playful, rest: .cushion, play: .moveAndPause),
        .init(id: CatCatalog.cowCatID, style: .curious, rest: .bed, play: .slowMove),
        .init(id: CatCatalog.blueCatID, style: .quiet, rest: .cushion, play: .slowMove),
        .init(id: CatCatalog.siameseCatID, style: .playful, rest: .bed, play: .moveAndPause),
        .init(id: CatCatalog.silverCatID, style: .curious, rest: .cushion, play: .moveAndPause)
    ]
    public static func definition(for catID: String) -> CatHabitDefinition? { all.first { $0.id == catID } }
    public static let cluesToConfirm = 2
    public static let playDuration: TimeInterval = 20
    public static let responseDuration: TimeInterval = 2
    public static let pauseResponseDuration: TimeInterval = 1.25
}

public enum CatMemoryKind: String, Codable, CaseIterable, Sendable {
    case firstResponse, favoriteRest, favoritePlay, littleCorner, settledAfterMove, understandEachOther
    public var isPinnable: Bool { [.favoritePlay, .littleCorner, .settledAfterMove].contains(self) }
    public var titleKey: String { "catMemories.\(rawValue).title" }
    public var bodyKey: String { "catMemories.\(rawValue).body" }
}

public struct CatMemory: Codable, Equatable, Sendable, Identifiable {
    public let kind: CatMemoryKind
    public let createdAt: Date
    public var id: String { kind.rawValue }
}
