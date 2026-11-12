import Foundation

public enum FurnitureKind: String, Codable, CaseIterable, Hashable, Sendable {
    case cabinet, catTree, catBed, wallFlower, wallCat, plant, floorCushion, flowerStool
    case bookcase, rattanChair, sideTable, wallSunrise, wallTownMemory

    public var supportsRotation: Bool { ![.wallFlower, .wallCat, .wallSunrise, .wallTownMemory].contains(self) }

}

public enum FurnitureOrientation: String, Codable, CaseIterable, Hashable, Sendable {
    case front, left, back, right

    public var turnedLeft: Self {
        switch self {
        case .front: .left
        case .left: .back
        case .back: .right
        case .right: .front
        }
    }

    public var turnedRight: Self {
        switch self {
        case .front: .right
        case .right: .back
        case .back: .left
        case .left: .front
        }
    }

    public var swapsFootprintAxes: Bool { self == .left || self == .right }

    /// Rotate a front-facing local offset in floor-grid axes: +x is right,
    /// +y is back, so front (0,-1) becomes left (-1,0).
    public func rotatedOffset(_ offset: CGPoint) -> CGPoint {
        switch self {
        case .front: offset
        case .left: CGPoint(x: offset.y, y: -offset.x)
        case .back: CGPoint(x: -offset.x, y: -offset.y)
        case .right: CGPoint(x: -offset.y, y: offset.x)
        }
    }

}

/// Ownership is independent of placement: putting an item away never deletes it.
public struct FurnitureItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: FurnitureKind
    public var orientation: FurnitureOrientation {
        didSet { usesLegacyFootprint = false }
    }
    public private(set) var usesLegacyFootprint = false

    public init(id: String, kind: FurnitureKind, orientation: FurnitureOrientation = .front) {
        self.id = id
        self.kind = kind
        self.orientation = orientation
    }

    private enum CodingKeys: String, CodingKey { case id, kind, orientation, usesLegacyFootprint }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(orientation, forKey: .orientation)
        try values.encode(usesLegacyFootprint, forKey: .usesLegacyFootprint)
    }

    /// Ignore only sub-pixel scene-coordinate round trips; keep saved coordinates
    /// and all floor/item references exact.
    public func applyingPlacement(from previous: FurniturePlacement?, to current: FurniturePlacement?) -> Self {
        var item = self
        let unchanged: Bool
        switch (previous, current) {
        case (nil, nil): unchanged = true
        case let (old?, new?):
            unchanged = old.itemID == new.itemID && old.floor == new.floor
                && abs(old.position.x - new.position.x) <= 0.000_001
                && abs(old.position.y - new.position.y) <= 0.000_001
        default: unchanged = false
        }
        if !unchanged { item.usesLegacyFootprint = false }
        return item
    }

    func usingCurrentFootprint() -> Self {
        var item = self
        item.usesLegacyFootprint = false
        return item
    }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }

    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(FurnitureKind.self, forKey: .kind)
        if schemaVersion < 6 && !values.contains(.orientation) {
            orientation = .front
        } else if schemaVersion < 15 {
            // Read the released vocabulary explicitly; accepting new strings here
            // would turn a damaged old snapshot into apparently valid progress.
            switch try values.decode(String.self, forKey: .orientation) {
            case "normal": orientation = .front
            case "mirrored": orientation = .left; usesLegacyFootprint = true
            default: throw SaveRepositoryError.invalidSnapshot
            }
        } else {
            orientation = try values.decode(FurnitureOrientation.self, forKey: .orientation)
            usesLegacyFootprint = try values.decode(Bool.self, forKey: .usesLegacyFootprint)
        }
        guard (orientation == .front || kind.supportsRotation),
              !usesLegacyFootprint || (orientation == .left && kind.supportsRotation) else {
            throw SaveRepositoryError.invalidSnapshot
        }
    }
}

/// Positions use the original 1024×1536 room artwork, normalized from its top left.
/// Floor items use their ground-contact center; wall art uses its image center.
public struct FurniturePlacement: Codable, Equatable, Identifiable, Sendable {
    public var itemID: String
    public var position: NormalizedPoint
    public var floor: HomeFloor
    public var id: String { itemID }

    public init(itemID: String, position: NormalizedPoint, floor: HomeFloor = .ground) {
        self.itemID = itemID
        self.position = position
        self.floor = floor
    }

    private enum CodingKeys: String, CodingKey { case itemID, position, floor }

    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, schemaVersion: GameSnapshot.currentSchemaVersion)
    }

    init(from decoder: Decoder, schemaVersion: Int) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try values.decode(String.self, forKey: .itemID)
        position = try values.decode(NormalizedPoint.self, forKey: .position)
        floor = schemaVersion < 10 && !values.contains(.floor)
            ? .ground : try values.decode(HomeFloor.self, forKey: .floor)
    }
}

/// Floor-grid dimensions. The existing front artwork projects one cell to
/// 128×64 points; swapping grid axes therefore retains the room's perspective.
public struct FurnitureFootprint: Equatable, Sendable {
    public let width: Double
    public let depth: Double

    public init(width: Double, depth: Double) {
        self.width = width
        self.depth = depth
    }

    public func rotated(for orientation: FurnitureOrientation) -> Self {
        orientation.swapsFootprintAxes ? .init(width: depth, depth: width) : self
    }

    public var artworkSize: CGSize { CGSize(width: width * 128, height: depth * 64) }
}

public struct FurnitureMetadata: Equatable, Sendable {
    public let kind: FurnitureKind
    public let isWall: Bool
    public let assetName: String
    public let nameKey: String
    public let footprint: FurnitureFootprint
    public let height: Double

    public func footprint(for orientation: FurnitureOrientation) -> FurnitureFootprint {
        isWall ? footprint : footprint.rotated(for: orientation)
    }
}

/// The food bowl keeps its existing independent field. Migrated mirrored items
/// retain these released collision sizes until explicitly moved or turned.
public enum FurnitureCatalog {
    public static var all: [FurnitureMetadata] { FurnitureKind.allCases.map { metadata(for: $0) } }

    public static func metadata(for kind: FurnitureKind) -> FurnitureMetadata {
        let asset: String
        switch kind {
        case .cabinet: asset = "furniture-cabinet"
        case .catTree: asset = "furniture-cat-tree"
        case .catBed: asset = "furniture-cat-bed"
        case .wallFlower: asset = "furniture-wall-flower"
        case .wallCat: asset = "furniture-wall-cat"
        case .plant: asset = "furniture-plant"
        case .floorCushion: asset = "furniture-floor-cushion"
        case .flowerStool: asset = "furniture-flower-stool"
        case .bookcase: asset = "furniture-bookcase"
        case .rattanChair: asset = "furniture-rattan-chair"
        case .sideTable: asset = "furniture-side-table"
        case .wallSunrise: asset = "furniture-wall-sunrise"
        case .wallTownMemory: asset = "furniture-town-memory-frame"
        }
        let dimensions: (width: Double, depth: Double, height: Double)
        switch kind {
        case .cabinet: dimensions = (186, 78, 1.5)
        case .catTree: dimensions = (160, 82, 3.9)
        case .catBed: dimensions = (292, 144, 0.6)
        case .plant: dimensions = (70, 42, 2)
        case .floorCushion: dimensions = (154, 80, 0.3)
        case .flowerStool: dimensions = (126, 68, 0.95)
        case .bookcase: dimensions = (190, 76, 2.4)
        case .rattanChair: dimensions = (158, 88, 1.9)
        case .sideTable: dimensions = (136, 72, 1.2)
        case .wallFlower: dimensions = (110, 170, 0)
        case .wallCat: dimensions = (108, 148, 0)
        case .wallSunrise: dimensions = (104, 178, 0)
        case .wallTownMemory: dimensions = (132, 126, 0)
        }
        return FurnitureMetadata(kind: kind, isWall: !kind.supportsRotation,
                                 assetName: asset, nameKey: "furniture.\(kind.rawValue)",
                                 footprint: .init(width: dimensions.width / 128, depth: dimensions.depth / 64),
                                 height: dimensions.height)
    }

    public static func footprint(for item: FurnitureItem) -> FurnitureFootprint {
        let footprint = metadata(for: item.kind).footprint(for: item.usesLegacyFootprint ? .front : item.orientation)
        let factor = item.kind == .plant && item.id == "plantSmall" ? 0.78 : 1
        return .init(width: footprint.width * factor, depth: footprint.depth * factor)
    }

    public static let defaultItems: [FurnitureItem] = [
        .init(id: "cabinet", kind: .cabinet),
        .init(id: "catTree", kind: .catTree),
        .init(id: "catBed", kind: .catBed),
        .init(id: "wallFlower", kind: .wallFlower),
        .init(id: "wallCat", kind: .wallCat),
        .init(id: "plantLarge", kind: .plant),
        .init(id: "plantSmall", kind: .plant),
        .init(id: "floorCushion", kind: .floorCushion),
        .init(id: "flowerStool", kind: .flowerStool)
    ]

    static let legacyPlacementsV6: [FurniturePlacement] = [
        .init(itemID: "cabinet", position: .init(x: 0.5, y: 0.425)),
        .init(itemID: "catTree", position: .init(x: 0.84, y: 0.6)),
        .init(itemID: "catBed", position: .init(x: 0.27, y: 0.6)),
        .init(itemID: "wallFlower", position: .init(x: 0.625, y: 0.25)),
        .init(itemID: "wallCat", position: .init(x: 0.77, y: 0.31)),
        .init(itemID: "plantLarge", position: .init(x: 0.32, y: 0.445)),
        .init(itemID: "plantSmall", position: .init(x: 0.88, y: 0.68)),
        .init(itemID: "floorCushion", position: .init(x: 0.22, y: 0.7)),
        .init(itemID: "flowerStool", position: .init(x: 0.25, y: 0.78))
    ]

    static let frontPlacementsV13: [FurniturePlacement] = [
        .init(itemID: "cabinet", position: .init(x: 0.58, y: 0.47)),
        .init(itemID: "catTree", position: .init(x: 0.835, y: 0.64)),
        .init(itemID: "catBed", position: .init(x: 0.285, y: 0.635)),
        .init(itemID: "wallFlower", position: .init(x: 0.54, y: 0.22)),
        .init(itemID: "wallCat", position: .init(x: 0.655, y: 0.245)),
        .init(itemID: "plantLarge", position: .init(x: 0.18, y: 0.54)),
        .init(itemID: "plantSmall", position: .init(x: 0.90, y: 0.76)),
        .init(itemID: "floorCushion", position: .init(x: 0.25, y: 0.74)),
        .init(itemID: "flowerStool", position: .init(x: 0.64, y: 0.648))
    ]

    public static let defaultPlacements = frontPlacementsV13
}
