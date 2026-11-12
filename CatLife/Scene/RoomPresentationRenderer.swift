import SpriteKit
import CatGameCore

/// One animation source, with reusable upright artwork above the projected room.
@MainActor
final class RoomPresentationRenderer {
    let root = SKNode()
    let camera = RoomViewCamera()
    private let backdrop = SKSpriteNode(color: UIColor(red: 0.97, green: 0.93, blue: 0.84, alpha: 1), size: .zero)
    private let content = SKNode()
    private let shell = RoomShellArtwork()
    private var mirrors: [String: RoomNodeMirror] = [:]
    private var objectFrames: [String: CGRect] = [:]
    private var objectDepths: [String: CGFloat] = [:]
    private var groundAnchors: [String: CGPoint] = [:]
    private var artworkNames: [String: String] = [:]
    private var artworkAngles: [String: RoomViewAngle] = [:]
    private var contactShadows: [String: RoomContactShadow68] = [:]
    private let arrangementArtwork68 = RoomArrangementRendering68()
    private let furnitureContact68 = RoomFurnitureContact68()
    private(set) var projection = RoomViewProjection(worldSize: CGSize(width: 390, height: 480), angle: .front)
    private var worldSize = CGSize.zero
    private var viewport = CGSize.zero
    private var polygon: [CGPoint] = []
    private var level = 0
    private var homeFloor: HomeFloor = .ground
    private var requestedUsableRect: CGRect?
    private var configuredUsableRect: CGRect?
    private var cameraUsableRect = CGRect.zero
    private var frontFramingBounds: CGRect?
    #if os(macOS)
    func configureDesktop(isDaylight: Bool, showsBackdrop: Bool) {
        backdrop.isHidden = !showsBackdrop
        guard shell.desktopDaylight != isDaylight else { return }
        shell.desktopDaylight = isDaylight
        if projection.macRoom != nil {
            shell.configure(projection: projection, floorPolygon: polygon, worldSize: worldSize, floor: homeFloor)
        }
    }
    func fixedStructure(at point: CGPoint) -> MacRoomStructure? {
        let projected = camera.worldPoint(viewPoint: point)
        return MacRoomStructure.allCases.first { structure in
            guard let points = shell.desktopArtwork.fixedPolygons[structure] else { return false }
            let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath()
            return path.contains(projected)
        }
    }
    func fixedFrame(_ structure: MacRoomStructure) -> CGRect? {
        guard let source = shell.desktopArtwork.fixedFrames[structure] else { return nil }
        let a = camera.viewPoint(projectedWorld: CGPoint(x: source.minX, y: source.maxY))
        let b = camera.viewPoint(projectedWorld: CGPoint(x: source.maxX, y: source.minY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
    #endif
    private var framingNeedsUpdate = true
    #if DEBUG
    private(set) var framingUpdateCount = 0
    #endif

    func invalidateFraming() { framingNeedsUpdate = true }

    init() {
        root.name = "room-presentation"
        root.zPosition = 100_000
        backdrop.zPosition = -1_000
        // Opaque stage paper also hides the simulation-only nodes beneath this renderer.
        let paper = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { context in
            let colors = [UIColor(red: 1, green: 0.98, blue: 0.92, alpha: 1).cgColor,
                          UIColor(red: 0.96, green: 0.91, blue: 0.80, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                    endCenter: CGPoint(x: 128, y: 128), endRadius: 190, options: [.drawsAfterEndLocation])
            }
        }
        backdrop.texture = SKTexture(image: paper)
        root.addChild(backdrop)
        root.addChild(content)
        content.addChild(shell)
        content.addChild(arrangementArtwork68)
    }

    func configure(world: CGSize, viewport: CGSize, floor: [CGPoint], angle: RoomViewAngle, level: Int,
                   homeFloor: HomeFloor = .ground) {
        guard viewport.width > 0, viewport.height > 0, !floor.isEmpty else { return }
        let geometryChanged = worldSize != world || polygon != floor || projection.angle != angle
            || self.level != level || self.homeFloor != homeFloor
        guard geometryChanged || self.viewport != viewport || configuredUsableRect != requestedUsableRect else { return }
        let reset = self.level != level || projection.angle != angle || self.homeFloor != homeFloor || worldSize == .zero
        let previousProjection = projection
        let wasWholeRoom = camera.isWholeRoom
        worldSize = world; self.viewport = viewport; polygon = floor; self.level = level; self.homeFloor = homeFloor
        backdrop.size = CGSize(width: viewport.width + 4, height: viewport.height + 4)
        let top = min(320, viewport.height * 0.43)
        let bottom = min(100, viewport.height * 0.15)
        let fallback = CGRect(x: 16, y: top, width: max(1, viewport.width - 32),
                              height: max(100, viewport.height - top - bottom))
        let usable = requestedUsableRect ?? fallback
        configuredUsableRect = requestedUsableRect
        cameraUsableRect = usable
        let scale = CGFloat(HomeCatalog.level(level)?.worldScale ?? 1)
        if geometryChanged {
            frontFramingBounds = nil
            invalidateFraming()
            #if os(macOS)
            projection = RoomViewProjection(worldSize: world, angle: angle)
            projection.macRoom = MacRoomProjection(legacyFloor: floor, worldSize: world, angle: angle)
            shell.desktopLevel = level
            #else
            let minX = floor.map(\.x).min()!, maxX = floor.map(\.x).max()!
            let minY = floor.map(\.y).min()!, maxY = floor.map(\.y).max()!
            let footprint = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            // Room shape follows the ordinary stage, never the transient tray or camera area.
            let reference = CGSize(width: world.width / scale, height: world.height / scale)
            let normalArea = RoomStageLayout.usableRect(in: reference)
            let frontBounds = CGRect(x: footprint.minX, y: footprint.minY, width: footprint.width,
                height: footprint.width * max(1, normalArea.height) / max(1, normalArea.width) * 0.66)
            let front = angle == .front ? RoomFrontFloorProjection(polygon: floor, destination: frontBounds) : nil
            projection = RoomViewProjection(worldSize: world, angle: angle, frontFloor: front)
            #endif
            shell.configure(projection: projection, floorPolygon: floor, worldSize: world, floor: homeFloor)
        }
        let mappingChanged = previousProjection.frontFloor?.destination != projection.frontFloor?.destination
        let previousCenter = !reset && !wasWholeRoom && mappingChanged
            ? previousProjection.unproject(camera.center) : nil
        #if os(macOS)
        let cameraBounds = shell.contentBounds
        let zoomScale: CGFloat = 1.0625 // 1.7× maximum desktop close-up with RoomViewCamera's existing clamp.
        #else
        let cameraBounds = projection.frontFloor == nil ? shell.contentBounds.insetBy(dx: -24, dy: -24)
            : frontFramingBounds?.insetBy(dx: -2, dy: -2) ?? shell.contentBounds
        let zoomScale = scale
        #endif
        camera.configure(bounds: cameraBounds, viewport: viewport,
                         usableRect: usable, worldScale: zoomScale, reset: reset)
        if !reset, mappingChanged {
            if wasWholeRoom { camera.fit() }
            else if let previousCenter { camera.recenter(on: projection.project(previousCenter)) }
        }
        updateCamera()
    }

    func setUsableRect(_ rect: CGRect) {
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0, requestedUsableRect != rect else { return }
        requestedUsableRect = rect
        configure(world: worldSize, viewport: viewport, floor: polygon, angle: projection.angle, level: level, homeFloor: homeFloor)
    }

    func update(cat: CatActor, residents: RoomResidentCats, furniture: [String: SKSpriteNode],
                items: [FurnitureItem], bowl: SKSpriteNode, bowlFront: SKSpriteNode, restFront: SKSpriteNode,
                selection: SKShapeNode, toy: SKSpriteNode, feeding: Bool, rest: RoomFurnitureRest?,
                selectedID: String? = nil, particles: [SKNode] = [],
                companionRing: SKShapeNode? = nil, companionPlaque: SKShapeNode? = nil,
                world: RoomFurnitureWorld? = nil, editing: Bool = false, bowlSelected: Bool = false,
                placementIssues: [String: ArrangementIssue68] = [:], bowlHasFood: Bool = false,
                reducedMotion: Bool = false) {
        var active = Set<String>()
        func sync(_ key: String, _ source: SKNode, anchor: CGPoint? = nil, depth: CGFloat? = nil,
                  variant: FurnitureArtwork68.Variant? = nil, lift: CGFloat = 0, displayScale: CGFloat? = nil) {
            active.insert(key)
            let mirror: RoomNodeMirror
            if let existing = mirrors[key] { mirror = existing }
            else { mirror = RoomNodeMirror(source); mirrors[key] = mirror; content.addChild(mirror.node) }
            mirror.synchronize(source, root: true, copyingSprite: variant == nil)
            mirror.node.name = key
            mirror.node.position = anchor ?? projection.project(source.position)
            groundAnchors[key] = mirror.node.position
            mirror.node.position.y += lift
            mirror.node.zPosition = depth ?? 10_000 - projection.projectedDepth(source.position)
            if let variant, let source = source as? SKSpriteNode, let sprite = mirror.node as? SKSpriteNode {
                sprite.texture = variant.texture
                sprite.size = variant.size(referenceWidth: source.size.width)
                sprite.anchorPoint = variant.anchorPoint
                sprite.xScale = 1; sprite.yScale = 1; sprite.warpGeometry = nil
                // Crossfade real model renders, rather than flattening through a negative x scale.
                if let old = artworkNames[key], old != variant.assetName,
                   artworkAngles[key] == projection.angle, !reducedMotion {
                    sprite.removeAction(forKey: "turn68")
                    sprite.alpha = source.alpha * 0.35
                    sprite.run(.fadeAlpha(to: source.alpha, duration: 0.2), withKey: "turn68")
                }
                if reducedMotion || artworkAngles[key] != projection.angle {
                    sprite.removeAction(forKey: "turn68")
                    sprite.alpha = source.alpha
                }
                artworkNames[key] = variant.assetName
                artworkAngles[key] = projection.angle
            }
            #if os(macOS)
            if let model = projection.macRoom {
                let factor = displayScale ?? model.perspectiveScale(at: source.position)
                mirror.node.xScale *= factor; mirror.node.yScale *= factor
            }
            #endif
            objectFrames[key] = mirror.node.calculateAccumulatedFrame()
            objectDepths[key] = mirror.node.zPosition
        }
        for (id, node) in furniture {
            guard let item = items.first(where: { $0.id == id }) else { sync("furniture-" + id, node); continue }
            let wall = FurnitureCatalog.metadata(for: item.kind).isWall
            let placement = world?.placements.first { $0.itemID == id }
            // The rectified front room has one flat wall; side views expose its two physical surfaces.
            #if os(macOS)
            let artworkPlacement = wall ? nil : placement
            #else
            let artworkPlacement = wall && projection.frontFloor != nil ? nil : placement
            #endif
            let variant = world == nil ? nil : FurnitureArtwork68.variant(for: item, angle: projection.angle, placement: artworkPlacement)
            let key = "furniture-" + id
            let selected = editing && selectedID == id
            var artworkScale: CGFloat? = nil
            #if os(macOS)
            if wall, let model = projection.macRoom {
                let cellX = (node.position.x - model.logicalBounds.minX) / model.logicalBounds.width * MacRoomProjection.columns
                artworkScale = model.scale(atCell: CGPoint(x: cellX, y: 7))
            }
            #endif
            sync(key, node, anchor: wall ? projection.wallPoint(node.position) : nil,
                 depth: wall ? 100 : nil, variant: variant,
                 lift: selected && !wall ? max(5, node.size.width * 0.06) : 0, displayScale: artworkScale)
            if !wall {
                let shadow: RoomContactShadow68
                if let old = contactShadows[id] { shadow = old }
                else { shadow = RoomContactShadow68(); contactShadows[id] = shadow; content.addChild(shadow) }
                let footprint = world?.footprint(item) ?? CGSize(width: node.size.width * 0.65, height: node.size.width * 0.25)
                #if os(macOS)
                let factor = projection.macRoom?.perspectiveScale(at: node.position) ?? 1
                let shadowSize = CGSize(width: footprint.width * factor, height: footprint.height * factor)
                #else
                let shadowSize = footprint
                #endif
                shadow.update(center: projection.project(node.position), size: shadowSize,
                              selected: selected, hidden: node.isHidden, alpha: node.alpha)
            }
        }
        for id in Array(contactShadows.keys) where id != "bowl" && furniture[id] == nil {
            contactShadows.removeValue(forKey: id)?.removeFromParent()
        }
        let bowlPoint = projection.project(bowl.position)
        let bowlDepth = 10_000 - projection.projectedDepth(bowl.position)
        let bowlVariant = world == nil ? nil : FurnitureArtwork68.bowlVariant(hasFood: bowlHasFood, angle: projection.angle)
        sync("bowl", bowl, anchor: bowlPoint, depth: bowlDepth, variant: bowlVariant)
        if let world {
            let shadow = contactShadows["bowl"] ?? RoomContactShadow68()
            if contactShadows["bowl"] == nil { contactShadows["bowl"] = shadow; content.addChild(shadow) }
            shadow.update(center: projection.project(world.roomFloor.bowlGround(at: bowl.position)),
                          size: world.roomFloor.bowlFootprint, selected: editing && bowlSelected,
                          hidden: bowl.isHidden, alpha: bowl.alpha)
        }
        sync("bowl-front", bowlFront, anchor: bowlPoint,
             depth: bowlDepth + min(1, max(-1, bowlFront.zPosition - bowl.zPosition)))
        if let bowlVariant {
            setFrontSlice68(key: "bowl-front", variant: bowlVariant, referenceWidth: bowl.size.width,
                            surface: "foodSurfaceCenter", defaultFraction: 0.45)
        }
        var catAnchor = projection.project(cat.position)
        var catDisplayScale: CGFloat? = nil
        #if os(macOS)
        catDisplayScale = projection.macRoom?.perspectiveScale(at: cat.position)
        #endif
        var catDepth = 10_000 - projection.projectedDepth(cat.position)
        // A calibrated mouth/paw contact is local artwork space, not a second
        // ground position. Blend into that space only near the active target.
        let target: SKNode? = rest.flatMap { furniture[$0.item.id] } ?? (feeding ? bowl : nil)
        if let target {
            let distance = hypot(cat.position.x - target.position.x, cat.position.y - target.position.y)
            let width = max(1, cat.visualFrame.width)
            let t = min(1, max(0, (3 * width - distance) / (1.5 * width)))
            let blend = t * t * (3 - 2 * t)
            let base = projection.project(target.position)
            #if os(macOS)
            let factor = projection.macRoom?.perspectiveScale(at: target.position) ?? 1
            catDisplayScale = (catDisplayScale ?? 1) + (factor - (catDisplayScale ?? 1)) * blend
            #else
            let factor: CGFloat = 1
            #endif
            let contact = CGPoint(x: base.x + (cat.position.x - target.position.x) * factor,
                                  y: base.y + (cat.position.y - target.position.y) * factor)
            catAnchor.x += (contact.x - catAnchor.x) * blend
            catAnchor.y += (contact.y - catAnchor.y) * blend
            if blend == 1 {
                catDepth = 10_000 - projection.projectedDepth(target.position)
                    + min(2, max(-2, cat.zPosition - target.zPosition))
            }
        }
        let restingNode = rest.flatMap { furniture[$0.item.id] }
        let restVariant = world == nil ? nil : rest.flatMap { visit in
            FurnitureArtwork68.variant(for: visit.item, angle: projection.angle,
                placement: world?.placements.first { $0.itemID == visit.item.id })
        }
        let contactOffset = furnitureContact68.update(cat: cat, rest: rest, furniture: restingNode,
            variant: restVariant, referenceWidth: restingNode?.size.width ?? 1,
            bowl: bowl, bowlVariant: bowlVariant, feeding: feeding)
        catAnchor.x += contactOffset.x * (catDisplayScale ?? 1); catAnchor.y += contactOffset.y * (catDisplayScale ?? 1)
        sync("cat", cat, anchor: catAnchor, depth: catDepth, displayScale: catDisplayScale)
        if let sprite = mirrors["cat"]?.mirroredNode(for: cat.renderSprite68) as? SKSpriteNode {
            furnitureContact68.applyPawCorrection(to: sprite, sourceSprite: cat.renderSprite68)
        }
        if let companionRing {
            sync("companion-ring", companionRing, anchor: catAnchor, depth: catDepth - 0.5, displayScale: catDisplayScale)
        }
        if let companionPlaque {
            let anchor = CGPoint(x: catAnchor.x + (companionPlaque.position.x - cat.position.x) * (catDisplayScale ?? 1),
                                 y: catAnchor.y + (companionPlaque.position.y - cat.position.y) * (catDisplayScale ?? 1))
            sync("companion-name", companionPlaque, anchor: anchor, depth: 20_001, displayScale: catDisplayScale)
        }
        for (id, actor) in residents.actors { sync("resident-" + id, actor) }
        if let rest, let target = furniture[rest.item.id] {
            let base = projection.project(target.position)
            sync("rest-front", restFront, anchor: base, depth: catDepth + 0.2)
            if let variant = FurnitureArtwork68.variant(for: rest.item, angle: projection.angle,
                placement: world?.placements.first { $0.itemID == rest.item.id }) {
                setFrontSlice68(key: "rest-front", variant: variant, referenceWidth: target.size.width,
                                surface: "frontEntrySurface", defaultFraction: 0.22)
            }
        }
        let selectedWall = selectedID.flatMap { id in items.first { $0.id == id } }
            .map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false
        sync("selection", selection, anchor: selectedWall ? projection.wallPoint(selection.position) : nil, depth: 25_000)
        mirrors["selection"]?.node.isHidden = true
        arrangementArtwork68.update(world: world, projection: projection, editing: editing,
            selectedID: selectedID, bowlSelected: bowlSelected, issues: placementIssues,
            previewCenter: selectedID.flatMap { furniture[$0]?.position } ?? (bowlSelected ? bowl.position : nil))
        sync("toy", toy)
        for particle in particles {
            sync("particle-\(ObjectIdentifier(particle))", particle,
                 anchor: CGPoint(x: catAnchor.x + (particle.position.x - cat.position.x) * (catDisplayScale ?? 1),
                                 y: catAnchor.y + (particle.position.y - cat.position.y) * (catDisplayScale ?? 1)), depth: 30_000,
                 displayScale: catDisplayScale)
        }
        for key in Array(mirrors.keys) where !active.contains(key) {
            mirrors.removeValue(forKey: key)?.node.removeFromParent()
            objectFrames.removeValue(forKey: key); objectDepths.removeValue(forKey: key)
            groundAnchors.removeValue(forKey: key); artworkNames.removeValue(forKey: key); artworkAngles.removeValue(forKey: key)
        }
        if projection.frontFloor != nil, framingNeedsUpdate, frontFramingBounds == nil || selection.isHidden {
            #if DEBUG
            framingUpdateCount += 1
            #endif
            framingNeedsUpdate = false
            let visible = Set(active.filter { key in
                guard key == "bowl" || key.hasPrefix("furniture-"), let node = mirrors[key]?.node else { return false }
                return !node.isHidden && node.alpha > 0.02
            })
            var bounds = shell.contentBounds
            for key in visible {
                if let frame = objectFrames[key] { bounds = bounds.union(frame) }
            }
            if bounds != frontFramingBounds {
                // Tall artwork can rise above the wall; keep it whole without changing its size or moving the camera during a drag.
                let wasWholeRoom = camera.isWholeRoom
                frontFramingBounds = bounds
                camera.configure(bounds: bounds.insetBy(dx: -2, dy: -2), viewport: viewport,
                                 usableRect: cameraUsableRect,
                                 worldScale: CGFloat(HomeCatalog.level(level)?.worldScale ?? 1), reset: wasWholeRoom)
            }
        }
        updateCamera()
    }

    /// Keep only the near lip in front of an eating/resting cat, using the new mesh render.
    private func setFrontSlice68(key: String, variant: FurnitureArtwork68.Variant,
                                 referenceWidth: CGFloat, surface: String, defaultFraction: CGFloat) {
        guard let sprite = mirrors[key]?.node as? SKSpriteNode else { return }
        let size = variant.size(referenceWidth: referenceWidth)
        let offset = variant.surfaceOffset(surface, referenceWidth: referenceWidth)
        let fraction = min(0.8, max(0.08, offset.map { (variant.anchorPoint.y * size.height + $0.y - 2) / size.height } ?? defaultFraction))
        sprite.texture = SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: fraction), in: variant.texture)
        sprite.size = CGSize(width: size.width, height: size.height * fraction)
        sprite.anchorPoint = CGPoint(x: variant.anchorPoint.x, y: variant.anchorPoint.y / fraction)
        sprite.xScale = 1; sprite.yScale = 1
        #if os(macOS)
        let anchor = groundAnchors[key].map(projection.unproject) ?? .zero
        let factor = projection.macRoom?.perspectiveScale(at: anchor) ?? 1
        sprite.setScale(factor)
        #endif
        objectFrames[key] = sprite.calculateAccumulatedFrame()
    }

    func updateCamera() {
        guard viewport.width > 0, camera.scale > 0 else { return }
        content.setScale(1 / camera.scale)
        let origin = camera.viewPoint(projectedWorld: .zero)
        content.position = CGPoint(x: origin.x - viewport.width / 2, y: viewport.height / 2 - origin.y)
    }

    func worldPoint(screen: CGPoint, wall: Bool = false, displayOffset: CGPoint = .zero) -> CGPoint {
        let point = camera.worldPoint(viewPoint: CGPoint(x: screen.x + displayOffset.x, y: screen.y + displayOffset.y))
        return wall ? projection.unprojectWallPoint(point) : projection.unproject(point)
    }

    func frame(_ key: String) -> CGRect? {
        guard let source = objectFrames[key], let mirror = mirrors[key],
              !mirror.node.isHidden, mirror.node.alpha > 0.02 else { return nil }
        let a = camera.viewPoint(projectedWorld: CGPoint(x: source.minX, y: source.maxY))
        let b = camera.viewPoint(projectedWorld: CGPoint(x: source.maxX, y: source.minY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    func displayedPoint(_ logicalPoint: CGPoint, source: SKNode, key: String) -> CGPoint? {
        guard let mirror = mirrors[key], !mirror.node.isHidden else { return nil }
        let logicalPoint = (source as? CatActor).map { furnitureContact68.adjustedPoint(logicalPoint, cat: $0) } ?? logicalPoint
        #if os(macOS)
        let sx = mirror.node.xScale, sy = mirror.node.yScale
        #else
        let sx: CGFloat = 1, sy: CGFloat = 1
        #endif
        return camera.viewPoint(projectedWorld: CGPoint(x: mirror.node.position.x + (logicalPoint.x - source.position.x) * sx,
                                                       y: mirror.node.position.y + (logicalPoint.y - source.position.y) * sy))
    }

    func anchor(_ key: String) -> CGPoint? {
        groundAnchors[key].map { camera.viewPoint(projectedWorld: $0) }
    }

    func hit(screen: CGPoint, editing: Bool) -> String? {
        let candidates = mirrors.keys.compactMap { key -> (key: String, frame: CGRect, depth: CGFloat)? in
            guard key == "bowl" || key == "cat" || key.hasPrefix("resident-") || key.hasPrefix("furniture-"),
                  !editing || key == "bowl" || key.hasPrefix("furniture-"), let frame = frame(key) else { return nil }
            return (key, frame, objectDepths[key] ?? 0)
        }
        // Touch padding helps small objects, but never covers another object's visible image.
        if let visible = candidates.filter({ $0.frame.contains(screen) })
            .max(by: { $0.depth < $1.depth }) { return visible.key }
        let assisted = candidates.filter {
            $0.frame.insetBy(dx: -max(3, (44 - $0.frame.width) / 2),
                            dy: -max(3, (44 - $0.frame.height) / 2)).contains(screen)
        }
        func distance(to rect: CGRect) -> CGFloat {
            let dx = max(0, max(rect.minX - screen.x, screen.x - rect.maxX))
            let dy = max(0, max(rect.minY - screen.y, screen.y - rect.maxY))
            return dx * dx + dy * dy
        }
        return assisted.min {
            let a = distance(to: $0.frame), b = distance(to: $1.frame)
            return a == b ? $0.depth > $1.depth : a < b
        }?.key
    }
}

/// Mirrors visual properties only; actions and game callbacks never get copied.
@MainActor
private final class RoomNodeMirror {
    let node: SKNode
    private let sourceID: ObjectIdentifier
    private var children: [ObjectIdentifier: RoomNodeMirror] = [:]

    init(_ source: SKNode) {
        sourceID = ObjectIdentifier(source)
        if source is SKSpriteNode { node = SKSpriteNode() }
        else if source is SKShapeNode { node = SKShapeNode() }
        else if source is SKLabelNode { node = SKLabelNode() }
        else { node = SKNode() }
    }

    func mirroredNode(for source: SKNode) -> SKNode? {
        if ObjectIdentifier(source) == sourceID { return node }
        if let direct = children[ObjectIdentifier(source)] { return direct.node }
        for child in children.values {
            if let found = child.mirroredNode(for: source) { return found }
        }
        return nil
    }

    func synchronize(_ source: SKNode, root: Bool = false, copyingSprite: Bool = true) {
        if !root { node.position = source.position; node.zPosition = source.zPosition }
        node.xScale = source.xScale; node.yScale = source.yScale; node.zRotation = source.zRotation
        if node.action(forKey: "turn68") == nil { node.alpha = source.alpha }; node.isHidden = source.isHidden
        if copyingSprite, let a = source as? SKSpriteNode, let b = node as? SKSpriteNode {
            if b.texture !== a.texture { b.texture = a.texture }
            b.size = a.size; b.anchorPoint = a.anchorPoint
            b.color = a.color; b.colorBlendFactor = a.colorBlendFactor; b.blendMode = a.blendMode
            b.centerRect = a.centerRect; b.warpGeometry = a.warpGeometry
        } else if let a = source as? SKShapeNode, let b = node as? SKShapeNode {
            if b.path != a.path { b.path = a.path }
            b.fillColor = a.fillColor; b.strokeColor = a.strokeColor
            b.lineWidth = a.lineWidth; b.glowWidth = a.glowWidth
        } else if let a = source as? SKLabelNode, let b = node as? SKLabelNode {
            if b.text != a.text { b.text = a.text }
            if b.fontName != a.fontName { b.fontName = a.fontName }
            if b.fontSize != a.fontSize { b.fontSize = a.fontSize }
            if b.fontColor != a.fontColor { b.fontColor = a.fontColor }
            if b.horizontalAlignmentMode != a.horizontalAlignmentMode { b.horizontalAlignmentMode = a.horizontalAlignmentMode }
            if b.verticalAlignmentMode != a.verticalAlignmentMode { b.verticalAlignmentMode = a.verticalAlignmentMode }
        }
        let ids = Set(source.children.map(ObjectIdentifier.init))
        for id in Array(children.keys) where !ids.contains(id) { children.removeValue(forKey: id)?.node.removeFromParent() }
        for child in source.children {
            let id = ObjectIdentifier(child)
            let mirror: RoomNodeMirror
            if let old = children[id] { mirror = old }
            else { mirror = RoomNodeMirror(child); children[id] = mirror; node.addChild(mirror.node) }
            mirror.synchronize(child)
        }
    }
}
