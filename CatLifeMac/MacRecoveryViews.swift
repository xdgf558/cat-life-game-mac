#if os(macOS)
import SwiftUI
import CatGameCore

/// Where a recovery flow can send the player; the desktop root owns navigation.
struct MacRecoveryExits {
    var cafe: () -> Void = {}
    var rest: () -> Void = {}
    var shop: () -> Void = {}
}

/// "🍴 Today's supplies ●○○ 1 / 3" — shared by bag, work, café and the top-bar popover.
struct MacRecoveryDots: View {
    let used: Int
    var limit = PlayerSupplyCatalog.dailyLimit
    var showsHint = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "fork.knife").foregroundStyle(RoomTheme.gold)
            Text(GameStrings.text("recover.dots.title"))
            HStack(spacing: 3) {
                ForEach(0..<limit, id: \.self) { index in
                    if index < used { Circle().fill(RoomTheme.gold).frame(width: 9, height: 9) }
                    else { Circle().strokeBorder(RoomTheme.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.4, dash: [2, 2])).frame(width: 9, height: 9) }
                }
            }.accessibilityHidden(true)
            Text(GameStrings.format("recover.dots.count", used, limit)).monospacedDigit()
            if showsHint { Text(GameStrings.text("recover.dots.resetHint")).foregroundStyle(RoomTheme.secondary).font(.system(size: 11, weight: .semibold)) }
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .accessibilityElement(children: .combine)
    }
}

enum MacRecoveryAttribute { case stamina, mood
    var key: String { self == .stamina ? "recover.attr.stamina" : "recover.attr.mood" }
    var symbol: String { self == .stamina ? "bolt.fill" : "face.smiling.inverse" }
    var tint: Color { self == .stamina ? RoomTheme.mint : RoomTheme.friendship }
}

/// One attribute: "Stamina 62 → 87  +25" over a 12-pt bar whose striped part is the gain.
struct MacRecoveryBar: View {
    let attribute: MacRecoveryAttribute
    let current: Int
    let gain: Int
    var body: some View {
        let applied = min(gain, max(0, 100 - current)), waste = gain - applied
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: attribute.symbol).foregroundStyle(attribute.tint)
                Text(GameStrings.text(attribute.key))
                Text("\(current) →").foregroundStyle(RoomTheme.secondary).monospacedDigit()
                Text("\(current + applied)").foregroundStyle(applied > 0 ? attribute.tint : RoomTheme.secondary).monospacedDigit()
                Spacer(minLength: 4)
                if applied == 0 {
                    Text(GameStrings.text("recover.preview.full")).foregroundStyle(RoomTheme.secondary)
                } else if waste > 0 {
                    Text(GameStrings.format("recover.preview.waste", applied, waste)).foregroundStyle(RoomTheme.coralDeep)
                } else {
                    Text(GameStrings.format("recover.preview.gain", applied)).foregroundStyle(attribute.tint)
                }
            }.font(.system(size: 13, weight: .heavy, design: .rounded))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(RoomTheme.track)
                    Capsule().fill(attribute.tint.opacity(0.35))
                        .overlay(MacStripes().stroke(attribute.tint.opacity(0.7), lineWidth: 2).clipShape(Capsule()))
                        .frame(width: proxy.size.width * CGFloat(min(100, current + applied)) / 100)
                    Capsule().fill(attribute.tint).frame(width: proxy.size.width * CGFloat(current) / 100)
                }
            }.frame(height: 12).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(attribute.key))
        .accessibilityValue("\(current) → \(current + applied)")
    }
}

private struct MacStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX { path.move(to: CGPoint(x: x, y: rect.maxY)); path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY)); x += 6 }
        return path
    }
}

/// Bars for every attribute an effect raises.
struct MacRecoveryPreview: View {
    let player: PlayerState
    let effect: RecoveryEffect
    var body: some View {
        VStack(spacing: 10) {
            if effect.stamina > 0 { MacRecoveryBar(attribute: .stamina, current: player.stamina, gain: effect.stamina) }
            if effect.mood > 0 { MacRecoveryBar(attribute: .mood, current: player.mood, gain: effect.mood) }
        }
    }
}

/// Effect chips such as "Stamina +25 · Mood +12".
struct MacEffectChips: View {
    let effect: RecoveryEffect
    var body: some View {
        HStack(spacing: 5) {
            if effect.stamina > 0 { chip(GameStrings.format("recover.notice.stamina", effect.stamina), RoomTheme.mint) }
            if effect.mood > 0 { chip(GameStrings.format("recover.notice.mood", effect.mood), RoomTheme.friendship) }
        }
    }
    private func chip(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3).background(tint.opacity(0.14), in: Capsule())
    }
}

/// Gold variant of the primary button, for confirming an action that wastes points.
struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 13).frame(minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RoomTheme.gold)
                    .shadow(color: Color(red: 0.62, green: 0.45, blue: 0.12).opacity(isEnabled ? 1 : 0.15), radius: 0, y: configuration.isPressed ? 1 : 4)
            }
            .opacity(isEnabled ? 1 : 0.5).offset(y: configuration.isPressed ? 2 : 0)
    }
}

/// Detail and confirm step for one carried supply (bag G1–G5 and the popover's confirm).
struct MacSupplyUseCard: View {
    let store: GameStore
    let kind: PlayerSupplyKind
    let exits: MacRecoveryExits
    /// "Keep it for now": closes the confirm step where there is one (popover), otherwise nothing to undo.
    var onKeep: () -> Void = {}
    var body: some View {
        let supply = PlayerSupplyCatalog.definition(kind)
        let snapshot = store.snapshot
        let player = snapshot?.player ?? PlayerState(staminaUpdatedAt: .now)
        let carried = player.carried(kind), left = snapshot?.suppliesLeftToday ?? 0
        let applied = supply.effect.applied(to: player)
        let waste = supply.effect.total - applied.total
        VStack(alignment: .leading, spacing: 14) {
            GameIcon(asset: supply.assetName, symbol: supply.symbol, size: 96, tint: RoomTheme.gold)
                .frame(maxWidth: .infinity).frame(height: 128)
                .background(RoomTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            HStack { Text(GameStrings.text(supply.nameKey)).font(.system(size: 22, weight: .heavy, design: .rounded)); Spacer(); MacEffectChips(effect: supply.effect) }
            Text(GameStrings.text(supply.detailKey)).font(.system(size: 13, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(GameStrings.format("recover.carried", carried, PlayerSupplyCatalog.maxCarried)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text(GameStrings.text("recover.afterUse")).font(.system(size: 13, weight: .heavy))
                MacRecoveryPreview(player: player, effect: supply.effect)
            }.padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
            MacRecoveryDots(used: snapshot?.suppliesUsedToday ?? 0, showsHint: true)
            if carried == 0 {
                Button(GameStrings.text("recover.use.restock"), action: exits.shop).buttonStyle(MintButtonStyle())
            } else if left == 0 {
                hint(GameStrings.format("recover.use.limitHint", PlayerSupplyCatalog.dailyLimit))
                Button(GameStrings.text("recover.use.limit")) {}.buttonStyle(MintButtonStyle()).disabled(true)
                HStack(spacing: 8) {
                    Button(GameStrings.text("recover.exit.cafe"), action: exits.cafe).buttonStyle(SoftButtonStyle())
                    Button(GameStrings.text("recover.exit.rest"), action: exits.rest).buttonStyle(SoftButtonStyle())
                }
            } else if applied.total == 0 {
                hint(GameStrings.format("recover.use.fullHint", GameStrings.text(supply.nameKey)))
                Button(GameStrings.text("recover.use.full")) {}.buttonStyle(MintButtonStyle()).disabled(true)
            } else if waste > 0 {
                // Overflow is allowed, but only through an explicit, gold "use anyway".
                hint(GameStrings.format("recover.wasteHint", waste), warning: true)
                Button { store.usePlayerSupply(kind, allowingWaste: true) } label: {
                    Text(GameStrings.text(supply.isDrink ? "recover.use.anywayDrink" : "recover.use.anyway")).frame(maxWidth: .infinity)
                }.buttonStyle(GoldButtonStyle()).disabled(store.isBusy).accessibilityIdentifier("macUseSupplyAnyway")
                Button(GameStrings.text("recover.use.keep"), action: onKeep).buttonStyle(SoftButtonStyle())
            } else {
                Button { store.usePlayerSupply(kind) } label: {
                    HStack { Text(GameStrings.format(supply.isDrink ? "recover.use.drink" : "recover.use.eat", GameStrings.text(supply.nameKey))); MacKeyCap(value: "↩") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction).disabled(store.isBusy)
                    .accessibilityIdentifier("macUseSupply")
            }
        }
    }
    private func hint(_ text: String, warning: Bool = false) -> some View {
        Label(text, systemImage: warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
            .font(.system(size: 12, weight: .bold)).foregroundStyle(warning ? RoomTheme.coralDeep : RoomTheme.secondary)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background((warning ? RoomTheme.coral : RoomTheme.track).opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Café and rest exits, with their availability today.
struct MacRecoveryExitRows: View {
    let store: GameStore
    let exits: MacRecoveryExits
    var body: some View {
        let snapshot = store.snapshot
        let napping = snapshot?.player.activeNap != nil, used = snapshot?.napUsedToday ?? false
        VStack(spacing: 8) {
            row(symbol: "cup.and.saucer.fill", tint: RoomTheme.lilac, title: "recover.exit.cafe",
                detail: napping ? GameStrings.text("recover.exit.cafeNapping")
                    : used ? GameStrings.text("recover.exit.cafeUsed")
                    : GameStrings.format("recover.exit.cafeDetail", Int(CafeCatalog.napDuration / 60), CafeCatalog.napPrice),
                action: exits.cafe)
            row(symbol: "moon.zzz.fill", tint: RoomTheme.darkMint, title: "recover.exit.rest",
                detail: GameStrings.text("recover.exit.restDetail"), action: exits.rest)
        }
    }
    private func row(symbol: String, tint: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 30, height: 30).background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.text(title)).font(.system(size: 13, weight: .heavy))
                    Text(detail).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
            }.padding(10).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14)).contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}

/// Top-bar popover (W2): current values, carried supplies (tap to confirm) and the two exits.
struct MacRecoveryPopover: View {
    let store: GameStore
    let exits: MacRecoveryExits
    @State private var selected: PlayerSupplyKind?
    var body: some View {
        let snapshot = store.snapshot
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(GameStrings.text("recover.popover.title")).font(.system(size: 16, weight: .heavy, design: .rounded))
                Spacer(); MacRecoveryDots(used: snapshot?.suppliesUsedToday ?? 0)
            }
            if let selected {
                Button { self.selected = nil } label: { Label(GameStrings.text("recover.popover.back"), systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).font(.system(size: 12, weight: .heavy))
                MacSupplyUseCard(store: store, kind: selected, exits: exits, onKeep: { self.selected = nil })
            } else {
                HStack(spacing: 10) {
                    value(.stamina, snapshot?.player.stamina ?? 0)
                    value(.mood, snapshot?.player.mood ?? 0)
                }
                VStack(spacing: 6) {
                    ForEach(PlayerSupplyCatalog.all) { supply in supplyRow(supply, carried: snapshot?.player.carried(supply.kind) ?? 0) }
                }
                MacRecoveryExitRows(store: store, exits: exits)
            }
        }
        .padding(16).frame(width: 380).foregroundStyle(RoomTheme.ink).background(RoomTheme.paper)
        .fontDesign(.rounded)
    }
    private func value(_ attribute: MacRecoveryAttribute, _ current: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attribute.symbol).foregroundStyle(attribute.tint)
            Text(GameStrings.text(attribute.key)).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            Text("\(current)").font(.system(size: 18, weight: .heavy)).monospacedDigit()
            Text("/100").font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
        }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
    }
    private func supplyRow(_ supply: PlayerSupplyDefinition, carried: Int) -> some View {
        Button { if carried > 0 { selected = supply.kind } else { exits.shop() } } label: {
            HStack(spacing: 10) {
                GameIcon(asset: supply.assetName, symbol: supply.symbol, size: 26, tint: RoomTheme.gold)
                    .frame(width: 36, height: 36).background(RoomTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.text(supply.nameKey)).font(.system(size: 13, weight: .heavy))
                    MacEffectChips(effect: supply.effect)
                }
                Spacer(minLength: 4)
                if carried > 0 { Text("×\(carried)").font(.system(size: 14, weight: .heavy)).monospacedDigit() }
                else { Text(GameStrings.text("recover.use.restock")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.darkMint) }
            }.padding(8).opacity(carried > 0 ? 1 : 0.6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Bag › player supplies (G1–G5). Other items show the existing inventory in the same window,
/// instead of swapping the sheet (which closed the bag without opening anything on macOS).
struct MacBagView: View {
    let store: GameStore
    let exits: MacRecoveryExits
    @State private var selected = PlayerSupplyKind.riceBall
    @State private var showsOthers = false
    var body: some View {
        let snapshot = store.snapshot
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                category("recover.bag.supplies", symbol: "fork.knife", selected: !showsOthers, isNew: true) { showsOthers = false }
                category("recover.bag.others", symbol: "shippingbox.fill", selected: showsOthers, isNew: false) { showsOthers = true }
                Spacer()
                Text(GameStrings.text("recover.bag.note")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            }.frame(width: 170)
            if showsOthers {
                NavigationStack { InventoryView(store: store) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("macBagOthers")
            } else {
                supplies(snapshot)
            }
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
        .accessibilityIdentifier("macBag")
    }
    @ViewBuilder private func supplies(_ snapshot: GameSnapshot?) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text(GameStrings.text("recover.bag.suppliesTitle")).font(.system(size: 18, weight: .heavy, design: .rounded)); Spacer()
                    MacRecoveryDots(used: snapshot?.suppliesUsedToday ?? 0) }
                HStack(spacing: 10) { ForEach(PlayerSupplyCatalog.all) { card($0, snapshot: snapshot) } }
                compare
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity)
            ScrollView { MacSupplyUseCard(store: store, kind: selected, exits: exits) }.frame(width: 300)
    }
    private func category(_ key: String, symbol: String, selected: Bool, isNew: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 20)
                Text(GameStrings.text(key)).font(.system(size: 13.5, weight: .heavy))
                Spacer(minLength: 0)
                if isNew { Text(GameStrings.text("supply.player.new")).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2).background(RoomTheme.friendship, in: Capsule()) }
            }.padding(10).foregroundStyle(selected ? RoomTheme.darkMint : RoomTheme.ink)
                .background(selected ? RoomTheme.paleMint : .clear, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func card(_ supply: PlayerSupplyDefinition, snapshot: GameSnapshot?) -> some View {
        let carried = snapshot?.player.carried(supply.kind) ?? 0
        let spent = (snapshot?.suppliesLeftToday ?? 0) == 0
        return Button { selected = supply.kind } label: {
            VStack(alignment: .leading, spacing: 8) {
                GameIcon(asset: supply.assetName, symbol: supply.symbol, size: 52, tint: RoomTheme.gold)
                    .frame(maxWidth: .infinity).frame(height: 76).background(RoomTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) { Text("×\(carried)").font(.system(size: 12, weight: .heavy)).padding(6) }
                Text(GameStrings.text(supply.nameKey)).font(.system(size: 14, weight: .heavy))
                if carried == 0 {
                    Text(GameStrings.text("recover.use.restock")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                } else { MacEffectChips(effect: supply.effect) }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected == supply.kind ? RoomTheme.mint : .white, lineWidth: selected == supply.kind ? 3 : 2))
                .opacity(spent ? 0.55 : 1).contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityAddTraits(selected == supply.kind ? .isSelected : [])
    }
    private var compare: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.text("recover.compare.title")).font(.system(size: 14, weight: .heavy))
            compareRow("fork.knife", RoomTheme.gold, GameStrings.format("recover.compare.supply", PlayerSupplyCatalog.dailyLimit))
            compareRow("cup.and.saucer.fill", RoomTheme.lilac, GameStrings.format("recover.compare.nap", Int(CafeCatalog.napDuration / 60),
                                                                                   CafeCatalog.napEffect.stamina, CafeCatalog.napEffect.mood))
            compareRow("moon.zzz.fill", RoomTheme.darkMint, GameStrings.text("recover.compare.rest"))
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 18))
    }
    private func compareRow(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        Label { Text(text).font(.system(size: 12.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
    }
}
#endif
