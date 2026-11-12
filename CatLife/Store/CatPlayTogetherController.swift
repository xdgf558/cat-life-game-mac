import Foundation
import Observation
import CatGameCore

@MainActor @Observable
final class CatPlayTogetherController {
    let store: GameStore
    let session: CatPlaySession
    let scene: CatPlayTogetherScene
    let generation: UUID
    let initialMemoryKinds: Set<CatMemoryKind>
    private(set) var phase = "watching"
    private(set) var remaining: Double
    private(set) var working = false
    private(set) var failed = false
    private(set) var ending = false
    private(set) var speedKind: CatPlayInputKind = .still
    private(set) var activeRhythm: CatPlayRhythm?
    private(set) var hasDragged = false
    private(set) var demonstrating = false
    var continuedStudy = false
    @ObservationIgnored private var queue: [CatPlayInputReport] = []
    @ObservationIgnored private var inputTask: Task<Void, Never>?
    @ObservationIgnored private var tutorialEndTask: Task<Void, Never>?
    @ObservationIgnored private var nextSequence = 0
    @ObservationIgnored private var visible = true
    @ObservationIgnored private let deadline: Double

    init(store: GameStore, session: CatPlaySession) {
        self.store = store; self.session = session; generation = store.saveSceneGeneration
        initialMemoryKinds = Set(store.snapshot?.cats.first { $0.id == session.catID }?.habits.memories.map(\.kind) ?? [])
        let remaining = max(0, min(20, session.endsAt.timeIntervalSince(max(Date(), store.snapshot?.meta.lastSyncAt ?? Date()))))
        self.remaining = remaining
        deadline = ProcessInfo.processInfo.systemUptime + remaining
        let appearance = store.snapshot?.cats.first { $0.id == session.catID }?.appearance ?? .orange
        scene = CatPlayTogetherScene(appearance: appearance)
        scene.style = CatHabitCatalog.definition(for: session.catID)?.style ?? .playful
        nextSequence = session.lastSequence
        scene.onMotion = { [weak self] phase in
            guard self?.phase != phase else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visible, !self.ending, self.phase != phase,
                      !self.scene.isResponding || phase == "satisfied" else { return }
                self.phase = phase
            }
        }
        scene.onInput = { [weak self] kind, control, duration, movement in self?.submit(kind, control: control, duration: duration, movement: movement) }
    }
    var result: CatPlayReceipt? { store.snapshot?.catPlay.lastResult.flatMap { $0.id == session.id ? $0 : nil } }
    var current: CatPlaySession { store.snapshot?.catPlay.activeSession.flatMap { $0.id == session.id ? $0 : nil } ?? result?.session ?? session }

    var motionKey: String {
        guard phase == "satisfied", let index = scene.responseFinishIndex else { return "catHabits.motion.\(phase)" }
        return index == 0 ? "catHabits.motion.contentSit" : "catHabits.motion.softPaw"
    }

    func tick() {
        speedKind = scene.feedbackKind; activeRhythm = scene.activeRhythm
        hasDragged = scene.hasDragged; demonstrating = scene.isDemonstrating
        let next = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        if ceil(next) != ceil(remaining) || next == 0 { remaining = next }
        if next == 0 { finish() }
    }
    func setVisible(_ active: Bool) { if !active { visible = false; finish() } }
    func control(_ rhythm: CatPlayRhythm) {
        guard !ending, result == nil, !scene.isResponding, !scene.isDemonstrating, !failed, !store.hasSaveFailure else { return }
        phase = "watching"; scene.runControl(rhythm)
    }
    func finish() {
        guard !ending else { return }
        ending = true; queue.removeAll(); tutorialEndTask?.cancel(); scene.stop()
        store.requestPlayEnd(catID: session.catID, sessionID: session.id, generation: generation)
    }
    func retry() {
        failed = false
        if ending { store.requestPlayEnd(catID: session.catID, sessionID: session.id, generation: generation) }
        else { process() }
    }
    private func submit(_ kind: CatPlayInputKind, control: CatPlayControl, duration: Double, movement: Double) {
        guard visible, !ending, result == nil, queue.count < 12 else { return }
        nextSequence += 1
        queue.append(.init(sequence: nextSequence, kind: kind, control: control, duration: min(20, duration), movementDuration: min(20, movement)))
        process()
    }
    private func process() {
        guard inputTask == nil, !queue.isEmpty, !ending else { return }
        inputTask = Task { [weak self] in
            guard let self else { return }
            while !self.queue.isEmpty && !self.ending && self.visible {
                guard self.generation == self.store.saveSceneGeneration else { self.finish(); break }
                if self.store.isBusy { try? await Task.sleep(for: .milliseconds(30)); continue }
                let report = self.queue[0]
                self.working = true
                let saved = await self.store.submitPlayInput(catID: self.session.catID, sessionID: self.session.id, report: report)
                self.working = false
                if !saved {
                    self.failed = self.store.hasSaveFailure
                    if self.store.snapshot?.catPlay.activeSession?.id != self.session.id { self.finish() }
                    break
                }
                if self.queue.first?.sequence == report.sequence { self.queue.removeFirst() }
                guard self.visible, !self.ending else { break }
                guard self.generation == self.store.saveSceneGeneration else { self.finish(); break }
                if let rhythm = report.kind.rhythm, self.current.observedRhythms.contains(rhythm),
                   report.duration >= (rhythm == .moveAndPause ? CatHabitCatalog.pauseResponseDuration : CatHabitCatalog.responseDuration) {
                    if rhythm == CatHabitCatalog.definition(for: self.session.catID)?.play {
                        self.phase = "pouncing"
                        let cat = self.store.snapshot?.cats.first { $0.id == self.session.catID }
                        self.scene.completeResponse(finishIndex: cat?.habits.playConfirmed == true ? cat?.habits.lastResponseFinishIndex : nil)
                    } else { self.phase = "waiting"; self.scene.waitAndWatch() }
                }
                if self.session.isTutorial, self.store.snapshot?.catPlay.tutorialCompleted == true, self.tutorialEndTask == nil {
                    self.tutorialEndTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(4.5)) } catch { return }
                        self?.finish()
                    }
                }
            }
            self.inputTask = nil
        }
    }
}
