import Foundation

/// Captured at the visible, player-initiated arrival, never at an animation's completion.
public struct CatRestObservation: Codable, Equatable, Sendable {
    public let floor: HomeFloor
    public let position: NormalizedPoint
    public init(floor: HomeFloor, position: NormalizedPoint) { self.floor = floor; self.position = position }
    var isValid: Bool { GameSnapshot.isUnitPosition(position) }
    public func isMeaningfullyDifferent(from previous: CatRestObservation) -> Bool {
        // Ignore floating-point noise at the 15% boundary.
        floor != previous.floor || hypot(position.x - previous.position.x, position.y - previous.position.y) > 0.15 + 1e-9
    }
}

public struct CatRestObservationReceipt: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let furnitureID: String
    public let kind: CatRestPreference
    public let location: CatRestObservation
    public let completedAt: Date
    public let matched: Bool
    var isValid: Bool {
        CatHabitState.validID(id) && CatHabitState.validID(furnitureID) && location.isValid
            && completedAt.timeIntervalSince1970.isFinite
    }
}

public struct CatPlayObservation: Codable, Equatable, Sendable {
    public let sessionID: String
    public let rhythm: CatPlayRhythm
    public let observedAt: Date
    public let matched: Bool
    var isValid: Bool { CatHabitState.validID(sessionID) && observedAt.timeIntervalSince1970.isFinite }
}


/// A real layout reference, not evidence that the cat visited it before this update.
public struct CatRestLocationRecord: Codable, Equatable, Sendable {
    public var reference: CatRestObservation
    public var visited: Bool
    public init(reference: CatRestObservation, visited: Bool = false) {
        self.reference = reference; self.visited = visited
    }
    var isValid: Bool { reference.isValid }
}

public struct CatHabitState: Codable, Equatable, Sendable {
    public var restClueSessionIDs: [String] = []
    public var playClueSessionIDs: [String] = []
    public var lastRestObservation: CatRestObservationReceipt?
    public var lastPlayObservation: CatPlayObservation?
    public var cornerFurnitureID: String?
    public var dismissedRestOfferID: String?
    public var memories: [CatMemory] = []
    public var restLocations: [String: CatRestLocationRecord] = [:]
    public var pinnedMemory: CatMemoryKind?
    public var pinnedHintCollapsed = false
    /// One pre-upgrade rest can finish P0 clues without inventing a new P1 memory.
    public var legacyRestSessionID: String?
    /// The next confirmed response; advance only in the existing durable input transaction.
    public var responseFinishIndex = 0
    public var lastResponseFinishIndex: Int { (responseFinishIndex + 1) % 2 }
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case restClueSessionIDs, playClueSessionIDs, lastRestObservation, lastPlayObservation
        case cornerFurnitureID, dismissedRestOfferID, memories
        case restLocations, pinnedMemory, pinnedHintCollapsed, responseFinishIndex, legacyRestSessionID
    }
    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }
    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        restClueSessionIDs = try values.decode([String].self, forKey: .restClueSessionIDs)
        playClueSessionIDs = try values.decode([String].self, forKey: .playClueSessionIDs)
        lastRestObservation = try values.decodeIfPresent(CatRestObservationReceipt.self, forKey: .lastRestObservation)
        lastPlayObservation = try values.decodeIfPresent(CatPlayObservation.self, forKey: .lastPlayObservation)
        cornerFurnitureID = try values.decodeIfPresent(String.self, forKey: .cornerFurnitureID)
        dismissedRestOfferID = try values.decodeIfPresent(String.self, forKey: .dismissedRestOfferID)
        memories = try values.decode([CatMemory].self, forKey: .memories)
        if schemaVersion >= 14 {
            restLocations = try values.decode([String: CatRestLocationRecord].self, forKey: .restLocations)
            guard values.contains(.pinnedMemory), values.contains(.legacyRestSessionID) else { throw SaveRepositoryError.invalidSnapshot }
            pinnedMemory = try values.decodeIfPresent(CatMemoryKind.self, forKey: .pinnedMemory)
            pinnedHintCollapsed = try values.decode(Bool.self, forKey: .pinnedHintCollapsed)
            responseFinishIndex = try values.decode(Int.self, forKey: .responseFinishIndex)
            legacyRestSessionID = try values.decodeIfPresent(String.self, forKey: .legacyRestSessionID)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(restClueSessionIDs, forKey: .restClueSessionIDs)
        try values.encode(playClueSessionIDs, forKey: .playClueSessionIDs)
        try values.encodeIfPresent(lastRestObservation, forKey: .lastRestObservation)
        try values.encodeIfPresent(lastPlayObservation, forKey: .lastPlayObservation)
        try values.encodeIfPresent(cornerFurnitureID, forKey: .cornerFurnitureID)
        try values.encodeIfPresent(dismissedRestOfferID, forKey: .dismissedRestOfferID)
        try values.encode(memories, forKey: .memories)
        try values.encode(restLocations, forKey: .restLocations)
        if let pinnedMemory { try values.encode(pinnedMemory, forKey: .pinnedMemory) }
        else { try values.encodeNil(forKey: .pinnedMemory) }
        try values.encode(pinnedHintCollapsed, forKey: .pinnedHintCollapsed)
        try values.encode(responseFinishIndex, forKey: .responseFinishIndex)
        if let legacyRestSessionID { try values.encode(legacyRestSessionID, forKey: .legacyRestSessionID) }
        else { try values.encodeNil(forKey: .legacyRestSessionID) }
    }

    public func needsRestIntroduction(furnitureID: String, location: CatRestObservation) -> Bool {
        guard let known = restLocations[furnitureID] else { return true }
        return !known.visited || location.isMeaningfullyDifferent(from: known.reference)
    }

    mutating func seedRestLocations(home: HomeState, inventory: InventoryState) {
        for placement in home.furniture where restLocations[placement.itemID] == nil {
            guard inventory.furniture.contains(where: {
                $0.id == placement.itemID && CatRestPreference(kind: $0.kind) != nil
            }) else { continue }
            restLocations[placement.itemID] = CatRestLocationRecord(
                reference: .init(floor: placement.floor, position: placement.position))
        }
    }
    public var restConfirmed: Bool { restClueSessionIDs.count >= CatHabitCatalog.cluesToConfirm }
    public var playConfirmed: Bool { playClueSessionIDs.count >= CatHabitCatalog.cluesToConfirm }

    mutating func remember(_ kind: CatMemoryKind, at date: Date) {
        guard !memories.contains(where: { $0.kind == kind }) else { return }
        memories.append(CatMemory(kind: kind, createdAt: date))
    }
    static func validID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 128
    }
    var isValid: Bool {
        [restClueSessionIDs, playClueSessionIDs].allSatisfy {
            $0.count <= CatHabitCatalog.cluesToConfirm && Set($0).count == $0.count && $0.allSatisfy(Self.validID)
        } && (lastRestObservation?.isValid ?? true) && (lastPlayObservation?.isValid ?? true)
            && (cornerFurnitureID.map(Self.validID) ?? true)
            && (dismissedRestOfferID.map(Self.validID) ?? true)
            && memories.count <= CatMemoryKind.allCases.count && Set(memories.map(\.kind)).count == memories.count
            && memories.allSatisfy { $0.createdAt.timeIntervalSince1970.isFinite }
            && (!memories.contains { $0.kind == .favoriteRest } || restConfirmed)
            && (!memories.contains { $0.kind == .favoritePlay } || playConfirmed)
            && restLocations.allSatisfy { Self.validID($0.key) && $0.value.isValid }
            && (pinnedMemory.map(\.isPinnable) ?? true)
            && (pinnedMemory != nil || !pinnedHintCollapsed)
            && (0..<2).contains(responseFinishIndex)
            && (legacyRestSessionID.map(Self.validID) ?? true)
            && (!memories.contains { $0.kind == .understandEachOther }
                || (restConfirmed && playConfirmed && memories.contains { $0.kind == .littleCorner }))
    }
}
