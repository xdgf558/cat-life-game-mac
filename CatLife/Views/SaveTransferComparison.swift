import SwiftUI
import CatGameCore

enum SaveTransferComparison {
    static func direction(current: Int, incoming: Int) -> Int {
        incoming == current ? 0 : (incoming > current ? 1 : -1)
    }

    static func isEarlier(current: GameSnapshot, incoming: GameSnapshot) -> Bool {
        guard !isInitialProgress(current) else { return false }
        return incoming.player.level < current.player.level || incoming.meta.lastSyncAt < current.meta.lastSyncAt
    }

    private static func isInitialProgress(_ current: GameSnapshot) -> Bool {
        var initial = GameSnapshot.fresh(now: current.meta.createdAt)
        guard GameEngine.synchronize(&initial, now: current.meta.lastSyncAt).succeeded,
              current.cats.count == 1 else { return false }
        // Choosing a language, portrait or name on a new device is not gameplay progress.
        initial.settings = current.settings
        initial.player.profile.name = current.player.profile.name
        initial.player.profile.avatarID = current.player.profile.avatarID
        initial.home.name = current.home.name
        initial.cats[0].customName = current.cats[0].customName
        return initial == current
    }
}

struct SaveTransferComparisonView: View {
    let current: GameSnapshot
    let incoming: GameSnapshot
    var isRecovery = false
    let language: GameLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 6) {
                    Text(" ").frame(maxWidth: .infinity)
                    Text(GameStrings.text("saveTransfer.compare.current")).frame(maxWidth: .infinity)
                    Image(systemName: "arrow.right").hidden().frame(width: 12)
                    Text(GameStrings.text(isRecovery ? "saveTransfer.compare.recovery" : "saveTransfer.compare.backup"))
                        .foregroundStyle(isRecovery ? RoomTheme.lilac : RoomTheme.gold)
                        .frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
                .padding(.bottom, 12)
            }
            row("saveTransfer.compare.player", symbol: "person.fill", current: SaveTransferPresentation.player(current),
                incoming: SaveTransferPresentation.player(incoming))
            numberRow("saveTransfer.stat.level", symbol: "star.fill", current: current.player.level, incoming: incoming.player.level)
            numberRow("saveTransfer.stat.gold", symbol: "dollarsign.circle.fill", current: current.player.gold, incoming: incoming.player.gold)
            numberRow("saveTransfer.stat.cats", symbol: "cat.fill", current: current.cats.count, incoming: incoming.cats.count)
            row("saveTransfer.compare.time", symbol: "clock.fill",
                current: SaveTransferPresentation.date(current.meta.lastSyncAt, language: language),
                incoming: SaveTransferPresentation.date(incoming.meta.lastSyncAt, language: language))
        }
        .padding(14).gameCard()
    }

    private func numberRow(_ key: String, symbol: String, current: Int, incoming: Int) -> some View {
        row(key, symbol: symbol, current: String(current), incoming: String(incoming),
            direction: SaveTransferComparison.direction(current: current, incoming: incoming))
    }

    private func row(_ key: String, symbol: String, current: String, incoming: String, direction: Int = 0) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(RoomTheme.wood.opacity(0.35))
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(GameStrings.text(key), systemImage: symbol).font(.caption.weight(.heavy))
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(GameStrings.text("saveTransfer.compare.current")).font(.caption.weight(.bold))
                            Text(verbatim: current).fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(RoomTheme.secondary)
                        Image(systemName: "arrow.down").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(RoomTheme.secondary.opacity(0.6)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(GameStrings.text(isRecovery ? "saveTransfer.compare.recovery" : "saveTransfer.compare.backup"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isRecovery ? RoomTheme.lilac : RoomTheme.gold)
                            incomingValue(incoming, direction: direction, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: 6) {
                        Label(GameStrings.text(key), systemImage: symbol)
                            .font(.caption.weight(.heavy)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: current).foregroundStyle(RoomTheme.secondary)
                            .frame(maxWidth: .infinity)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(RoomTheme.secondary.opacity(0.6)).frame(width: 12)
                        incomingValue(incoming, direction: direction)
                    }
                    .multilineTextAlignment(.center)
                }
            }
            .font(.subheadline.weight(.heavy))
            .padding(.vertical, 8).monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.text(key))
            .accessibilityValue(GameStrings.format("saveTransfer.compare.values", current, incoming)
                + (direction == 0 ? "" : " · " + GameStrings.text(direction > 0 ? "saveTransfer.compare.increase" : "saveTransfer.compare.decrease")))
            .accessibilityIdentifier("saveComparison_\(key)")
        }
    }

    private func incomingValue(_ value: String, direction: Int, alignment: Alignment = .center) -> some View {
        HStack(spacing: 2) {
            Text(verbatim: value).fixedSize(horizontal: false, vertical: true)
            if direction != 0 {
                Image(systemName: direction > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 12, weight: .heavy)).accessibilityHidden(true)
            }
        }
        .foregroundStyle(direction == 0 ? RoomTheme.ink : (direction > 0 ? RoomTheme.darkMint : RoomTheme.coralDeep))
        .frame(maxWidth: .infinity, alignment: alignment).padding(.vertical, 7)
        .background(direction == 0 ? Color.clear : (direction > 0 ? RoomTheme.paleMint : RoomTheme.paleCoral).opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
