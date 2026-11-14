#if os(macOS)
import SwiftUI
import CatGameCore

/// Café (K1–K6): dine-in drinks and snacks, plus a once-a-day sofa nap.
/// The interior uses placeholder art until the café illustration is delivered.
@MainActor
struct MacCafeView: View {
    let store: GameStore
    let onBack: () -> Void
    let onWork: () -> Void
    let onHome: () -> Void
    let onRest: () -> Void
    @State private var tab = Tab.menu
    @State private var selected = CafeItemKind.latte
    @State private var pendingOrder: (kind: CafeItemKind, usedBefore: Int)?
    @State private var served: CafeItemKind?
    @State private var shownNapResult: String?
    @State private var petLine: String?
    @State private var hoveredCat: Int?
    private enum Tab { case menu, nap }

    private var snapshot: GameSnapshot? { store.snapshot }
    private var isOpen: Bool { CafeCatalog.isOpen(at: store.now) || snapshot?.player.activeNap != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            scene.frame(maxWidth: .infinity, maxHeight: .infinity)
            panel.frame(width: 372).frame(maxHeight: .infinity)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .contain).accessibilityIdentifier("macCafePage")
        .onAppear { if snapshot?.player.activeNap != nil { tab = .nap } }
        .onChange(of: store.isBusy) { _, busy in if !busy { finishOrder() } }
        .onChange(of: snapshot?.player.lastNapResult?.napID) { _, id in if id != nil { tab = .nap; shownNapResult = id } }
    }

    // MARK: Scene
    private var scene: some View {
        let napping = snapshot?.player.activeNap != nil
        return ZStack {
            LinearGradient(colors: [Color(red: 0.99, green: 0.93, blue: 0.86), Color(red: 0.95, green: 0.85, blue: 0.74)], startPoint: .top, endPoint: .bottom)
            // `cafe-interior` is the delivered illustration; until then the town-map café stands in.
            if UIImage(named: "cafe-interior") != nil {
                interiorArt(napping: napping)
            } else {
                GameIcon(asset: "town-cafe-cartoon", symbol: "cup.and.saucer.fill", size: 360, tint: RoomTheme.lilac)
                    .opacity(isOpen ? 1 : 0.55)
                HStack(spacing: 26) {
                    ForEach(Array(cafeCats.enumerated()), id: \.offset) { index, appearance in
                        Button { pet(index) } label: {
                            GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: appearance), symbol: "cat.fill", size: 62)
                                .frame(width: 74, height: 74).background(RoomTheme.paper.opacity(0.9), in: Circle())
                        }.buttonStyle(.plain).help(GameStrings.text("cafe.petHint"))
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 92)
                hereMarker(napping: napping).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(napping ? 60 : 80)
            }
            if napping { Color(red: 0.62, green: 0.52, blue: 0.84).opacity(0.18).allowsHitTesting(false) }
            if !isOpen { Color.black.opacity(0.18).allowsHitTesting(false) }
            if let petLine {
                Text(petLine).font(.system(size: 13, weight: .heavy)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoomTheme.paper, in: Capsule()).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 30)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) { header.padding(16) }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white, lineWidth: 3))
        .accessibilityElement(children: .contain)
    }
    private var cafeCats: [CatAppearance] { [.silver, .cow, .orange] }
    /// Where things sit in `cafe-interior` (fractions of the 1672×1254 art): the three painted cats
    /// (silver on the cat tree, black-and-white in the basket, orange on the rug), the sofa seat and a free spot on the floor.
    private static let artSize = CGSize(width: 1672, height: 1254)
    private static let catSpots: [CGRect] = [
        CGRect(x: 0.616, y: 0.125, width: 0.105, height: 0.090),
        CGRect(x: 0.470, y: 0.350, width: 0.120, height: 0.095),
        CGRect(x: 0.390, y: 0.565, width: 0.135, height: 0.150),
    ]
    private static let sofaSpot = CGPoint(x: 0.80, y: 0.44)
    private static let floorSpot = CGPoint(x: 0.66, y: 0.80)

    /// The illustration filled into the scene, with invisible pet zones over the painted cats and the player
    /// marker on the sofa while napping. Positions follow the same aspect-fill crop as the image.
    private func interiorArt(napping: Bool) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = max(size.width / Self.artSize.width, size.height / Self.artSize.height)
            let drawn = CGSize(width: Self.artSize.width * scale, height: Self.artSize.height * scale)
            let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
            let place = { (point: CGPoint) in CGPoint(x: origin.x + point.x * drawn.width, y: origin.y + point.y * drawn.height) }
            ZStack(alignment: .topLeading) {
                Image("cafe-interior").resizable().frame(width: drawn.width, height: drawn.height).offset(x: origin.x, y: origin.y)
                ForEach(Array(Self.catSpots.enumerated()), id: \.offset) { index, spot in
                    let rect = CGRect(origin: place(spot.origin), size: CGSize(width: spot.width * drawn.width, height: spot.height * drawn.height))
                    Button { pet(index) } label: {
                        Ellipse().fill(Color.white.opacity(hoveredCat == index ? 0.22 : 0.001))
                            .overlay(Ellipse().strokeBorder(.white.opacity(hoveredCat == index ? 0.9 : 0), lineWidth: 2.5))
                            .frame(width: rect.width, height: rect.height)
                    }.buttonStyle(.plain).onHover { hoveredCat = $0 ? index : (hoveredCat == index ? nil : hoveredCat) }
                        .help(GameStrings.text("cafe.petHint")).accessibilityLabel(GameStrings.text("cafe.petHint"))
                        .position(x: rect.midX, y: rect.midY)
                }
                hereMarker(napping: napping).position(place(napping ? Self.sofaSpot : Self.floorSpot))
            }.frame(width: size.width, height: size.height).clipped()
        }
    }
    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) { HStack(spacing: 6) { Image(systemName: "chevron.left"); Text(GameStrings.text("cafe.back")); MacKeyCap(value: "Esc") } }
                .buttonStyle(MacCompactButtonStyle()).accessibilityIdentifier("macCafeBack")
            chip(isOpen ? GameStrings.format("cafe.hours", CafeCatalog.openHour, CafeCatalog.closeHour)
                        : GameStrings.format("cafe.closedHours", CafeCatalog.openHour),
                 symbol: isOpen ? "clock.fill" : "moon.fill")
            chip(GameStrings.format("cafe.catsInside", cafeCats.count), symbol: "pawprint.fill")
        }
    }
    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12.5, weight: .heavy)).padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoomTheme.paper, in: Capsule())
    }
    private func hereMarker(napping: Bool) -> some View {
        let avatar = snapshot?.player.profile.avatarID.flatMap(PlayerCatalog.avatar(id:))?.assetName ?? "app-icon-preview"
        return VStack(spacing: 3) {
            Text(GameStrings.text(napping ? "cafe.onSofa" : "mac.town.v2.here")).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3).background(napping ? RoomTheme.lilac : RoomTheme.mint, in: Capsule())
            GameIcon(asset: avatar, symbol: "person.crop.circle.fill", size: 40)
                .frame(width: 46, height: 46).background(RoomTheme.paper, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .overlay(alignment: .topTrailing) { if napping { Text("z z").font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.lilac).offset(x: 14, y: -10) } }
        }.accessibilityHidden(true)
    }
    private func pet(_ index: Int) {
        let lines = ["cafe.pet.1", "cafe.pet.2", "cafe.pet.3"]
        withAnimation { petLine = GameStrings.text(lines[index % lines.count]) }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { petLine = nil } }
    }

    // MARK: Panel
    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isOpen {
                closed
            } else {
                MacSegmented(selection: Binding(get: { tab == .menu ? 0 : 1 }, set: { tab = $0 == 0 ? .menu : .nap }),
                             options: [(0, GameStrings.text("cafe.tab.menu")), (1, GameStrings.text("cafe.tab.nap"))])
                ScrollView { tab == .menu ? AnyView(menuContent) : AnyView(napContent) }
            }
        }.macContentCard69(padding: 18)
    }

    private var closed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(GameStrings.text("cafe.closed.title"), systemImage: "moon.stars.fill").font(.system(size: 18, weight: .heavy))
            Text(GameStrings.format("cafe.closed.body", CafeCatalog.openHour)).foregroundStyle(RoomTheme.secondary)
            Spacer()
            Button(GameStrings.text("cafe.back"), action: onBack).buttonStyle(MintButtonStyle())
        }
    }

    @ViewBuilder private var menuContent: some View {
        let used = snapshot?.suppliesUsedToday ?? 0
        let left = snapshot?.suppliesLeftToday ?? 0
        let player = snapshot?.player ?? PlayerState(staminaUpdatedAt: .now)
        VStack(alignment: .leading, spacing: 14) {
            if let served {
                servedCard(served)
            } else {
                ForEach(CafeCatalog.menu) { item in menuRow(item, enabled: left > 0) }
                if left > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(GameStrings.text(CafeCatalog.item(selected).isDrink ? "cafe.afterDrink" : "cafe.afterEat")).font(.system(size: 13, weight: .heavy))
                        MacRecoveryPreview(player: player, effect: CafeCatalog.item(selected).effect)
                    }.padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
                }
                MacRecoveryDots(used: used)
                Text(GameStrings.text(snapshot?.napUsedToday == true ? "cafe.limit.nap" : "cafe.napAvailable"))
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.lilac)
                Text(GameStrings.text("cafe.dineInNote")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if left == 0 {
                    Label(GameStrings.format("cafe.limit.menu", PlayerSupplyCatalog.dailyLimit), systemImage: "info.circle.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    Button(GameStrings.text("recover.exit.rest"), action: onRest).buttonStyle(LilacButtonStyle())
                    Button(GameStrings.text("cafe.sitAwhile")) { tab = .nap }.buttonStyle(SoftButtonStyle())
                } else {
                    let item = CafeCatalog.item(selected)
                    let useful = item.effect.isUseful(for: player)
                    let affordable = player.gold >= item.price
                    Button { order(item) } label: {
                        HStack {
                            Text(!useful ? GameStrings.text("recover.preview.full")
                                 : !affordable ? GameStrings.format("supply.player.goldShort", item.price - player.gold)
                                 : GameStrings.format(item.isDrink ? "cafe.order.cup" : "cafe.order.plate", item.price))
                            MacKeyCap(value: "↩")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction)
                        .disabled(store.isBusy || !useful || !affordable).accessibilityIdentifier("macCafeOrder")
                }
            }
        }
    }
    private func menuRow(_ item: CafeMenuItem, enabled: Bool) -> some View {
        let isSelected = selected == item.kind
        return Button { selected = item.kind } label: {
            HStack(spacing: 12) {
                GameIcon(asset: item.assetName, symbol: item.symbol, size: 34, tint: RoomTheme.friendship)
                    .frame(width: 50, height: 50).background(RoomTheme.friendship.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.text(item.nameKey)).font(.system(size: 14.5, weight: .heavy))
                    Text(GameStrings.text(item.detailKey)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(2)
                    MacEffectChips(effect: item.effect)
                }
                Spacer(minLength: 4)
                Label("\(item.price)", systemImage: "dollarsign.circle.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.gold)
            }.padding(10).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isSelected && enabled ? RoomTheme.friendship : .white, lineWidth: isSelected && enabled ? 3 : 2))
                .opacity(enabled ? 1 : 0.5).contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(!enabled).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    private func servedCard(_ kind: CafeItemKind) -> some View {
        let item = CafeCatalog.item(kind)
        return VStack(spacing: 12) {
            GameIcon(asset: item.assetName, symbol: item.symbol, size: 90, tint: RoomTheme.friendship)
                .frame(maxWidth: .infinity).frame(height: 120).background(RoomTheme.friendship.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            Text(GameStrings.format("cafe.served.title", GameStrings.text(item.nameKey))).font(.system(size: 20, weight: .heavy))
            Text(GameStrings.text("cafe.served.line")).foregroundStyle(RoomTheme.secondary)
            HStack { MacEffectChips(effect: item.effect); Label("−\(item.price)", systemImage: "dollarsign.circle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.gold) }
            Button(GameStrings.text("cafe.stay")) { served = nil }.buttonStyle(MintButtonStyle())
            Button(GameStrings.text("cafe.backToWork"), action: onWork).buttonStyle(SoftButtonStyle())
        }
    }
    private func order(_ item: CafeMenuItem) {
        guard !store.isBusy else { return }
        pendingOrder = (item.kind, snapshot?.suppliesUsedToday ?? 0)
        store.orderCafeItem(item.kind)
    }
    private func finishOrder() {
        guard let pending = pendingOrder else { return }
        pendingOrder = nil
        if (snapshot?.suppliesUsedToday ?? 0) > pending.usedBefore { served = pending.kind }
    }

    @ViewBuilder private var napContent: some View {
        if let nap = snapshot?.player.activeNap {
            napping(nap)
        } else if let result = snapshot?.player.lastNapResult, result.napID == shownNapResult {
            awake(result)
        } else if snapshot?.napUsedToday == true {
            VStack(alignment: .leading, spacing: 12) {
                Label(GameStrings.text("cafe.limit.nap"), systemImage: "moon.zzz.fill").font(.system(size: 17, weight: .heavy)).foregroundStyle(RoomTheme.lilac)
                Text(GameStrings.text("cafe.limit.hint")).foregroundStyle(RoomTheme.secondary)
                Button(GameStrings.text("recover.exit.rest"), action: onRest).buttonStyle(LilacButtonStyle())
                Button(GameStrings.text("cafe.sitAwhile")) { tab = .menu }.buttonStyle(SoftButtonStyle())
            }
        } else {
            napInfo
        }
    }
    private var napInfo: some View {
        let player = snapshot?.player ?? PlayerState(staminaUpdatedAt: .now)
        let minutes = Int(CafeCatalog.napDuration / 60)
        let blocked = player.activeWork != nil ? "cafe.napWorking" : player.activeSleep != nil ? "cafe.napSleeping" : nil
        let useful = CafeCatalog.napEffect.isUseful(for: player), affordable = player.gold >= CafeCatalog.napPrice
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label(GameStrings.text("cafe.nap.title"), systemImage: "sofa.fill").font(.system(size: 17, weight: .heavy))
                Text(GameStrings.format("cafe.nap.meta", minutes, CafeCatalog.napPrice, CafeCatalog.napsPerDay)).font(.system(size: 12, weight: .bold))
                MacEffectChips(effect: CafeCatalog.napEffect)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.lilac.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 10) {
                Text(GameStrings.text("cafe.nap.after")).font(.system(size: 13, weight: .heavy))
                MacRecoveryPreview(player: player, effect: CafeCatalog.napEffect)
            }.padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
            ForEach(["cafe.nap.note1", "cafe.nap.note2", "cafe.nap.note3"], id: \.self) { key in
                Label(GameStrings.text(key), systemImage: "checkmark.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            }
            if let blocked {
                Label(GameStrings.text(blocked), systemImage: "exclamationmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.coralDeep)
            }
            Button { store.startCafeNap() } label: {
                HStack {
                    Text(!useful ? GameStrings.text("recover.preview.full")
                         : !affordable ? GameStrings.format("supply.player.goldShort", CafeCatalog.napPrice - player.gold)
                         : GameStrings.format("cafe.nap.start", CafeCatalog.napPrice))
                    MacKeyCap(value: "↩")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(LilacButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(store.isBusy || blocked != nil || !useful || !affordable).accessibilityIdentifier("macCafeNap")
        }
    }
    private func napping(_ nap: PlayerNap) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, nap.endsAt.timeIntervalSince(context.date))
            let sofar = GameEngine.napGain(nap, at: context.date)
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(RoomTheme.track, lineWidth: 18)
                    Circle().trim(from: 0, to: max(0.002, min(1, 1 - remaining / max(1, nap.duration))))
                        .stroke(RoomTheme.lilac, style: StrokeStyle(lineWidth: 18)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(MacWorkClock.text(Int(ceil(remaining)))).font(.system(size: 42, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text(GameStrings.format("mac.work.v2.total", WorkJobPresentation.duration(Int(nap.duration)))).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    }
                }.frame(width: 200, height: 200).padding(10)
                Text(GameStrings.text("cafe.napping")).font(.system(size: 18, weight: .heavy))
                Text(GameStrings.text("cafe.napping.line")).foregroundStyle(RoomTheme.secondary)
                HStack(spacing: 6) {
                    MacEffectChips(effect: sofar)
                    Text(GameStrings.format("cafe.napping.total", nap.effect.stamina, nap.effect.mood)).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                }
                Button(GameStrings.format("cafe.wakeEarly", sofar.stamina)) { store.wakeFromCafeNap() }
                    .buttonStyle(SoftButtonStyle()).disabled(store.isBusy).accessibilityIdentifier("macCafeWake")
                Button(GameStrings.text("cafe.homeCheck"), action: onHome).buttonStyle(MintButtonStyle())
            }.frame(maxWidth: .infinity)
        }
    }
    private func awake(_ result: PlayerNapResult) -> some View {
        let player = snapshot?.player ?? PlayerState(staminaUpdatedAt: .now)
        return VStack(spacing: 12) {
            Image(systemName: "sun.max.fill").font(.system(size: 44)).foregroundStyle(RoomTheme.gold)
            Text(GameStrings.text("cafe.awake.title")).font(.system(size: 20, weight: .heavy))
            Text(GameStrings.text("cafe.awake.line")).foregroundStyle(RoomTheme.secondary)
            VStack(spacing: 10) {
                if result.gained.stamina > 0 { MacRecoveryBar(attribute: .stamina, current: player.stamina - result.gained.stamina, gain: result.gained.stamina) }
                if result.gained.mood > 0 { MacRecoveryBar(attribute: .mood, current: player.mood - result.gained.mood, gain: result.gained.mood) }
            }.padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
            Button(GameStrings.text("cafe.backToWork"), action: onWork).buttonStyle(MintButtonStyle())
            Button(GameStrings.text("cafe.orderAgain")) { shownNapResult = nil; tab = .menu }.buttonStyle(SoftButtonStyle())
        }.frame(maxWidth: .infinity)
    }
}

/// Lilac primary button used for the nap flow.
struct LilacButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 13).frame(maxWidth: .infinity, minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RoomTheme.lilac)
                    .shadow(color: Color(red: 0.45, green: 0.36, blue: 0.62).opacity(isEnabled ? 1 : 0.15), radius: 0, y: configuration.isPressed ? 1 : 4)
            }
            .opacity(isEnabled ? 1 : 0.5).offset(y: configuration.isPressed ? 2 : 0)
    }
}
#endif
