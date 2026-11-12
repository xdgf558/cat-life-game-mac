import SwiftUI

@MainActor
struct RoomViewControls: View {
    let angle: RoomViewAngle
    let isWholeRoomView: Bool
    let canChangeView: Bool
    let catName: String
    let turn: (Int) -> Void
    let showWholeRoom: () -> Void
    let focusCat: () -> Void

    private var angleKey: String {
        switch angle {
        case .left: "roomView.angle.left"
        case .front: "roomView.angle.front"
        case .right: "roomView.angle.right"
        }
    }

    private var viewDescription: String {
        GameStrings.format("roomView.current", GameStrings.text(angleKey),
                           GameStrings.text(isWholeRoomView ? "roomView.whole" : "roomView.close"))
    }

    private var modeTitle: String {
        isWholeRoomView ? GameStrings.format("home63.closeCat", catName) : GameStrings.text("roomView.whole")
    }

    var body: some View {
        HStack(spacing: 0) {
            turnButton(-1, symbol: "chevron.left", key: "roomView.turnLeft",
                       identifier: "roomViewLeftButton", atLimit: angle == .left)
            VStack(spacing: 4) {
                Text(GameStrings.text(angleKey))
                    .font(.caption2.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.75)
                HStack(spacing: 4) {
                    ForEach(RoomViewAngle.allCases, id: \.self) { candidate in
                        Capsule().fill(candidate == angle ? RoomTheme.mint : RoomTheme.wood)
                            .frame(width: candidate == angle ? 14 : 5, height: 5)
                    }
                }.accessibilityHidden(true)
            }
            .frame(minWidth: 64, maxWidth: 100).frame(height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("roomViewStatus").accessibilityLabel(viewDescription)
            turnButton(1, symbol: "chevron.right", key: "roomView.turnRight",
                       identifier: "roomViewRightButton", atLimit: angle == .right)
            Rectangle().fill(RoomTheme.wood.opacity(0.6)).frame(width: 1, height: 26).padding(.horizontal, 6)
                .accessibilityHidden(true)
            Button(action: isWholeRoomView ? focusCat : showWholeRoom) {
                Label(modeTitle, systemImage: isWholeRoomView ? "plus.magnifyingglass" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.heavy)).lineLimit(2).minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 66, maxWidth: .infinity).frame(height: 44)
                    .foregroundStyle(isWholeRoomView ? RoomTheme.ink : .white)
                    .background(isWholeRoomView ? RoomTheme.gold.opacity(0.14) : RoomTheme.mint, in: Capsule())
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("roomOverviewButton")
            .accessibilityLabel(isWholeRoomView ? modeTitle : GameStrings.text("roomView.showWhole"))
            .accessibilityValue(viewDescription)
        }
        .padding(4)
        .background(RoomTheme.paper.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
        .shadow(color: RoomTheme.ink.opacity(0.12), radius: 5, y: 3)
        .buttonStyle(.plain).foregroundStyle(RoomTheme.ink)
        .disabled(!canChangeView).opacity(canChangeView ? 1 : 0.6)
        .accessibilityElement(children: .contain).accessibilityIdentifier("roomViewControls")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func turnButton(_ steps: Int, symbol: String, key: String,
                            identifier: String, atLimit: Bool) -> some View {
        Button { turn(steps) } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .heavy))
                .frame(width: 36, height: 36)
                .background(atLimit ? RoomTheme.wood.opacity(0.18) : RoomTheme.paleMint, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(atLimit).opacity(atLimit ? 0.35 : 1)
        .accessibilityLabel(GameStrings.text(key)).accessibilityIdentifier(identifier)
    }
}
