#if DEBUG
import SpriteKit
import CatGameCore

/// Debug-only UI-test instrumentation; no counters, test flags or JSON samples
/// from this component are compiled into a shipping Release app.
@MainActor
final class RoomSceneDiagnostics {
    let navigationTesting: Bool
    let dragTesting: Bool
    let furnitureTesting: Bool
    var enabled: Bool { navigationTesting || dragTesting || furnitureTesting }
    var onPresentationChanged: ((String) -> Void)?
    var onNavigationChanged: ((String) -> Void)?
    var onDragMetricsChanged: ((String) -> Void)?
    var onFurnitureDiagnosticsChanged: ((String) -> Void)?
    private(set) var navigationDescription = ""
    private(set) var dragDescription = "0|0|0|0,0"
    private(set) var furnitureDescription = "{}"
    private var presentationEvents: [String] = []
    func recordPresentationEvent(_ event: String) {
        guard enabled else { return }
        presentationEvents.append(event)
        if presentationEvents.count > 10 { presentationEvents.removeFirst() }
    }
    var lastRestEndReason = "none"
    var lastRestInput = "none"
    var restExits = 0
    var carePlanning = false
    var carePlanCompletions = 0
    var carePlanCancelled = 0
    var lastCarePlanMilliseconds: Double = 0
    var lastCarePlanOnMainThread = false
    var bowlPlanning = false
    var bowlPlanCompletions = 0
    var bowlPlanCancelled = 0
    var lastBowlPlanOnMainThread = false
    var lastRestInterrupt: [String: Any]?
    var dragMoveSamples = 0
    var furnitureDragPreviewSamples = 0
    var furnitureDragPreviewPoint: CGPoint?
    var maximumDragMoveMs: Double = 0
    private var restContactSamples = 0
    private var stepForeSupportSamples = 0
    private var bedEdgeContactSamples = 0
    private var bedEdgeContactViolations = 0
    private var bedEdgeMaxError: CGFloat = 0
    private var stepLiftSamples = 0
    private var stepDownSamples = 0
    private var stepClearanceViolations = 0
    private var foodContactSamples = 0
    private var foodContactViolations = 0
    private var collisionViolations = 0
    private var residentCollisionViolations = 0
    private var longestRoute = 0
    private var lastDiagnosticTime: TimeInterval = 0

    init() {
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("--ui-testing")
        navigationTesting = testing && args.contains("--navigation-test")
        dragTesting = testing && args.contains("--drag-performance-test")
        furnitureTesting = testing && (args.contains("--furniture-test") || args.contains("--rest-test"))
    }

    struct FurnitureState {
        let geometry: RoomWorldGeometry
        let cameraPosition: CGPoint
        let cameraScale: CGFloat
        let roomLevel: Int
        let catWidth: CGFloat
        let bowlWidth: CGFloat
        let furnitureWorld: RoomFurnitureWorld
        let renderedFurniture: [FurniturePlacement]
        let ownedFurniture: [FurnitureItem]
        let furnitureNodes: [String: SKSpriteNode]
        let selectedFurnitureID: String?
        let isPlacementPending: Bool
        let presentationPhase: String
        let activeRest: RoomFurnitureRest?
        let restSessionID: String?
        let restSessionWasCommitted: Bool
        let restEndReported: Bool
        let restDeadline: Date?
        let latest: GameSnapshot?
        let presentation: RoomPresentationRenderer
        let viewAngle: RoomViewAngle
    }

    func sample(at currentTime: TimeInterval, cat: CatActor, floor: RoomFloor?, navigation: RoomNavigation?,
                activeRest: RoomFurnitureRest?, editing: Bool, activeFeedingDock: FeedingDock?,
                dockingNavigation: RoomNavigation?, furnitureWorld: RoomFurnitureWorld,
                renderedFurniture: [FurniturePlacement], bowl: CGPoint) -> Bool {
        if navigationTesting || furnitureTesting {
            if (!editing || activeRest != nil), let floor {
                let feet: CGRect
                let occupied = cat.isEnteringFurniture ? activeRest : nil
                if cat.isDockingForMeal, let dock = activeFeedingDock, let dockingNavigation {
                    feet = dock.feetRect(at: cat.position)
                    if !dockingNavigation.isWalkable(dock.footCenter(at: cat.position)) { collisionViolations += 1 }
                } else {
                    feet = CGRect(x: cat.position.x - floor.catFootprint.width / 2,
                                  y: cat.position.y - floor.catFootprint.height / 2,
                                  width: floor.catFootprint.width, height: floor.catFootprint.height)
                    if (occupied?.navigation ?? navigation)?.isWalkable(cat.position) != true { collisionViolations += 1 }
                }
                // Independently audit the live bowl even if a navigation cache
                // becomes stale. Docking changes foot registration, not solidity.
                if feet.intersects(floor.bowlObstacle(at: bowl)) { collisionViolations += 1 }
                if furnitureWorld.floorObstacles(excluding: occupied?.item.id).contains(where: { feet.intersects($0) }) {
                    collisionViolations += 1
                }
                if cat.isRestingOnFurniture, let visit = occupied {
                    if visit.target.contains(cat.position),
                       hypot(cat.position.x - visit.plan.restPoint.x, cat.position.y - visit.plan.restPoint.y) < 1,
                       renderedFurniture.contains(where: { $0.itemID == visit.item.id }) {
                        restContactSamples += 1
                    } else { collisionViolations += 1 }
                }
                // Audit the sprite's measured paw landmarks, not just the
                // actor's floor anchor. Ground collision alone cannot prove
                // that a climbing pose clears the cushion's visible edge.
                if let front = cat.frontPawContact, let rear = cat.rearPawContact {
                    if ![front.x, front.y, rear.x, rear.y, cat.supportElevation].allSatisfy(\.isFinite) {
                        stepClearanceViolations += 1
                    } else {
                        switch cat.stepPhase {
                        case .frontPaws:
                            stepForeSupportSamples += 1
                            if front.y <= rear.y { stepClearanceViolations += 1 }
                            if let visit = occupied, let band = visit.entrySupportBand,
                               cat.stepProgress >= visit.entryContactProgress - 0.001 {
                                // Measure the held paw against the real yellow
                                // mattress edge, not merely against its rear paw.
                                let dx = max(band.minX - front.x, 0, front.x - band.maxX)
                                let dy = max(band.minY - front.y, 0, front.y - band.maxY)
                                let error = hypot(dx, dy)
                                bedEdgeContactSamples += 1
                                bedEdgeMaxError = max(bedEdgeMaxError, error)
                                if error > 1 { bedEdgeContactViolations += 1 }
                            }
                        case .lifting: stepLiftSamples += 1
                        case .frontPawsDown, .lowering:
                            stepDownSamples += 1
                            if rear.y <= front.y { stepClearanceViolations += 1 }
                        case .rearPawsDown:
                            // Backing out of a partially completed climb puts
                            // the rear paws down first, without turning midair.
                            stepDownSamples += 1
                        default: break
                        }
                    }
                }
                if let contact = cat.currentMealContact {
                    foodContactSamples += 1
                    if activeFeedingDock?.containsFoodContact(contact) != true { foodContactViolations += 1 }
                }
            }
        }
        if (navigationTesting || dragTesting || furnitureTesting), currentTime - lastDiagnosticTime > 0.25 {
            lastDiagnosticTime = currentTime
            return true
        }
        return false
    }

    func sampleResidents(_ residents: RoomResidentCats, cat: CatActor, floor: RoomFloor?, dock: FeedingDock?) {
        guard furnitureTesting, let floor else { return }
        let activeFeet = cat.isDockingForMeal ? dock?.feetRect(at: cat.position) : nil
        let groundFeet = CGRect(x: cat.position.x - floor.catFootprint.width / 2,
                                y: cat.position.y - floor.catFootprint.height / 2,
                                width: floor.catFootprint.width, height: floor.catFootprint.height)
        let footprints = [activeFeet ?? groundFeet] + residents.actors.values.filter { !$0.isHidden }.map {
            CGRect(x: $0.position.x - floor.catFootprint.width / 2,
                   y: $0.position.y - floor.catFootprint.height / 2,
                   width: floor.catFootprint.width, height: floor.catFootprint.height)
        }
        for first in footprints.indices {
            for second in footprints.indices where second > first {
                if footprints[first].intersects(footprints[second]) { residentCollisionViolations += 1 }
            }
        }
    }

    func noteRoute(_ path: [CGPoint], navigation: RoomNavigation?) {
        longestRoute = max(longestRoute, path.count)
        if navigationTesting, let navigation,
           !zip(path, path.dropFirst()).allSatisfy({ navigation.segmentIsWalkable(from: $0.0, to: $0.1) }) {
            collisionViolations += 1
        }
    }

    func publishNavigationStatus(phase presentationPhase: String, cat: CatActor, bowl: CGPoint,
                                 geometry: RoomWorldGeometry, presentation: RoomPresentationRenderer) {
        let size = presentation.camera.viewportSize
        guard navigationTesting, size.width > 0, size.height > 0 else { return }
        let catPoint = presentation.anchor("cat") ?? .zero
        let bowlPoint = presentation.anchor("bowl") ?? .zero
        navigationDescription = String(format: "%@|%d|%.3f,%.3f|%.3f,%.3f|%d|%d|%d|%d|%d", presentationPhase,
                                       collisionViolations, catPoint.x / size.width, catPoint.y / size.height,
                                       bowlPoint.x / size.width, bowlPoint.y / size.height, longestRoute,
                                       cat.completedMeals, cat.completedPounces, foodContactSamples, foodContactViolations)
        navigationDescription += "|" + presentationEvents.joined(separator: "; ")
        onNavigationChanged?(navigationDescription)
    }
    func publishDragMetrics(pending isPlacementPending: Bool, bowl: CGPoint,
                            geometry: RoomWorldGeometry, presentation: RoomPresentationRenderer) {
        let size = presentation.camera.viewportSize
        guard dragTesting, size.width > 0, size.height > 0 else { return }
        let point = presentation.anchor("bowl") ?? .zero
        dragDescription = String(format: "%d|%.3f|%d|%.3f,%.3f", dragMoveSamples, maximumDragMoveMs,
                                 isPlacementPending ? 1 : 0, point.x / size.width, point.y / size.height)
        onDragMetricsChanged?(dragDescription)
    }

    func publishFurnitureStatus(_ state: FurnitureState, cat: CatActor, bowl: CGPoint,
                                residents: RoomResidentCats, bowlHasFood: Bool) {
        let size = state.presentation.camera.viewportSize
        let worldSize = state.geometry.worldSize
        func screenPoint(_ point: CGPoint) -> [String: CGFloat] {
            let projected = state.presentation.camera.viewPoint(projectedWorld: state.presentation.projection.project(point))
            return ["x": projected.x / size.width, "y": projected.y / size.height]
        }
        func worldPoint(_ point: CGPoint) -> [String: CGFloat] {
            ["x": point.x / worldSize.width, "y": 1 - point.y / worldSize.height]
        }
        func catScreenPoint(_ point: CGPoint) -> [String: CGFloat] {
            guard let display = state.presentation.displayedPoint(point, source: cat, key: "cat") else { return screenPoint(point) }
            return ["x": display.x / size.width, "y": display.y / size.height]
        }
        let renderedFurniture = state.renderedFurniture
        let ownedFurniture = state.ownedFurniture
        let furnitureNodes = state.furnitureNodes
        let selectedFurnitureID = state.selectedFurnitureID
        let isPlacementPending = state.isPlacementPending
        let presentationPhase = state.presentationPhase
        let activeRest = state.activeRest
        let restSessionID = state.restSessionID
        let restSessionWasCommitted = state.restSessionWasCommitted
        let restEndReported = state.restEndReported
        let restDeadline = state.restDeadline
        let latest = state.latest
        guard furnitureTesting, size.width > 0, size.height > 0 else { return }
        let objects: [[String: Any]] = renderedFurniture.compactMap { placement in
            guard let item = ownedFurniture.first(where: { $0.id == placement.itemID }),
                  let node = furnitureNodes[item.id] else { return nil }
            let anchor = state.presentation.anchor("furniture-" + item.id)
            let screen = anchor.map { ["x": $0.x / size.width, "y": $0.y / size.height] } ?? screenPoint(node.position)
            let world = worldPoint(node.position)
            let footprint = state.furnitureWorld.footprint(item)
            return ["id": item.id, "kind": item.kind.rawValue,
                    "orientation": item.orientation.rawValue, "usesLegacyFootprint": item.usesLegacyFootprint,
                    "x": screen["x"]!, "y": screen["y"]!,
                    "worldX": world["x"]!, "worldY": world["y"]!,
                    "width": node.size.width, "height": node.size.height,
                    "screenWidth": node.size.width / state.cameraScale, "screenHeight": node.size.height / state.cameraScale,
                    "footprintWidth": footprint.width, "footprintHeight": footprint.height]
        }
        let catNodes = [(state.latest?.activeCatID ?? "", cat)] + residents.actors.map { ($0.key, $0.value) }
        let residentCats: [[String: Any]] = catNodes.map { id, actor in
            let frame = state.presentation.frame(actor === cat ? "cat" : "resident-" + id)
            let point = frame.map { ["x": $0.midX / size.width, "y": $0.midY / size.height] } ?? screenPoint(actor.position)
            return ["id": id, "x": point["x"]!, "y": point["y"]!, "visible": !actor.isHidden,
                    "screenWidth": frame?.width ?? 0, "screenHeight": frame?.height ?? 0]
        }
        let meshRestSeat: [String: CGFloat]? = activeRest.flatMap { visit in
            guard let node = furnitureNodes[visit.item.id],
                  let variant = FurnitureArtwork68.variant(for: visit.item, angle: state.viewAngle),
                  let offset = variant.surfaceOffset("seatCenter", referenceWidth: node.size.width),
                  let anchor = state.presentation.anchor("furniture-" + visit.item.id) else { return nil }
            return ["x": (anchor.x + offset.x / state.cameraScale) / size.width,
                    "y": (anchor.y - offset.y / state.cameraScale) / size.height]
        }
        let payload: [String: Any] = [
            "meshRestSeat": meshRestSeat as Any? ?? NSNull(),
            "companionLabelText": (state.presentation.root.childNode(withName: "*/companion-name")?.children.first as? SKLabelNode)?.text ?? "",
            "viewAngle": state.viewAngle.rawValue, "wholeRoom": state.presentation.camera.isWholeRoom,
            "fitScale": state.presentation.camera.fitScale,
            "residentCollisions": residentCollisionViolations, "residentCats": residentCats, "residentsBusy": residents.isBusy, "bowlHasFood": bowlHasFood,
            "roomLevel": state.roomLevel,
            "worldWidth": worldSize.width, "worldHeight": worldSize.height,
            "viewportWidth": size.width, "viewportHeight": size.height,
            "cameraX": state.cameraPosition.x, "cameraY": state.cameraPosition.y,
            "cameraScale": state.cameraScale, "zoomFactor": 1 / state.cameraScale,
            "catVisualWidth": state.catWidth, "bowlVisualWidth": state.bowlWidth,
            "catScreenWidth": state.catWidth / state.cameraScale, "bowlScreenWidth": state.bowlWidth / state.cameraScale,
            "savedBowl": latest.map { ["x": $0.home.bowlPosition.x, "y": $0.home.bowlPosition.y] } as Any? ?? NSNull(),
            "savedFurniture": latest?.home.furniture.map {
                ["itemID": $0.itemID, "x": $0.position.x, "y": $0.position.y] as [String: Any]
            } as Any? ?? NSNull(),
            "items": objects, "selected": selectedFurnitureID ?? "bowl", "pending": isPlacementPending,
            "dragPreviewSamples": furnitureDragPreviewSamples,
            "dragPreviewWorld": furnitureDragPreviewPoint.map(worldPoint) as Any? ?? NSNull(),
            "phase": presentationPhase, "violations": collisionViolations,
            "completedMeals": cat.completedMeals, "completedPounces": cat.completedPounces,
            "foodContactSamples": foodContactSamples,
            "foodContactViolations": foodContactViolations,
            "restFurniture": activeRest?.item.id as Any? ?? NSNull(),
            "restPoint": activeRest.map { screenPoint($0.plan.restPoint) } as Any? ?? NSNull(),
            "restPhase": cat.restPhase.rawValue, "restContactSamples": restContactSamples,
            "restSession": restSessionID as Any? ?? NSNull(),
            "restSessionCommitted": restSessionWasCommitted,
            "restSessionEndReported": restEndReported,
            "restDeadline": restDeadline?.timeIntervalSince1970 as Any? ?? NSNull(),
            "activeCatID": latest?.activeCatID as Any? ?? NSNull(),
            "catAppearance": latest?.activeCat?.appearance.rawValue as Any? ?? NSNull(),
            "savedRestSession": latest?.activeCat?.activeRest?.id as Any? ?? NSNull(),
            "catEnergy": latest?.activeCat?.energy as Any? ?? NSNull(),
            "lastRestEndReason": lastRestEndReason,
            "lastRestInput": lastRestInput,
            "stepPhase": cat.stepPhase.rawValue, "stepProgress": cat.stepProgress,
            "supportElevation": cat.supportElevation,
            "restVisualPoint": cat.restVisualContactPoint.map(catScreenPoint) as Any? ?? NSNull(),
            "bedEdgeContactSamples": bedEdgeContactSamples,
            "bedEdgeContactViolations": bedEdgeContactViolations,
            "bedEdgeMaxError": bedEdgeMaxError,
            "frontPaw": cat.frontPawContact.map(catScreenPoint) as Any? ?? NSNull(),
            "rearPaw": cat.rearPawContact.map(catScreenPoint) as Any? ?? NSNull(),
            "stepForeSupportSamples": stepForeSupportSamples, "stepLiftSamples": stepLiftSamples,
            "stepDownSamples": stepDownSamples, "stepClearanceViolations": stepClearanceViolations,
            "lastRestInterrupt": lastRestInterrupt as Any? ?? NSNull(),
            "completedRests": cat.completedRests, "restExits": restExits,
            "carePlanning": carePlanning, "carePlanCompletions": carePlanCompletions,
            "carePlanCancelled": carePlanCancelled, "lastCarePlanMilliseconds": lastCarePlanMilliseconds,
            "lastCarePlanOnMainThread": lastCarePlanOnMainThread,
            "bowlPlanning": bowlPlanning, "bowlPlanCompletions": bowlPlanCompletions,
            "bowlPlanCancelled": bowlPlanCancelled, "lastBowlPlanOnMainThread": lastBowlPlanOnMainThread,
            "bowl": screenPoint(bowl), "cat": screenPoint(cat.position),
            "bowlWorld": worldPoint(bowl), "catWorld": worldPoint(cat.position)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            furnitureDescription = text
            onFurnitureDiagnosticsChanged?(text)
        }
    }

}
#endif
