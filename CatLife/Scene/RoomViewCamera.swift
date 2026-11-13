import Foundation
import CoreGraphics

/// Maps projected room coordinates (y up) into the usable UIKit viewport (y down).
@MainActor
final class RoomViewCamera {
    private(set) var center = CGPoint.zero
    private(set) var scale: CGFloat = 1
    private(set) var fitScale: CGFloat = 1
    private(set) var viewportSize = CGSize.zero

    var visibleRect: CGRect {
        CGRect(x: center.x - usableRect.width * scale / 2,
               y: center.y - usableRect.height * scale / 2,
               width: usableRect.width * scale, height: usableRect.height * scale)
    }

    var isWholeRoom: Bool {
        abs(scale - fitScale) <= fitScale * 0.000001
            && abs(center.x - bounds.midX) <= 0.0001
            && abs(center.y - bounds.midY) <= 0.0001
    }

    var isPinching: Bool { pinchAnchor != nil }

    private var bounds = CGRect.zero
    private var usableRect = CGRect.zero
    private var worldScale: CGFloat = 1
    private var configured = false
    private var panOrigin: CGPoint?
    private var panCenter = CGPoint.zero
    private var isPanning = false
    private var pinchAnchor: CGPoint?
    private var pinchScale: CGFloat = 1

    private var minScale: CGFloat {
        max(CGFloat.leastNormalMagnitude, fitScale / worldScale * 0.625)
    }

    func configure(bounds: CGRect, viewport: CGSize, usableRect: CGRect,
                   worldScale: CGFloat, reset: Bool) {
        guard valid(bounds), viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0, valid(usableRect) else { return }
        let usable = usableRect.intersection(CGRect(origin: .zero, size: viewport))
        guard valid(usable) else { return }
        let nextFit = max(bounds.width / usable.width, bounds.height / usable.height)
        guard nextFit.isFinite, nextFit > 0 else { return }
        let relativeZoom = scale / fitScale
        cancelGestures()
        self.bounds = bounds
        viewportSize = viewport
        self.usableRect = usable
        self.worldScale = worldScale.isFinite ? max(1, worldScale) : 1
        fitScale = nextFit
        if reset || !configured {
            scale = fitScale
            center = CGPoint(x: bounds.midX, y: bounds.midY)
        } else {
            scale = clampedScale(fitScale * relativeZoom)
            center = clampedCenter(center)
        }
        configured = true
    }

    func viewPoint(projectedWorld point: CGPoint) -> CGPoint {
        CGPoint(x: usableRect.midX + (point.x - center.x) / scale,
                y: usableRect.midY - (point.y - center.y) / scale)
    }

    func worldPoint(viewPoint point: CGPoint) -> CGPoint {
        CGPoint(x: center.x + (point.x - usableRect.midX) * scale,
                y: center.y - (point.y - usableRect.midY) * scale)
    }

    func fit() {
        cancelGestures()
        scale = fitScale
        center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func focus(on point: CGPoint) {
        guard finite(point) else { return }
        cancelGestures()
        scale = clampedScale(fitScale / max(1.6, worldScale))
        center = clampedCenter(point)
    }

    func recenter(on point: CGPoint) {
        guard finite(point) else { return }
        center = clampedCenter(point)
    }

    func follow(_ point: CGPoint) {
        guard !isWholeRoom, !isPinching, panOrigin == nil, finite(point) else { return }
        let halfWidth = visibleRect.width * 0.3
        let halfHeight = visibleRect.height * 0.3
        center = clampedCenter(CGPoint(
            x: min(point.x + halfWidth, max(point.x - halfWidth, center.x)),
            y: min(point.y + halfHeight, max(point.y - halfHeight, center.y))))
    }

    @discardableResult
    func scrollNearEdge(at point: CGPoint, delta: TimeInterval) -> Bool {
        guard !isPinching, finite(point), delta.isFinite, delta > 0 else { return false }
        let edge: CGFloat = 30
        let dx = point.x < usableRect.minX + edge ? -(usableRect.minX + edge - point.x) / edge
            : point.x > usableRect.maxX - edge ? (point.x - usableRect.maxX + edge) / edge : 0
        let dy = point.y < usableRect.minY + edge ? (usableRect.minY + edge - point.y) / edge
            : point.y > usableRect.maxY - edge ? -(point.y - usableRect.maxY + edge) / edge : 0
        guard dx != 0 || dy != 0 else { return false }
        let distance = 100 * CGFloat(min(1.0 / 15, delta)) * scale
        let before = center
        center = clampedCenter(CGPoint(x: center.x + min(1, max(-1, dx)) * distance,
                                       y: center.y + min(1, max(-1, dy)) * distance))
        return center != before
    }

    func beginPan(at point: CGPoint) {
        guard !isPinching, finite(point) else { return }
        panOrigin = point
        panCenter = center
        isPanning = false
    }

    @discardableResult
    func changePan(to point: CGPoint) -> Bool {
        guard !isPinching, let origin = panOrigin, finite(point) else { return false }
        let dx = point.x - origin.x, dy = point.y - origin.y
        guard isPanning || hypot(dx, dy) >= 8 else { return false }
        isPanning = true
        center = clampedCenter(CGPoint(x: panCenter.x - dx * scale, y: panCenter.y + dy * scale))
        return true
    }

    @discardableResult
    func endPan() -> Bool {
        let moved = isPanning
        panOrigin = nil
        isPanning = false
        return moved
    }

    func beginPinch(at point: CGPoint) {
        guard finite(point) else { return }
        let anchor = worldPoint(viewPoint: point)
        guard finite(anchor) else { return }
        cancelGestures()
        pinchAnchor = anchor
        pinchScale = scale
    }

    func changePinch(factor: CGFloat, at point: CGPoint) {
        guard let anchor = pinchAnchor, factor.isFinite, factor > 0, finite(point) else { return }
        scale = clampedScale(pinchScale / factor)
        center = clampedCenter(CGPoint(x: anchor.x - (point.x - usableRect.midX) * scale,
                                       y: anchor.y + (point.y - usableRect.midY) * scale))
    }

    func endPinch() { pinchAnchor = nil }

    func zoom(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        cancelGestures()
        scale = clampedScale(scale / factor)
        center = clampedCenter(center)
    }

    func cancelGestures() {
        endPan()
        endPinch()
    }

    private func clampedScale(_ proposed: CGFloat) -> CGFloat {
        min(fitScale, max(minScale, proposed))
    }

    private func clampedCenter(_ proposed: CGPoint) -> CGPoint {
        let halfWidth = usableRect.width * scale / 2
        let halfHeight = usableRect.height * scale / 2
        return CGPoint(
            x: halfWidth * 2 >= bounds.width ? bounds.midX
                : min(bounds.maxX - halfWidth, max(bounds.minX + halfWidth, proposed.x)),
            y: halfHeight * 2 >= bounds.height ? bounds.midY
                : min(bounds.maxY - halfHeight, max(bounds.minY + halfHeight, proposed.y)))
    }

    private func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }

    private func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && finite(rect.origin)
            && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}
