import SpriteKit
#if os(macOS)
import AppKit
#endif
import CatGameCore

/// A bounded observation stage, separate from home navigation, furniture and recovery.
@MainActor
final class CatPlayTogetherScene: SKScene {
    let actor = CatActor()
    private let toy = SKSpriteNode(imageNamed: "icon-play")
    private let wand = SKShapeNode()
    private let wall = SKSpriteNode(imageNamed: "room-wall-plaster")
    private let floor = SKSpriteNode(imageNamed: "room-floor-wood")
    private let mat = SKSpriteNode(imageNamed: "furniture-floor-cushion")
    private let trail = (0..<5).map { _ in SKShapeNode(circleOfRadius: 4) }
    private var trailPositions: [CGPoint] = []
    private var lastTrailAt: TimeInterval = 0
    private(set) var feedbackKind: CatPlayInputKind = .still
    private(set) var activeRhythm: CatPlayRhythm?
    private(set) var hasDragged = false
    var isDemonstrating: Bool { program != nil }
    private var tracker = CatPlayInputTracker()
    private var dragging = false
    private var program: (rhythm: CatPlayRhythm, start: TimeInterval)?
    private var previousInputKind: CatPlayInputKind = .still
    private var baseReported = false
    private var reported: Set<CatPlayRhythm> = []
    private var attentionUntil: TimeInterval = 0
    private(set) var isResponding = false
    private(set) var responseFinishIndex: Int?
    private(set) var pounces = 0
    var onInput: ((CatPlayInputKind, CatPlayControl, Double, Double) -> Void)?
    var onMotion: ((String) -> Void)?
    var reducedMotion = false { didSet {
        actor.reducedMotion = reducedMotion
        if reducedMotion { trail.forEach { $0.isHidden = true } }
    } }
    var style: CatBehaviorStyle = .playful

    init(appearance: CatAppearance) {
        super.init(size: CGSize(width: 350, height: 280))
        backgroundColor = .clear; scaleMode = .resizeFill
        actor.setAppearance(appearance); actor.setIdleEnabled(true)
        toy.zPosition = 5; toy.size = CGSize(width: 38, height: 38)
        wand.strokeColor = UIColor(red: 0.55, green: 0.35, blue: 0.2, alpha: 1); wand.lineWidth = 3
        wall.zPosition = -4; floor.zPosition = -3; mat.zPosition = -2
        addChild(wall); addChild(floor); addChild(mat)
        for (index, dot) in trail.enumerated() {
            dot.fillColor = UIColor(red: 0.91, green: 0.44, blue: 0.54, alpha: 1)
            dot.strokeColor = .clear; dot.zPosition = 4
            dot.alpha = CGFloat(index + 1) / 8; dot.isHidden = true; addChild(dot)
        }
        addChild(wand); addChild(actor); addChild(toy)
        layoutStage()
    }
    required init?(coder: NSCoder) { fatalError("CatPlayTogetherScene is created in code") }
    override func didChangeSize(_ oldSize: CGSize) { super.didChangeSize(oldSize); layoutStage() }
    private var home: CGPoint { CGPoint(x: size.width * 0.35, y: size.height * 0.29) }
    private var area: CGRect { CGRect(x: 42, y: size.height * 0.25, width: max(40, size.width - 84), height: size.height * 0.43) }
    private func layoutStage() {
        guard size.width > 0, size.height > 0 else { return }
        wall.size = CGSize(width: size.width, height: size.height * 0.62)
        wall.position = CGPoint(x: size.width / 2, y: size.height * 0.69)
        floor.size = CGSize(width: size.width, height: size.height * 0.43)
        floor.position = CGPoint(x: size.width / 2, y: size.height * 0.215)
        mat.size = CGSize(width: size.width * 0.7, height: size.height * 0.29)
        mat.position = CGPoint(x: size.width * 0.43, y: home.y)
        trailPositions.removeAll(); trail.forEach { $0.isHidden = true }
        // The compact stage reserves its top strip for the reaction bubble.
        // Scale this separate play scene to its height, not only its width.
        actor.setVisualWidth(min(112, min(size.width * 0.29, max(48, (size.height - 90) * 0.55))))
        actor.cancelAndSettle(at: home); actor.setIdleEnabled(true)
        toy.position = CGPoint(x: size.width * 0.65, y: size.height * 0.49)
        updateWand()
    }

    func runControl(_ rhythm: CatPlayRhythm) {
        guard !isPaused, !isResponding, program == nil else { return }
        dragging = false; tracker.reset(); program = (rhythm, CACurrentMediaTime()); activeRhythm = rhythm
        attentionUntil = CACurrentMediaTime() + (style == .playful ? 0.05 : 0.35)
        actor.habitAttention(style: style, facing: toy.position.x < actor.position.x ? -1 : 1)
        onInput?(CatPlayInputKind(rawValue: rhythm.rawValue)!, .tap, 0, 0)
    }

    override func update(_ currentTime: TimeInterval) {
        let now = CACurrentMediaTime()
        if let program {
            let elapsed = now - program.start
            let movingTime = program.rhythm == .moveAndPause ? min(elapsed, 1.1) : elapsed
            let amplitude: CGFloat = reducedMotion ? 10 : area.width * 0.21
            toy.position = CGPoint(x: size.width * 0.62 + amplitude * sin(movingTime * 1.8), y: size.height * 0.48)
            feedbackKind = program.rhythm == .moveAndPause && elapsed > 1.1 ? .moveAndPause : .slowMove
            let threshold = program.rhythm == .moveAndPause ? 1.75 : 2.15
            if elapsed >= threshold {
                self.program = nil
                onInput?(CatPlayInputKind(rawValue: program.rhythm.rawValue)!, .tap, elapsed, 0)
                onMotion?("waiting")
            } else { onMotion?(program.rhythm == .moveAndPause && elapsed > 1.1 ? "waiting" : "following") }
        } else {
            tracker.tick(at: now)
            feedbackKind = tracker.kind
            if let rhythm = tracker.kind.rhythm { activeRhythm = rhythm }
            let kindChanged = tracker.kind != previousInputKind
            if kindChanged, tracker.kind == .slowMove || tracker.kind == .tooFast { reported.removeAll() }
            previousInputKind = tracker.kind
            if tracker.movementDuration >= 1 && !baseReported {
                baseReported = true
                onInput?(tracker.kind, .drag, tracker.duration, tracker.movementDuration)
            }
            if let rhythm = tracker.kind.rhythm,
               tracker.duration >= (rhythm == .moveAndPause ? CatHabitCatalog.pauseResponseDuration : CatHabitCatalog.responseDuration),
               !reported.contains(rhythm) {
                reported.insert(rhythm)
                onInput?(tracker.kind, .drag, tracker.duration, tracker.movementDuration)
            }
            if dragging && kindChanged { onMotion?(tracker.kind == .tooFast ? "tooFast" : "following") }
            else if tracker.kind == .moveAndPause && kindChanged { onMotion?("waiting") }
        }
        if !reducedMotion, !actor.isPerforming, now >= attentionUntil, (dragging && tracker.kind != .tooFast || program != nil) {
            let targetX = min(size.width * 0.76, max(size.width * 0.24, toy.position.x - 35))
            if abs(targetX - actor.position.x) > 10 {
                let origin = actor.position
                actor.stroll(along: [origin, CGPoint(x: targetX, y: origin.y)]) {}
            }
        }
        updateTrail(at: now)
        updateWand()
    }

    /// Called only after Core accepts and saves a complete response.
    func completeResponse(finishIndex: Int? = nil) {
        guard !isResponding else { return }
        dragging = false; program = nil; tracker.reset(); previousInputKind = .still; feedbackKind = .still
        actor.cancelAndSettle(at: actor.position); actor.setIdleEnabled(false)
        isResponding = true
        responseFinishIndex = finishIndex
        pounces += 1; onMotion?("pouncing")
        let origin = actor.position
        let target = CGPoint(x: min(size.width - 65, max(65, toy.position.x)), y: home.y)
        actor.play(landing: target, facing: target.x < origin.x ? -1 : 1, returnPath: [target], prepared: true, responseFinishIndex: finishIndex) { [weak self] in
            self?.isResponding = false
            self?.onMotion?("satisfied")
        }
    }

    func waitAndWatch() {
        guard !isResponding else { return }
        actor.cancelAndSettle(at: actor.position); actor.setIdleEnabled(false)
        actor.habitWaiting(facing: toy.position.x < actor.position.x ? -1 : 1); onMotion?("waiting")
    }
    func stop() {
        program = nil; dragging = false; feedbackKind = .still
        onInput = nil; onMotion = nil
        actor.cancelAndSettle(at: actor.position); actor.setIdleEnabled(false)
    }
    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touches.count == 1 else { return }
        beginPointer(at: touch.location(in: self))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if dragging, let touch = touches.first { hasDragged = true; receive(point: touch.location(in: self)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { dragging = false }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { dragging = false; tracker.reset() }
    #elseif os(macOS)
    override func mouseDown(with event: NSEvent) { beginPointer(at: event.location(in: self)) }
    override func mouseDragged(with event: NSEvent) {
        if dragging { hasDragged = true; receive(point: event.location(in: self)) }
    }
    override func mouseUp(with event: NSEvent) { dragging = false }
    #endif
    private func beginPointer(at point: CGPoint) {
        guard !isResponding else { return }
        dragging = true; program = nil; tracker.reset(); reported.removeAll()
        attentionUntil = CACurrentMediaTime() + (style == .playful ? 0.05 : 0.35)
        receive(point: point)
        actor.habitAttention(style: style, facing: toy.position.x < actor.position.x ? -1 : 1)
    }
    private func receive(point: CGPoint) {
        toy.position = CGPoint(x: min(area.maxX, max(area.minX, point.x)), y: min(area.maxY, max(area.minY, point.y)))
        tracker.move(to: .init(x: Double(toy.position.x / max(1, size.width)), y: Double(1 - toy.position.y / max(1, size.height))), at: CACurrentMediaTime())
        if tracker.kind == .tooFast, !isResponding {
            actor.cancelAndSettle(at: actor.position); actor.setIdleEnabled(false)
            actor.habitWaiting(facing: toy.position.x < actor.position.x ? -1 : 1)
        }
    }
    private func updateTrail(at now: TimeInterval) {
        guard !reducedMotion, now - lastTrailAt >= 0.08 else { return }
        lastTrailAt = now
        if trailPositions.last.map({ hypot($0.x - toy.position.x, $0.y - toy.position.y) > 2 }) ?? true {
            trailPositions.append(toy.position)
            trailPositions = Array(trailPositions.suffix(trail.count))
        }
        for (index, dot) in trail.enumerated() {
            dot.isHidden = index >= trailPositions.count
            if !dot.isHidden { dot.position = trailPositions[index] }
        }
    }
    private func updateWand() {
        let path = CGMutablePath(); path.move(to: CGPoint(x: size.width * 0.91, y: size.height * 0.86))
        path.addQuadCurve(to: toy.position, control: CGPoint(x: toy.position.x + 18, y: toy.position.y + 80))
        wand.path = path
    }
}
