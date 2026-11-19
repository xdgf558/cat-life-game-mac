#if os(macOS)
import SwiftUI
import CatGameCore

/// Room upgrade on the desktop: now → after side by side, each with the level's cutaway home drawn
/// to scale, then one strip with the price, the work-level gate and the confirm button.
@MainActor
struct MacHomeUpgradeView: View {
    let store: GameStore
    /// The level whose confirmation card is open.
    @State private var confirming: HomeLevel?
    @State private var upgradeFailed = false
    @State private var saving = false

    private var level: Int { store.snapshot?.home.roomLevel ?? 1 }
    private var current: HomeLevel? { HomeCatalog.level(level) }
    private var next: HomeLevel? { HomeCatalog.nextLevel(after: level) }
    private var gold: Int { store.snapshot?.player.gold ?? 0 }
    private var playerLevel: Int { store.snapshot?.player.level ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(GameStrings.text("homeUpgrade.preserve"), systemImage: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let current {
                HStack(alignment: .center, spacing: 10) {
                    levelCard(current, previous: nil, highlighted: next == nil)
                    if let next {
                        Image(systemName: "arrow.right").font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(RoomTheme.darkMint).frame(width: 34, height: 34)
                            .background(RoomTheme.paleMint, in: Circle()).accessibilityHidden(true)
                        levelCard(next, previous: current, highlighted: true)
                    }
                }
            }
            if let next { checkout(next) } else { maxed }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
        .sheet(item: $confirming) { target in
            if let current {
                MacHomeUpgradeConfirmSheet(store: store, current: current, target: target, saving: saving, failed: upgradeFailed,
                                           ready: canUpgrade(target), confirm: { upgrade(target) },
                                           cancel: { if !saving { confirming = nil } })
            }
        }
        // The card stays open while saving and closes only once the new level is saved.
        .onChange(of: store.isBusy) { _, busy in
            guard saving, !busy, let target = confirming else { return }
            saving = false
            if level >= target.level { confirming = nil } else { upgradeFailed = true }
        }
        .onChange(of: store.saveSceneGeneration) { _, _ in confirming = nil; saving = false }
        .accessibilityIdentifier("macHomeUpgrade")
    }

    // MARK: Level cards

    private func levelCard(_ home: HomeLevel, previous: HomeLevel?, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(GameStrings.text(previous == nil ? "mac.upgrade.now" : "mac.upgrade.after"))
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                Spacer(minLength: 4)
                Text("Lv\(home.level)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(highlighted && previous != nil ? RoomTheme.gold : RoomTheme.darkMint, in: Capsule())
                    .accessibilityIdentifier(previous == nil ? "homeUpgradeCurrentLevel" : "homeUpgradeNextLevel")
                    .accessibilityValue("\(home.level)")
            }
            HStack(alignment: .center, spacing: 14) {
                MacMiniRoom(home: home, previous: previous).frame(width: 150, height: 120)
                VStack(alignment: .leading, spacing: 7) {
                    stat("square.dashed", "mac.upgrade.area", "×" + number(area(home)),
                         delta: previous.map { "+" + number(area(home) - area($0)) })
                    stat("arrow.up.left.and.arrow.down.right", "mac.upgrade.size", "×" + number(home.worldScale),
                         delta: previous.flatMap { $0.worldScale == home.worldScale ? nil : "+" + number(home.worldScale - $0.worldScale) })
                    stat("sofa.fill", "mac.upgrade.capacity",
                         GameStrings.format("mac.upgrade.pieces", store.totalFurnitureCapacity(for: home)),
                         delta: previous.map { "+\(store.totalFurnitureCapacity(for: home) - store.totalFurnitureCapacity(for: $0))" })
                }
            }
            if home.floors.count > 1 || home.level >= RoomResidentCats.unlockLevel {
                VStack(alignment: .leading, spacing: 4) {
                    if home.floors.count > 1 {
                        perk("stairs", GameStrings.format("homeUpgrade.floorCapacity", store.floorFurnitureCapacity(for: home)),
                             isNew: (previous?.floors.count ?? 2) < 2)
                    }
                    if home.level >= RoomResidentCats.unlockLevel {
                        perk("pawprint.fill", GameStrings.text("catDirectory.sharedHomeUnlocked"),
                             isNew: (previous?.level ?? Int.max) < RoomResidentCats.unlockLevel)
                    }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted && previous != nil ? RoomTheme.paleMint.opacity(0.7) : RoomTheme.paper,
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(highlighted && previous != nil ? RoomTheme.mint.opacity(0.7) : .white,
                                                                  lineWidth: 2))
    }

    private func stat(_ symbol: String, _ key: String, _ value: String, delta: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.darkMint).frame(width: 16)
            Text(GameStrings.text(key)).font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            Text(value).font(.system(size: 14, weight: .heavy)).monospacedDigit()
            if let delta, delta != "+0" {
                Text(delta).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(.white.opacity(0.7), in: Capsule())
            }
        }.lineLimit(1)
    }

    private func perk(_ symbol: String, _ text: String, isNew: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 11.5, weight: .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if isNew {
                Text(GameStrings.text("supply.player.new")).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(RoomTheme.friendship, in: Capsule())
            }
        }.foregroundStyle(RoomTheme.darkMint)
    }

    // MARK: Checkout strip

    private func checkout(_ next: HomeLevel) -> some View {
        let enoughGold = gold >= next.upgradeCost
        let enoughLevel = playerLevel >= next.requiredPlayerLevel
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                requirement(symbol: "dollarsign.circle.fill", title: GameStrings.text("mac.upgrade.cost"),
                            value: GameStrings.format("shop.buy", next.upgradeCost),
                            note: GameStrings.format("mac.upgrade.wallet", gold), met: enoughGold)
                    .accessibilityIdentifier("homeUpgradeCost").accessibilityValue("\(next.upgradeCost)")
                requirement(symbol: "briefcase.fill", title: GameStrings.text("mac.upgrade.need"),
                            value: GameStrings.format("mac.upgrade.workLevel", next.requiredPlayerLevel),
                            note: GameStrings.format("mac.upgrade.yourLevel", playerLevel), met: enoughLevel)
                    .accessibilityIdentifier("homeUpgradeRequirement")
                Button { upgradeFailed = false; confirming = next } label: {
                    Label(GameStrings.text("homeUpgrade.action"), systemImage: "hammer.fill")
                        .font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(SupplyUseButtonStyle(available: canUpgrade(next))).disabled(!canUpgrade(next))
                .frame(width: 190).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("homeUpgradeAction")
            }
            Label(statusText(next, enoughGold: enoughGold, enoughLevel: enoughLevel),
                  systemImage: enoughGold && enoughLevel ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enoughGold && enoughLevel ? RoomTheme.darkMint : RoomTheme.coral)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 2))
    }

    private func requirement(symbol: String, title: String, value: String, note: String, met: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: met ? "checkmark.circle.fill" : symbol).font(.system(size: 20, weight: .bold))
                .foregroundStyle(met ? RoomTheme.mint : RoomTheme.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                Text(value).font(.system(size: 15, weight: .heavy)).monospacedDigit()
                Text(note).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(met ? RoomTheme.secondary : RoomTheme.coral)
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statusText(_ next: HomeLevel, enoughGold: Bool, enoughLevel: Bool) -> String {
        if !enoughLevel { return GameStrings.format("home.levelRequired", next.requiredPlayerLevel) }
        if !enoughGold { return GameStrings.format("mac.upgrade.shortGold", next.upgradeCost - gold) }
        if store.isDecorating || store.placingFurnitureID != nil { return GameStrings.text("mac.upgrade.finishLayout") }
        return GameStrings.text("mac.upgrade.ready")
    }

    private var maxed: some View {
        Label(GameStrings.text("homeUpgrade.maxed"), systemImage: "checkmark.seal.fill")
            .font(.system(size: 15, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("homeUpgradeMaxed")
    }

    // MARK: Rules

    private func upgrade(_ target: HomeLevel) {
        guard !saving, canUpgrade(target) else { return }
        upgradeFailed = false
        saving = true
        store.upgradeHome(toLevel: target.level)
        // Nothing started (a guard in the store said no): leave the card open and say so.
        if !store.isBusy { saving = false; upgradeFailed = level < target.level }
    }

    private func canUpgrade(_ next: HomeLevel) -> Bool {
        store.snapshot != nil && !store.isBusy && !store.isSavingLayout && !store.isResolvingLayout
            && store.placingFurnitureID == nil && gold >= next.upgradeCost && playerLevel >= next.requiredPlayerLevel
    }
    private func area(_ home: HomeLevel) -> Double { home.worldScale * home.worldScale * Double(home.floors.count) }
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: store.language.rawValue)))
    }
}

/// 3.01: the upgrade confirmation, in place of the grey system dialog. The home now and after side by side
/// on a sunny strip, what grows, what it costs and what is left, then 再想想 (Esc) and 确认升级 (Return).
@MainActor
private struct MacHomeUpgradeConfirmSheet: View {
    let store: GameStore
    let current: HomeLevel
    let target: HomeLevel
    let saving: Bool
    let failed: Bool
    let ready: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    @Environment(\.gameReduceMotionOverride) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown = false
    @FocusState private var focus: Control?
    private enum Control: Hashable { case cancel, confirm }

    private var still: Bool { reduceMotion || systemReduceMotion }
    private var balance: Int { store.snapshot?.player.gold ?? 0 }

    var body: some View {
        VStack(spacing: 16) {
            hero
            VStack(spacing: 6) {
                Text(GameStrings.format("mac.upgrade.cardTitle", target.level))
                    .font(.system(size: 22, weight: .heavy)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("macHomeUpgradeConfirmTitle")
                Text(GameStrings.text("mac.upgrade.cardBody"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            gains
            perks
            ledger
            if failed {
                Label(GameStrings.text("mac.upgrade.cardFailed"), systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.coralDeep)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoomTheme.paleCoral.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("macHomeUpgradeConfirmFailed")
            }
            buttons
            Label(GameStrings.text("mac.upgrade.cardSave"), systemImage: "lock.shield.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 460)
        .background(RoomTheme.paper).foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
        .interactiveDismissDisabled(saving)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macHomeUpgradeConfirm")
        .onAppear {
            focus = ready ? .confirm : .cancel
            withAnimation(still ? nil : .spring(response: 0.45, dampingFraction: 0.62)) { shown = true }
        }
    }

    /// Now → after on a sunny strip: the small home, an arrow, the bigger home with its new level.
    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [RoomTheme.paleMint, RoomTheme.cream], startPoint: .top, endPoint: .bottom))
            ForEach(Array(Self.decor.enumerated()), id: \.offset) { _, item in
                Image(systemName: item.symbol).font(.system(size: item.size, weight: .bold))
                    .foregroundStyle(item.symbol == "sparkle" ? RoomTheme.gold.opacity(0.75) : RoomTheme.darkMint.opacity(0.14))
                    .rotationEffect(.degrees(item.angle))
                    .position(x: 416 * item.x, y: 156 * item.y)
                    .opacity(shown || still ? 1 : 0)
            }
            HStack(alignment: .bottom, spacing: 8) {
                room(current, width: 118, badge: RoomTheme.darkMint).opacity(0.85)
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(RoomTheme.mint, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5)).padding(.bottom, 34)
                room(target, width: 176, badge: RoomTheme.gold)
                    .scaleEffect(shown || still ? 1 : 0.86, anchor: .bottom)
            }
            Label(GameStrings.text("mac.upgrade.cardKicker"), systemImage: "hammer.fill")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.92), in: Capsule())
                .position(x: 66, y: 22)
        }
        .frame(width: 416, height: 156)
        .accessibilityHidden(true)
    }

    private func room(_ home: HomeLevel, width: CGFloat, badge: Color) -> some View {
        MacMiniRoom(home: home).frame(width: width, height: width * 0.62)
            .overlay(alignment: .topTrailing) {
                Text(verbatim: "Lv\(home.level)").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(badge, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 2)).offset(x: 6, y: -6)
            }
    }

    /// What grows: area and furniture, before → after.
    private var gains: some View {
        HStack(spacing: 10) {
            gain("square.dashed", GameStrings.text("mac.upgrade.area"), "×" + number(area(current)), "×" + number(area(target)))
            gain("sofa.fill", GameStrings.text("mac.upgrade.capacity"),
                 "\(store.totalFurnitureCapacity(for: current))", "\(store.totalFurnitureCapacity(for: target))")
        }
    }

    private func gain(_ symbol: String, _ title: String, _ before: String, _ after: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            HStack(spacing: 6) {
                Text(before).foregroundStyle(RoomTheme.secondary)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.mint)
                Text(after).foregroundStyle(RoomTheme.darkMint)
            }.font(.system(size: 17, weight: .heavy)).monospacedDigit()
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// New this level: a second floor, or cats sharing the home.
    @ViewBuilder private var perks: some View {
        let upstairs = target.floors.count > 1 && current.floors.count < 2
        let shared = target.level >= RoomResidentCats.unlockLevel && current.level < RoomResidentCats.unlockLevel
        if upstairs || shared {
            VStack(alignment: .leading, spacing: 6) {
                if upstairs { perk("stairs", GameStrings.format("homeUpgrade.floorCapacity", store.floorFurnitureCapacity(for: target))) }
                if shared { perk("pawprint.fill", GameStrings.text("catDirectory.sharedHomeUnlocked")) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
            Text(text).font(.system(size: 12, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
            Text(GameStrings.text("supply.player.new")).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2).background(RoomTheme.friendship, in: Capsule())
        }.foregroundStyle(RoomTheme.friendshipDeep)
    }

    /// A small receipt: the cost, then the coins before and after.
    private var ledger: some View {
        VStack(spacing: 10) {
            HStack {
                Label(GameStrings.text("cat.adoptionSpend"), systemImage: "dollarsign.circle.fill").labelStyle(LedgerLabelStyle())
                Spacer()
                Text(verbatim: "−" + target.upgradeCost.formatted()).font(.system(size: 17, weight: .heavy).monospacedDigit())
                    .foregroundStyle(RoomTheme.coralDeep)
            }
            Line().stroke(RoomTheme.rewardBorder, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).frame(height: 1)
            HStack {
                Label(GameStrings.text("mac.upgrade.cardBalance"), systemImage: "wallet.bifold.fill").labelStyle(LedgerLabelStyle())
                Spacer()
                HStack(spacing: 6) {
                    Text(balance, format: .number).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(RoomTheme.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    Text(max(0, balance - target.upgradeCost), format: .number).font(.system(size: 20, weight: .heavy).monospacedDigit())
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(RoomTheme.letterPaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RoomTheme.rewardBorder.opacity(0.8), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(action: cancel) {
                HStack(spacing: 8) {
                    Text(GameStrings.text("cat.adoptionThinkAgain")).font(.system(size: 14, weight: .heavy))
                    MacKeyCap(value: "esc")
                }
            }
            .buttonStyle(SoftButtonStyle()).disabled(saving)
            .keyboardShortcut(.cancelAction).focused($focus, equals: .cancel)
            .accessibilityIdentifier("macHomeUpgradeConfirmCancel")
            Button(action: confirm) {
                HStack(spacing: 8) {
                    if saving { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "hammer.fill").font(.system(size: 13, weight: .bold)) }
                    Text(GameStrings.text(saving ? "common.saving" : "homeUpgrade.confirm")).font(.system(size: 14, weight: .heavy))
                    if !saving { MacKeyCap(value: "↩") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MintButtonStyle()).disabled(saving || !ready)
            .keyboardShortcut(.defaultAction).focused($focus, equals: .confirm)
            .accessibilityIdentifier("homeUpgradeConfirm")
        }
    }

    /// x, y as fractions of the hero, size and tilt.
    private static let decor: [(symbol: String, x: CGFloat, y: CGFloat, size: CGFloat, angle: Double)] = [
        ("sparkle", 0.08, 0.70, 14, 0), ("leaf.fill", 0.16, 0.30, 16, -24), ("sparkle", 0.92, 0.24, 16, 0),
        ("leaf.fill", 0.90, 0.74, 18, 28), ("sparkle", 0.70, 0.12, 10, 0), ("pawprint.fill", 0.30, 0.86, 12, 14)
    ]

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
    }
    private struct LedgerLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                configuration.icon.font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.gold)
                configuration.title.font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.ink)
            }
        }
    }

    private func area(_ home: HomeLevel) -> Double { home.worldScale * home.worldScale * Double(home.floors.count) }
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: store.language.rawValue)))
    }
}

/// This level's cutaway home. The painted `home-level-N` art is drawn to scale (a bigger home is a
/// wider picture, cats and furniture keep their size); levels without art fall back to a tiny
/// code-drawn room with the previous room dashed on the floor.
struct MacMiniRoom: View {
    let home: HomeLevel
    var previous: HomeLevel? = nil

    static func artwork(level: Int) -> NSImage? { NSImage(named: "home-level-\(level)") }

    var body: some View {
        if let art = Self.artwork(level: home.level) {
            Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            drawn
        }
    }

    private static let floorWood = Color(red: 0.95, green: 0.72, blue: 0.43)
    private static let plank = Color(red: 0.80, green: 0.52, blue: 0.27)
    private static let wall = Color(red: 0.99, green: 0.91, blue: 0.80)
    private static let sideWall = Color(red: 0.96, green: 0.84, blue: 0.69)
    private static let trim = Color(red: 0.91, green: 0.56, blue: 0.24)
    private static let glass = Color(red: 0.62, green: 0.82, blue: 0.93)
    private static let bed = Color(red: 0.55, green: 0.70, blue: 0.42)

    private var drawn: some View {
        Canvas { context, size in
            let largest = HomeCatalog.all.map(\.worldScale).max() ?? 2
            func fit(_ scale: Double) -> CGFloat { 0.58 + 0.42 * CGFloat((scale - 1) / max(0.01, largest - 1)) }
            let room = Self.geometry(size: size, fit: fit(home.worldScale))

            // Side walls, then the back wall with its trim and window.
            for side in [room.leftWall, room.rightWall] {
                context.fill(side, with: .color(Self.sideWall))
                context.stroke(side, with: .color(Self.trim.opacity(0.55)), lineWidth: 1)
            }
            context.fill(Path(room.backWall), with: .color(Self.wall))
            context.stroke(Path(room.backWall), with: .color(Self.trim.opacity(0.55)), lineWidth: 1)
            context.fill(Path(CGRect(x: room.backWall.minX, y: room.backWall.minY, width: room.backWall.width, height: 2.5)),
                         with: .color(Self.trim))
            let pane = CGRect(x: room.backWall.midX - room.backWall.width * 0.12, y: room.backWall.minY + room.backWall.height * 0.22,
                              width: room.backWall.width * 0.24, height: room.backWall.height * 0.56)
            context.fill(Path(roundedRect: pane, cornerSize: CGSize(width: pane.width / 2, height: pane.width / 2)), with: .color(Self.glass))
            context.stroke(Path(roundedRect: pane, cornerSize: CGSize(width: pane.width / 2, height: pane.width / 2)),
                           with: .color(Self.trim), lineWidth: 1.6)
            context.stroke(Path { $0.move(to: CGPoint(x: pane.midX, y: pane.minY + 2)); $0.addLine(to: CGPoint(x: pane.midX, y: pane.maxY)) },
                           with: .color(Self.trim), lineWidth: 1)

            // Wooden floor with planks running towards the viewer.
            context.fill(room.floor, with: .color(Self.floorWood))
            for index in 1..<6 {
                let t = CGFloat(index) / 6
                var line = Path()
                line.move(to: room.backLeft.lerp(room.backRight, t))
                line.addLine(to: room.frontLeft.lerp(room.frontRight, t))
                context.stroke(line, with: .color(Self.plank.opacity(0.35)), lineWidth: 0.8)
            }
            context.stroke(room.floor, with: .color(Self.plank.opacity(0.8)), lineWidth: 1.2)

            if let previous {
                let old = Self.geometry(size: size, fit: fit(previous.worldScale))
                context.stroke(old.floor, with: .color(Color.black.opacity(0.42)),
                               style: StrokeStyle(lineWidth: 1.3, dash: [3.5, 2.5]))
            }
            if home.floors.count > 1 {
                for step in 0..<4 {
                    let w = room.backWall.width * 0.16, h = room.backWall.height * 0.2
                    let rect = CGRect(x: room.backRight.x - w - 2, y: room.backRight.y - h * CGFloat(step + 1),
                                      width: w, height: h * CGFloat(step + 1))
                    context.fill(Path(rect.insetBy(dx: CGFloat(step) * w * 0.1, dy: 0)), with: .color(Self.plank.opacity(0.75 - Double(step) * 0.1)))
                }
            }

            // A cat bed and the cat, sized to the room so a bigger home really looks roomier.
            let center = room.backLeft.lerp(room.frontRight, 0.55).lerp(room.frontLeft.lerp(room.backRight, 0.55), 0.5)
            // Furniture keeps its real size, so it takes up less of a larger room.
            let bedWidth = (room.frontRight.x - room.frontLeft.x) * 0.26 / CGFloat(home.worldScale)
            context.fill(Path(ellipseIn: CGRect(x: center.x - bedWidth / 2, y: center.y - bedWidth * 0.2,
                                                width: bedWidth, height: bedWidth * 0.42)), with: .color(Self.bed))
            var cat = context.resolve(Image(systemName: "cat.fill"))
            cat.shading = .color(Color(red: 0.88, green: 0.52, blue: 0.22))
            context.draw(cat, in: CGRect(x: center.x - bedWidth * 0.3, y: center.y - bedWidth * 0.62,
                                         width: bedWidth * 0.6, height: bedWidth * 0.6))
        }
        .accessibilityHidden(true)
    }

    private struct Geometry {
        let frontLeft: CGPoint, frontRight: CGPoint, backLeft: CGPoint, backRight: CGPoint
        let backWall: CGRect
        var floor: Path { Path { $0.addLines([frontLeft, frontRight, backRight, backLeft]); $0.closeSubpath() } }
        var leftWall: Path {
            Path { $0.addLines([frontLeft, backLeft, CGPoint(x: backLeft.x, y: backWall.minY),
                                CGPoint(x: frontLeft.x, y: backWall.minY - (frontLeft.y - backLeft.y) * 0.35)]); $0.closeSubpath() }
        }
        var rightWall: Path {
            Path { $0.addLines([frontRight, backRight, CGPoint(x: backRight.x, y: backWall.minY),
                                CGPoint(x: frontRight.x, y: backWall.minY - (frontRight.y - backRight.y) * 0.35)]); $0.closeSubpath() }
        }
    }

    /// Front view like the game camera: the floor narrows towards the back wall.
    private static func geometry(size: CGSize, fit: CGFloat) -> Geometry {
        let width = size.width * 0.9 * fit
        let depth = width * 0.36, backWidth = width * 0.68, wallHeight = width * 0.34
        let bottom = size.height - 3
        let centerX = size.width / 2
        let frontLeft = CGPoint(x: centerX - width / 2, y: bottom), frontRight = CGPoint(x: centerX + width / 2, y: bottom)
        let backLeft = CGPoint(x: centerX - backWidth / 2, y: bottom - depth)
        let backRight = CGPoint(x: centerX + backWidth / 2, y: bottom - depth)
        return Geometry(frontLeft: frontLeft, frontRight: frontRight, backLeft: backLeft, backRight: backRight,
                        backWall: CGRect(x: backLeft.x, y: backLeft.y - wallHeight, width: backWidth, height: wallHeight))
    }
}

private extension CGPoint {
    func lerp(_ other: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t) }
}

/// Shown over the room after an upgrade: confetti, sun rays behind the house, Lv old → new,
/// and what the new room offers. Return or Esc closes it.
@MainActor
struct MacHomeUpgradeCelebration: View {
    let store: GameStore
    let celebration: HomeUpgradeCelebration
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.gameReduceMotionOverride) private var motionOverride
    @State private var appeared = false
    @State private var burst = false

    private var reduceMotion: Bool { systemReduceMotion || motionOverride }
    private var home: HomeLevel? { HomeCatalog.level(celebration.level) }
    private var previous: HomeLevel? { HomeCatalog.level(celebration.level - 1) }

    var body: some View {
        ZStack {
            RoomTheme.ink.opacity(appeared ? 0.42 : 0).ignoresSafeArea()
                .onTapGesture(perform: dismiss).accessibilityHidden(true)
            if !reduceMotion { confetti }
            card.scaleEffect(appeared ? 1 : 0.82).opacity(appeared ? 1 : 0)
        }
        .onAppear {
            store.playSceneSound(.levelUp)
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.35)) { appeared = true }
            if !reduceMotion { withAnimation(.easeOut(duration: 2.2)) { burst = true } }
        }
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("homeUpgradeCelebration")
    }

    private var card: some View {
        VStack(spacing: 14) {
            ZStack {
                rays
                celebrationArt
                    .padding(10).background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 30))
                    .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white, lineWidth: 4))
                    .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -8))
                    .overlay(alignment: .topTrailing) {
                        Text("Lv\(celebration.level)").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5).background(RoomTheme.gold, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white, lineWidth: 3)).offset(x: 14, y: -10)
                    }
            }.frame(height: 190)
            Text(GameStrings.text("homeUpgrade.successTitle")).font(.system(size: 26, weight: .heavy, design: .rounded))
            Text(GameStrings.text("homeUpgrade.successBody")).font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let home, let previous {
                HStack(spacing: 10) {
                    gain("square.dashed", GameStrings.text("mac.upgrade.area"),
                         "×" + number(area(previous)), "×" + number(area(home)))
                    gain("sofa.fill", GameStrings.text("mac.upgrade.capacity"),
                         "\(store.totalFurnitureCapacity(for: previous))", "\(store.totalFurnitureCapacity(for: home))")
                }
            }
            if celebration.level == 6 {
                Label(GameStrings.text("homeUpgrade.upperUnlocked"), systemImage: "stairs")
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(RoomTheme.friendshipDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 16))
            }
            Button(action: dismiss) {
                Label(GameStrings.text("homeUpgrade.enjoy"), systemImage: "house.fill")
                    .font(.system(size: 15, weight: .heavy)).frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(SupplyUseButtonStyle(available: true)).keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("homeUpgradeCelebrationDone")
        }
        .padding(26).frame(width: 420)
        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white, lineWidth: 4))
        .compositingGroup().shadow(color: RoomTheme.ink.opacity(0.25), radius: 30, y: 12)
        .foregroundStyle(RoomTheme.ink)
    }

    @ViewBuilder private var celebrationArt: some View {
        if let art = MacMiniRoom.artwork(level: celebration.level) {
            Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 190, height: 152).accessibilityHidden(true)
        } else {
            GameIcon(asset: "town-home-cartoon", symbol: "house.fill", size: 116, tint: RoomTheme.darkMint)
        }
    }

    private var rays: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                Capsule().fill(RoomTheme.gold.opacity(index.isMultiple(of: 2) ? 0.32 : 0.18))
                    .frame(width: 14, height: 78).offset(y: -66).rotationEffect(.degrees(Double(index) * 20))
            }
        }
        .frame(width: 210, height: 210)
        .rotationEffect(.degrees(!reduceMotion && appeared ? 40 : 0))
        .animation(reduceMotion ? nil : .linear(duration: 14).repeatForever(autoreverses: false), value: appeared)
        .accessibilityHidden(true)
    }

    /// Two bursts from the left and right edges that arc up and fall across the window.
    private var confetti: some View {
        GeometryReader { geometry in
            let colors = [RoomTheme.mint, RoomTheme.gold, RoomTheme.coral, RoomTheme.lilac, RoomTheme.sky, .white]
            ForEach(0..<56, id: \.self) { index in
                let fromLeft = index.isMultiple(of: 2)
                let spread = CGFloat((index * 37) % 100) / 100
                let start = CGPoint(x: fromLeft ? -10 : geometry.size.width + 10, y: geometry.size.height * 0.62)
                let end = CGPoint(x: geometry.size.width * (fromLeft ? 0.08 + spread * 0.6 : 0.92 - spread * 0.6),
                                  y: geometry.size.height * (0.55 + CGFloat((index * 13) % 40) / 100))
                RoundedRectangle(cornerRadius: index.isMultiple(of: 3) ? 4 : 1.5)
                    .fill(colors[index % colors.count])
                    .frame(width: index.isMultiple(of: 3) ? 8 : 6, height: index.isMultiple(of: 3) ? 8 : 13)
                    .rotationEffect(.degrees(burst ? Double(index * 83) : 0))
                    .position(burst ? end : start)
                    .offset(y: burst ? 0 : -geometry.size.height * (0.25 + spread * 0.3))
                    .opacity(burst ? 0 : 1)
                    .animation(.timingCurve(0.2, 0.7, 0.4, 1, duration: 2.1).delay(Double(index % 9) * 0.04), value: burst)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private func gain(_ symbol: String, _ title: String, _ before: String, _ after: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            HStack(spacing: 6) {
                Text(before).foregroundStyle(RoomTheme.secondary)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.mint)
                Text(after).foregroundStyle(RoomTheme.darkMint)
            }.font(.system(size: 17, weight: .heavy)).monospacedDigit()
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
    }

    private func area(_ home: HomeLevel) -> Double { home.worldScale * home.worldScale * Double(home.floors.count) }
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: store.language.rawValue)))
    }
}
#endif
