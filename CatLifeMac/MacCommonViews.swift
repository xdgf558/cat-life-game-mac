#if os(macOS)
import SwiftUI
import CatGameCore

enum MacPage: String, CaseIterable, Identifiable {
    case home, work, shop, town, cats, settings
    var id: String { rawValue }
    var key: String { "mac.page." + rawValue }
    var icon: String { switch self { case .home: "icon-home"; case .work: "icon-work"; case .shop: "icon-shop"; case .town: "icon-town"; case .cats: "cat-avatar"; case .settings: "" } }
    var symbol: String { switch self { case .home: "house.fill"; case .work: "briefcase.fill"; case .shop: "storefront.fill"; case .town: "map.fill"; case .cats: "pawprint.fill"; case .settings: "gearshape.fill" } }
}
struct MacKeyCap: View {
    let value: String
    var body: some View {
        Text(value).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(RoomTheme.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(RoomTheme.track)).accessibilityHidden(true)
    }
}
/// Toolbar controls keep their intrinsic width instead of expanding across the stage.
struct MacCompactButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(RoomTheme.ink)
            .padding(.horizontal, 11).padding(.vertical, 8).frame(minHeight: 36)
            .background(RoomTheme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
            .compositingGroup()
            .shadow(color: RoomTheme.ink.opacity(0.1), radius: 0, y: configuration.isPressed ? 1 : 3)
            .offset(y: configuration.isPressed ? 1 : 0).opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Native macOS progress indicators ignore some tint styles; the drawn fill stays consistent.
struct MacCapsuleProgress: View {
    let value: Double
    var total: Double = 100
    let tint: Color
    private var fraction: Double {
        guard value.isFinite, total.isFinite, total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(RoomTheme.track).overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: geometry.size.width * fraction)
            }
        }.frame(height: 8).accessibilityHidden(true)
    }
}

/// Cream pill segments from the handoff, in place of the grey system segmented control.
struct MacSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index], selected = option.0 == selection
                Button { selection = option.0 } label: {
                    Text(option.1).font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(selected ? RoomTheme.darkMint : RoomTheme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8).frame(minWidth: 52)
                        .background(selected ? RoomTheme.paper : .clear, in: RoundedRectangle(cornerRadius: 11))
                        .shadow(color: selected ? RoomTheme.ink.opacity(0.08) : .clear, radius: 0, y: 2)
                        .contentShape(RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(4).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(RoomTheme.track.opacity(0.6)))
            .fixedSize().accessibilityElement(children: .contain)
    }
}
struct MacPanel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).font(.system(size: 18, weight: .heavy, design: .rounded)) }
            content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.9), lineWidth: 2))
    }
}
struct MacNavigationRail: View {
    let page: MacPage
    let preferences: MacPreferences
    var isWorking = false
    let select: (MacPage) -> Void
    let help: () -> Void
    var body: some View {
        VStack(spacing: 15) {
            Image("app-icon-preview").resizable().scaledToFit().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(.top, 16).accessibilityHidden(true)
            ForEach(Array(MacPage.allCases.prefix(5).enumerated()), id: \.element.id) { index, item in
                Button { select(item) } label: {
                    VStack(spacing: 4) {
                        GameIcon(asset: item.icon, symbol: item.symbol, size: 30)
                        Text(GameStrings.text(item.key)).font(.system(size: 12, weight: .heavy, design: .rounded))
                        MacKeyCap(value: preferences.binding(for: [.home, .work, .shop, .town, .cats][index]).label)
                    }.frame(width: 74, height: 86).background(page == item ? RoomTheme.paleMint : .clear, in: RoundedRectangle(cornerRadius: 19))
                }.buttonStyle(.plain).help(GameStrings.text(item.key)).accessibilityIdentifier("macNav_" + item.rawValue)
                    .overlay(alignment: .topTrailing) {
                        if item == .work, isWorking { Circle().fill(RoomTheme.gold).frame(width: 8, height: 8).padding(8).accessibilityHidden(true) }
                    }
            }
            Spacer(minLength: 8)
            Button(action: help) { Image(systemName: "questionmark.circle.fill").font(.system(size: 25)).frame(width: 60, height: 42) }.buttonStyle(.plain).help(GameStrings.text("mac.help"))
            Button { select(.settings) } label: { Image(systemName: "gearshape.fill").font(.system(size: 25)).frame(width: 74, height: 52)
                .background(page == .settings ? RoomTheme.paleMint : .clear, in: RoundedRectangle(cornerRadius: 17))
                .foregroundStyle(page == .settings ? RoomTheme.darkMint : RoomTheme.ink) }.buttonStyle(.plain).help(GameStrings.text("mac.page.settings")).accessibilityIdentifier("macNav_settings")
        }.foregroundStyle(RoomTheme.ink).frame(width: 92).background(RoomTheme.paper)
            .overlay(alignment: .trailing) { Rectangle().fill(RoomTheme.track).frame(width: 1) }
    }
}
struct MacTopBar: View {
    let store: GameStore
    let page: MacPage
    let onSaves: () -> Void
    let onPlayer: () -> Void
    private var subtitle: String? {
        guard let snapshot = store.snapshot else { return nil }
        switch page {
        case .home:
            let floor = GameStrings.text(store.visibleHomeFloor == .ground ? "mac.floor.ground" : "mac.floor.upper")
            if store.isDecorating { return GameStrings.format("mac.build.v2.subtitle", floor) }
            let day = MacTitleMetricsV2.dayNumber(createdAt: snapshot.meta.createdAt, at: max(store.now, snapshot.meta.lastSyncAt))
            return [store.homeDisplayName, "Lv\(snapshot.home.roomLevel)", GameStrings.format("mac.home.v2.day", day)].joined(separator: " · ")
        case .work: return GameStrings.format("mac.top.v2.work", snapshot.player.level)
        case .shop: return GameStrings.text("mac.top.v2.shop")
        case .town: return GameStrings.text("mac.top.v2.town")
        case .cats: return GameStrings.text("mac.top.v2.cats")
        default: return nil
        }
    }
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: page == .home && store.isDecorating ? "sofa.fill" : page.symbol).foregroundStyle(RoomTheme.darkMint)
                Text(page == .home && store.isDecorating ? GameStrings.text("mac.build.v2.title") : GameStrings.text(page.key)).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1)
            }.padding(.horizontal, 20).padding(.vertical, 10)
                .background(RoomTheme.wood.opacity(0.85), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(red: 0.72, green: 0.52, blue: 0.33).opacity(0.55), lineWidth: 2))
                .compositingGroup().shadow(color: Color(red: 0.6, green: 0.42, blue: 0.25).opacity(0.5), radius: 0, y: 4)
            if let subtitle {
                Text(subtitle).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(RoomTheme.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Button(action: onSaves) {
                Label(GameStrings.text(store.hasSaveFailure ? "mac.save.failed" : store.isBusy ? "mac.save.saving" : "mac.save.local"), systemImage: store.hasSaveFailure ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(store.hasSaveFailure ? RoomTheme.coral : RoomTheme.darkMint)
            }.buttonStyle(.plain).help(GameStrings.text("mac.save.steamOffline"))
            Button(action: onPlayer) {
                HStack(spacing: 7) {
                    GameIcon(asset: store.snapshot?.player.profile.avatarID.flatMap(PlayerCatalog.avatar(id:))?.assetName ?? "", symbol: "person.crop.circle.fill", size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.playerDisplayName).font(.caption.weight(.heavy))
                        Text(GameStrings.format("career.level", store.snapshot?.player.level ?? 1)).font(.caption2)
                        if let player = store.snapshot?.player {
                            MacCapsuleProgress(value: Double(player.exp), total: Double(max(1, WorkCatalog.requiredExperience(forLevel: player.level))), tint: RoomTheme.mint).frame(width: 80)
                        }
                    }
                }
            }.buttonStyle(.plain)
            HStack(spacing: 14) {
                Label("\(store.snapshot?.player.gold ?? 0)", systemImage: "dollarsign.circle.fill").foregroundStyle(RoomTheme.gold)
                Label("\(store.snapshot?.player.stamina ?? 0)/100", systemImage: "bolt.fill").foregroundStyle(RoomTheme.darkMint)
                Label("\(store.snapshot?.player.mood ?? 0)", systemImage: "face.smiling.fill").foregroundStyle(RoomTheme.secondary)
            }.font(.system(size: 17, weight: .heavy, design: .rounded)).padding(.horizontal, 16).padding(.vertical, 12).background(RoomTheme.paper, in: Capsule())
        }.foregroundStyle(RoomTheme.ink).padding(.horizontal, 20).frame(height: 68)
    }
}
#endif
