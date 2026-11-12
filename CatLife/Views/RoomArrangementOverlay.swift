import SwiftUI
import CatGameCore

struct ArrangementPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

enum RoomArrangementOverlayLayout {
    static func center(for frame: CGRect, canvas: CGSize, bottomInset: CGFloat, width: CGFloat, topInset: CGFloat = 160) -> CGPoint {
        let half = min(width, max(0, canvas.width - 24)) / 2
        let x = min(max(frame.midX, half + 12), max(half + 12, canvas.width - half - 12))
        let upper = max(27, topInset + 27)
        let lower = max(upper, canvas.height - bottomInset - 38)
        return CGPoint(x: x, y: min(max(frame.minY - 32, upper), lower))
    }
}

@MainActor
struct RoomArrangementOverlay: View {
    let store: GameStore
    let selectedFrame: CGRect
    let canvasSize: CGSize
    let bottomInset: CGFloat
    var topInset: CGFloat = 160

    private var canRotate: Bool { store.selectedFurniture?.kind.supportsRotation == true }
    private var orientation: FurnitureOrientation { store.selectedFurniture?.orientation ?? .front }
    private var unavailableKey: String { store.selectedFurniture == nil ? "layout.bowlCannotFlip" : "layout.wallCannotFlip" }

    var body: some View {
        let width = min(222.0, max(0, canvasSize.width - 24))
        let center = RoomArrangementOverlayLayout.center(for: selectedFrame, canvas: canvasSize,
                                                         bottomInset: bottomInset, width: width, topInset: topInset)
        ZStack(alignment: .topLeading) {
            HStack(spacing: 3) {
                rotate(clockwise: false)
                rotate(clockwise: true)
                Button { store.storeSelectedFurniture() } label: {
                    icon("backpack.fill")
                }.buttonStyle(.plain).disabled(!store.canStoreSelectedFurniture)
                    .accessibilityLabel(GameStrings.text("layout.storeFurniture"))
                    .accessibilityIdentifier("quickStoreFurnitureButton")
                Button { store.confirmArrangementSelection68() } label: {
                    icon("checkmark").foregroundStyle(.white).background(RoomTheme.mint, in: Circle())
                }.buttonStyle(.plain).disabled(store.selectedArrangementIssue68 != nil)
                    .accessibilityLabel(GameStrings.text("build68.placeHere"))
                    .accessibilityIdentifier("quickConfirmFurniture68")
            }.foregroundStyle(RoomTheme.darkMint)
                .padding(5).frame(width: width).gameCard(cornerRadius: 30).position(center)
            Text(store.selectedArrangementIssue68.map(store.arrangementIssueText68)
                 ?? (store.selectedFurnitureName + " · " + GameStrings.text("build68.facing.\(orientation.rawValue)")))
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(store.selectedArrangementIssue68 == nil ? RoomTheme.mint : RoomTheme.coralDeep, in: Capsule())
                .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                .frame(maxWidth: min(280, max(24, canvasSize.width - 24)))
                .position(x: min(max(selectedFrame.midX, 100), max(100, canvasSize.width - 100)),
                          y: min(max(selectedFrame.maxY + 12, center.y + 42),
                                 max(center.y + 42, canvasSize.height - bottomInset - 15)))
                .accessibilityHidden(true).allowsHitTesting(false)
        }.frame(width: canvasSize.width, height: canvasSize.height)
            .disabled(!store.canEditArrangement68)
    }
    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    private func rotate(clockwise: Bool) -> some View {
        Button {
            if canRotate { store.rotateSelectedFurniture68(clockwise: clockwise) }
            else { store.playFeedback(.softError); store.showFurnitureNotice(unavailableKey) }
        } label: {
            icon(clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .foregroundStyle(canRotate ? RoomTheme.darkMint : RoomTheme.secondary.opacity(0.45))
        }.buttonStyle(.plain)
            .accessibilityIdentifier(clockwise ? "flipFurnitureButton" : "quickRotateLeft68")
            .accessibilityLabel(GameStrings.text(clockwise ? "build68.rotateRight" : "build68.rotateLeft"))
            .accessibilityValue(GameStrings.text(canRotate ? "build68.facing.\(orientation.rawValue)" : unavailableKey))
            .accessibilityHint(canRotate ? "" : GameStrings.text(unavailableKey))
    }
}
