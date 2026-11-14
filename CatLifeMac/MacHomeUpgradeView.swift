#if os(macOS)
import SwiftUI
import CatGameCore

/// Room upgrade on the desktop: now → after side by side, with a floor-plan sketch of how much
/// the room grows, then one strip with the price, the work-level gate and the confirm button.
@MainActor
struct MacHomeUpgradeView: View {
    let store: GameStore
    @State private var confirming = false

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
        .confirmationDialog(GameStrings.text("homeUpgrade.confirmTitle"), isPresented: $confirming) {
            if let next {
                Button(GameStrings.text("homeUpgrade.confirm")) { store.upgradeHome(toLevel: next.level) }
                    .accessibilityIdentifier("homeUpgradeConfirm")
            }
            Button(GameStrings.text("layout.cancel"), role: .cancel) {}
        } message: {
            if let next {
                Text(GameStrings.format("homeUpgrade.confirmMessage", next.upgradeCost, next.level,
                                        number(area(next)), store.totalFurnitureCapacity(for: next)))
            }
        }
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
                floorPlan(home, previous: previous).frame(width: 92, height: 92)
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

    /// A small floor plan: the room at its size, with the previous room dashed inside it.
    private func floorPlan(_ home: HomeLevel, previous: HomeLevel?) -> some View {
        let largest = HomeCatalog.all.map(\.worldScale).max() ?? 2
        func side(_ scale: Double) -> CGFloat { 30 + 58 * CGFloat((scale - 1) / max(0.01, largest - 1)) }
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.93, green: 0.77, blue: 0.55))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(red: 0.78, green: 0.56, blue: 0.32), lineWidth: 2))
                .frame(width: side(home.worldScale), height: side(home.worldScale))
                .overlay(alignment: .topTrailing) {
                    if home.floors.count > 1 {
                        Image(systemName: "stairs").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .padding(3).background(RoomTheme.friendshipDeep, in: RoundedRectangle(cornerRadius: 4)).offset(x: 6, y: -6)
                    }
                }
            if let previous {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(RoomTheme.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: side(previous.worldScale), height: side(previous.worldScale))
            }
            Image(systemName: "cat.fill").font(.system(size: 13)).foregroundStyle(RoomTheme.ink.opacity(0.55))
        }.accessibilityHidden(true)
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
                Button { confirming = true } label: {
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

    private func canUpgrade(_ next: HomeLevel) -> Bool {
        store.snapshot != nil && !store.isBusy && !store.isSavingLayout && !store.isResolvingLayout
            && store.placingFurnitureID == nil && gold >= next.upgradeCost && playerLevel >= next.requiredPlayerLevel
    }
    private func area(_ home: HomeLevel) -> Double { home.worldScale * home.worldScale * Double(home.floors.count) }
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: store.language.rawValue)))
    }
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
                GameIcon(asset: "town-home-cartoon", symbol: "house.fill", size: 116, tint: RoomTheme.darkMint)
                    .padding(10).background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 30))
                    .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white, lineWidth: 4))
                    .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -8))
                    .overlay(alignment: .topTrailing) {
                        Text("Lv\(celebration.level)").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5).background(RoomTheme.gold, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white, lineWidth: 3)).offset(x: 14, y: -10)
                    }
            }.frame(height: 176)
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
