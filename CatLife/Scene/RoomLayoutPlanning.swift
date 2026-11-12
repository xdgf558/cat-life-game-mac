import Foundation
import CoreGraphics
import CatGameCore

/// A complete proposed world. Visible nodes stay in their last validated world
/// until this proposal has a matching bowl, safe cat position and navigator.
struct RoomLayoutProposal: Sendable {
    let geometry: RoomWorldGeometry
    let roomLevel: Int
    let artworkSize: CGSize
    let items: [FurnitureItem]
    let placements: [FurniturePlacement]
    let catWidth: CGFloat
    let bowlSize: CGSize
    let planner: RoomBowlPlanner
    let opening: RoomHabitOpening?
    let snapshotCatID: String?

    init(viewport: CGSize, roomLevel: Int, artworkSize: CGSize, bowlAspect: CGFloat,
         items: [FurnitureItem], placements: [FurniturePlacement], bowl: NormalizedPoint,
         previousCat: CGPoint?, previousWorld: CGSize, opening: RoomHabitOpening? = nil, snapshotCatID: String? = nil) {
        self.opening = opening
        self.snapshotCatID = snapshotCatID
        self.geometry = RoomWorldGeometry(viewportSize: viewport,
            worldScale: CGFloat(HomeCatalog.level(roomLevel)?.worldScale ?? 1))
        self.roomLevel = roomLevel
        self.artworkSize = artworkSize
        self.items = items
        self.placements = placements
        catWidth = min(viewport.width * 0.14, viewport.height * 0.172)
        let bowlWidth = min(viewport.width * 0.156, viewport.height * 0.185)
        bowlSize = CGSize(width: bowlWidth, height: bowlWidth * bowlAspect)
        let worldSize = geometry.worldSize
        let catPoint = previousCat.map {
            CGPoint(x: $0.x / previousWorld.width * worldSize.width,
                    y: $0.y / previousWorld.height * worldSize.height)
        } ?? CGPoint(x: worldSize.width * 0.43, y: worldSize.height * 0.18)
        let bowlPoint = CGPoint(x: worldSize.width * bowl.x, y: worldSize.height * (1 - bowl.y))
        let world = RoomFurnitureWorld(transform: .init(sceneSize: worldSize, artworkSize: artworkSize,
            viewportSize: viewport), catWidth: catWidth, bowlSize: bowlSize,
            bowlPosition: bowlPoint, items: items, placements: placements)
        planner = RoomBowlPlanner(floor: world.roomFloor, requested: bowlPoint, catPosition: catPoint)
    }

    func resolve() -> RoomBowlResolution? {
        guard var result = planner.resolve() else { return nil }
        guard let opening, let origin = result.catPosition else { return result }
        let world = RoomFurnitureWorld(transform: .init(sceneSize: geometry.worldSize, artworkSize: artworkSize,
            viewportSize: geometry.viewportSize), catWidth: catWidth, bowlSize: bowlSize,
            bowlPosition: result.center, items: items, placements: placements)
        result.openingPosition = RoomHabitBehavior.openingPoint(opening, world: world, origin: origin, navigation: result.navigation)
        return result
    }
}

/// Owns cancellation and publication of layout generations, including a retained
/// request while the scene is backgrounded. No worker can mutate SpriteKit nodes.
@MainActor
final class RoomLayoutPlanning {
    private(set) var proposal: RoomLayoutProposal?
    private var worker: Task<RoomBowlResolution?, Never>?
    private var revision = 0
    var isRunning: Bool { worker != nil }
#if DEBUG
    var delay: Duration = .zero
#endif

    func prepare(_ proposal: RoomLayoutProposal) {
        cancel(keepingRequest: false)
        self.proposal = proposal
    }

    func cancel(keepingRequest: Bool) {
        revision += 1
        worker?.cancel()
        worker = nil
        if !keepingRequest { proposal = nil }
    }

    func start(completion: @escaping @MainActor (RoomLayoutProposal, RoomBowlResolution) -> Void) {
        guard worker == nil, let proposal else { return }
        revision += 1
        let ticket = revision
#if DEBUG
        let delay = delay
#endif
        let task = Task.detached(priority: .userInitiated) {
#if DEBUG
            if delay > .zero { try? await Task.sleep(for: delay) }
#endif
            return proposal.resolve()
        }
        worker = task
        Task { [weak self] in
            let result = await task.value
            guard let self, self.revision == ticket else { return }
            self.worker = nil
            guard let result else { return }
            self.proposal = nil
            completion(proposal, result)
        }
    }
}
