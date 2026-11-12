import Foundation
import Observation
import CatGameCore

enum ArrangementFilter68: String, CaseIterable, Sendable { case floor, wall, bag }
enum ArrangementIssue68: Equatable, Sendable { case outside, overlap(String?), blocked }
enum ArrangementCommand68: Equatable, Sendable {
    case rotate(id: String, orientation: FurnitureOrientation)
    case nudge(id: String?, dx: Int, dy: Int, step: Double)
    case confirm(id: String?)
    case focus(id: String)
}
struct ArrangementRequest68: Identifiable, Equatable, Sendable {
    let id = UUID()
    let command: ArrangementCommand68
}

struct ArrangementDraft68: Equatable {
    let bowl: NormalizedPoint?
    let furniture: [FurniturePlacement]?
    let orientations: [String: FurnitureOrientation]?
    let selectedID: String?
    let storedID: String?
    let bowlSelected: Bool
    var issues: [String: ArrangementIssue68] = [:]

    func hasSameLayout(as other: ArrangementDraft68) -> Bool {
        bowl == other.bowl && furniture == other.furniture && orientations == other.orientations
    }
}

/// Editing-only state. It never adds fields to a player's save or owns room geometry.
@MainActor @Observable
final class ArrangementEditor68 {
    var snapEnabled = true
    var filter: ArrangementFilter68 = .floor
    var previewAngle: RoomViewAngle = .front
    var pendingRequest: ArrangementRequest68?
    var placementIssues: [String: ArrangementIssue68] = [:]
    var bowlSelected = false
    private(set) var history: [ArrangementDraft68] = []
    private(set) var future: [ArrangementDraft68] = []
    var canRedo: Bool { !future.isEmpty && pendingRequest == nil }
    @ObservationIgnored private var gestureStart: ArrangementDraft68?
    var canUndo: Bool { !history.isEmpty && pendingRequest == nil }
    var gridStep: Double { snapEnabled ? 0.5 : 0.1 }
    var hasInvalidPlacement: Bool { !placementIssues.isEmpty }

    func begin(_ draft: ArrangementDraft68) {
        if gestureStart == nil { gestureStart = draft }
    }
    func end(_ draft: ArrangementDraft68) {
        defer { gestureStart = nil }
        guard let previous = gestureStart, !previous.hasSameLayout(as: draft) else { return }
        future.removeAll()
        history.append(previous)
        if history.count > 20 { history.removeFirst(history.count - 20) }
    }
    func undo(current: ArrangementDraft68? = nil) -> ArrangementDraft68? {
        guard canUndo else { return nil }
        gestureStart = nil
        if let current { future.append(current) }
        return history.popLast()
    }
    func redo(current: ArrangementDraft68) -> ArrangementDraft68? {
        guard canRedo, let next = future.popLast() else { return nil }
        gestureStart = nil
        history.append(current)
        if history.count > 20 { history.removeFirst(history.count - 20) }
        return next
    }
    func reset() {
        snapEnabled = true; filter = .floor; previewAngle = .front; pendingRequest = nil
        placementIssues.removeAll(); bowlSelected = false; history.removeAll(); future.removeAll(); gestureStart = nil
    }
}
