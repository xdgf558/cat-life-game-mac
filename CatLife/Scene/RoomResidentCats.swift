import SpriteKit
import CatGameCore

/// Other companions share the floor, but care and durable rest belong to the selected cat.
@MainActor
final class RoomResidentCats {
    static let unlockLevel = 4
    private(set) var actors: [String: CatActor] = [:]
    private var preparedIDs: [String]?
    private var revision = 0
    private var worker: Task<Void, Never>?
    private(set) var isBusy = false
    private(set) var isPreparing = false
    var isStrolling: Bool { isBusy && !isPreparing }
    var onFinished: (() -> Void)?
    var onLimitedSpace: (() -> Void)?

    var obstacles: [CGRect] {
        actors.values.filter { !$0.isHidden }.map {
            RoomResidentPlanner.obstacle(at: $0.position, width: visualWidth)
        }
    }
    private var visualWidth: CGFloat = 0

    func hit(at point: CGPoint) -> String? {
        actors.filter { !$0.value.isHidden && $0.value.visualFrame.contains(point) }
            .max { $0.value.zPosition < $1.value.zPosition }?.key
    }

    func updateDepths() {
        for actor in actors.values { actor.zPosition = 1_000 - actor.position.y }
    }

    func invalidate(hide: Bool = false) {
        revision += 1
        worker?.cancel()
        worker = nil
        isBusy = false
        isPreparing = false
        preparedIDs = nil
        for actor in actors.values {
            actor.cancelAndSettle(at: actor.position)
            actor.setIdleEnabled(false)
            if hide { actor.isHidden = true }
        }
    }

    func setIdleEnabled(_ enabled: Bool) {
        for actor in actors.values { actor.setIdleEnabled(enabled && !actor.isPerforming && !actor.isHidden) }
    }

    /// Layout previews may cover a cat's old tile. Plan its short evacuation
    /// against the previous floor, accepting only a clear endpoint in the new one.
    func yieldForArrangement68(from previous: RoomFloor, to next: RoomFloor, bowl: CGPoint, active: CGPoint,
                               previousBowl: CGPoint? = nil, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        let positions = actors.filter { !$0.value.isHidden }.mapValues(\.position)
        guard !positions.isEmpty else { completion(true); return }
        let previousIDs = preparedIDs
        invalidate()
        preparedIDs = previousIDs
        let ticket = revision
        let width = visualWidth
        isBusy = true; isPreparing = true
        let calculation = Task.detached(priority: .userInitiated) {
            var occupied = positions
            var paths: [(String, [CGPoint])] = []
            var allSafe = true
            for id in positions.keys.sorted() {
                guard !Task.isCancelled, let start = positions[id] else { return (paths, false) }
                let others = occupied.filter { $0.key != id }.values.map {
                    RoomResidentPlanner.obstacle(at: $0, width: width)
                } + [RoomResidentPlanner.obstacle(at: active, width: width)]
                let destination = next.addingObstacles(others).navigator(bowlAt: bowl)
                guard !destination.isWalkable(start) else { continue }
                let original = previous.addingObstacles(others).navigator(bowlAt: previousBowl ?? bowl, precomputeGrid: false)
                var found = false
                for point in destination.walkablePoints.sorted(by: {
                    hypot($0.x - start.x, $0.y - start.y) < hypot($1.x - start.x, $1.y - start.y)
                }) {
                    guard let route = original.route(from: start, to: point) else { continue }
                    paths.append((id, route)); occupied[id] = point; found = true; break
                }
                if !found { allSafe = false }
            }
            return (paths, allSafe)
        }
        worker = Task { [weak self] in
            let (paths, allSafe) = await withTaskCancellationHandler { await calculation.value } onCancel: { calculation.cancel() }
            guard let self, self.revision == ticket, !Task.isCancelled else { return }
            self.worker = nil; self.isPreparing = false
            @MainActor func move(_ index: Int) {
                guard self.revision == ticket else { return }
                guard index < paths.count else { self.isBusy = false; completion(allSafe); return }
                guard let actor = self.actors[paths[index].0] else { move(index + 1); return }
                actor.stroll(along: paths[index].1) { move(index + 1) }
            }
            move(0)
        }
    }

    /// Exchange render roles at their actual positions, keeping the scene's care actor stable.
    func exchangeActive(from old: CatState?, to new: CatState?, at position: CGPoint) -> CGPoint? {
        guard let old, let new, let replacement = actors[new.id], !replacement.isHidden else {
            invalidate(); return nil
        }
        actors.removeValue(forKey: new.id)
        let destination = replacement.position
        invalidate()
        replacement.cancelAndSettle(at: position)
        replacement.setAppearance(old.appearance)
        replacement.name = "resident-\(old.id)"
        actors[old.id] = replacement
        return destination
    }

    func prepare(snapshot: GameSnapshot, active: CGPoint, scene: SKScene,
                 planner: RoomResidentPlanner, width: CGFloat, reducedMotion: Bool) {
        let cats = snapshot.home.roomLevel >= Self.unlockLevel
            ? snapshot.cats.filter { $0.id != snapshot.activeCatID } : []
        let ids = cats.map(\.id)
        guard preparedIDs != ids, !isBusy else { return }
        for id in Array(actors.keys) where !ids.contains(id) {
            actors.removeValue(forKey: id)?.removeFromParent()
        }
        visualWidth = width
        guard !cats.isEmpty else { preparedIDs = []; return }
        revision += 1
        let ticket = revision
        isBusy = true
        isPreparing = true
        let existing = ids.prefix { actors[$0] != nil }.compactMap { actors[$0]?.position }
        let calculation = Task.detached(priority: .userInitiated) {
            planner.positions(count: cats.count, existing: existing)
        }
        worker = Task { [weak self, weak scene] in
            let points = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: { calculation.cancel() }
            guard let self, let scene, !Task.isCancelled, self.revision == ticket else { return }
            self.worker = nil
            for (index, state) in cats.enumerated() {
                guard index < points.count else {
                    self.actors[state.id]?.isHidden = true
                    continue
                }
                let actor = self.actors[state.id] ?? CatActor()
                actor.name = "resident-\(state.id)"
                actor.setAppearance(state.appearance)
                actor.setVisualWidth(width)
                actor.reducedMotion = reducedMotion
                actor.cancelAndSettle(at: points[index])
                actor.isHidden = false
                if actor.parent == nil { ((scene as? RoomScene)?.simulationRoot ?? scene).addChild(actor) }
                actor.setIdleEnabled(true)
                self.actors[state.id] = actor
            }
            self.preparedIDs = ids
            self.isBusy = false
            self.isPreparing = false
            if points.count < cats.count { self.onLimitedSpace?() }
            self.onFinished?()
        }
    }

    /// One cat travels at a time. All other cats keep breathing and looking around.
    @discardableResult
    func stroll(planner: RoomResidentPlanner, active: CGPoint, activeActor: CatActor) -> Bool {
        var candidates = actors.filter { !$0.value.isHidden }
        candidates["active"] = activeActor
        guard !isBusy, let (id, actor) = candidates.randomElement() else { return false }
        isBusy = true
        revision += 1
        let ticket = revision
        let origin = actor.position
        let others = actors.filter { $0.key != id && !$0.value.isHidden }.map { $0.value.position }
        let calculation = Task.detached(priority: .utility) {
            planner.stroll(from: origin, others: others, active: active)
        }
        worker = Task { [weak self, weak actor] in
            let path = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: { calculation.cancel() }
            guard let self, let actor, !Task.isCancelled, self.revision == ticket else { return }
            self.worker = nil
            guard let path else { self.isBusy = false; self.onFinished?(); return }
            actor.setIdleEnabled(false)
            actor.stroll(along: path) { [weak self, weak actor] in
                guard let self, self.revision == ticket else { return }
                self.isBusy = false
                actor?.setIdleEnabled(true)
                self.onFinished?()
            }
        }
        return true
    }
}
