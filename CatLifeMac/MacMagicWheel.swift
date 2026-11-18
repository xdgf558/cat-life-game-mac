#if os(macOS)
import SwiftUI
import CatGameCore

/// M2: the magic wheel with its odds, stardust and today's turns. The odds table is Core's own
/// `CraftCatalog.wheel`; the disc's eight equal wedges are only decoration for the landing.
@MainActor
struct MacMagicWheelPage: View {
    let store: GameStore
    let angle: Double
    let spinning: Bool
    let spin: () -> Void
    let exchange: () -> Void
    let back: () -> Void

    /// The disc's wedges, clockwise from the top.
    static let wedges: [WheelPrize] = [.fabric, .thread, .stardust, .wood, .blueprint, .dye, .fabric, .wood]
    /// Where (degrees clockwise from the top) the pointer should stop for a prize. A prize on two
    /// wedges picks one from the spin's ID, so the same result always lands the same way.
    static func centerAngle(for prize: WheelPrize, seed: String) -> Double {
        let matches = wedges.indices.filter { wedges[$0] == prize }
        guard !matches.isEmpty else { return 0 }
        let pick = matches[seed.utf8.reduce(0) { ($0 + Int($1)) % 97 } % matches.count]
        return Double(pick) * 360 / Double(wedges.count)
    }

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }
    private var today: String? { store.snapshot?.tasks.dailyDayKey }
    private var gold: Int { store.snapshot?.player.gold ?? 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            stage.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                VStack(spacing: 14) { odds; stardust; todayCard }
            }.scrollIndicators(.never).frame(width: 320)
        }
    }

    private var stage: some View {
        ZStack {
            MacCottageBackdrop()
            // Dim the room a little so the wheel is the bright thing on stage.
            LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.30).opacity(0.45), Color(red: 0.16, green: 0.12, blue: 0.30).opacity(0.2)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(spacing: 12) {
                HStack {
                    Button(action: back) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text(GameStrings.text("craft.backToHub"))
                            MacKeyCap(value: "Esc")
                        }.font(.system(size: 13, weight: .heavy)).padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoomTheme.paper, in: Capsule())
                    }.buttonStyle(.plain).disabled(spinning).accessibilityIdentifier("magicWheelBack")
                    Spacer()
                }
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)
                    MacWheelDisc(angle: angle).frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                spinButton
            }.padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white, lineWidth: 3))
    }

    private var spinButton: some View {
        let free = craft.wheel.freeLeft(today: today), paid = craft.wheel.paidLeft(today: today)
        let price = CraftCatalog.wheelSpinPrice
        let title: String
        let note: String
        if spinning {
            title = GameStrings.text("craft.wheel.skip")
            note = GameStrings.text("craft.wheel.skipNote")
        } else if free > 0 {
            title = GameStrings.text("craft.wheel.free")
            note = GameStrings.format("craft.wheel.freeNote", price, CraftCatalog.wheelPaidSpins)
        } else if paid > 0 {
            title = GameStrings.format("craft.wheel.paid", price)
            note = gold >= price ? GameStrings.format("craft.wheel.paidNote", gold, gold - price, paid)
                : GameStrings.format("craft.wheel.poor", price - gold)
        } else {
            title = GameStrings.text("craft.wheel.tomorrow")
            note = GameStrings.text("craft.wheel.tomorrowNote")
        }
        let enabled = spinning || free > 0 || (paid > 0 && gold >= price)
        return VStack(spacing: 7) {
            Button(action: spin) {
                HStack(spacing: 8) {
                    Image(systemName: spinning ? "forward.fill" : free > 0 ? "gift.fill" : "dollarsign.circle.fill")
                    Text(title)
                    MacKeyCap(value: GameStrings.text("craft.key.space"))
                }.font(.system(size: 16, weight: .heavy)).padding(.horizontal, 10)
            }
            .buttonStyle(MintButtonStyle()).fixedSize().disabled(!enabled || store.isBusy)
            .accessibilityIdentifier("magicSpinButton")
            Text(note).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 5).background(RoomTheme.paper.opacity(0.92), in: Capsule())
                .accessibilityIdentifier("magicSpinNote")
        }
    }

    private var odds: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(GameStrings.text("craft.wheel.odds"), systemImage: "list.bullet").font(.system(size: 15, weight: .heavy))
                Spacer()
                Text(GameStrings.text("craft.wheel.always")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            }
            ForEach(CraftCatalog.wheel) { slice in
                HStack(spacing: 10) {
                    MacPrizeArt(prize: slice.prize, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.prizeName(slice.prize, count: slice.count)).font(.system(size: 13, weight: .heavy))
                        if slice.prize == .blueprint {
                            Text(GameStrings.text("craft.wheel.blueprintNote")).font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Text(verbatim: "\(slice.percent)%").font(.system(size: 14, weight: .black)).monospacedDigit().foregroundStyle(RoomTheme.lilac)
                }.accessibilityElement(children: .combine)
            }
        }.macContentCard69(padding: 16).accessibilityIdentifier("magicWheelOdds")
    }

    static func prizeName(_ prize: WheelPrize, count: Int) -> String {
        if let material = prize.material { return GameStrings.text(material.titleKey) + " ×\(count)" }
        return GameStrings.text("craft.wheel.blueprint")
    }

    private var stardust: some View {
        let have = craft.count(of: .stardust)
        let cheapest = CraftTier.basic.stardustPrice
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(GameStrings.text(CraftMaterial.stardust.titleKey), systemImage: "sparkles").font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(RoomTheme.lilac)
                Spacer()
                Text("\(have)").font(.system(size: 17, weight: .black)).monospacedDigit().foregroundStyle(RoomTheme.lilac)
            }
            HStack(spacing: 6) {
                ForEach(CraftTier.allCases, id: \.self) { tier in
                    VStack(spacing: 2) {
                        Text(GameStrings.text(tier.titleKey)).font(.system(size: 10.5, weight: .heavy))
                        Text("\(tier.stardustPrice)").font(.system(size: 14, weight: .black)).monospacedDigit()
                    }
                    .foregroundStyle(have >= tier.stardustPrice ? RoomTheme.lilac : RoomTheme.secondary)
                    .padding(.vertical, 6).frame(maxWidth: .infinity)
                    .background(RoomTheme.lilac.opacity(have >= tier.stardustPrice ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text(GameStrings.text("craft.stardust.note")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: exchange) {
                Label(GameStrings.text("craft.stardust.exchange"), systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
            }.buttonStyle(SoftButtonStyle()).disabled(spinning || have < cheapest).accessibilityIdentifier("magicOpenExchange")
        }.macContentCard69(padding: 16)
    }

    private var todayCard: some View {
        let freeUsed = CraftCatalog.wheelFreeSpins - craft.wheel.freeLeft(today: today)
        let paidUsed = CraftCatalog.wheelPaidSpins - craft.wheel.paidLeft(today: today)
        return VStack(alignment: .leading, spacing: 10) {
            Label(GameStrings.text("craft.wheel.today"), systemImage: "calendar").font(.system(size: 15, weight: .heavy))
            HStack(spacing: 6) {
                ForEach(0..<(CraftCatalog.wheelFreeSpins + CraftCatalog.wheelPaidSpins), id: \.self) { index in
                    let isFree = index < CraftCatalog.wheelFreeSpins
                    let used = isFree ? index < freeUsed : index - CraftCatalog.wheelFreeSpins < paidUsed
                    Text(isFree ? GameStrings.text("craft.wheel.slotFree") : GameStrings.format("craft.wheel.slotPaid", CraftCatalog.wheelSpinPrice))
                        .font(.system(size: 12, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                        .strikethrough(used)
                        .foregroundStyle(used ? RoomTheme.secondary.opacity(0.6) : isFree ? RoomTheme.darkMint : ExchangePalette.goldInk)
                        .padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background((isFree ? RoomTheme.paleMint : RoomTheme.gold.opacity(0.14)).opacity(used ? 0.4 : 1),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text(GameStrings.text("craft.wheel.rule")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.macContentCard69(padding: 16)
    }
}

/// The disc itself, turned by `angle` degrees clockwise; the pointer stays at the top. Each wedge shows
/// its prize as a picture (`material-<prize>`), no words; the odds table beside it names them.
struct MacWheelDisc: View {
    let angle: Double
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let outer = side / 2 - 6
            let rim = outer * 0.11
            let radius = outer - rim
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let count = MacMagicWheelPage.wedges.count
            let step = 360 / Double(count)
            ZStack {
                // Soft shadow under the wheel.
                Ellipse().fill(Color.black.opacity(0.18)).frame(width: outer * 1.7, height: outer * 0.22).blur(radius: 10)
                    .position(x: center.x, y: center.y + outer * 0.98)
                // Gold rim.
                Circle()
                    .fill(AngularGradient(colors: [Self.goldLight, Self.goldDeep, Self.goldLight, Self.goldDeep, Self.goldLight],
                                          center: .center))
                    .frame(width: outer * 2, height: outer * 2)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2))
                    .shadow(color: Self.goldDeep.opacity(0.5), radius: 0, y: 5)
                    .position(center)
                // Little lights around the rim.
                ForEach(0..<16, id: \.self) { index in
                    let theta = (Double(index) * 22.5 - 90) * .pi / 180
                    Circle().fill(index.isMultiple(of: 2) ? Color.white : Color(red: 1, green: 0.88, blue: 0.55))
                        .frame(width: rim * 0.42, height: rim * 0.42)
                        .shadow(color: Color(red: 1, green: 0.85, blue: 0.4).opacity(0.9), radius: rim * 0.3)
                        .position(x: center.x + (outer - rim / 2) * cos(theta), y: center.y + (outer - rim / 2) * sin(theta))
                }
                // The turning part: wedges and their pictures.
                ZStack {
                    ForEach(0..<count, id: \.self) { index in
                        let prize = MacMagicWheelPage.wedges[index]
                        let middle = Double(index) * step
                        WheelWedge(center: center, radius: radius, start: middle - step / 2, end: middle + step / 2)
                            .fill(RadialGradient(colors: [Color.white, Self.fill(prize)], center: UnitPoint(x: center.x / max(1, geometry.size.width),
                                                                                                         y: center.y / max(1, geometry.size.height)),
                                                 startRadius: radius * 0.15, endRadius: radius))
                        MacPrizeArt(prize: prize, size: radius * 0.42)
                            .rotationEffect(.degrees(middle))
                            .position(x: center.x + radius * 0.63 * cos((middle - 90) * .pi / 180),
                                      y: center.y + radius * 0.63 * sin((middle - 90) * .pi / 180))
                    }
                    ForEach(0..<count, id: \.self) { index in
                        let edge = (Double(index) * step - step / 2 - 90) * .pi / 180
                        Path { path in
                            path.move(to: center)
                            path.addLine(to: CGPoint(x: center.x + radius * cos(edge), y: center.y + radius * sin(edge)))
                        }.stroke(Color.white, style: StrokeStyle(lineWidth: max(2, radius * 0.018), lineCap: .round))
                    }
                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: max(2, radius * 0.02))
                        .frame(width: radius * 2, height: radius * 2).position(center)
                }
                .rotationEffect(.degrees(angle))
                // Hub.
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.72, green: 0.56, blue: 0.86), RoomTheme.lilac], center: UnitPoint(x: 0.35, y: 0.3),
                                         startRadius: 2, endRadius: radius * 0.22))
                    .frame(width: radius * 0.36, height: radius * 0.36)
                    .overlay(Image(systemName: "star.fill").font(.system(size: radius * 0.15, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), RoomTheme.gold], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().strokeBorder(Self.goldLight, lineWidth: max(3, radius * 0.035)))
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 3)
                    .position(center)
                // Pointer at the top.
                WheelPointer()
                    .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.52, blue: 0.42), RoomTheme.coralDeep], startPoint: .top, endPoint: .bottom))
                    .overlay(WheelPointer().stroke(Color.white, lineWidth: 3))
                    .frame(width: rim * 2.3, height: rim * 3)
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 3)
                    .overlay(alignment: .top) {
                        Circle().fill(Self.goldLight).frame(width: rim * 0.9, height: rim * 0.9)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2)).offset(y: rim * 0.35)
                    }
                    .position(x: center.x, y: center.y - outer + rim * 0.9)
            }
        }
        .accessibilityHidden(true)
    }
    private static let goldLight = Color(red: 0.98, green: 0.82, blue: 0.45)
    private static let goldDeep = Color(red: 0.80, green: 0.55, blue: 0.22)

    static func fill(_ prize: WheelPrize) -> Color {
        switch prize {
        case .fabric: Color(red: 0.98, green: 0.76, blue: 0.70)
        case .thread: Color(red: 0.99, green: 0.80, blue: 0.86)
        case .wood: Color(red: 0.93, green: 0.80, blue: 0.62)
        case .dye: Color(red: 0.72, green: 0.85, blue: 0.97)
        case .stardust: Color(red: 0.82, green: 0.74, blue: 0.96)
        case .blueprint: Color(red: 1.0, green: 0.86, blue: 0.48)
        }
    }
}

/// A teardrop pointing down.
private struct WheelPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + w / 2),
                      control1: CGPoint(x: rect.midX - w * 0.15, y: rect.maxY - h * 0.25),
                      control2: CGPoint(x: rect.minX, y: rect.minY + w * 0.95))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + w / 2), radius: w / 2,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + w * 0.95),
                      control2: CGPoint(x: rect.midX + w * 0.15, y: rect.maxY - h * 0.25))
        path.closeSubpath()
        return path
    }
}

/// A prize or material as a little picture: `material-<name>` once drawn, a coloured badge until then.
struct MacPrizeArt: View {
    let prize: WheelPrize
    var size: CGFloat = 40
    static func asset(_ prize: WheelPrize) -> String { "material-\(prize.rawValue)" }
    static func symbol(_ prize: WheelPrize) -> String { prize.material?.symbol ?? "scroll.fill" }
    static func tint(_ prize: WheelPrize) -> Color { prize.material.map { MacCraftStyle.tint($0) } ?? Color(red: 0.70, green: 0.45, blue: 0.10) }
    var body: some View {
        if UIImage(named: Self.asset(prize)) != nil {
            Image(Self.asset(prize)).resizable().scaledToFit().frame(width: size, height: size)
                .shadow(color: .black.opacity(0.15), radius: 0, y: 2)
        } else {
            Image(systemName: Self.symbol(prize)).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
                .frame(width: size * 0.82, height: size * 0.82)
                .background(Self.tint(prize), in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: max(2, size * 0.06)))
                .shadow(color: .black.opacity(0.15), radius: 0, y: 2)
                .frame(width: size, height: size)
        }
    }
}

/// A material as a picture (same art as the wheel).
struct MacMaterialArt: View {
    let material: CraftMaterial
    var size: CGFloat = 32
    var body: some View {
        if let prize = WheelPrize(rawValue: material.rawValue), UIImage(named: MacPrizeArt.asset(prize)) != nil {
            Image(MacPrizeArt.asset(prize)).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: material.symbol).font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(MacCraftStyle.tint(material))
                .frame(width: size, height: size).background(MacCraftStyle.tint(material).opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28))
        }
    }
}

/// A pie slice; angles are degrees clockwise from the top.
private struct WheelWedge: Shape {
    let center: CGPoint
    let radius: CGFloat
    let start: Double
    let end: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// M3 / M4: what the wheel gave, with the before and after numbers.
@MainActor
struct MacWheelResultCard: View {
    let store: GameStore
    let back: () -> Void
    let again: () -> Void
    let goCraft: (String) -> Void
    let pickBlueprint: () -> Void

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }

    var body: some View {
        if let result = craft.lastSpin {
            card(result)
        }
    }

    private func card(_ result: WheelSpinResult) -> some View {
        let today = store.snapshot?.tasks.dailyDayKey
        let gold = store.snapshot?.player.gold ?? 0
        let paidLeft = craft.wheel.paidLeft(today: today), freeLeft = craft.wheel.freeLeft(today: today)
        let price = CraftCatalog.wheelSpinPrice
        let blueprint = result.blueprintID.flatMap(CraftCatalog.blueprint(id:))
        let goal = craft.goalBlueprintID.flatMap(CraftCatalog.blueprint(id:))
        let helpsGoal = goal.map { goal in result.prize.material.map { goal.cost(of: $0) > 0 } ?? (goal.id == blueprint?.id) } ?? false
        return VStack(spacing: 14) {
            Text(GameStrings.text("craft.result.kicker")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.lilac).tracking(1.2)
            Group {
                if let blueprint {
                    MacBlueprintIcon(definition: blueprint, size: 86)
                } else {
                    MacPrizeArt(prize: result.prize, size: 96)
                }
            }
            if let blueprint {
                Text(GameStrings.format(result.isNewBlueprint ? "craft.result.newBlueprint" : "craft.result.moreUses",
                                        GameStrings.text(blueprint.nameKey)))
                    .font(.system(size: 21, weight: .heavy)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                MacBlueprintTags(definition: blueprint)
                beforeAfter(GameStrings.text("craft.result.uses"), result.usesBefore, result.usesAfter)
                if result.overflowStardust > 0 {
                    beforeAfter(GameStrings.format("craft.result.overflow", result.overflowStardust),
                                craft.count(of: .stardust) - result.overflowStardust, craft.count(of: .stardust))
                }
            } else if let material = result.prize.material {
                Text(GameStrings.format("craft.result.got", GameStrings.text(material.titleKey), result.count))
                    .font(.system(size: 21, weight: .heavy)).accessibilityAddTraits(.isHeader)
                beforeAfter(GameStrings.text("craft.result.bag"), result.materialBefore, result.materialAfter)
            }
            if result.paidGold > 0 {
                beforeAfter(GameStrings.text("player.gold"), result.goldBefore, result.goldAfter)
            }
            if helpsGoal, let goal {
                let ready = craft.readiness(for: goal) == .ready
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill").foregroundStyle(RoomTheme.coralDeep)
                    Text(ready ? GameStrings.format("craft.result.goalReady", GameStrings.text(goal.nameKey))
                         : GameStrings.format("craft.result.goalProgress", GameStrings.text(goal.nameKey),
                                              goal.costs.filter { craft.count(of: $0.material) >= $0.count }.count, goal.costs.count))
                        .font(.system(size: 12.5, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if ready {
                        Button(GameStrings.text("craft.result.goCraft") + " ›") { goCraft(goal.id) }.buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    }
                }.padding(12).background(RoomTheme.paleCoral.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(spacing: 10) {
                Button(action: back) {
                    HStack(spacing: 8) { Text(GameStrings.text("craft.backToHub")); MacKeyCap(value: "esc") }
                }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction).accessibilityIdentifier("magicResultBack")
                if craft.count(of: .stardust) >= CraftTier.basic.stardustPrice, result.overflowStardust > 0 {
                    Button(action: pickBlueprint) {
                        Label(GameStrings.text("craft.result.pick"), systemImage: "sparkles").frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction)
                } else if freeLeft > 0 || (paidLeft > 0 && gold >= price) {
                    Button(action: again) {
                        HStack(spacing: 8) {
                            Text(freeLeft > 0 ? GameStrings.text("craft.wheel.free") : GameStrings.format("craft.wheel.paid", price))
                            MacKeyCap(value: "↩")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("magicResultAgain")
                }
            }
            if freeLeft == 0, paidLeft > 0 {
                Text(gold >= price ? GameStrings.format("craft.wheel.paidNote", gold, gold - price, paidLeft)
                     : GameStrings.format("craft.wheel.poor", price - gold))
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            }
        }
        .padding(22).frame(width: 420).modifier(MacMagicCardChrome())
        .accessibilityIdentifier("magicSpinResult").accessibilityValue(Text(verbatim: "\(result.prize.rawValue):\(result.count)"))
    }

    private func beforeAfter(_ title: String, _ before: Int, _ after: Int) -> some View {
        MacBeforeAfterRow(title: title, before: before, after: after)
    }
}

/// "金币 2,480 → 2,380" — one line of a result card.
struct MacBeforeAfterRow: View {
    let title: String
    let before: Int
    let after: Int
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .heavy))
            Spacer()
            Text(before, format: .number).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(RoomTheme.secondary)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
            Text(after, format: .number).font(.system(size: 17, weight: .black).monospacedDigit())
                .foregroundStyle(after > before ? RoomTheme.darkMint : after < before ? RoomTheme.coralDeep : RoomTheme.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// M5: pick one blueprint for stardust. Prices follow the blueprint's tier.
@MainActor
struct MacStardustExchange: View {
    let store: GameStore
    @Binding var pick: String?
    let working: Bool
    let confirm: () -> Void
    let cancel: () -> Void

    /// Wearable blueprints that still have room for more uses.
    static func options(_ craft: CraftState) -> [BlueprintDefinition] {
        CraftCatalog.craftableBlueprints.filter { craft.usesLeft($0.id) < $0.tier.maximumUses }
    }
    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }

    var body: some View {
        let list = Self.options(craft)
        let have = craft.count(of: .stardust)
        let chosen = pick.flatMap(CraftCatalog.blueprint(id:))
        let price = chosen?.tier.stardustPrice ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(GameStrings.text("craft.exchange.title"), systemImage: "sparkles").font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(RoomTheme.lilac).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(GameStrings.format("craft.exchange.have", have)).font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.lilac)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(list) { definition in row(definition, have: have) }
                }.padding(.vertical, 2)
            }.frame(maxHeight: 360)
            if let chosen {
                MacBeforeAfterRow(title: GameStrings.text(CraftMaterial.stardust.titleKey), before: have, after: max(0, have - price))
                MacBeforeAfterRow(title: GameStrings.format("craft.exchange.uses", GameStrings.text(chosen.nameKey)),
                                  before: craft.usesLeft(chosen.id),
                                  after: min(chosen.tier.maximumUses, craft.usesLeft(chosen.id) + chosen.tier.usesPerCopy))
            }
            HStack(spacing: 10) {
                Button(action: cancel) {
                    HStack(spacing: 8) { Text(GameStrings.text("common.cancel")); MacKeyCap(value: "esc") }
                }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction).disabled(working)
                Button(action: confirm) {
                    HStack(spacing: 8) {
                        if working { ProgressView().controlSize(.small).tint(.white) }
                        Text(chosen == nil ? GameStrings.text("craft.exchange.pick")
                             : have >= price ? GameStrings.format("craft.exchange.confirm", price)
                             : GameStrings.format("craft.exchange.short", price - have))
                        if chosen != nil, have >= price { MacKeyCap(value: "↩") }
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(working || chosen == nil || have < price || store.isBusy).accessibilityIdentifier("magicExchangeConfirm")
            }
        }
        .padding(22).frame(width: 520).modifier(MacMagicCardChrome())
        .accessibilityIdentifier("magicExchange")
    }

    private func row(_ definition: BlueprintDefinition, have: Int) -> some View {
        let chosen = pick == definition.id
        let affordable = have >= definition.tier.stardustPrice
        return Button { pick = definition.id } label: {
            HStack(spacing: 10) {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(chosen ? RoomTheme.lilac : RoomTheme.secondary)
                MacBlueprintIcon(definition: definition, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(GameStrings.text(definition.nameKey)).font(.system(size: 14, weight: .heavy))
                        if craft.hasEverHeld(definition.id) {
                            Text(GameStrings.format("craft.usesLeftShort", craft.usesLeft(definition.id)))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        }
                    }
                    MacBlueprintTags(definition: definition)
                    if definition.source != .luck {
                        Text(GameStrings.text("craft.exchange.otherRoute") + MacCraftStyle.sourceText(definition.source, store: store))
                            .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Label(String(definition.tier.stardustPrice), systemImage: "sparkles").font(.system(size: 13, weight: .black)).monospacedDigit()
                    .foregroundStyle(affordable ? RoomTheme.lilac : RoomTheme.secondary)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? RoomTheme.lilac.opacity(0.1) : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(chosen ? RoomTheme.lilac : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("magicExchange_\(definition.id)")
    }
}
#endif
