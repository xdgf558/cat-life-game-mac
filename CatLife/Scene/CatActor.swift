import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// Presentation only. A single owner serializes movement, expressions and care
/// feedback, so a second tap never resets a walking cat to the room's origin.
@MainActor
final class CatActor: SKNode {
    var onSound: ((GameSoundEffect) -> Void)?
    enum RestPhase: String {
        case none, approaching, entering, settling, resting, waking, leaving
    }

    typealias FurnitureStepPhase = CatFurnitureStepPhase

    private struct RestRequest {
        let approach: [CGPoint]
        let entry: [CGPoint]
        let facing: CGFloat
        let duration: TimeInterval
        let elevation: CGFloat
        let contactProgress: CGFloat
        let onSettled: () -> Void
        let habitMatched: Bool?
        let introductionStyle: CatBehaviorStyle?
    }

    private enum Activity {
        case feed(eatingPoint: CGPoint, facing: CGFloat, approach: [CGPoint], dockingPath: [CGPoint],
                  returnPath: [CGPoint], onMealFinished: () -> Void)
        case clean(home: CGPoint)
        case play(landing: CGPoint, facing: CGFloat, returnPath: [CGPoint], prepared: Bool, finishIndex: Int?)
        case stroll(path: [CGPoint])
        case rest(RestRequest)

        func restingPoint(from origin: CGPoint) -> CGPoint {
            switch self {
            case let .clean(home): home
            case .rest: origin
            case let .feed(_, _, _, _, path, _), let .play(_, _, path, _, _), let .stroll(path):
                // Empty/single-point routes convey no movement. In particular,
                // they must not turn a reduced-motion change into a teleport.
                CatWalkRoute(path)?.destination ?? origin
            }
        }
    }

    private final class WalkTraversal {
        var mayMove = false
        var initialPoseX: CGFloat = 0
        var withdrawalForeHeight: CGFloat?
    }

    private final class StepSpanTransition {
        var initialSpan: CGFloat?
        var initialForeHeight: CGFloat?
        var preservesSpan = false
        var blendsToSupport = false
        var releasesReachingPaw = false
    }

    private struct PendingActivity {
        var activity: Activity
        var completions: [() -> Void]
    }

    private let pose = SKNode()
    private let sprite = SKSpriteNode()
    private let shadow = SKNode()
    private let shadowOuter = SKShapeNode()
    private let shadowInner = SKShapeNode()
    private let art = CatSpriteLibrary()
    private var appearance: CatAppearance = .orange
    private var visualWidth: CGFloat = 128
    private var idleEnabled = true
    private var facing: CGFloat = 1
    private var lastFrameKey = ""
    private var currentClip: CatClip = .expressions
    private var currentFrameIndex = 0
    private var restingPoint = CGPoint.zero
    private var activityGeneration = 0
    private var idleGeneration = 0
    private var completions: [() -> Void] = []
    private var pending: PendingActivity?
    private var furnitureSurfaceElevation: CGFloat = 0
    private var stepFrontWarp = CGPoint.zero
    private var stepRearWarp = CGPoint.zero

    private(set) var isPerforming = false
    private(set) var isDockingForMeal = false
#if DEBUG
    private(set) var completedMeals = 0
    private(set) var completedPounces = 0
    private(set) var lastRestIntroductionStyle: CatBehaviorStyle?
    private(set) var lastResponseFinishIndex: Int?
#endif
    private(set) var restPhase: RestPhase = .none
    /// Covers entry, the stay, and exit until the scene's safe stage is reached.
    private(set) var isEnteringFurniture = false
    private(set) var isRestingOnFurniture = false
#if DEBUG
    /// Count a visit once, only after the cat has actually lain down at its target.
    private(set) var completedRests = 0
#endif
    private(set) var stepPhase: FurnitureStepPhase = .none
    /// Distance along the furniture entry, not an animation clock. Reversing an
    /// unfinished entry preserves this value and returns continuously to zero.
    private(set) var stepProgress: CGFloat = 0
#if DEBUG
    var supportElevation: CGFloat { isEnteringFurniture ? pose.position.y : 0 }

    /// These are visible paw landmarks, not the navigation footprint's center.
    /// Return nil for sleep/walk poses where no step landmark was registered.
    var frontPawContact: CGPoint? {
        guard let parent else { return nil }
        return stepPawContact(front: true, to: parent)
    }
    var rearPawContact: CGPoint? {
        guard let parent else { return nil }
        return stepPawContact(front: false, to: parent)
    }

    /// Ground-space audit point; visual elevation never changes the route.
    var restContactPoint: CGPoint? { isEnteringFurniture ? position : nil }
    var restVisualContactPoint: CGPoint? {
        guard isEnteringFurniture, let parent else { return nil }
        return pose.convert(CGPoint.zero, to: parent)
    }

#endif

    private func stepPawContact(front: Bool, to node: SKNode) -> CGPoint? {
        guard isEnteringFurniture, currentClip == .step else { return nil }
        let sequence = art.sequence(.step)
        let frame = sequence.frames[min(currentFrameIndex, sequence.frames.count - 1)]
        guard let landmark = front ? frame.frontPaw : frame.rearPaw else { return nil }
        let unit = sprite.size.height / max(1, frame.bounds.height)
        let warp = front ? stepFrontWarp : stepRearWarp
        let local = CGPoint(x: (landmark.x - frame.bounds.midX) * unit + warp.x,
                            y: (frame.bounds.maxY - landmark.y) * unit + warp.y)
        return sprite.convert(local, to: node)
    }

    var renderSprite68: SKSpriteNode { sprite }

    /// Immutable actor-local landmarks used by the mesh presentation adapter.
    var artworkLandmarks68: CatArtworkLandmarks68 {
        var step: CatArtworkStepLandmarks68?
        if isEnteringFurniture, currentClip == .step,
           let front = stepPawContact(front: true, to: self),
           let rear = stepPawContact(front: false, to: self) {
            let sequence = art.sequence(.step)
            let frame = sequence.frames[min(currentFrameIndex, sequence.frames.count - 1)]
            if let f = frame.frontPaw, let r = frame.rearPaw {
                let origin = sprite.convert(CGPoint.zero, to: self)
                let x = sprite.convert(CGPoint(x: 1, y: 0), to: self)
                let y = sprite.convert(CGPoint(x: 0, y: 1), to: self)
                step = CatArtworkStepLandmarks68(frame: currentFrameIndex, frontPaw: front, rearPaw: rear,
                    frontUV: CGPoint(x: (f.x - frame.bounds.minX) / frame.bounds.width, y: (frame.bounds.maxY - f.y) / frame.bounds.height),
                    rearUV: CGPoint(x: (r.x - frame.bounds.minX) / frame.bounds.width, y: (frame.bounds.maxY - r.y) / frame.bounds.height),
                    spriteSize: sprite.size, spriteXAxis: CGPoint(x: x.x - origin.x, y: x.y - origin.y),
                    spriteYAxis: CGPoint(x: y.x - origin.x, y: y.y - origin.y), spriteID: ObjectIdentifier(sprite))
            }
        }
        let mealFrame = isDockingForMeal && currentClip == .meal ? currentFrameIndex : nil
        let mouth = mealFrame.flatMap { registeredMealContact(frame: $0, to: self) }
        var mean: CGPoint?
        if mealFrame != nil, let a = registeredMealContact(frame: 2, to: self),
           let b = registeredMealContact(frame: 3, to: self) {
            mean = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        return CatArtworkLandmarks68(poseOrigin: pose.convert(CGPoint.zero, to: self), visualWidth: visualWidth,
                                    mealFrame: mealFrame, mouth: mouth, meanMouth: mean, step: step)
    }

    private func stepPawHeight(front: Bool) -> CGFloat? {
        guard currentClip == .step else { return nil }
        let sequence = art.sequence(.step)
        let frame = sequence.frames[min(currentFrameIndex, sequence.frames.count - 1)]
        guard let landmark = front ? frame.frontPaw : frame.rearPaw else { return nil }
        let unit = sprite.size.height / max(1, frame.bounds.height)
        let height = (frame.groundY - landmark.y) * unit + (front ? stepFrontWarp.y : stepRearWarp.y)
        return height.isFinite ? height : nil
    }

    private var currentStepSpan: CGFloat? {
        guard let front = stepPawHeight(front: true), let rear = stepPawHeight(front: false) else { return nil }
        let span = front - rear
        return span.isFinite ? span : nil
    }

    private func nativeStepSpan(frame index: Int) -> CGFloat? {
        let sequence = art.sequence(.step)
        let frame = sequence.frames[min(max(index, 0), sequence.frames.count - 1)]
        guard let front = frame.frontPaw, let rear = frame.rearPaw else { return nil }
        let unit = visualWidth * 1.20 * sequence.heightRatio / max(1, sequence.referenceHeight)
        let span = (rear.y - front.y) * unit
        return span.isFinite ? span : nil
    }

    private func nativeStepRearHeight(frame index: Int) -> CGFloat? {
        let sequence = art.sequence(.step)
        let frame = sequence.frames[min(max(index, 0), sequence.frames.count - 1)]
        guard let rear = frame.rearPaw else { return nil }
        let unit = visualWidth * 1.20 * sequence.heightRatio / max(1, sequence.referenceHeight)
        let height = (frame.groundY - rear.y) * unit
        return height.isFinite ? height : nil
    }

    /// Production depth ordering needs only the contact pose, not audit coordinates.
    var isMuzzleOverFood: Bool {
        isDockingForMeal && currentClip == .meal && (currentFrameIndex == 2 || currentFrameIndex == 3)
    }

#if DEBUG
    /// The audit uses the same production landmark as mesh mouth alignment.
    var currentMealContact: CGPoint? {
        guard isDockingForMeal, currentClip == .meal, let parent else { return nil }
        return registeredMealContact(frame: currentFrameIndex, to: parent)
    }
#endif

    private func registeredMealContact(frame: Int, to node: SKNode) -> CGPoint? {
        let offset: CGPoint
        switch (appearance, frame) {
        case (.orange, 2): offset = CGPoint(x: 0.3791 * visualWidth, y: 0.1472 * visualWidth)
        case (.orange, 3): offset = CGPoint(x: 0.3084 * visualWidth, y: 0.1472 * visualWidth)
        case (.cow, 2): offset = CGPoint(x: 0.356148 * visualWidth, y: 0.140313 * visualWidth)
        case (.cow, 3): offset = CGPoint(x: 0.322526 * visualWidth, y: 0.106760 * visualWidth)
        case (.blue, 2): offset = CGPoint(x: 0.359527 * visualWidth, y: 0.144857 * visualWidth)
        case (.blue, 3): offset = CGPoint(x: 0.269013 * visualWidth, y: 0.122571 * visualWidth)
        case (.siamese, 2): offset = CGPoint(x: 0.345657 * visualWidth, y: 0.122156 * visualWidth)
        case (.siamese, 3): offset = CGPoint(x: 0.308259 * visualWidth, y: 0.118454 * visualWidth)
        case (.silver, 2): offset = CGPoint(x: 0.311914 * visualWidth, y: 0.111429 * visualWidth)
        case (.silver, 3): offset = CGPoint(x: 0.289271 * visualWidth, y: 0.081714 * visualWidth)
        default: return nil
        }
        return pose.convert(offset, to: node)
    }

    var reducedMotion = false {
        didSet {
            guard reducedMotion != oldValue else { return }
            if reducedMotion, restPhase == .none {
                cancelAndSettle(at: isPerforming ? restingPoint : position)
            }
            else { startIdleIfNeeded() }
        }
    }

    /// Hit testing in the actor's parent's coordinates, excluding its shadow.
    var visualFrame: CGRect {
        guard let parent else { return calculateAccumulatedFrame() }
        let rect = pose.calculateAccumulatedFrame()
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            .map { convert($0, to: parent) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min() ?? position.x, y: ys.min() ?? position.y,
                      width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    override init() {
        super.init()
        shadow.zPosition = -1
        shadowOuter.fillColor = UIColor(red: 0.34, green: 0.21, blue: 0.12, alpha: 0.045)
        shadowInner.fillColor = UIColor(red: 0.34, green: 0.21, blue: 0.12, alpha: 0.055)
        shadowOuter.strokeColor = .clear
        shadowInner.strokeColor = .clear
        shadow.addChild(shadowOuter)
        shadow.addChild(shadowInner)
        addChild(shadow)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        pose.addChild(sprite)
        addChild(pose)
        setVisualWidth(visualWidth)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("CatActor is created in code") }

    func setAppearance(_ appearance: CatAppearance) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        art.setAppearance(appearance)
        lastFrameKey = ""
        show(.expressions, frame: 0)
    }

    func setVisualWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        visualWidth = width
        shadowOuter.path = CGPath(ellipseIn: CGRect(x: -width * 0.43, y: -width * 0.065,
                                                   width: width * 0.86, height: width * 0.13), transform: nil)
        shadowInner.path = CGPath(ellipseIn: CGRect(x: -width * 0.32, y: -width * 0.045,
                                                   width: width * 0.64, height: width * 0.09), transform: nil)
        lastFrameKey = ""
        if !isPerforming { show(isRestingOnFurniture ? .rest : .expressions, frame: isRestingOnFurniture ? 4 : 0) }
    }

    func setIdleEnabled(_ enabled: Bool) {
        guard idleEnabled != enabled else {
            if enabled { startIdleIfNeeded() }
            return
        }
        idleEnabled = enabled
        if enabled { startIdleIfNeeded() }
        else { stopIdle() }
    }

    func feed(at eatingPoint: CGPoint, facing: CGFloat, approach: [CGPoint], dockingPath: [CGPoint],
              returnPath: [CGPoint], onMealFinished: @escaping () -> Void,
              completion: @escaping () -> Void) {
        submit(.feed(eatingPoint: eatingPoint, facing: facing, approach: approach,
                     dockingPath: dockingPath, returnPath: returnPath, onMealFinished: onMealFinished),
               completion: completion)
    }

    func clean(returnTo home: CGPoint, completion: @escaping () -> Void) {
        submit(.clean(home: home), completion: completion)
    }

    func play(landing: CGPoint, facing: CGFloat, returnPath: [CGPoint], prepared: Bool = false,
              responseFinishIndex: Int? = nil, completion: @escaping () -> Void) {
        submit(.play(landing: landing, facing: facing, returnPath: returnPath, prepared: prepared, finishIndex: responseFinishIndex), completion: completion)
    }

    func stroll(along path: [CGPoint], completion: @escaping () -> Void) {
        submit(.stroll(path: path), completion: completion)
    }

    /// Completion ends the stay, not the furniture contact: remain lying down
    /// until the scene supplies a separately validated exit with leaveRest().
    func rest(approach: [CGPoint], entry: [CGPoint], facing: CGFloat,
              duration: TimeInterval, elevation: CGFloat,
               contactProgress: CGFloat = CatFurnitureStepTimeline.defaultContactProgress,
               introductionStyle: CatBehaviorStyle? = nil,
               habitMatched: Bool? = nil,
              onSettled: @escaping () -> Void,
              completion: @escaping () -> Void) {
        submit(.rest(RestRequest(approach: approach, entry: entry, facing: facing,
                                  duration: duration, elevation: elevation, contactProgress: contactProgress,
                                  onSettled: onSettled, habitMatched: habitMatched, introductionStyle: introductionStyle)),
               completion: completion)
    }

    func habitAttention(style: CatBehaviorStyle, facing direction: CGFloat) {
        guard !isPerforming, !isEnteringFurniture else { return }
        stopIdle(); setFacing(direction)
        let action: SKAction
        switch style {
        case .playful: action = frame(.expressions, 4, hold: 0.08)
        case .curious: action = frames(.expressions, [4, 5, 4], durations: [0.15, 0.1, 0.1])
        case .quiet: action = frames(.play, [0, 1], durations: [0.18, 0.16])
        }
        run(action, withKey: "habit-attention")
    }

    func habitWaiting(facing direction: CGFloat) {
        guard !isPerforming, !isEnteringFurniture else { return }
        removeAction(forKey: "habit-attention")
        stopIdle(); setFacing(direction); show(.expressions, frame: 4)
    }

    /// The scene may interrupt a rest while approaching, stepping in or asleep.
    /// Do not run the superseded rest completion before beginning this exit.
    /// atSafeStage authorizes a zero-distance exit only after the scene has
    /// verified that this exact point supports the ordinary walking footprint.
    func leaveRest(along path: [CGPoint], atSafeStage: Bool = false, completion: @escaping () -> Void) {
        let destination = path.last ?? position
        guard Self.path(path, connects: position, to: destination) else {
            completion()
            return
        }
        let onFurniture = isEnteringFurniture
        let elevated = pose.position.y
        let previousClip = currentClip
        let previousFrame = currentFrameIndex
        let reversingEntry = onFurniture && restPhase == .entering && currentClip == .step && stepProgress < 1
        let previousProgress = stepProgress
        activityGeneration += 1
        let generation = activityGeneration
        stopIdle()
        removeAction(forKey: "activity")
        pose.removeAllActions()
        sprite.removeAllActions()
        completions = [completion]
        pending = nil
        isPerforming = true
        restingPoint = position
        restPhase = onFurniture ? .waking : .leaving

        // An empty outside approach is a request to stop where the cat is.
        // An empty inside route cannot revoke the furniture's support/obstacle
        // authorization; leave it settled for the scene to choose a safe exit.
        guard !onFurniture || CatWalkRoute(path) != nil || atSafeStage else {
            run(.sequence([.wait(forDuration: 0.06), .run { [weak self] in
                guard let self, self.activityGeneration == generation else { return }
                self.restPhase = self.isRestingOnFurniture ? .resting : .entering
                self.finishRest(generation: generation)
            }]), withKey: "activity")
            return
        }

        var actions: [SKAction] = []
        if previousClip == .rest {
            if reducedMotion {
                actions.append(frame(.rest, 0, hold: 0.14))
            } else if previousFrame >= 3 {
                actions.append(frames(.rest, [6, 7, 1, 0], durations: [0.24, 0.38, 0.19, 0.17]))
            } else {
                let indices = Array((0...min(previousFrame, 2)).reversed())
                actions.append(frames(.rest, indices, durations: Array(repeating: 0.18, count: indices.count)))
            }
        } else if !reversingEntry {
            actions.append(frame(.walk, 0, hold: reducedMotion ? 0.06 : 0.14))
        }
        actions += [.run { [weak self] in
            self?.isRestingOnFurniture = false
            self?.restPhase = .leaving
        }]
        if CatWalkRoute(path) != nil {
            if onFurniture {
                if reversingEntry {
                    // A front paw on the rim must be withdrawn before turning.
                    // Keep the current facing and reverse the attained poses;
                    // the room supplies the exact retreat from this position.
                    actions.append(retreatingStep(along: path, startingFrame: previousFrame,
                                                  progress: previousProgress, elevation: elevated,
                                                  generation: generation))
                } else {
                    actions += [turnForFurnitureExit(along: path, fromRest: previousClip == .rest),
                                descendingStep(along: path, elevation: elevated, generation: generation)]
                }
            } else {
                actions += [turn(along: path), walk(along: path, speed: 0.38, quiet: true)]
            }
            if !reducedMotion { actions.append(sit()) }
        } else if onFurniture {
            // Only the scene's atSafeStage check permits this zero-length
            // withdrawal. No root position or stale rest callback is replayed.
            actions.append(stationaryStepDown(from: previousFrame, elevation: elevated,
                                              generation: generation))
        }
        actions.append(.run { [weak self] in
            guard let self, self.activityGeneration == generation else { return }
            self.isEnteringFurniture = false
            self.isRestingOnFurniture = false
            self.restPhase = .none
            self.stepPhase = .none
            self.stepProgress = 0
            self.finish(generation: generation, keepingPose: CatWalkRoute(path) == nil)
        })
        run(.sequence(actions), withKey: "activity")
    }

    /// Explicit scene resets are the only operations allowed to relocate a cat.
    /// Cancellation still completes observers exactly once, with no stale actions.
    func cancelAndSettle(at point: CGPoint) {
        activityGeneration += 1
        stopIdle()
        removeAction(forKey: "activity")
        removeAction(forKey: "habit-attention")
        pose.removeAllActions()
        sprite.removeAllActions()
        let callbacks = completions + (pending?.completions ?? [])
        completions = []
        pending = nil
        isPerforming = false
        position = point
        restingPoint = point
        restorePose()
        callbacks.forEach { $0() }
        startIdleIfNeeded()
    }

    private func submit(_ activity: Activity, completion: @escaping () -> Void) {
        guard !isPerforming, !isEnteringFurniture else {
            // A burst of taps becomes one latest visual response. All successful
            // game actions already happened in the store; none is replayed here.
            var waiting = pending ?? PendingActivity(activity: activity, completions: [])
            waiting.activity = activity
            waiting.completions.append(completion)
            pending = waiting
            return
        }
        start(activity, completions: [completion])
    }

    private func start(_ activity: Activity, completions callbacks: [() -> Void]) {
        stopIdle()
        removeAction(forKey: "activity")
        removeAction(forKey: "habit-attention")
        activityGeneration += 1
        let generation = activityGeneration
        isPerforming = true
#if DEBUG
        if case let .play(_, _, _, _, finishIndex) = activity { lastResponseFinishIndex = finishIndex }
#endif
        restingPoint = activity.restingPoint(from: position)
        completions = callbacks
        restorePose()

        let animation: SKAction
        if case let .rest(request) = activity {
            animation = resting(request, generation: generation)
        } else if reducedMotion {
            // The accessibility version conveys a calm expression without any
            // translation, bounce, shake or repeated breathing motion.
            let sound: GameSoundEffect?
            switch activity {
            case .feed: sound = .feed
            case .clean: sound = .clean
            case .play: sound = .play
            default: sound = nil
            }
            let calmFrame: Int
            if case let .play(_, _, _, _, finishIndex) = activity { calmFrame = finishIndex == 1 ? 3 : 6 }
            else { calmFrame = 6 }
            animation = .sequence([.run { [weak self] in
                if let sound { self?.onSound?(sound) }
            }, frame(.expressions, calmFrame), .wait(forDuration: 0.35), .run { [weak self] in
                guard let self, self.activityGeneration == generation else { return }
                if case let .feed(_, _, _, _, _, onMealFinished) = activity { onMealFinished() }
            }])
        } else {
            switch activity {
            case let .feed(eatingPoint, facing, approach, dockingPath, returnPath, onMealFinished):
                animation = feeding(at: eatingPoint, facing: facing, approach: approach,
                                    dockingPath: dockingPath, returnPath: returnPath,
                                    generation: generation, onMealFinished: onMealFinished)
            case let .clean(home): animation = cleaning(home: home)
            case let .play(landing, facing, returnPath, prepared, finishIndex):
                animation = playing(landing: landing, facing: facing, returnPath: returnPath, prepared: prepared, finishIndex: finishIndex)
            case let .stroll(path): animation = strolling(along: path)
            case .rest: preconditionFailure("Rest is composed above")
            }
        }
        run(.sequence([animation, .run { [weak self] in
            guard let self else { return }
            if self.isRestingOnFurniture { self.finishRest(generation: generation) }
            else { self.finish(generation: generation) }
        }]), withKey: "activity")
    }

    private func finishRest(generation: Int) {
        guard generation == activityGeneration, isPerforming else { return }
        let callbacks = completions
        completions = []
        isPerforming = false
        deform(chest: 0, sway: 0)
        if isRestingOnFurniture { show(.rest, frame: 4) }
        // Keep rest flags, facing and elevation intact. A completion can now
        // call leaveRest without a one-frame jump to the ordinary seated pose.
        callbacks.forEach { $0() }
    }

    private func resting(_ request: RestRequest, generation: Int) -> SKAction {
        let stage = request.entry.first ?? request.approach.last ?? position
        let destination = request.entry.last ?? stage
        guard request.facing.isFinite, request.facing != 0,
              request.duration.isFinite, request.elevation.isFinite, request.elevation >= 0,
              request.contactProgress.isFinite,
              request.contactProgress >= CatFurnitureStepTimeline.defaultContactProgress,
              request.contactProgress <= CatFurnitureStepTimeline.maximumContactProgress,
              Self.path(request.approach, connects: position, to: stage),
              Self.path(request.entry, connects: stage, to: destination)
        else { return frame(.expressions, 6, hold: 0.25) }

        restPhase = .approaching
        var actions: [SKAction] = []
#if DEBUG
        lastRestIntroductionStyle = request.introductionStyle
#endif
        if request.introductionStyle == .quiet {
            // A brief seated look happens before leaving the safe ground position.
            actions.append(frame(.expressions, 4, hold: reducedMotion ? 0.12 : 0.28))
        }
        if CatWalkRoute(request.approach) != nil {
            actions += [stand(facing: initialDirection(along: request.approach)),
                        walk(along: request.approach, speed: 0.43, quiet: true, arrivalHurry: request.introductionStyle == .playful)]
        } else {
            actions.append(stand(facing: initialDirection(along: request.entry)))
        }
        if request.introductionStyle == .curious {
            actions.append(reducedMotion ? frame(.expressions, 4, hold: 0.12)
                           : frames(.play, [0, 1, 0], durations: [0.08, 0.18, 0.08]))
        }
        actions += [turn(toward: request.facing), .run { [weak self] in
            guard let self, self.activityGeneration == generation else { return }
            self.isEnteringFurniture = true
            self.restPhase = .entering
            self.stepProgress = 0
            self.furnitureSurfaceElevation = request.elevation
        }, ascendingStep(along: request.entry, startingAt: stage, elevation: request.elevation,
                         contactProgress: request.contactProgress, generation: generation), .run { [weak self] in
            guard let self, self.activityGeneration == generation else { return }
            self.pose.position.y = request.elevation
            self.shadow.position.y = request.elevation
            self.restPhase = .settling
            self.setFacing(request.facing)
        }]
        if let matched = request.habitMatched {
            actions.append(frames(.expressions, matched ? [6, 3, 0] : [4, 5, 0], durations: [0.14, 0.12, 0.10]))
        }
        actions.append(settlingAfterStep(elevation: request.elevation, generation: generation))
        actions.append(.run { [weak self] in
            guard let self, self.activityGeneration == generation else { return }
            self.isRestingOnFurniture = true
            self.restPhase = .resting
#if DEBUG
            self.completedRests += 1
#endif
            request.onSettled()
        })
        let stay = max(0.2, request.duration)
        let breathPeriod = Double.random(in: 3.8...5.1)
        actions.append(.customAction(withDuration: stay) { [weak self] _, elapsed in
            guard let self, self.activityGeneration == generation else { return }
            guard !self.reducedMotion else { self.deform(chest: 0, sway: 0); return }
            // One stable sleeping pose with minute chest motion. Avoid cycling
            // whole-body scale or moving the paws against the furniture.
            let t = Double(elapsed) / breathPeriod
            let amount = sin(t * .pi * 2) * 0.003
            self.deform(chest: Float(amount), sway: 0)
        })
        return .sequence(actions)
    }

    /// Both standing drawings have the same registered eye height, but the
    /// step sheet's head is slightly farther forward. Carry that measured
    /// offset into rest frame 0, then release it while the body curls down.
    /// This avoids a one-frame horizontal jump or rescaling either atlas.
    private var stepToRestOffset: CGPoint {
        func registered(_ clip: CatClip, _ index: Int, _ landmark: CGPoint) -> CGPoint {
            let sequence = art.sequence(clip)
            let frame = sequence.frames[min(index, sequence.frames.count - 1)]
            let unit = visualWidth * 1.20 * sequence.heightRatio / max(1, sequence.referenceHeight)
            return CGPoint(x: (landmark.x - frame.groundCenter) * unit,
                           y: (frame.groundY - landmark.y) * unit)
        }
        // Centers of the near-eye dark pupil components in the original cells.
        let step = registered(.step, 4, CGPoint(x: 328.20, y: 153.59))
        let rest = registered(.rest, 0, CGPoint(x: 314.03, y: 213.53))
        return CGPoint(x: step.x - rest.x, y: step.y - rest.y)
    }

    private func settlingAfterStep(elevation: CGFloat, generation: Int) -> SKAction {
        let offset = stepToRestOffset
        let indices = reducedMotion ? [0, 2, 4] : [0, 1, 2, 3, 4]
        let durations = reducedMotion ? [0.10, 0.12, 0.14] : [0.18, 0.24, 0.25, 0.35, 0.25]
        let duration = durations.reduce(0, +)
        return .sequence([
            .run { [weak self] in
                guard let self, self.activityGeneration == generation else { return }
                self.pose.position = CGPoint(x: offset.x * self.facing, y: elevation + offset.y)
            },
            .group([frames(.rest, indices, durations: durations),
                    .customAction(withDuration: duration) { [weak self] _, elapsed in
                guard let self, self.activityGeneration == generation else { return }
                let t = min(1, max(0, elapsed / duration))
                let remaining = 1 - t * t * (3 - 2 * t)
                self.pose.position = CGPoint(x: offset.x * self.facing * remaining,
                                             y: elevation + offset.y * remaining)
            }]),
            .run { [weak self] in
                guard let self, self.activityGeneration == generation else { return }
                self.pose.position = CGPoint(x: 0, y: elevation)
            }
        ])
    }

    private func turnForFurnitureExit(along path: [CGPoint], fromRest: Bool) -> SKAction {
        let direction = initialDirection(along: path)
        let offset = stepToRestOffset
        return .sequence([
            .wait(forDuration: reducedMotion ? 0.06 : 0.14),
            .run { [weak self] in
                guard let self else { return }
                self.setFacing(direction)
                if fromRest {
                    self.pose.position.x -= offset.x * self.facing
                    self.pose.position.y -= offset.y
                }
                self.show(.step, frame: 4)
                self.sprite.warpGeometry = nil
                self.stepFrontWarp = .zero
                self.stepRearWarp = .zero
            }
        ])
    }

    private func ascendingStep(along path: [CGPoint], startingAt stage: CGPoint,
                               elevation: CGFloat, contactProgress: CGFloat, generation: Int) -> SKAction {
        let keys = CatFurnitureStepTimeline.ascending(elevation: elevation, contactProgress: contactProgress)
        return furnitureSteps(along: path, startingAt: stage, initialProgress: 0,
                              initialElevation: 0, initialShadowElevation: 0,
                              keys: keys, generation: generation)
    }

    private func descendingStep(along path: [CGPoint], elevation: CGFloat,
                                generation: Int) -> SKAction {
        let keys = CatFurnitureStepTimeline.descending(elevation: elevation)
        return furnitureSteps(along: path, startingAt: path.first ?? position, initialProgress: 1,
                              initialElevation: elevation, initialShadowElevation: shadow.position.y,
                              keys: keys, generation: generation)
    }

    private func retreatingStep(along path: [CGPoint], startingFrame: Int, progress: CGFloat,
                                elevation: CGFloat, generation: Int) -> SKAction {
        let keys = CatFurnitureStepTimeline.retreating(startingFrame: startingFrame, progress: progress,
                                                        elevation: elevation, shadowElevation: shadow.position.y)
        return furnitureSteps(along: path, startingAt: path.first ?? position, initialProgress: progress,
                              initialElevation: elevation, initialShadowElevation: shadow.position.y,
                              keys: keys, generation: generation, withdrawing: true)
    }

    private func stationaryStepDown(from frame: Int, elevation: CGFloat, generation: Int) -> SKAction {
        let keys = CatFurnitureStepTimeline.stationary(from: frame)
        return furnitureSteps(along: [], startingAt: position, initialProgress: stepProgress,
                              initialElevation: elevation, initialShadowElevation: shadow.position.y,
                              keys: keys, generation: generation, withdrawing: true)
    }

    private func furnitureSteps(along path: [CGPoint], startingAt origin: CGPoint,
                                initialProgress: CGFloat, initialElevation: CGFloat,
                                initialShadowElevation: CGFloat, keys: [CatFurnitureStepKeyframe],
                                generation: Int, withdrawing: Bool = false) -> SKAction {
        let route = CatWalkRoute(path)
        let traversal = WalkTraversal()
        var actions: [SKAction] = [.run { [weak self] in
            guard let self, self.activityGeneration == generation else { return }
            traversal.mayMove = Self.samePoint(self.position, origin)
            traversal.initialPoseX = self.pose.position.x
            if let frontHeight = self.stepPawHeight(front: true) {
                let height = self.pose.position.y + frontHeight
                traversal.withdrawalForeHeight = height.isFinite ? height : nil
            }
            // A cancellation can arrive halfway through a high reach. Keep
            // that exact mesh until the first reverse key has captured it.
            if self.currentClip != .step {
                self.sprite.warpGeometry = nil
                self.stepFrontWarp = .zero
                self.stepRearWarp = .zero
            }
        }]
        var priorTravel: CGFloat = 0
        var priorProgress = initialProgress
        var priorElevation = initialElevation
        var priorShadow = initialShadowElevation
        for (index, key) in keys.enumerated() {
            let fromTravel = priorTravel, fromProgress = priorProgress
            let fromElevation = priorElevation, fromShadow = priorShadow
            let duration = key.duration * (reducedMotion ? 0.70 : 1)
            let spanTransition = StepSpanTransition()
            actions.append(.run { [weak self] in
                guard let self, self.activityGeneration == generation, traversal.mayMove else { return }
                spanTransition.initialSpan = self.currentStepSpan
                spanTransition.initialForeHeight = self.stepPawHeight(front: true)
                spanTransition.preservesSpan = index == 0 && self.currentClip == .step
                    && self.currentFrameIndex == key.frame && spanTransition.initialSpan != nil
                let highStep = self.furnitureSurfaceElevation.isFinite
                    && self.furnitureSurfaceElevation > self.visualWidth * 0.25
                spanTransition.blendsToSupport = highStep && self.currentClip == .step
                    && ((key.frame == 2 && self.currentFrameIndex == 1)
                        || (key.frame == 5 && self.currentFrameIndex == 4))
                spanTransition.releasesReachingPaw = highStep && withdrawing && self.currentClip == .step
                    && key.frame == 1 && self.currentFrameIndex == 2
            })
            actions.append(.customAction(withDuration: duration) { [weak self] _, elapsed in
                guard let self, self.activityGeneration == generation, traversal.mayMove else { return }
                let t = min(1, max(0, elapsed / duration))
                let eased = t * t * (3 - 2 * t)
                let travel = fromTravel + (key.travel - fromTravel) * eased
                if let route { self.position = route.sample(at: route.distance * travel).point }
                self.pose.position.x = index == 0 ? traversal.initialPoseX * (1 - eased) : 0
                self.pose.position.y = fromElevation + (key.elevation - fromElevation) * eased
                self.shadow.position.y = fromShadow + (key.shadowElevation - fromShadow) * eased
                self.stepProgress = fromProgress + (key.progress - fromProgress) * eased
                self.stepPhase = key.phase
                self.show(.step, frame: key.frame)
                var span = self.stepSupportSpan(frame: key.frame, withdrawing: withdrawing,
                                               foreHeight: traversal.withdrawalForeHeight)
                if spanTransition.preservesSpan, let initial = spanTransition.initialSpan {
                    span = initial
                } else if (spanTransition.blendsToSupport || spanTransition.releasesReachingPaw),
                          let initial = spanTransition.initialSpan {
                    // Finish reaching before the entry's contact key ends;
                    // its following hold has complete support at any bed height.
                    let progress = min(1, eased / 0.95)
                    let blend = progress * progress * (3 - 2 * progress)
                    var initial = initial
                    if spanTransition.releasesReachingPaw {
                        // Frame 1's planted rear paw sits six source pixels
                        // above frame 2's support baseline. Carry the actual
                        // forepaw height across that registration change;
                        // preserving only their span would briefly raise it.
                        if let height = spanTransition.initialForeHeight,
                           let rear = self.nativeStepRearHeight(frame: key.frame) {
                            initial = height - rear
                        }
                        span = self.nativeStepSpan(frame: key.frame) ?? span
                    }
                    span = initial + (span - initial) * blend
                }
                self.fitStepPaws(to: span, allowReaching: spanTransition.releasesReachingPaw)
            })
            actions.append(.run { [weak self] in
                guard let self, self.activityGeneration == generation, traversal.mayMove else { return }
                if let route { self.position = route.sample(at: route.distance * key.travel).point }
                self.pose.position.x = 0
                self.pose.position.y = key.elevation
                self.shadow.position.y = key.shadowElevation
                self.stepProgress = key.progress
                let span: CGFloat
                if spanTransition.preservesSpan, let initial = spanTransition.initialSpan { span = initial }
                else if spanTransition.releasesReachingPaw { span = self.nativeStepSpan(frame: key.frame) ?? 0 }
                else {
                    span = self.stepSupportSpan(frame: key.frame, withdrawing: withdrawing,
                                                foreHeight: traversal.withdrawalForeHeight)
                }
                self.fitStepPaws(to: span, allowReaching: spanTransition.releasesReachingPaw)
            })
            priorTravel = key.travel
            priorProgress = key.progress
            priorElevation = key.elevation
            priorShadow = key.shadowElevation
        }
        return .sequence(actions)
    }

    private func stepSupportSpan(frame: Int, withdrawing: Bool, foreHeight: CGFloat?) -> CGFloat {
        guard frame == 2 || frame == 3 else { return -pose.position.y }
        // Do not finish reaching for the bed after a partial reach was
        // cancelled. Withdraw from the forepaw height that was actually held.
        let height = withdrawing ? min(furnitureSurfaceElevation, foreHeight ?? furnitureSurfaceElevation)
                                 : furnitureSurfaceElevation
        return max(0, height - pose.position.y)
    }

    /// The generated paws describe one small step height. Adapt only the lower
    /// foreleg region to this furniture's measured height, keeping the head,
    /// torso and rear support untouched. Whole-body scaling would erase the
    /// weight transfer and drive the front paws through a shallower cushion.
    private func fitStepPaws(to targetSpan: CGFloat, allowReaching: Bool = false) {
        guard targetSpan.isFinite, currentClip == .step,
              [2, 3, 5, 6].contains(currentFrameIndex) || (allowReaching && currentFrameIndex == 1) else {
            sprite.warpGeometry = nil
            stepFrontWarp = .zero
            stepRearWarp = .zero
            return
        }
        let frame = art.sequence(.step).frames[currentFrameIndex]
        guard let front = frame.frontPaw, let rear = frame.rearPaw else { return }
        let width = max(1, frame.bounds.width), height = max(1, frame.bounds.height)
        let frontUV = CGPoint(x: (front.x - frame.bounds.minX) / width,
                              y: (frame.bounds.maxY - front.y) / height)
        let rearUV = CGPoint(x: (rear.x - frame.bounds.minX) / width,
                             y: (frame.bounds.maxY - rear.y) / height)
        let span = (frontUV.y - rearUV.y) * sprite.size.height
        let shift = (targetSpan - span) / max(1, sprite.size.height)
        let columns = 8, rows = 8
        var source: [SIMD2<Float>] = [], target: [SIMD2<Float>] = []
        for row in 0...rows {
            for column in 0...columns {
                let x = CGFloat(column) / CGFloat(columns), y = CGFloat(row) / CGFloat(rows)
                let horizontal = min(1, max(0, (x - rearUV.x - 0.125) / max(0.08, frontUV.x - rearUV.x - 0.25)))
                let vertical = max(0, 1 - max(0, abs(y - frontUV.y) - 0.125) / 0.35)
                let weight = horizontal * vertical
                source.append(SIMD2(Float(x), Float(y)))
                target.append(SIMD2(Float(x), Float(y + shift * weight)))
            }
        }
        sprite.warpGeometry = SKWarpGeometryGrid(columns: columns, rows: rows,
                                                sourcePositions: source, destinationPositions: target)
        // SpriteKit interpolates each grid cell. Audit the same interpolation,
        // rather than reporting an unwarped source landmark as a contact.
        func displacement(at uv: CGPoint) -> CGPoint {
            let gx = min(CGFloat(columns), max(0, uv.x * CGFloat(columns)))
            let gy = min(CGFloat(rows), max(0, uv.y * CGFloat(rows)))
            let column = min(columns - 1, Int(gx)), row = min(rows - 1, Int(gy))
            let fx = gx - CGFloat(column), fy = gy - CGFloat(row)
            func delta(_ x: Int, _ y: Int) -> CGFloat {
                let index = y * (columns + 1) + x
                return CGFloat(target[index].y - source[index].y)
            }
            let low = delta(column, row) * (1 - fx) + delta(column + 1, row) * fx
            let high = delta(column, row + 1) * (1 - fx) + delta(column + 1, row + 1) * fx
            return CGPoint(x: 0, y: (low * (1 - fy) + high * fy) * sprite.size.height)
        }
        stepFrontWarp = displacement(at: frontUV)
        stepRearWarp = displacement(at: rearUV)
    }

    private func finish(generation: Int, keepingPose: Bool = false) {
        guard generation == activityGeneration, isPerforming else { return }
        let callbacks = completions
        let next = pending
        completions = []
        pending = nil
        isPerforming = false
        if keepingPose { resetModifiers() }
        else { restorePose() }
        callbacks.forEach { $0() }
        // A callback may reset the scene. Do not revive its previous queue.
        guard generation == activityGeneration, !isPerforming else { return }
        if let next { start(next.activity, completions: next.completions) }
        else { startIdleIfNeeded() }
    }

    private func feeding(at eatingPoint: CGPoint, facing direction: CGFloat, approach: [CGPoint],
                         dockingPath: [CGPoint], returnPath: [CGPoint], generation: Int,
                         onMealFinished: @escaping () -> Void) -> SKAction {
        let stage = dockingPath.first ?? eatingPoint
        let home = returnPath.last ?? stage
        // The room validates obstacles; the actor verifies continuity. A stale
        // queued route must not invent a connector or snap into its next leg.
        guard direction.isFinite, direction != 0,
              Self.path(approach, connects: position, to: stage),
              Self.path(dockingPath, connects: stage, to: eatingPoint),
              Self.path(returnPath, connects: stage, to: home)
        else { return frame(.expressions, 6, hold: 0.35) }
        let mealDirection: CGFloat = direction > 0 ? 1 : -1

        let mouthPause = Double.random(in: 0.20...0.34)
        var actions = [stand(facing: initialDirection(along: approach)), walk(along: approach, speed: 0.55),
                       turn(toward: mealDirection),
                       SKAction.run { [weak self] in
                           guard let self else { return }
                           self.setFacing(mealDirection)
                           self.isDockingForMeal = true
                       },
                       walk(along: dockingPath, speed: 0.28, facingOverride: mealDirection),
                       frame(.meal, 0, hold: mouthPause),
                       frames(.meal, [0, 1, 2], durations: [0.10, 0.13, 0.14]),
                       .run { [weak self] in self?.onSound?(.feed) }]

        // Only frames 2 and 3 actually touch the food. Frame 4 lifts the muzzle
        // to lick its nose, so use it once between bites, not on every chew.
        let lickAfterBite = Int.random(in: 0...1)
        for bite in 0..<3 {
            actions.append(frames(.meal, [2, 3, 2], durations: [0.16, 0.20, 0.18]))
            actions.append(.wait(forDuration: Double.random(in: 0.13...0.27)))
            if bite == lickAfterBite {
                actions.append(frames(.meal, [4, 5], durations: [0.22, 0.27]))
                actions.append(.wait(forDuration: Double.random(in: 0.18...0.30)))
                actions.append(frames(.meal, [1, 2], durations: [0.13, 0.17]))
            }
        }
        actions.append(frames(.meal, [5, 6, 7], durations: [0.13, 0.18, 0.24]))
        actions.append(.run { [weak self] in
            guard let self, self.activityGeneration == generation else { return }
#if DEBUG
            self.completedMeals += 1
#endif
            // Empty the bowl before withdrawal; completion includes the walk home.
            onMealFinished()
        })
        actions += [
                    // Back away while still facing the bowl. A turn at the food
                    // would swing the body through the bowl's solid footprint.
                    walk(along: Array(dockingPath.reversed()), speed: 0.24,
                         facingOverride: mealDirection, reverseGait: true),
                    .run { [weak self] in self?.isDockingForMeal = false },
                    turn(along: returnPath), walk(along: returnPath, speed: 0.43), sit(),
                    frame(.expressions, 6, hold: 0.35), frame(.expressions, 0)]
        return .sequence(actions)
    }

    private func cleaning(home: CGPoint) -> SKAction {
        let shake = SKAction.customAction(withDuration: 0.42) { [weak self] _, elapsed in
            guard let self else { return }
            let progress = min(1, elapsed / 0.42)
            let envelope = sin(progress * .pi) * (1 - progress * 0.45)
            let wave = sin(progress * .pi * 7) * envelope
            self.deform(chest: 0, sway: Float(wave * 0.009))
        }
        return .sequence([
            .run { [weak self] in self?.onSound?(.clean) },
            frames(.expressions, [0, 1, 2, 6], durations: [0.15, 0.09, 0.12, 0.27]),
            shake,
            .run { [weak self] in self?.deform(chest: 0, sway: 0) },
            .wait(forDuration: 0.24),
            frames(.expressions, [6, 3, 0], durations: [0.24, 0.08, 0.20])
        ])
    }

    private func playing(landing: CGPoint, facing direction: CGFloat, returnPath: [CGPoint], prepared: Bool, finishIndex: Int?) -> SKAction {
        let origin = position
        guard landing.x.isFinite, landing.y.isFinite else { return frame(.expressions, 6, hold: 0.35) }
        let leapHeight = visualWidth * 0.095
        let leapDuration: TimeInterval = 0.40
        let leap = SKAction.customAction(withDuration: leapDuration) { [weak self] _, elapsed in
            guard let self else { return }
            let t = min(1, elapsed / leapDuration)
            self.position = CGPoint(x: origin.x + (landing.x - origin.x) * t,
                                    y: origin.y + (landing.y - origin.y) * t)
            // A single shallow ballistic arc, followed by actual landing frames.
            self.pose.position.y = 4 * leapHeight * t * (1 - t)
            self.show(.play, frame: t < 0.32 ? 3 : (t < 0.83 ? 4 : 5))
            self.shadow.xScale = 1 - 0.13 * sin(t * .pi)
            self.shadow.yScale = 1 - 0.13 * sin(t * .pi)
            self.shadow.alpha = 1 - 0.2 * sin(t * .pi)
        }
        let landingRecovery = SKAction.customAction(withDuration: 0.24) { [weak self] _, elapsed in
            guard let self else { return }
            self.pose.position.y = 0
            let t = min(1, elapsed / 0.24)
            self.show(.play, frame: t < 0.48 ? 5 : 6)
            self.deform(chest: Float(-0.014 * sin(t * .pi)), sway: 0)
        }
        let preparation: [SKAction] = prepared ? [
            .run { [weak self] in self?.setFacing(direction) },
            frames(.play, [1, 2], durations: [0.08, 0.12])
        ] : [
            frame(.expressions, 4, hold: Double.random(in: 0.30...0.52)),
            stand(facing: direction),
            frames(.play, [0, 1, 2], durations: [0.09, 0.14, 0.21])
        ]
        var ending: [SKAction] = [turn(along: returnPath), walk(along: returnPath, speed: 0.39)]
        if finishIndex == 1 {
            ending.append(frames(.play, [0, 1, 0], durations: [0.12, 0.20, 0.16]))
        }
        ending.append(sit())
        ending.append(finishIndex == 0
            ? frames(.expressions, [6, 3, 6, 0], durations: [0.18, 0.12, 0.18, 0.12])
            : .sequence([frame(.expressions, 6, hold: 0.28), frame(.expressions, 0)]))
        return .sequence(preparation + [
            leap,
            .run { [weak self] in self?.onSound?(.play) },
            .run { [weak self] in self?.position = landing },
            landingRecovery,
            .run { [weak self] in
#if DEBUG
                self?.completedPounces += 1
#endif
                self?.resetModifiers()
            },
            frame(.play, 7, hold: 0.33)
        ] + ending)
    }

    private func strolling(along path: [CGPoint]) -> SKAction {
        guard let route = CatWalkRoute(path), Self.samePoint(position, route.origin) else {
            return frame(.expressions, 4, hold: 0.30)
        }
        return .sequence([frame(.expressions, 4, hold: 0.30), stand(facing: initialDirection(along: path)),
                          walk(along: path, speed: 0.35),
                          .wait(forDuration: 0.18), sit()])
    }

    private func stand(facing direction: CGFloat) -> SKAction {
        .sequence([
            .run { [weak self] in self?.setFacing(direction) },
            frames(.rise, Array(0...7), durations: [0.09, 0.11, 0.12, 0.11, 0.09, 0.07, 0.07, 0.08])
        ])
    }

    private func sit() -> SKAction {
        .sequence([frames(.rise, Array((0...7).reversed()), durations: [0.08, 0.07, 0.07, 0.10, 0.12, 0.13, 0.12, 0.10]),
                   .run { [weak self] in
                       self?.facing = 1
                       self?.pose.xScale = 1
                       self?.show(.expressions, frame: 0)
                   }])
    }

    private func turn(toward direction: CGFloat) -> SKAction {
        .sequence([frame(.rise, 4, hold: 0.11),
                   .run { [weak self] in
                       self?.setFacing(direction)
                       self?.show(.walk, frame: 0)
                   }, .wait(forDuration: 0.08)])
    }

    private func turn(along points: [CGPoint]) -> SKAction {
        guard let route = CatWalkRoute(points) else { return .wait(forDuration: 0.06) }
        return turn(toward: route.sample(at: 0).horizontalDirection)
    }

    /// Step phases depend on ground distance, including acceleration and braking.
    /// Both the first and last pose are contact poses, never a suspended paw.
    private func walk(along points: [CGPoint], speed: CGFloat, facingOverride: CGFloat? = nil,
                      reverseGait: Bool = false, elevationFrom: CGFloat? = nil,
                      elevationTo: CGFloat? = nil, quiet: Bool = false, arrivalHurry: Bool = false) -> SKAction {
        guard let route = CatWalkRoute(points) else { return .wait(forDuration: 0.06) }
        let duration = max(0.42, TimeInterval(route.distance / max(1, visualWidth * speed)) + 0.16 - (arrivalHurry ? 0.12 : 0))
        let halfSteps = max(1, (route.distance / (visualWidth * 0.24)).rounded())
        let cycles = halfSteps * 0.5
        let traversal = WalkTraversal()
        return .sequence([
            .run { [weak self] in
                guard let self else { return }
                // Validate when this leg actually starts (the return leg is
                // constructed before the approach/pounce has finished).
                traversal.mayMove = Self.samePoint(self.position, route.origin)
                if traversal.mayMove, let facingOverride { self.setFacing(facingOverride) }
            },
            .customAction(withDuration: duration) { [weak self] _, elapsed in
                guard let self, traversal.mayMove else { return }
                let t = min(1, elapsed / duration)
                let progress = Self.smoothTravel(t)
                let sample = route.sample(at: route.distance * progress)
                self.position = sample.point
                if let elevationFrom, let elevationTo {
                    // Required movement onto a cushion follows the same safe
                    // route. This is a monotonic surface-height change, no hop.
                    self.pose.position.y = elevationFrom + (elevationTo - elevationFrom) * progress
                }
                self.setFacing(facingOverride ?? sample.horizontalDirection)
                let phase = progress * cycles
                let forwardIndex = Int(floor(phase * 8 + 0.0001)) % 8
                let index = reverseGait ? (8 - forwardIndex) % 8 : forwardIndex
                self.show(.walk, frame: index)
                let gaitPhase = reverseGait ? -phase : phase
                if !quiet || !self.reducedMotion {
                    self.deform(chest: Float(0.0025 * sin(gaitPhase * .pi * 4)), sway: 0)
                    self.shadow.xScale = 1 + 0.015 * sin(gaitPhase * .pi * 4)
                } else {
                    self.deform(chest: 0, sway: 0)
                    self.shadow.xScale = 1
                }
            },
            .run { [weak self] in
                guard let self, traversal.mayMove else { return }
                self.position = route.destination
                self.resetModifiers()
                if let elevationTo { self.pose.position.y = elevationTo }
            }
        ])
    }

    private func initialDirection(along points: [CGPoint]) -> CGFloat {
        guard let route = CatWalkRoute(points) else { return facing }
        let dx = route.segments[0].destination.x - route.origin.x
        return dx == 0 ? facing : (dx > 0 ? 1 : -1)
    }

    private func setFacing(_ direction: CGFloat) {
        // A vertical segment has no new horizontal intent; preserve the last
        // facing instead of flickering to the right at every vertical edge.
        guard direction.isFinite, direction != 0 else { return }
        facing = direction > 0 ? 1 : -1
        pose.xScale = facing
    }

    private static func samePoint(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y) <= 0.001
    }

    private static func path(_ points: [CGPoint], connects origin: CGPoint, to destination: CGPoint) -> Bool {
        guard origin.x.isFinite, origin.y.isFinite, destination.x.isFinite, destination.y.isFinite,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
        guard let first = points.first, let last = points.last else { return samePoint(origin, destination) }
        guard samePoint(first, origin), samePoint(last, destination) else { return false }
        return CatWalkRoute(points) != nil || samePoint(origin, destination)
    }

    /// Short acceleration/deceleration regions keep the center of a walk calm.
    private static func smoothTravel(_ t: CGFloat) -> CGFloat {
        let ramp: CGFloat = 0.20
        let maximumSpeed = 1 / (1 - ramp)
        if t < ramp { return maximumSpeed * t * t / (2 * ramp) }
        if t > 1 - ramp {
            let remaining = 1 - t
            return 1 - maximumSpeed * remaining * remaining / (2 * ramp)
        }
        return maximumSpeed * (t - ramp / 2)
    }

    private func frames(_ clip: CatClip, _ indices: [Int], durations: [TimeInterval]) -> SKAction {
        .sequence(indices.enumerated().flatMap { offset, index in
            [frame(clip, index), SKAction.wait(forDuration: durations[min(offset, durations.count - 1)])]
        })
    }

    private func frame(_ clip: CatClip, _ index: Int, hold: TimeInterval = 0) -> SKAction {
        .sequence([.run { [weak self] in self?.show(clip, frame: index) }, .wait(forDuration: hold)])
    }

    private func show(_ clip: CatClip, frame index: Int) {
        let sequence = art.sequence(clip)
        let actualIndex = min(max(index, 0), sequence.frames.count - 1)
        currentClip = clip
        currentFrameIndex = actualIndex
        let key = "\(clip.rawValue):\(actualIndex):\(visualWidth)"
        guard key != lastFrameKey else { return }
        lastFrameKey = key
        let frame = sequence.frames[actualIndex]
        let unit = visualWidth * 1.20 * sequence.heightRatio / max(1, sequence.referenceHeight)
        sprite.texture = frame.texture
        sprite.size = CGSize(width: frame.bounds.width * unit, height: frame.bounds.height * unit)
        sprite.position = CGPoint(x: (frame.bounds.midX - frame.groundCenter) * unit,
                                  y: (frame.groundY - frame.bounds.maxY) * unit)
    }

    private func restorePose() {
        isDockingForMeal = false
        isEnteringFurniture = false
        isRestingOnFurniture = false
        restPhase = .none
        stepPhase = .none
        stepProgress = 0
        furnitureSurfaceElevation = 0
        stepFrontWarp = .zero
        stepRearWarp = .zero
        resetModifiers()
        facing = 1
        pose.xScale = 1
        show(.expressions, frame: 0)
    }

    private func resetModifiers() {
        pose.position = .zero
        pose.yScale = 1
        pose.zRotation = 0
        shadow.setScale(1)
        shadow.position = .zero
        shadow.alpha = 1
        deform(chest: 0, sway: 0)
    }

    private func stopIdle() {
        idleGeneration += 1
        removeAction(forKey: "idle-event")
        removeAction(forKey: "breathing")
        if !isPerforming, !isEnteringFurniture { resetModifiers() }
    }

    private func startIdleIfNeeded() {
        guard idleEnabled, !isPerforming, !isEnteringFurniture, !reducedMotion else { return }
        if action(forKey: "breathing") == nil { breathe(generation: idleGeneration) }
        if action(forKey: "idle-event") == nil { scheduleExpression(generation: idleGeneration) }
    }

    private func breathe(generation: Int) {
        guard generation == idleGeneration, idleEnabled, !isPerforming, !isEnteringFurniture, !reducedMotion else { return }
        let duration = Double.random(in: 3.7...5.2)
        run(.sequence([
            .customAction(withDuration: duration) { [weak self] _, elapsed in
                guard let self, generation == self.idleGeneration else { return }
                let t = min(1, elapsed / duration)
                // Feet stay pinned; only the chest and shoulders move fractions
                // of a point. Exhalation is longer than inhalation.
                let phase = t < 0.42 ? t / 0.42 : (1 - t) / 0.58
                let expansion = sin(phase * .pi / 2)
                self.deform(chest: Float(expansion * 0.0045), sway: 0)
            },
            .wait(forDuration: Double.random(in: 0.12...0.38)),
            .run { [weak self] in self?.breathe(generation: generation) }
        ]), withKey: "breathing")
    }

    private func scheduleExpression(generation: Int) {
        guard generation == idleGeneration, idleEnabled, !isPerforming, !isEnteringFurniture, !reducedMotion else { return }
        let event: SKAction
        switch Int.random(in: 0..<10) {
        case 0...5:
            var blink = [frames(.expressions, [1, 2, 3, 0], durations: [0.065, 0.08, 0.06, 0.03])]
            if Int.random(in: 0..<5) == 0 {
                blink += [.wait(forDuration: 0.15), frames(.expressions, [1, 2, 3, 0], durations: [0.06, 0.065, 0.06, 0.03])]
            }
            event = .sequence(blink)
        case 6...7:
            event = .sequence([frame(.expressions, 4, hold: Double.random(in: 0.65...1.2)), frame(.expressions, 0)])
        case 8:
            event = .sequence([frame(.expressions, 5, hold: 0.20), frame(.expressions, 0)])
        default:
            event = frames(.expressions, [1, 6, 3, 0], durations: [0.10, 0.65, 0.09, 0.05])
        }
        run(.sequence([.wait(forDuration: Double.random(in: 3.1...7.4)), event,
                       .run { [weak self] in self?.scheduleExpression(generation: generation) }]), withKey: "idle-event")
    }

    /// A tiny mesh deformation gives shoulders and fur some give while leaving
    /// the bottom row (the contact paws) fixed. No whole-cat accordion scaling.
    private func deform(chest: Float, sway: Float) {
        var source: [SIMD2<Float>] = []
        var target: [SIMD2<Float>] = []
        for row in 0...3 {
            for column in 0...2 {
                let x = Float(column) / 2, y = Float(row) / 3
                let weight: Float = row == 0 ? 0 : (row == 3 ? 0.45 : 1)
                source.append(SIMD2(x, y))
                target.append(SIMD2(x + (x - 0.5) * chest * weight + sway * weight,
                                    y + chest * weight * 0.35))
            }
        }
        sprite.warpGeometry = SKWarpGeometryGrid(columns: 2, rows: 3,
                                                sourcePositions: source, destinationPositions: target)
    }
}
