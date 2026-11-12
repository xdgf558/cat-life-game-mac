import CoreGraphics

/// Stable app-owned regions; camera math receives only the stage-local viewport.
enum HomeRoomLayout {
    static func careHeight(in canvas: CGSize) -> CGFloat { canvas.height < 600 ? 72 : 84 }

    static func stageFrame(in canvas: CGSize, headerHeight: CGFloat, editing: Bool) -> CGRect {
        guard canvas.width.isFinite, canvas.height.isFinite, headerHeight.isFinite,
              canvas.width > 0, canvas.height > 0 else { return .zero }
        if editing { return CGRect(origin: .zero, size: canvas) }
        let top = min(canvas.height, max(0, headerHeight) + 12)
        return CGRect(x: 10, y: top, width: max(0, canvas.width - 20),
                      height: max(0, canvas.height - top - careHeight(in: canvas) - 20))
    }
}
