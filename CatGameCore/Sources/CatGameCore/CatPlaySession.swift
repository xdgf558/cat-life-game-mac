import Foundation

public enum CatPlayInputKind: String, Codable, CaseIterable, Sendable {
    case slowMove, moveAndPause, tooFast, still
    public var rhythm: CatPlayRhythm? { CatPlayRhythm(rawValue: rawValue) }
}
public enum CatPlayControl: String, Codable, Sendable { case drag, tap }

public struct CatPlayInputReport: Equatable, Sendable {
    public let sequence: Int
    public let kind: CatPlayInputKind
    public let control: CatPlayControl
    public let duration: TimeInterval
    public let movementDuration: TimeInterval
    public init(sequence: Int, kind: CatPlayInputKind, control: CatPlayControl,
                duration: TimeInterval, movementDuration: TimeInterval) {
        self.sequence = sequence; self.kind = kind; self.control = control
        self.duration = duration; self.movementDuration = movementDuration
    }
    var isValid: Bool {
        (1...1_000_000).contains(sequence) && [duration, movementDuration].allSatisfy { $0.isFinite && (0...20).contains($0) }
            && (control != .tap || kind.rhythm != nil)
    }
}

public struct CatPlayEffects: Codable, Equatable, Sendable {
    public var toysSpent = 0
    public var catMood = 0
    public var intimacy = 0
    public var energySpent = 0
    public var playerMood = 0
    public init() {}
    var isValid: Bool {
        (0...1).contains(toysSpent) && [catMood, intimacy, energySpent, playerMood].allSatisfy { (0...100).contains($0) }
    }
}

public struct CatPlaySession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let catID: String
    public let openedAt: Date
    public let isTutorial: Bool
    public var paidAt: Date?
    public var lastSequence = 0
    public var observedRhythms: [CatPlayRhythm] = []
    public var completeResponse = false
    public var effects = CatPlayEffects()
    public var endsAt: Date { openedAt.addingTimeInterval(CatHabitCatalog.playDuration) }
    init(catID: String, openedAt: Date, isTutorial: Bool) {
        self.id = UUID().uuidString; self.catID = catID; self.openedAt = openedAt; self.isTutorial = isTutorial
    }
    var isValid: Bool {
        CatHabitState.validID(id) && CatHabitState.validID(catID) && openedAt.timeIntervalSince1970.isFinite
            && (paidAt.map { $0.timeIntervalSince1970.isFinite && $0 >= openedAt && $0 <= endsAt } ?? true)
            && (0...1_000_000).contains(lastSequence)
            && observedRhythms.count <= 2 && Set(observedRhythms).count == observedRhythms.count
            && effects.isValid && (isTutorial ? paidAt == nil && effects == CatPlayEffects() : (paidAt == nil) == (effects.toysSpent == 0))
            && (observedRhythms.isEmpty || isTutorial || paidAt != nil)
    }
}

public struct CatPlayReceipt: Codable, Equatable, Sendable, Identifiable {
    public let session: CatPlaySession
    public let endedAt: Date
    public var id: String { session.id }
    public var catID: String { session.catID }
    var isValid: Bool {
        session.isValid && endedAt.timeIntervalSince1970.isFinite && endedAt >= session.openedAt && endedAt <= session.endsAt
    }
}

public struct CatPlayState: Codable, Equatable, Sendable {
    public var tutorialCompleted = false
    public var introDismissed = false
    public var tutorialID: String?
    public var tutorialCatID: String?
    public var tutorialRhythms: [CatPlayRhythm] = []
    public var activeSession: CatPlaySession?
    public var lastResult: CatPlayReceipt?
    public init() {}
    var isValid: Bool {
        (activeSession?.isValid ?? true) && (lastResult?.isValid ?? true)
            && (activeSession == nil || activeSession?.id != lastResult?.id)
            && (tutorialID == nil) == (tutorialCatID == nil)
            && (tutorialID.map(CatHabitState.validID) ?? true) && (tutorialCatID.map(CatHabitState.validID) ?? true)
            && tutorialRhythms.count <= 2 && Set(tutorialRhythms).count == tutorialRhythms.count
            && (!tutorialCompleted || (tutorialID != nil && tutorialRhythms.count == 2))
    }
}
