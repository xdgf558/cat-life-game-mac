import Foundation
import CoreGraphics
import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// Art coordinates keep furniture attached to the same room floor on every screen.
struct RoomArtworkTransform: Sendable {
    let sceneSize: CGSize
    let artworkSize: CGSize
    let viewportSize: CGSize

    init(sceneSize: CGSize, artworkSize: CGSize, viewportSize: CGSize? = nil) {
        self.sceneSize = sceneSize
        self.artworkSize = artworkSize
        self.viewportSize = viewportSize ?? sceneSize
    }

    var scale: CGFloat { max(sceneSize.width / artworkSize.width, sceneSize.height / artworkSize.height) }
    var visualScale: CGFloat { max(viewportSize.width / artworkSize.width, viewportSize.height / artworkSize.height) }
    func point(_ normalized: NormalizedPoint) -> CGPoint {
        CGPoint(x: sceneSize.width / 2 + (normalized.x - 0.5) * artworkSize.width * scale,
                y: sceneSize.height / 2 + (0.5 - normalized.y) * artworkSize.height * scale)
    }
    func normalized(_ point: CGPoint) -> NormalizedPoint {
        .init(x: min(1, max(0, 0.5 + (point.x - sceneSize.width / 2) / (artworkSize.width * scale))),
              y: min(1, max(0, 0.5 - (point.y - sceneSize.height / 2) / (artworkSize.height * scale))))
    }
}

struct RoomFurnitureSpec: Sendable {
    let width: CGFloat
    let footprint: CGSize
    let anchorY: CGFloat
    let isWall: Bool

    static func forItem(_ item: FurnitureItem) -> Self {
        switch item.kind {
        case .cabinet: return .init(width: 244, footprint: CGSize(width: 186, height: 78), anchorY: 0.12, isWall: false)
        case .catTree: return .init(width: 225, footprint: CGSize(width: 160, height: 82), anchorY: 0.07, isWall: false)
        case .catBed: return .init(width: 344, footprint: CGSize(width: 292, height: 144), anchorY: 0.23, isWall: false)
        case .wallFlower: return .init(width: 110, footprint: CGSize(width: 110, height: 170), anchorY: 0.5, isWall: true)
        case .wallCat: return .init(width: 108, footprint: CGSize(width: 108, height: 148), anchorY: 0.5, isWall: true)
        case .plant:
            let factor: CGFloat = item.id == "plantSmall" ? 0.78 : 1
            return .init(width: 138 * factor, footprint: CGSize(width: 70 * factor, height: 42 * factor), anchorY: 0.09, isWall: false)
        case .floorCushion: return .init(width: 184, footprint: CGSize(width: 154, height: 80), anchorY: 0.42, isWall: false)
        case .flowerStool: return .init(width: 190, footprint: CGSize(width: 126, height: 68), anchorY: 0.14, isWall: false)
        case .bookcase: return .init(width: 228, footprint: CGSize(width: 190, height: 76), anchorY: 0.12, isWall: false)
        case .rattanChair: return .init(width: 204, footprint: CGSize(width: 158, height: 88), anchorY: 0.14, isWall: false)
        case .sideTable: return .init(width: 170, footprint: CGSize(width: 136, height: 72), anchorY: 0.13, isWall: false)
        case .wallSunrise: return .init(width: 104, footprint: CGSize(width: 104, height: 178), anchorY: 0.5, isWall: true)
        case .wallTownMemory: return .init(width: 132, footprint: CGSize(width: 132, height: 126), anchorY: 0.5, isWall: true)
        }
    }
}

/// This value contains no nodes or UIKit objects and can be sent to a worker.
struct RoomFurnitureWorld: Sendable {
    let transform: RoomArtworkTransform
    let catWidth: CGFloat
    let bowlSize: CGSize
    let bowlPosition: CGPoint
    let items: [FurnitureItem]
    let placements: [FurniturePlacement]

    var roomFloor: RoomFloor {
        RoomFloor(sceneSize: transform.sceneSize, artworkSize: transform.artworkSize,
                  catWidth: catWidth, bowlSize: bowlSize, furnitureObstacles: floorObstacles())
    }

    func item(_ id: String) -> FurnitureItem? { items.first { $0.id == id } }
    func center(_ id: String) -> CGPoint? { placements.first { $0.itemID == id }.map { transform.point($0.position) } }

    func footprint(_ item: FurnitureItem) -> CGSize {
        let size = FurnitureCatalog.footprint(for: item).artworkSize
        #if os(macOS)
        let scale = transform.visualScale * MacRoomProjection.spriteScale
        #else
        let scale = transform.visualScale
        #endif
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func rectangle(_ item: FurnitureItem, at center: CGPoint) -> CGRect {
        let size = footprint(item)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    func floorObstacles(excluding excludedID: String? = nil) -> [CGRect] {
        var obstacles = placements.compactMap { placement -> CGRect? in
            guard placement.itemID != excludedID, let item = item(placement.itemID),
                  !RoomFurnitureSpec.forItem(item).isWall else { return nil }
            return rectangle(item, at: transform.point(placement.position))
        }
        #if os(macOS)
        if let stairs = MacRoomReservations.stairObstacle(transform: transform) { obstacles.append(stairs) }
        #endif
        return obstacles
    }

    var wallPolygon: [CGPoint] {
        let ground = [NormalizedPoint(x: 0, y: 785.0 / 1536),
                      .init(x: 442.0 / 1024, y: 530.0 / 1536),
                      .init(x: 1, y: 825.0 / 1536)].map(transform.point)
        let height = 384 * transform.scale
        let points = ground + ground.reversed().map { CGPoint(x: $0.x, y: $0.y + height) }
        return RoomFloor.clip(points, to: CGRect(x: 8, y: 8,
                          width: max(1, transform.sceneSize.width - 16),
                          height: max(1, transform.sceneSize.height - 16)))
    }

    func placementNavigator(for id: String?, catAt cat: CGPoint) -> RoomNavigation {
        let floor = roomFloor
        guard let id, let item = item(id) else { return floor.placementNavigator(catAt: cat) }
        let spec = RoomFurnitureSpec.forItem(item)
        if spec.isWall {
            let obstacles = placements.compactMap { placement -> CGRect? in
                guard placement.itemID != id, let other = self.item(placement.itemID),
                      RoomFurnitureSpec.forItem(other).isWall else { return nil }
                return rectangle(other, at: transform.point(placement.position)).insetBy(dx: -3, dy: -3)
            }
            return RoomNavigation(floor: wallPolygon, obstacles: obstacles, footprint: footprint(item), cellSize: 7)
        }
        let catRect = CGRect(x: cat.x - floor.catFootprint.width / 2 - 3,
                             y: cat.y - floor.catFootprint.height / 2 - 3,
                             width: floor.catFootprint.width + 6, height: floor.catFootprint.height + 6)
        var fixedPlacement: [CGRect] = []
        #if os(macOS)
        if let model = MacRoomReservations.projection(transform: transform) {
            fixedPlacement.append(MacRoomProjection.bounds(model.logicalBoundary(of: MacRoomProjection.doorClearanceCells)))
        }
        #endif
        return RoomNavigation(floor: floor.polygon,
                              obstacles: fixedPlacement + floorObstacles(excluding: id).map { $0.insetBy(dx: -2, dy: -2) }
                                + [floor.bowlObstacle(at: bowlPosition).insetBy(dx: -2, dy: -2), catRect],
                              footprint: footprint(item), cellSize: 7,
                              floorFootprintShape: item.kind == .catBed ? .clippedCorners : .rectangle)
    }

    func replacing(_ id: String, with center: CGPoint, preservingLegacyFootprint: Bool = false,
                   placementFloor: HomeFloor? = nil) -> Self {
        let previous = placements.first { $0.itemID == id }
        let placement = FurniturePlacement(itemID: id, position: RoomArrangementGrid68(transform: transform).normalized(world: center),
                                           floor: previous?.floor ?? placementFloor ?? .ground)
        var updated = placements.filter { $0.itemID != id }
        updated.append(placement)
        let owned = preservingLegacyFootprint ? items : items.map { $0.id == id ? $0.applyingPlacement(from: previous, to: placement) : $0 }
        return Self(transform: transform, catWidth: catWidth, bowlSize: bowlSize, bowlPosition: bowlPosition,
                    items: owned, placements: updated)
    }

    func replacingOrientation(_ id: String, with orientation: FurnitureOrientation) -> Self {
        var updated = items
        guard let index = updated.firstIndex(where: { $0.id == id }),
              orientation == .front || updated[index].kind.supportsRotation else { return self }
        updated[index].orientation = orientation
        return Self(transform: transform, catWidth: catWidth, bowlSize: bowlSize, bowlPosition: bowlPosition,
                    items: updated, placements: placements)
    }

    /// Floor rotation happens in grid axes, before the legacy 128×64 projection.
    func rotatedFloorOffset(_ offset: CGPoint, by orientation: FurnitureOrientation) -> CGPoint {
        guard orientation != .front else { return offset }
        let grid = CGPoint(x: offset.x / (128 * transform.visualScale),
                           y: offset.y / (64 * transform.visualScale))
        let rotated = orientation.rotatedOffset(grid)
        return CGPoint(x: rotated.x * 128 * transform.visualScale,
                       y: rotated.y * 64 * transform.visualScale)
    }

    func rotatedFloorPoint(_ point: CGPoint, around center: CGPoint, by orientation: FurnitureOrientation) -> CGPoint {
        let offset = rotatedFloorOffset(CGPoint(x: point.x - center.x, y: point.y - center.y), by: orientation)
        return CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }

    private func rotatedFloorRectangle(_ rectangle: CGRect, around center: CGPoint,
                                       by orientation: FurnitureOrientation) -> CGRect {
        let point = rotatedFloorPoint(CGPoint(x: rectangle.midX, y: rectangle.midY), around: center, by: orientation)
        let size = rotatedFloorOffset(CGPoint(x: rectangle.width, y: rectangle.height), by: orientation)
        return CGRect(x: point.x - abs(size.x) / 2, y: point.y - abs(size.y) / 2,
                      width: abs(size.x), height: abs(size.y))
    }

    func resolve(id: String?, near point: CGPoint, catAt cat: CGPoint,
                 placement: RoomNavigation) -> RoomFurnitureResolution? {
        let floor = roomFloor
        if id == nil {
            guard let result = floor.resolvePlacement(near: point, catAt: cat, placement: placement) else { return nil }
            return .init(id: nil, center: result.center, floor: floor, navigation: result.navigation)
        }
        guard let id, let item = item(id) else { return nil }
        let nearest = placement.nearestWalkable(to: point).map { [$0] } ?? []
        let candidates = nearest + placement.walkablePoints.sorted {
            hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
        }
        for candidate in candidates {
            guard !Task<Never, Never>.isCancelled else { return nil }
            let proposedWorld = replacing(id, with: candidate)
            let proposedFloor = proposedWorld.roomFloor
            let navigator = proposedFloor.navigator(bowlAt: bowlPosition, precomputeGrid: false)
            guard navigator.isWalkable(cat) else { continue }
            if !RoomFurnitureSpec.forItem(item).isWall,
               proposedFloor.feedingPlan(from: cat, bowlAt: bowlPosition, navigator: navigator, firstReachable: true) == nil {
                continue
            }
            // Beds and cushions need enough room for both entering and waking
            // up. Validate this on the same worker as the feeding route.
            if [.catBed, .floorCushion].contains(item.kind),
               proposedWorld.restVisit(to: id, from: cat) == nil { continue }
            return .init(id: id, center: candidate, floor: proposedFloor,
                         navigation: proposedFloor.navigator(bowlAt: bowlPosition))
        }
        return nil
    }
}

struct RoomFurnitureResolution: Sendable {
    let id: String?
    let center: CGPoint
    let floor: RoomFloor
    let navigation: RoomNavigation
}

/// A visit owns permission to enter exactly one furniture footprint. The
/// ordinary navigation remains unchanged for every other activity.
struct RoomFurnitureRest: Sendable {
    let item: FurnitureItem
    let plan: FurnitureRestPlan
    let navigation: RoomNavigation
    let target: CGRect
    let elevation: CGFloat
    let entryContactProgress: CGFloat
    /// Measured visible front-mattress band, independent of the actor's pose.
    let entrySupportBand: CGRect?
    var entryOrientation: FurnitureOrientation = .front
}

extension RoomFurnitureWorld {
    func restVisit(to id: String, from start: CGPoint, additionalObstacles: [CGRect] = []) -> RoomFurnitureRest? {
        guard let item = item(id), [.catBed, .floorCushion].contains(item.kind),
              let center = center(id) else { return nil }
        let floor = roomFloor
        let target = rectangle(item, at: center)
        let otherObstacles = floorObstacles(excluding: id) + [floor.bowlObstacle(at: bowlPosition)] + additionalObstacles
        let inverse: FurnitureOrientation = item.orientation == .left ? .right : item.orientation == .right ? .left : item.orientation
        let frontTarget = rotatedFloorRectangle(target, around: center, by: inverse)
        var point = center
        var elevation = catWidth * 0.14
        var contactProgress = CatFurnitureStepTimeline.defaultContactProgress
        var supportBand: CGRect?
        if item.kind == .catBed {
            let spec = RoomFurnitureSpec.forItem(item)
            let width = spec.width * transform.visualScale
            // Preserve the legacy vertical step calibration. New artwork uses
            // mesh surface samples in the renderer for visible paw contact.
            // The old alpha crop was (86,44)..(1477,961), with its rim at .17.
            let height = width * 917 / 1391
            let edgeY = center.y + height * (0.17 - spec.anchorY)
            supportBand = CGRect(x: center.x - width * 0.22,
                                 y: center.y + height * (0.155 - spec.anchorY),
                                 width: width * 0.44, height: height * 0.05)
            let visualRestY = center.y + frontTarget.height * 0.16 + catWidth * 0.06
            let stageY = frontTarget.minY - floor.catFootprint.height / 2
                - max(1, floor.catFootprint.height * 0.15)
            // Front-paw support normally holds at .14 of the validated entry. Solve
            // ground projection + physical elevation against the visible rim;
            // using only the old .06C sleeping offset left both paws on floor.
            elevation = (edgeY - stageY - contactProgress * (visualRestY - stageY))
                / (1 - contactProgress)
            // A narrow/tall crop can make the bed taller relative to the cat.
            // Approach its rim a little farther before reaching, instead of
            // stretching the forelegs beyond their supported height. Preserve
            // safe existing entries and the final visible sleeping position.
            if elevation > catWidth * 0.55 {
                let reachableElevation = catWidth * 0.54
                let remainingRise = visualRestY - stageY - reachableElevation
                guard remainingRise.isFinite, remainingRise > 0 else { return nil }
                contactProgress = (edgeY - stageY - reachableElevation) / remainingRise
                guard contactProgress.isFinite,
                      contactProgress >= CatFurnitureStepTimeline.defaultContactProgress,
                      contactProgress <= CatFurnitureStepTimeline.maximumContactProgress else { return nil }
                elevation = reachableElevation
            }
            // This remains a step-up, not a jump or an unconstrained warp.
            guard elevation.isFinite, elevation > 0, elevation <= catWidth * 0.55 else { return nil }
            point.y = visualRestY - elevation
        }
        let restPoint = rotatedFloorPoint(point, around: center, by: item.orientation)
        let preferredFacing: CGFloat = item.orientation == .left ? -1 : 1
        let directions = [item.orientation, item.orientation.turnedRight,
                          item.orientation.turnedRight.turnedRight, item.orientation.turnedLeft]
        // Round nests and cushions can use another rim, with the same complete
        // floor/obstacle checks; a wall must never become a walk-through fallback.
        for entryOrientation in directions {
            guard !Task<Never, Never>.isCancelled else { return nil }
            let inverse: FurnitureOrientation = entryOrientation == .left ? .right : entryOrientation == .right ? .left : entryOrientation
            let localFloor = floor.polygon.map { rotatedFloorPoint($0, around: center, by: inverse) }
            let localObstacles = otherObstacles.map { rotatedFloorRectangle($0, around: center, by: inverse) }
            let localFootprint = rotatedFloorOffset(CGPoint(x: floor.catFootprint.width, y: floor.catFootprint.height), by: inverse)
            guard let localPlan = FurnitureRestPlanner.plan(floor: localFloor, obstacles: localObstacles,
                    target: rotatedFloorRectangle(target, around: center, by: inverse),
                    footprint: CGSize(width: abs(localFootprint.x), height: abs(localFootprint.y)),
                    start: rotatedFloorPoint(start, around: center, by: inverse),
                    restPoint: rotatedFloorPoint(restPoint, around: center, by: inverse),
                    preferredFacing: preferredFacing) else { continue }
            func worldPoint(_ point: CGPoint) -> CGPoint { rotatedFloorPoint(point, around: center, by: entryOrientation) }
            let stage = worldPoint(localPlan.stage)
            let entryDX = restPoint.x - stage.x
            let plan = FurnitureRestPlan(approach: localPlan.approach.map(worldPoint), entry: localPlan.entry.map(worldPoint),
                exit: localPlan.exit.map(worldPoint), stage: stage, restPoint: restPoint,
                facing: abs(entryDX) <= 0.000_001 ? preferredFacing : (entryDX > 0 ? 1 : -1))
            let band = supportBand.map { rotatedFloorRectangle($0, around: center, by: entryOrientation) }
            return .init(item: item, plan: plan,
                         navigation: RoomNavigation(floor: floor.polygon, obstacles: otherObstacles,
                                                    footprint: floor.catFootprint, cellSize: 7, precomputeGrid: false),
                         target: target, elevation: elevation, entryContactProgress: contactProgress,
                         entrySupportBand: band, entryOrientation: entryOrientation)
        }
        return nil
    }
}

/// Register the generated transparent sprites once, retaining their original PNGs.
@MainActor
enum RoomFurnitureArt {
    private static var textures: [FurnitureKind: SKTexture] = [:]

    static func texture(for kind: FurnitureKind) -> SKTexture {
        if let texture = textures[kind] { return texture }
        let name = FurnitureCatalog.metadata(for: kind).assetName
        let full = SKTexture(imageNamed: name)
        guard let cg = UIImage(named: name)?.cgImage else { return full }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let found: CGRect? = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            var minX = width, minY = height, maxX = 0, maxY = 0
            let pixels = buffer.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 24 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
            guard minX <= maxX, minY <= maxY else { return nil }
            return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(height - maxY - 1) / CGFloat(height),
                          width: CGFloat(maxX - minX + 1) / CGFloat(width), height: CGFloat(maxY - minY + 1) / CGFloat(height))
        }
        let texture = found.map { SKTexture(rect: $0, in: full) } ?? full
        textures[kind] = texture
        return texture
    }
}
