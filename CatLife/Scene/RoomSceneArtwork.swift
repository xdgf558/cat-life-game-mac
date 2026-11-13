import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// Owns room nodes, layering and decoration visuals. It never plans routes or
/// mutates saved furniture; RoomScene remains the interaction coordinator.
@MainActor
final class RoomSceneArtwork {
    private weak var scene: SKScene?
    private var container: SKNode? { (scene as? RoomScene)?.simulationRoot ?? scene }
    let room = SKSpriteNode(imageNamed: "room-empty")
    let bowl = SKSpriteNode(imageNamed: "bowl-empty")
    let bowlFront = SKSpriteNode()
    let toy = SKSpriteNode(imageNamed: "icon-play")
    let restFront = SKSpriteNode()
    let selection = SKShapeNode(ellipseOf: CGSize(width: 105, height: 52))
    let thought = SKNode()
    let companionRing = SKShapeNode()
    let companionPlaque = SKShapeNode()
    private let companionName = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var companionRingWidth: CGFloat?
    private var companionLabelSize: CGSize?
    private let upperWall = SKNode()
    private(set) var furnitureNodes: [String: SKSpriteNode] = [:]

    func install(in scene: SKScene) {
        self.scene = scene
        room.zPosition = 0
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(room)
        upperWall.zPosition = 0.1
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(upperWall)
        companionRing.fillColor = UIColor(red: 0.2, green: 0.68, blue: 0.54, alpha: 0.18)
        companionRing.name = "companion-ring"
        companionPlaque.name = "companion-name"
        companionRing.strokeColor = UIColor(red: 0.2, green: 0.68, blue: 0.54, alpha: 1)
        companionRing.lineWidth = 3
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(companionRing)
        companionPlaque.fillColor = UIColor(white: 1, alpha: 0.96)
        companionPlaque.strokeColor = companionRing.strokeColor
        companionPlaque.lineWidth = 2
        companionPlaque.zPosition = 2_001
        companionName.fontSize = 12
        companionName.fontColor = UIColor(red: 0.08, green: 0.48, blue: 0.37, alpha: 1)
        companionName.verticalAlignmentMode = .center
        companionPlaque.addChild(companionName)
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(companionPlaque)
        bowl.name = "bowl"
        bowl.zPosition = 25
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(bowl)
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(bowlFront)
        restFront.isHidden = true
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(restFront)
        setBowlTexture("bowl-empty")
        toy.zPosition = 26
        toy.isHidden = true
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(toy)
        selection.fillColor = UIColor(red: 0.3, green: 0.75, blue: 0.60, alpha: 0.15)
        selection.strokeColor = UIColor(red: 0.15, green: 0.61, blue: 0.46, alpha: 0.9)
        selection.lineWidth = 2
        selection.zPosition = 1_500
        selection.isHidden = true
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(selection)
        let bubble = SKShapeNode(rectOf: CGSize(width: 58, height: 46), cornerRadius: 20)
        bubble.fillColor = UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 0.98)
        bubble.strokeColor = UIColor(red: 0.81, green: 0.71, blue: 0.56, alpha: 0.4)
        bubble.lineWidth = 1
        let food = SKSpriteNode(imageNamed: "bowl-full")
        food.size = CGSize(width: 43, height: 36)
        food.zPosition = 1
        bubble.addChild(food)
        thought.addChild(bubble)
        for (x, y, radius) in [(CGFloat(-17), CGFloat(-27), CGFloat(4)), (-22, -36, 2.5)] {
            let dot = SKShapeNode(circleOfRadius: radius)
            dot.fillColor = bubble.fillColor
            dot.strokeColor = .clear
            dot.position = CGPoint(x: x, y: y)
            thought.addChild(dot)
        }
        thought.zPosition = 30
        ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(thought)
    }

    func updateCompanionMarker(cat: CatActor, name: String, hidden: Bool, reducedMotion: Bool, hidesName: Bool = false) {
        companionRing.isHidden = hidden
        companionPlaque.isHidden = hidden || hidesName
        let frame = cat.visualFrame
        let width = frame.width
        // Ignore rounding from world movement; only a visible size change needs a new path.
        if companionRingWidth.map({ abs($0 - width) > 0.01 }) ?? true {
            companionRing.path = CGPath(ellipseIn: CGRect(x: -width * 0.44, y: -width * 0.12, width: width * 0.88, height: width * 0.24), transform: nil)
            companionRingWidth = width
        }
        companionRing.position = cat.position
        companionRing.zPosition = cat.zPosition - 0.5
        let nameChanged = companionName.text != "♥ " + name
        if nameChanged {
            companionName.text = "♥ " + name
        }
        let labelSize = companionName.frame.size
        if nameChanged || companionLabelSize != labelSize {
            companionPlaque.path = CGPath(roundedRect: CGRect(x: -companionName.frame.width / 2 - 10, y: -12,
                width: companionName.frame.width + 20, height: 24), cornerWidth: 12, cornerHeight: 12, transform: nil)
            companionLabelSize = labelSize
        }
        companionPlaque.position = CGPoint(x: frame.midX, y: frame.maxY + 17)
        if reducedMotion {
            companionRing.removeAction(forKey: "breathe"); companionRing.alpha = 1
        } else if companionRing.action(forKey: "breathe") == nil {
            companionRing.run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])), withKey: "breathe")
        }
    }

    func updateFloorAmbience(upper: Bool, transform: RoomArtworkTransform) {
        upperWall.removeAllChildren()
        room.color = UIColor(red: 0.67, green: 0.59, blue: 0.78, alpha: 1)
        room.colorBlendFactor = upper ? 0.12 : 0
        guard upper else { return }
        // Tint the existing wall without mirroring the asymmetric floor or changing collision geometry.
        let wall = SKShapeNode()
        let points = [(0.435, 0.067), (1.0, 0.267), (1.0, 0.506), (0.435, 0.310)]
            .map { transform.point(NormalizedPoint(x: $0.0, y: $0.1)) }
        let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath()
        wall.path = path; wall.fillColor = UIColor(red: 0.77, green: 0.70, blue: 0.89, alpha: 0.55); wall.strokeColor = .clear
        upperWall.addChild(wall)
        for x in stride(from: 0.46, to: 1.0, by: 0.045) {
            let fraction = (x - 0.435) / (1 - 0.435)
            let top = transform.point(.init(x: x, y: 0.067 + 0.2 * fraction))
            let bottom = transform.point(.init(x: x, y: 0.310 + 0.196 * fraction))
            let line = SKShapeNode(); let stripe = CGMutablePath(); stripe.move(to: top); stripe.addLine(to: bottom)
            line.path = stripe; line.strokeColor = UIColor(white: 1, alpha: 0.16); line.lineWidth = 9
            upperWall.addChild(line)
        }
    }

    func synchronizeFurniture(items ownedFurniture: [FurnitureItem], placements renderedFurniture: [FurniturePlacement],
                              keeping newPlacementID: String?, transform artworkTransform: RoomArtworkTransform,
                              animateOrientation: Bool = false) {
        let visible = Set(renderedFurniture.map(\.itemID))
        for id in Array(furnitureNodes.keys) where !visible.contains(id) && id != newPlacementID {
            furnitureNodes.removeValue(forKey: id)?.removeFromParent()
        }
        for placement in renderedFurniture {
            guard let item = ownedFurniture.first(where: { $0.id == placement.itemID }) else { continue }
            let node = furnitureNode(for: item, transform: artworkTransform, animateOrientation: animateOrientation)
            node.position = artworkTransform.point(placement.position)
            node.alpha = 1
        }
    }

    func furnitureNode(for item: FurnitureItem, transform artworkTransform: RoomArtworkTransform,
                       animateOrientation: Bool = false) -> SKSpriteNode {
        let texture = RoomFurnitureArt.texture(for: item.kind)
        let node: SKSpriteNode
        if let existing = furnitureNodes[item.id] { node = existing }
        else {
            node = SKSpriteNode(texture: texture)
            node.name = "furniture-" + item.id
            furnitureNodes[item.id] = node
            container?.addChild(node)
        }
        let spec = RoomFurnitureSpec.forItem(item)
        let width = spec.width * artworkTransform.visualScale
        let ratio = texture.size().height / max(1, texture.size().width)
        node.size = CGSize(width: width, height: width * ratio)
        node.anchorPoint = CGPoint(x: 0.5, y: spec.anchorY)
        // The renderer owns real view/facing variants; simulation stays unmirrored.
        node.removeAction(forKey: "orientation")
        node.xScale = 1
        return node
    }

    func finishOrientationAnimations() {
        for node in furnitureNodes.values {
            node.removeAction(forKey: "orientation")
            node.xScale = 1
        }
    }

    func updateFurnitureLayers(items ownedFurniture: [FurnitureItem], cat: CatActor, activeRest: RoomFurnitureRest?) {
        for item in ownedFurniture {
            guard let node = furnitureNodes[item.id] else { continue }
            node.zPosition = RoomFurnitureSpec.forItem(item).isWall ? 10 : 1_000 - node.position.y
        }
        restFront.isHidden = true
        if cat.isEnteringFurniture, let visit = activeRest, let node = furnitureNodes[visit.item.id] {
            // Before front-paw contact, preserve ordinary ground depth. Once
            // supported, the cat and its paw-height animation sit above the
            // cushion surface; never draw the entire cushion across its body.
            if cat.stepPhase != .reaching { node.zPosition = cat.zPosition - 0.2 }
            // The near rim can cover paws only after the whole cat has crossed
            // onto the mattress. During entry/exit it otherwise cuts through
            // the chest while the rear paws are still on the floor.
            if visit.item.kind == .catBed, cat.stepPhase == .supported {
                let fraction: CGFloat = 0.22
                restFront.isHidden = false
                restFront.xScale = node.xScale
                restFront.size = CGSize(width: node.size.width, height: node.size.height * fraction)
                restFront.position = CGPoint(x: node.position.x,
                                             y: node.position.y + node.size.height * (fraction / 2 - node.anchorPoint.y))
                restFront.zPosition = cat.zPosition + 0.2
            }
        }
    }

    func setBowlTexture(_ name: String) {
        let texture = SKTexture(imageNamed: name)
        bowl.texture = texture
        // SpriteKit UV y=0 is the image bottom. Keep the lower bowl wall in
        // front while a feeding muzzle reaches over the rear rim and food.
        // The cut starts below the measured mouth (source y=315) and above
        // the paws, so paws never appear painted onto the food surface.
        bowlFront.texture = SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: 0.68), in: texture)
    }

    func updateBowlLayers(cat: CatActor, floor: RoomFloor?) {
        bowlFront.isHidden = bowl.isHidden
        bowlFront.size = CGSize(width: bowl.size.width, height: bowl.size.height * 0.68)
        bowlFront.position = CGPoint(x: bowl.position.x, y: bowl.position.y - bowl.size.height * 0.16)
        let groundDepth = 1_000 - (floor?.bowlGround(at: bowl.position).y ?? bowl.position.y)
        let muzzleOverFood = cat.isMuzzleOverFood
        bowl.zPosition = muzzleOverFood ? cat.zPosition - 0.2 : groundDepth
        bowlFront.zPosition = muzzleOverFood ? cat.zPosition + 0.2 : groundDepth + 0.01
    }

    func updateSelection(editing: Bool, selectedFurnitureID: String?, ownedFurniture: [FurnitureItem],
                         furnitureWorld: RoomFurnitureWorld, floor: RoomFloor?) {
        selection.isHidden = !editing
        if let id = selectedFurnitureID, let item = ownedFurniture.first(where: { $0.id == id }),
           let node = furnitureNodes[id] {
            let size = furnitureWorld.footprint(item)
            let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            selection.path = RoomFurnitureSpec.forItem(item).isWall
                ? CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
                : CGPath(ellipseIn: rect, transform: nil)
            selection.position = node.position
            selection.setScale(1)
        } else {
            let rect = CGRect(x: -bowl.size.width * 0.55, y: -bowl.size.width * 0.24,
                              width: bowl.size.width * 1.10, height: bowl.size.width * 0.48)
            selection.path = CGPath(ellipseIn: rect, transform: nil)
            selection.position = floor?.bowlGround(at: bowl.position) ?? bowl.position
            selection.setScale(1)
        }
    }
    func showCareParticles(cat: CatActor, reducedMotion: Bool) {
        guard !reducedMotion else { return }
        #if os(iOS)
        guard let image = UIImage(systemName: "sparkles")?.withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
        #else
        guard let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.white])) else { return }
        #endif
        for index in 0..<3 {
            let particle = SKSpriteNode(texture: SKTexture(image: image))
            particle.name = "care-particle"
            particle.size = CGSize(width: 14, height: 14)
            particle.position = CGPoint(x: cat.position.x - 18 + CGFloat(index) * 19, y: cat.visualFrame.midY)
            particle.zPosition = 2_010
            particle.alpha = 0
            container?.addChild(particle)
            particle.run(.sequence([.wait(forDuration: 0.4 + Double(index) * 0.12), .fadeIn(withDuration: 0.1),
                                    .group([.moveBy(x: CGFloat(index - 1) * 6, y: 22, duration: 0.8), .fadeOut(withDuration: 0.8)]), .removeFromParent()]))
        }
    }
}
