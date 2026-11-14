#if os(macOS)
import SwiftUI
import CatGameCore

extension Notification.Name {
    /// The keys bound to pages 1/2/3, handed to the garden while it is walking (object: Int 0…2).
    static let macGardenKey = Notification.Name("MacGardenKey")
    static let macGardenConfirm = Notification.Name("MacGardenConfirm")
    static let macGardenEscape = Notification.Name("MacGardenEscape")
}

/// Where the garden sends the player.
struct MacGardenExits {
    let town: () -> Void
    let home: () -> Void
    let album: () -> Void
    /// Enter arrange mode with this furniture item selected.
    let arrange: (String) -> Void
}

/// 猫町花园 (2.0): pick a cat, walk three spots with six footprints, bring finds home.
/// Every number shown comes from Core (`OutingCatalog` and the saved trip).
@MainActor
struct MacGardenView: View {
    let store: GameStore
    let preferences: MacPreferences
    let exits: MacGardenExits
    var preselectedCatID: String?
    /// True while number keys mean spots / options here instead of switching pages.
    @Binding var takesNumberKeys: Bool

    @State private var onMap = false
    @State private var chosenCatID: String?
    @State private var cardEntryID: String?
    @State private var confirmsLeave = false
    @State private var hoveredSpot: OutingSpot?
    @State private var working = false
    @State private var deferredCompare = false

    private var state: GameSnapshot? { store.snapshot }
    private var trip: OutingTrip? { state?.outing.trip }
    private var tripCat: CatState? { trip.flatMap { trip in state?.cats.first { $0.id == trip.catID } } }
    private var settlement: OutingSettlement? { state?.outing.unacknowledgedSettlement }
    private var compareID: String? {
        guard trip == nil, settlement == nil, !deferredCompare else { return nil }
        return state?.outing.pendingDuplicates.first
    }
    private var departuresLeft: Int { state?.outing.departuresLeft(today: state?.tasks.dailyDayKey) ?? 0 }
    private var chosenCat: CatState? {
        if let tripCat { return tripCat }
        return state?.cats.first { $0.id == chosenCatID }
    }
    private func key(_ command: MacCommand) -> String { preferences.binding(for: command).label }
    private var numberCommands: [MacCommand] { [.home, .work, .shop] }

    var body: some View {
        ZStack {
            if onMap, let trip, let cat = tripCat { mapPage(trip, cat) } else { prepPage }
            if confirmsLeave, trip != nil { leaveDialog }
            if let settlement { settlementModal(settlement) }
            else if let compareID {
                MacModalScrim { MacDecorCompareCard(store: store, decorID: compareID, onLater: { deferredCompare = true }) }
            }
        }
        .font(.system(size: 13.5, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .contain).accessibilityIdentifier("macGardenPage")
        .onAppear {
            chosenCatID = preselectedCatID ?? chosenCatID ?? firstAvailableCat()
            updateNumberKeys()
        }
        .onDisappear { takesNumberKeys = false }
        .onChange(of: trip?.id) { _, id in if id == nil { onMap = false; cardEntryID = nil; confirmsLeave = false }; updateNumberKeys() }
        .onChange(of: onMap) { _, _ in updateNumberKeys() }
        .onChange(of: settlement?.id) { _, _ in updateNumberKeys() }
        .onChange(of: store.saveSceneGeneration) { _, _ in
            onMap = false; cardEntryID = nil; confirmsLeave = false; chosenCatID = firstAvailableCat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macGardenKey)) { note in
            if let index = note.object as? Int { number(index) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macGardenConfirm)) { _ in confirm() }
        .onReceive(NotificationCenter.default.publisher(for: .macGardenEscape)) { _ in escape() }
    }

    private func updateNumberKeys() { takesNumberKeys = onMap && trip != nil && settlement == nil }

    private func firstAvailableCat() -> String? {
        guard let state else { return nil }
        if let cat = store.cat, OutingCatalog.blocker(for: cat, in: state) == nil { return cat.id }
        return state.cats.first { OutingCatalog.blocker(for: $0, in: state) == nil }?.id ?? store.cat?.id
    }

    // MARK: Keys

    private func number(_ index: Int) {
        guard !working, settlement == nil, !confirmsLeave, let trip, let cat = tripCat, onMap else { return }
        if let eventID = trip.pendingEventID, let event = OutingCatalog.event(id: eventID) {
            let options = event.options(for: cat)
            if options.indices.contains(index) { choose(options[index].id) }
        } else if cardEntryID == nil, OutingSpot.allCases.indices.contains(index) {
            explore(OutingSpot.allCases[index])
        }
    }

    private func confirm() {
        if let settlement { mainSettlementAction(settlement); return }
        if compareID != nil { return }
        if confirmsLeave { goHome(); return }
        if onMap {
            if cardEntryID != nil { continueAfterCard() }
            return
        }
        if trip != nil { onMap = true } else { depart() }
    }

    private func escape() {
        if settlement != nil { Task { await store.acknowledgeOutingSettlement() }; return }
        if compareID != nil { deferredCompare = true; return }
        if confirmsLeave { confirmsLeave = false; return }
        if onMap {
            if cardEntryID != nil { cardEntryID = nil } else if trip?.pendingEventID == nil { confirmsLeave = true }
            return
        }
        exits.town()
    }

    // MARK: Actions

    private func depart() {
        guard !working, trip == nil, let cat = chosenCat else { return }
        working = true
        Task {
            if await store.startOuting(catID: cat.id) { onMap = true; cardEntryID = nil }
            working = false
        }
    }

    private func explore(_ spot: OutingSpot) {
        guard !working, let trip, trip.pendingEventID == nil, trip.footprintsLeft > 0, cardEntryID == nil else { return }
        working = true
        Task {
            if await store.exploreOuting(spot: spot), let last = store.outingTrip?.log.last, last.kind != .event {
                cardEntryID = last.id
            }
            working = false
        }
    }

    private func choose(_ optionID: String) {
        guard !working else { return }
        working = true
        Task {
            if await store.chooseOutingEvent(optionID: optionID),
               let last = store.outingTrip?.log.last(where: { $0.kind == .outcome }) { cardEntryID = last.id }
            working = false
        }
    }

    private func continueAfterCard() {
        cardEntryID = nil
        if let trip, trip.footprintsLeft == 0, trip.pendingEventID == nil { end() }
    }

    private func end() {
        guard !working else { return }
        working = true; confirmsLeave = false
        Task { _ = await store.endOuting(); working = false }
    }

    private func goHome() {
        confirmsLeave = false; onMap = false; cardEntryID = nil
        exits.home()
    }

    // MARK: Prep (O1 / O9)

    private var prepPage: some View {
        VStack(spacing: 14) {
            MacPlaceBanner(store: store, place: .garden, height: 120, onTown: exits.town) {
                HStack(spacing: 8) {
                    MacBannerChip(text: GameStrings.format("outing.chip.departures", departuresLeft, OutingCatalog.dailyDepartures),
                                  symbol: "figure.walk")
                    MacBannerChip(text: GameStrings.format("outing.chip.keepsakes", state?.outing.foundKeepsakeCount ?? 0,
                                                           OutingCatalog.keepsakes.count),
                                  symbol: "book.closed.fill", tint: RoomTheme.friendshipDeep)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                spotsColumn.frame(width: 268)
                catsColumn.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                departColumn.frame(width: 320)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var spotsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            MacGardenScene(highlight: nil).frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            Text(GameStrings.text("outing.spots.title")).font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            ForEach(OutingSpot.allCases) { spot in spotRow(spot) }
            Button(action: exits.album) {
                HStack {
                    Label(GameStrings.text("outing.album.open"), systemImage: "book.closed.fill")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                }
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                .padding(10).background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain).accessibilityIdentifier("outingAlbumLink")
            if (state?.outing.pendingDuplicates.isEmpty == false) {
                Button { deferredCompare = false } label: {
                    Label(GameStrings.format("outing.compare.pending", state?.outing.pendingDuplicates.count ?? 0), systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                }.buttonStyle(.plain).disabled(trip != nil)
            }
        }
        .macContentCard69(padding: 12)
    }

    private func spotRow(_ spot: OutingSpot) -> some View {
        let outing = state?.outing
        let keepsakes = OutingCatalog.keepsakes(at: spot).filter { outing?.keepsakes[$0.id] != nil }.count
        let decor = OutingCatalog.decor(at: spot).filter { outing?.decor[$0.id] != nil }.count
        return HStack(spacing: 10) {
            Image(systemName: MacGardenScene.symbol(spot)).font(.system(size: 15, weight: .bold))
                .foregroundStyle(MacGardenScene.tint(spot)).frame(width: 32, height: 32)
                .background(MacGardenScene.tint(spot).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(GameStrings.text(spot.titleKey)).font(.system(size: 13.5, weight: .heavy))
                Text(GameStrings.format("outing.spot.progress", keepsakes, OutingCatalog.keepsakes(at: spot).count,
                                        decor, OutingCatalog.decor(at: spot).count))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let trip, trip.visits(at: spot) > 0 {
                Text("×\(trip.visits(at: spot))").font(.system(size: 11, weight: .heavy)).monospacedDigit().foregroundStyle(RoomTheme.darkMint)
            }
        }
        .padding(8).background(RoomTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var catsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(GameStrings.text(trip == nil ? "outing.pickCat" : "outing.catLocked")).font(.system(size: 15, weight: .heavy))
                Spacer(minLength: 0)
                Text(GameStrings.text("outing.pickCatHint")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(state?.cats ?? []) { cat in
                        if trip == nil || trip?.catID == cat.id { catCard(cat) }
                    }
                }.padding(2)
            }.scrollIndicators(.never)
        }
        .macContentCard69(padding: 12)
    }

    private func catCard(_ cat: CatState) -> some View {
        let blocker = state.flatMap { trip == nil ? OutingCatalog.blocker(for: cat, in: $0) : nil }
        let selected = chosenCat?.id == cat.id
        return Button { if trip == nil { chosenCatID = cat.id } } label: {
            VStack(spacing: 6) {
                CatCollectionPortrait(appearance: cat.appearance, size: 62, faded: blocker != nil)
                Text(verbatim: GameStrings.catName(cat)).font(.system(size: 13.5, weight: .heavy)).lineLimit(1)
                miniStat("stat.satiety", cat.satiety, tint: RoomTheme.gold)
                miniStat("rest.energy", cat.energy, tint: RoomTheme.lilac)
                Text(GameStrings.text(blocker?.messageKey ?? (trip == nil ? "outing.catReady" : "outing.catOnTrip")))
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(blocker == nil ? RoomTheme.darkMint : RoomTheme.coralDeep)
                    .lineLimit(2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10).frame(maxWidth: .infinity)
            .background(selected ? RoomTheme.paleMint : RoomTheme.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? RoomTheme.mint : RoomTheme.track, lineWidth: 2))
            .opacity(blocker == nil ? 1 : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(blocker != nil || working)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("outingCat_\(cat.id)")
    }

    private func miniStat(_ key: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(GameStrings.text(key)).font(.system(size: 10, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .frame(width: 34, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
            MacCapsuleProgress(value: Double(value), tint: tint).frame(height: 6)
            Text("\(value)").font(.system(size: 10, weight: .heavy)).monospacedDigit().frame(width: 22, alignment: .trailing)
        }
    }

    @ViewBuilder private var departColumn: some View {
        if let trip, let cat = tripCat { resumeCard(trip, cat) } else { costsCard }
    }

    /// Why the selected cat can't leave, or nil when departure is possible.
    private var departBlocker: String? {
        guard let state else { return "game.invalidState" }
        guard let cat = chosenCat else { return "outing.error.noCat" }
        if state.player.activeWork != nil { return "outing.error.working" }
        if state.player.activeSleep != nil { return "outing.error.sleeping" }
        if state.player.activeNap != nil { return "outing.error.napping" }
        if departuresLeft == 0 { return "outing.error.dailyLimit" }
        if let blocker = OutingCatalog.blocker(for: cat, in: state) { return blocker.messageKey }
        if state.player.stamina < OutingCatalog.staminaCost { return "outing.error.stamina" }
        return nil
    }

    private var costsCard: some View {
        let stamina = state?.player.stamina ?? 0
        let footprints = OutingCatalog.footprints + (state.map { OutingBonuses.value(.footprint, in: $0) } ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            Text(GameStrings.text("outing.prep.title")).font(.system(size: 15, weight: .heavy))
            VStack(spacing: 8) {
                costRow("outing.prep.stamina", symbol: "bolt.heart.fill", from: stamina, to: max(0, stamina - OutingCatalog.staminaCost), tint: RoomTheme.coral)
                if let cat = chosenCat {
                    costRow("outing.prep.energy", symbol: "moon.zzz.fill", from: cat.energy,
                            to: max(0, cat.energy - OutingCatalog.energyCost), tint: RoomTheme.lilac,
                            name: GameStrings.catName(cat))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(GameStrings.format("outing.prep.footprints", footprints)).font(.system(size: 12.5, weight: .heavy))
                MacFootprints(total: footprints, left: footprints)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(["outing.rule.daily", "outing.rule.noWork", "outing.rule.sleep", "outing.rule.resume"], id: \.self) { rule in
                    Label {
                        Text(rule == "outing.rule.daily" ? GameStrings.format(rule, OutingCatalog.dailyDepartures, departuresLeft) : GameStrings.text(rule))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "pawprint.fill").foregroundStyle(RoomTheme.mint) }
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                }
            }
            Spacer(minLength: 0)
            if let blocker = departBlocker {
                Text(GameStrings.text(blocker)).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("outingDepartBlocker")
            }
            Button(action: depart) {
                Text(GameStrings.format("outing.depart", chosenCat.map(GameStrings.catName) ?? "") + "  " + key(.confirm))
                    .font(.system(size: 15, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(MintButtonStyle()).disabled(departBlocker != nil || working || store.isBusy)
            .accessibilityIdentifier("outingDepart")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .macContentCard69(padding: 14)
    }

    private func costRow(_ key: String, symbol: String, from: Int, to: Int, tint: Color, name: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 22)
            Text(name.map { GameStrings.format(key, $0) } ?? GameStrings.text(key)).font(.system(size: 12.5, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("\(from)").monospacedDigit().foregroundStyle(RoomTheme.secondary)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
            Text("\(to)").monospacedDigit().foregroundStyle(tint)
        }
        .font(.system(size: 13, weight: .heavy))
        .padding(9).background(RoomTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func resumeCard(_ trip: OutingTrip, _ cat: CatState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GameStrings.text("outing.resume.title")).font(.system(size: 15, weight: .heavy))
            Text(GameStrings.format("outing.resume.body", GameStrings.catName(cat))).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(GameStrings.format("outing.footprintsLeft", trip.footprintsLeft)).font(.system(size: 12.5, weight: .heavy))
                MacFootprints(total: trip.footprintsTotal, left: trip.footprintsLeft)
            }
            Text(GameStrings.text("outing.loot.title")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            MacOutingLootChips(loot: trip.loot)
            Spacer(minLength: 0)
            Button { onMap = true } label: {
                Text(GameStrings.text("outing.resume.continue") + "  " + key(.confirm)).font(.system(size: 15, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(MintButtonStyle()).disabled(working).accessibilityIdentifier("outingResume")
            Button(action: end) {
                Text(GameStrings.text("outing.resume.settle")).font(.system(size: 13, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle()).disabled(working).accessibilityIdentifier("outingSettleNow")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .macContentCard69(padding: 14)
    }

    // MARK: Map (O2–O7)

    private func mapPage(_ trip: OutingTrip, _ cat: CatState) -> some View {
        HStack(spacing: 14) {
            GeometryReader { proxy in
                ZStack {
                    MacGardenScene(highlight: hoveredSpot)
                    ForEach(Array(OutingSpot.allCases.enumerated()), id: \.element) { index, spot in
                        spotLabel(spot, index: index, trip: trip)
                            .position(x: MacGardenScene.position(spot).x * proxy.size.width,
                                      y: MacGardenScene.position(spot).y * proxy.size.height)
                    }
                    if let hoveredSpot, trip.pendingEventID == nil, cardEntryID == nil {
                        spotTooltip(hoveredSpot)
                            .position(x: min(proxy.size.width - 150, max(150, MacGardenScene.position(hoveredSpot).x * proxy.size.width)),
                                      y: max(80, MacGardenScene.position(hoveredSpot).y * proxy.size.height - 96))
                            .allowsHitTesting(false)
                    }
                    VStack { mapTopBar(trip); Spacer() }.padding(12)
                    VStack { Spacer(); HStack { catBubble(trip, cat); Spacer() } }.padding(14)
                    if let eventID = trip.pendingEventID, let event = OutingCatalog.event(id: eventID) {
                        MacModalScrim(opacity: 0.18) { eventCard(event, cat) }
                    } else if let id = cardEntryID, let entry = trip.log.first(where: { $0.id == id }) {
                        MacModalScrim(opacity: 0.18) { resultCard(entry, trip: trip, cat: cat) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
            .accessibilityElement(children: .contain).accessibilityIdentifier("outingMap")
            sidePanel(trip, cat).frame(width: 320)
        }
    }

    private func spotLabel(_ spot: OutingSpot, index: Int, trip: OutingTrip) -> some View {
        let enabled = trip.footprintsLeft > 0 && trip.pendingEventID == nil && cardEntryID == nil && !working
        return Button { explore(spot) } label: {
            HStack(spacing: 6) {
                Text(key(numberCommands[index])).font(.system(size: 11, weight: .heavy).monospaced())
                    .foregroundStyle(.white).frame(width: 20, height: 20).background(MacGardenScene.tint(spot), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(GameStrings.text(spot.titleKey)).font(.system(size: 14, weight: .heavy))
                    Text(GameStrings.format("outing.spot.visits", trip.visits(at: spot))).font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(RoomTheme.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoomTheme.paper.opacity(0.95), in: Capsule())
            .overlay(Capsule().strokeBorder(hoveredSpot == spot ? MacGardenScene.tint(spot) : .white, lineWidth: 2.5))
            .compositingGroup().shadow(color: RoomTheme.ink.opacity(0.15), radius: 0, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .onHover { inside in hoveredSpot = inside ? spot : (hoveredSpot == spot ? nil : hoveredSpot) }
        .help(GameStrings.text("outing.spot.hint"))
        .accessibilityIdentifier("outingSpot_\(spot.rawValue)")
    }

    /// O3: what can be found here, found ones shown, the rest as "?".
    private func spotTooltip(_ spot: OutingSpot) -> some View {
        let outing = state?.outing
        return VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.text(spot.titleKey)).font(.system(size: 13, weight: .heavy))
            HStack(spacing: 6) {
                ForEach(OutingCatalog.keepsakes(at: spot)) { item in
                    tooltipSlot(found: outing?.keepsakes[item.id] != nil, asset: "keepsake-\(item.id)", symbol: item.symbol)
                }
                Divider().frame(height: 28).overlay(.white.opacity(0.3))
                ForEach(OutingCatalog.decor(at: spot)) { item in
                    tooltipSlot(found: outing?.decor[item.id] != nil,
                                asset: FurnitureCatalog.metadata(for: item.kind).assetName, symbol: item.symbol)
                }
            }
            Text(GameStrings.text("outing.tooltip.hint")).font(.system(size: 10.5, weight: .semibold)).opacity(0.75)
        }
        .foregroundStyle(.white).padding(12)
        .background(RoomTheme.ink.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .frame(width: 290)
    }

    private func tooltipSlot(found: Bool, asset: String, symbol: String) -> some View {
        Group {
            if found { GameIcon(asset: asset, symbol: symbol, size: 22, tint: .white) }
            else { Text("?").font(.system(size: 14, weight: .heavy)) }
        }
        .frame(width: 30, height: 30)
        .background(.white.opacity(found ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: found ? [] : [3, 3])))
    }

    private func mapTopBar(_ trip: OutingTrip) -> some View {
        HStack(spacing: 8) {
            Button { confirmsLeave = true } label: {
                Label(GameStrings.text("outing.goHome") + "  " + key(.escape), systemImage: "house.fill")
                    .font(.system(size: 12.5, weight: .heavy)).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoomTheme.paper.opacity(0.95), in: Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).disabled(trip.pendingEventID != nil || working)
            .accessibilityIdentifier("outingGoHome")
            Spacer()
            HStack(spacing: 6) {
                MacFootprints(total: trip.footprintsTotal, left: trip.footprintsLeft, size: 13)
                Text(GameStrings.format("outing.footprintsLeft", trip.footprintsLeft)).font(.system(size: 12, weight: .heavy)).monospacedDigit()
            }
            .padding(.horizontal, 11).padding(.vertical, 6).background(RoomTheme.paper.opacity(0.95), in: Capsule())
            .accessibilityElement(children: .combine).accessibilityIdentifier("outingFootprints")
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                Label { Text(clock.date, format: .dateTime.hour().minute()).monospacedDigit() }
                    icon: { Image(systemName: MacGardenScene.isEvening(clock.date) ? "sunset.fill" : "sun.max.fill") }
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    .padding(.horizontal, 11).padding(.vertical, 6).background(RoomTheme.paper.opacity(0.95), in: Capsule())
            }
        }
    }

    private func catBubble(_ trip: OutingTrip, _ cat: CatState) -> some View {
        let key = trip.footprintsLeft == 0 ? "outing.bubble.tired" : trip.footprintsUsed == 0 ? "outing.bubble.start" : "outing.bubble.walking"
        return HStack(alignment: .bottom, spacing: 6) {
            CatCollectionPortrait(appearance: cat.appearance, size: 58)
            Text(GameStrings.format(key, GameStrings.catName(cat))).font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(RoomTheme.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 260, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)
        }
        .accessibilityElement(children: .combine)
    }

    private func sidePanel(_ trip: OutingTrip, _ cat: CatState) -> some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    CatCollectionPortrait(appearance: cat.appearance, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: GameStrings.catName(cat)).font(.system(size: 15, weight: .heavy)).lineLimit(1)
                        miniStat("stat.mood", cat.mood, tint: RoomTheme.coral)
                        miniStat("rest.energy", cat.energy, tint: RoomTheme.lilac)
                    }
                }
                let habits = MacOutingText.knownHabits(cat)
                if !habits.isEmpty {
                    OutingChips(items: habits, tint: RoomTheme.friendshipDeep, background: RoomTheme.friendshipPaper)
                } else {
                    Text(GameStrings.text("outing.habits.none")).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                }
            }
            .macContentCard69(padding: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(GameStrings.text("outing.loot.title")).font(.system(size: 13, weight: .heavy))
                MacOutingLootChips(loot: trip.loot)
            }
            .macContentCard69(padding: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(GameStrings.text("outing.log.title")).font(.system(size: 13, weight: .heavy))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if trip.log.isEmpty {
                            Text(GameStrings.text("outing.log.empty")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        }
                        ForEach(trip.log.reversed()) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: MacGardenScene.symbol(entry.spot)).font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MacGardenScene.tint(entry.spot)).frame(width: 14).padding(.top, 2)
                                Text(MacOutingText.logLine(entry, trip: trip)).font(.system(size: 11.5, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.never)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .macContentCard69(padding: 12)
            HStack(spacing: 8) {
                Button { confirmsLeave = true } label: {
                    Text(GameStrings.text("outing.goHome")).font(.system(size: 13, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(SoftButtonStyle())
                Button { confirmsLeave = true } label: {
                    Text(GameStrings.text("outing.end")).font(.system(size: 13, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("outingEnd")
            }
            .disabled(trip.pendingEventID != nil || working)
        }
    }

    /// O5: two or three answers, the habit one outlined in pink.
    private func eventCard(_ event: OutingEventDefinition, _ cat: CatState) -> some View {
        let name = GameStrings.catName(cat)
        let options = event.options(for: cat)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: event.symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(RoomTheme.gold)
                    .frame(width: 42, height: 42).background(RoomTheme.rewardPaper, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.text("outing.event.kicker")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    Text(GameStrings.text(event.titleKey)).font(.system(size: 18, weight: .heavy))
                }
            }
            Text(GameStrings.format(event.bodyKey, name)).font(.system(size: 13, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    Button { choose(option.id) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(key(numberCommands[min(index, 2)])).font(.system(size: 11, weight: .heavy).monospaced())
                                .foregroundStyle(.white).frame(width: 22, height: 22)
                                .background(option.habit == nil ? RoomTheme.mint : RoomTheme.friendship, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                if option.habit != nil {
                                    Text(GameStrings.format("outing.habitBadge", name)).font(.system(size: 10.5, weight: .heavy))
                                        .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(RoomTheme.friendship, in: Capsule())
                                }
                                Text(GameStrings.format(event.optionKey(option), name)).font(.system(size: 13.5, weight: .heavy))
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text(option.effect.hintKeys.map(GameStrings.text).joined(separator: " · "))
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(option.habit == nil ? RoomTheme.cream : RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(option.habit == nil ? RoomTheme.track : RoomTheme.friendship, lineWidth: 2))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain).disabled(working)
                    .accessibilityIdentifier("outingOption_\(option.id)")
                }
            }
            Text(GameStrings.text("outing.event.noWrong")).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
        }
        .padding(18).frame(width: 440)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal).accessibilityIdentifier("outingEventCard")
    }

    /// O4 / O6 / O7 and the quiet results: what this footprint actually gave.
    private func resultCard(_ entry: OutingLogEntry, trip: OutingTrip, cat: CatState) -> some View {
        let name = GameStrings.catName(cat)
        let loot = entry.lootID.flatMap { id in trip.loot.first { $0.id == id } }
        let isLast = trip.footprintsLeft == 0
        return VStack(spacing: 12) {
            switch entry.kind {
            case .find:
                if let loot { MacOutingLootDetail(loot: loot, catName: name, reactionKey: entry.reactionKey, outing: state?.outing) }
            case .outcome:
                if let event = entry.eventID.flatMap(OutingCatalog.event(id:)) {
                    VStack(spacing: 8) {
                        Image(systemName: event.symbol).font(.system(size: 26, weight: .bold)).foregroundStyle(RoomTheme.gold)
                            .frame(width: 60, height: 60).background(RoomTheme.rewardPaper, in: Circle())
                        Text(GameStrings.text(event.titleKey)).font(.system(size: 17, weight: .heavy))
                        Text(GameStrings.format(entry.reactionKey ?? "", name)).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text(GameStrings.text("outing.result.actual")).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                        OutingChips(items: MacOutingText.effects(entry), tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                    }
                }
            case .nothing:
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(RoomTheme.coral)
                        .frame(width: 60, height: 60).background(RoomTheme.paleCoral, in: Circle())
                    Text(GameStrings.format("outing.reaction.nothing", name)).font(.system(size: 13.5, weight: .semibold))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    OutingChips(items: MacOutingText.effects(entry), tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                }
            case .event:
                EmptyView()
            }
            Button(action: continueAfterCard) {
                Text(GameStrings.text(isLast ? "outing.card.finish" : "outing.card.continue") + "  " + key(.confirm))
                    .font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(MintButtonStyle()).disabled(working).accessibilityIdentifier("outingCardContinue")
        }
        .padding(18).frame(width: 400)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal).accessibilityIdentifier("outingResultCard")
    }

    // MARK: Leave (O8)

    private var leaveDialog: some View {
        MacModalScrim {
            VStack(alignment: .leading, spacing: 12) {
                Text(GameStrings.text("outing.leave.title")).font(.system(size: 18, weight: .heavy))
                Text(GameStrings.format("outing.leave.body", trip?.footprintsLeft ?? 0)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action: goHome) {
                    VStack(spacing: 2) {
                        Text(GameStrings.text("outing.leave.later") + "  " + key(.confirm)).font(.system(size: 14, weight: .heavy))
                        Text(GameStrings.text("outing.leave.laterHint")).font(.system(size: 11, weight: .semibold)).opacity(0.85)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("outingLeaveLater")
                Button(action: end) {
                    VStack(spacing: 2) {
                        Text(GameStrings.text("outing.leave.end")).font(.system(size: 14, weight: .heavy))
                        Text(GameStrings.text("outing.leave.endHint")).font(.system(size: 11, weight: .semibold)).opacity(0.85)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(SoftButtonStyle()).disabled(working).accessibilityIdentifier("outingLeaveEnd")
                Button { confirmsLeave = false } label: {
                    Text(GameStrings.text("common.cancel") + "  " + key(.escape)).font(.system(size: 12.5, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(.plain).foregroundStyle(RoomTheme.secondary)
            }
            .padding(20).frame(width: 380)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal).accessibilityIdentifier("outingLeaveDialog")
        }
    }

    // MARK: Settlement (O10)

    /// The first new decor piece, which the main button takes home to place.
    private func newDecor(_ settlement: OutingSettlement) -> OutingDecorDefinition? {
        settlement.loot.first { $0.kind == .decor && !$0.duplicate }.flatMap { $0.itemID.flatMap(OutingCatalog.decor(id:)) }
    }

    private func mainSettlementAction(_ settlement: OutingSettlement) {
        let decor = newDecor(settlement)
        Task {
            guard await store.acknowledgeOutingSettlement() else { return }
            if let decor { exits.arrange(decor.itemID) } else { exits.home() }
        }
    }

    private func settlementModal(_ settlement: OutingSettlement) -> some View {
        let cat = state?.cats.first { $0.id == settlement.catID }
        let name = cat.map(GameStrings.catName) ?? ""
        let decor = newDecor(settlement)
        return MacModalScrim(opacity: 0.32) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let cat { CatCollectionPortrait(appearance: cat.appearance, size: 56) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(GameStrings.format("outing.settle.title", name)).font(.system(size: 20, weight: .heavy))
                        Text(GameStrings.format("outing.settle.reason.\(settlement.reason.rawValue)", settlement.footprintsUsed, settlement.footprintsTotal))
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(GameStrings.text("outing.loot.title")).font(.system(size: 13, weight: .heavy))
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if settlement.loot.isEmpty {
                                    Text(GameStrings.text("outing.loot.empty")).font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                                }
                                ForEach(settlement.loot) { loot in MacOutingLootRow(loot: loot) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 230).scrollIndicators(.never)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(GameStrings.format("outing.settle.catChanges", name)).font(.system(size: 13, weight: .heavy))
                        OutingChips(items: [GameStrings.format("outing.effect.mood", settlement.catMood),
                                          GameStrings.format("outing.effect.bond", settlement.bond),
                                          GameStrings.format("outing.effect.gold", settlement.gold)],
                                  tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                        Text(GameStrings.text("outing.settle.people")).font(.system(size: 13, weight: .heavy))
                        Text(settlement.neighborsMet.isEmpty ? GameStrings.text("outing.settle.nobody")
                             : settlement.neighborsMet.map(MacOutingText.neighborName).joined(separator: "、"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        Text(GameStrings.text("outing.settle.album")).font(.system(size: 13, weight: .heavy))
                        let found = state?.outing.foundKeepsakeCount ?? 0
                        HStack(spacing: 8) {
                            MacCapsuleProgress(value: Double(found), total: Double(OutingCatalog.keepsakes.count), tint: RoomTheme.friendship)
                            Text("\(found)/\(OutingCatalog.keepsakes.count)").font(.system(size: 12, weight: .heavy)).monospacedDigit()
                        }
                        if state?.outing.pendingDuplicates.isEmpty == false {
                            Text(GameStrings.text("outing.settle.compareNext")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.coralDeep)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12).frame(width: 260, alignment: .leading)
                    .background(RoomTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }
                HStack(spacing: 8) {
                    Text(GameStrings.format("outing.settle.departuresLeft", departuresLeft)).font(.system(size: 12, weight: .bold))
                        .foregroundStyle(RoomTheme.secondary)
                    Spacer(minLength: 6)
                    Button { Task { if await store.acknowledgeOutingSettlement() { exits.album() } } } label: {
                        Text(GameStrings.text("outing.album.open")).font(.system(size: 13, weight: .heavy))
                    }.buttonStyle(SoftButtonStyle()).fixedSize()
                    Button { Task { if await store.acknowledgeOutingSettlement() { exits.town() } } } label: {
                        Text(GameStrings.text("outing.settle.town")).font(.system(size: 13, weight: .heavy))
                    }.buttonStyle(SoftButtonStyle()).fixedSize()
                    Button { mainSettlementAction(settlement) } label: {
                        Text((decor.map { GameStrings.format($0.placement == .wall ? "outing.settle.hang" : "outing.settle.place",
                                                             GameStrings.text($0.nameKey)) } ?? GameStrings.text("outing.settle.home"))
                             + "  " + key(.confirm))
                            .font(.system(size: 14, weight: .heavy))
                    }.buttonStyle(MintButtonStyle()).fixedSize().accessibilityIdentifier("outingSettleMain")
                }
            }
            .padding(20).frame(width: 760)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white, lineWidth: 3))
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal).accessibilityIdentifier("outingSettlement")
        }
    }
}

// MARK: Shared pieces

/// Dims what's behind and blocks its clicks; the card on top is the only thing that answers.
struct MacModalScrim<Content: View>: View {
    var opacity: Double = 0.26
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            RoomTheme.ink.opacity(opacity).contentShape(Rectangle()).onTapGesture {}.accessibilityHidden(true)
            content
        }
    }
}

struct MacFootprints: View {
    let total: Int
    let left: Int
    var size: CGFloat = 16
    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(0..<max(0, total), id: \.self) { index in
                Image(systemName: "pawprint.fill").font(.system(size: size, weight: .bold))
                    .foregroundStyle(index < left ? RoomTheme.mint : RoomTheme.track)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.format("outing.footprintsLeft", left)).accessibilityValue("\(left)/\(total)")
    }
}

/// Wrapping capsules for short labels.
struct OutingChips: View {
    let items: [String]
    var tint: Color = RoomTheme.darkMint
    var background: Color = RoomTheme.paleMint
    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(background, in: Capsule())
            }
        }
    }
}

struct MacOutingLootChips: View {
    let loot: [OutingLoot]
    var body: some View {
        if loot.isEmpty {
            Text(GameStrings.text("outing.loot.empty")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
        } else {
            FlowLayout(spacing: 5) {
                ForEach(loot) { item in
                    HStack(spacing: 4) {
                        GameIcon(asset: MacOutingText.asset(item), symbol: MacOutingText.symbol(item), size: 14, tint: MacOutingText.tint(item))
                        Text(MacOutingText.name(item)).font(.system(size: 11, weight: .heavy)).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(MacOutingText.tint(item).opacity(0.13), in: Capsule())
                }
            }
        }
    }
}

struct MacOutingLootRow: View {
    let loot: OutingLoot
    var body: some View {
        HStack(spacing: 8) {
            GameIcon(asset: MacOutingText.asset(loot), symbol: MacOutingText.symbol(loot), size: 26, tint: MacOutingText.tint(loot))
                .frame(width: 34, height: 34).background(MacOutingText.tint(loot).opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(MacOutingText.name(loot)).font(.system(size: 12.5, weight: .heavy))
                Text(MacOutingText.lootDetail(loot)).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// O4 keepsake card and O7 decor card.
struct MacOutingLootDetail: View {
    let loot: OutingLoot
    let catName: String
    let reactionKey: String?
    let outing: OutingState?
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let roll = loot.roll {
                    Circle().fill(MacOutingText.qualityTint(roll.quality).opacity(0.22)).frame(width: 104, height: 104)
                    Circle().strokeBorder(MacOutingText.qualityTint(roll.quality), lineWidth: 3).frame(width: 92, height: 92)
                } else {
                    Circle().fill(MacOutingText.tint(loot).opacity(0.14)).frame(width: 96, height: 96)
                }
                GameIcon(asset: MacOutingText.asset(loot), symbol: MacOutingText.symbol(loot), size: 60, tint: MacOutingText.tint(loot))
            }
            Text(MacOutingText.kicker(loot)).font(.system(size: 11, weight: .heavy)).foregroundStyle(MacOutingText.tint(loot))
            Text(MacOutingText.name(loot)).font(.system(size: 19, weight: .heavy))
            if let roll = loot.roll {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(GameStrings.text(roll.quality.titleKey)).font(.system(size: 11.5, weight: .heavy))
                            .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(MacOutingText.qualityTint(roll.quality), in: Capsule())
                        Text(MacOutingText.attribute(roll)).font(.system(size: 13, weight: .heavy))
                        Spacer(minLength: 0)
                    }
                    MacCapsuleProgress(value: Double(roll.value - roll.attribute.range.lowerBound + 1),
                                       total: Double(roll.attribute.range.count), tint: MacOutingText.qualityTint(roll.quality))
                    Text(MacOutingText.range(roll.attribute)).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                }
                .padding(10).background(RoomTheme.cream.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            }
            Text(MacOutingText.lootStory(loot, catName: catName, reactionKey: reactionKey))
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if loot.kind == .keepsake, let outing {
                Text(GameStrings.format("outing.result.albumProgress", outing.foundKeepsakeCount, OutingCatalog.keepsakes.count))
                    .font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
            }
        }
    }
}

/// Text helpers shared by the garden and the album.
@MainActor
enum MacOutingText {
    static func name(_ loot: OutingLoot) -> String {
        switch loot.kind {
        case .keepsake: return loot.itemID.flatMap(OutingCatalog.keepsake(id:)).map { GameStrings.text($0.nameKey) } ?? ""
        case .decor: return loot.itemID.flatMap(OutingCatalog.decor(id:)).map { GameStrings.text($0.nameKey) } ?? ""
        case .gold: return GameStrings.format("outing.effect.gold", loot.gold)
        }
    }
    static func asset(_ loot: OutingLoot) -> String {
        switch loot.kind {
        case .keepsake: return loot.itemID.map { "keepsake-\($0)" } ?? ""
        case .decor: return loot.itemID.flatMap(OutingCatalog.decor(id:)).map { FurnitureCatalog.metadata(for: $0.kind).assetName } ?? ""
        case .gold: return "icon-coin"
        }
    }
    static func symbol(_ loot: OutingLoot) -> String {
        switch loot.kind {
        case .keepsake: return loot.itemID.flatMap(OutingCatalog.keepsake(id:))?.symbol ?? "star.fill"
        case .decor: return loot.itemID.flatMap(OutingCatalog.decor(id:))?.symbol ?? "sofa.fill"
        case .gold: return "circle.circle.fill"
        }
    }
    static func tint(_ loot: OutingLoot) -> Color {
        switch loot.kind {
        case .keepsake: return RoomTheme.friendshipDeep
        case .decor: return loot.roll.map { qualityTint($0.quality) } ?? RoomTheme.darkMint
        case .gold: return RoomTheme.gold
        }
    }
    static func qualityTint(_ quality: OutingDecorQuality) -> Color {
        switch quality {
        case .common: return RoomTheme.mint
        case .fine: return RoomTheme.sky
        case .treasured: return RoomTheme.gold
        }
    }
    static func kicker(_ loot: OutingLoot) -> String {
        switch loot.kind {
        case .keepsake: return GameStrings.text(loot.duplicate ? "outing.kicker.keepsakeAgain" : "outing.kicker.keepsake")
        case .decor: return GameStrings.text(loot.duplicate ? "outing.kicker.decorAgain" : "outing.kicker.decor")
        case .gold: return GameStrings.text("outing.kicker.gold")
        }
    }
    static func lootDetail(_ loot: OutingLoot) -> String {
        switch loot.kind {
        case .keepsake:
            return loot.duplicate ? GameStrings.format("outing.loot.keepsakeAgain", loot.gold) : GameStrings.text("outing.loot.keepsakeNew")
        case .decor:
            let roll = loot.roll.map { GameStrings.text($0.quality.titleKey) + " · " + attribute($0) } ?? ""
            return loot.duplicate ? roll + " · " + GameStrings.text("outing.loot.decorAgain") : roll
        case .gold: return GameStrings.text("outing.loot.gold")
        }
    }
    static func lootStory(_ loot: OutingLoot, catName: String, reactionKey: String?) -> String {
        switch loot.kind {
        case .keepsake:
            if loot.duplicate { return GameStrings.format("outing.loot.keepsakeAgain", loot.gold) }
            return GameStrings.format(reactionKey ?? "outing.reaction.plain", catName)
        case .decor:
            let base = GameStrings.format(reactionKey ?? "outing.reaction.plain", catName)
            return loot.duplicate ? base + "\n" + GameStrings.text("outing.loot.decorAgainLong") : base
        case .gold: return GameStrings.format("outing.loot.goldStory", catName)
        }
    }
    static func attribute(_ roll: OutingDecorRoll) -> String {
        GameStrings.format("outing.attribute.\(roll.attribute.rawValue).value", roll.value)
    }
    static func range(_ attribute: OutingDecorAttribute) -> String {
        GameStrings.format("outing.attribute.range", attribute.range.lowerBound, attribute.range.upperBound)
    }
    static func effects(_ entry: OutingLogEntry) -> [String] {
        var items: [String] = []
        if entry.catMood > 0 { items.append(GameStrings.format("outing.effect.mood", entry.catMood)) }
        if entry.bond > 0 { items.append(GameStrings.format("outing.effect.bond", entry.bond)) }
        if entry.friendship > 0, let id = entry.neighborID {
            items.append(GameStrings.format("outing.effect.friendship", neighborName(id), entry.friendship))
        }
        if entry.gold > 0 { items.append(GameStrings.format("outing.effect.gold", entry.gold)) }
        if entry.refundedFootprint { items.append(GameStrings.text("outing.effect.refund")) }
        return items.isEmpty ? [GameStrings.text("outing.effect.quiet")] : items
    }
    static func logLine(_ entry: OutingLogEntry, trip: OutingTrip) -> String {
        let spot = GameStrings.text(entry.spot.titleKey)
        switch entry.kind {
        case .find:
            let loot = entry.lootID.flatMap { id in trip.loot.first { $0.id == id } }
            return spot + " · " + (loot.map { name($0) + (($0.duplicate) ? " · " + GameStrings.text("outing.log.again") : "") } ?? "")
        case .event:
            return spot + " · " + (entry.eventID.flatMap(OutingCatalog.event(id:)).map { GameStrings.text($0.titleKey) } ?? "")
                + " · " + GameStrings.text("outing.log.waiting")
        case .outcome:
            let title = entry.eventID.flatMap(OutingCatalog.event(id:)).map { GameStrings.text($0.titleKey) } ?? ""
            return spot + " · " + title + " · " + effects(entry).joined(separator: " ")
        case .nothing:
            return spot + " · " + effects(entry).joined(separator: " ")
        }
    }
    static func neighborName(_ id: String) -> String {
        CommunityCatalog.neighbor(id: id).map { GameStrings.text($0.nameKey) } ?? id
    }
    static func knownHabits(_ cat: CatState) -> [String] {
        guard let definition = CatHabitCatalog.definition(for: cat.id) else { return [] }
        let habits: [OutingHabit] = [.style(definition.style), .play(definition.play), .rest(definition.rest)]
        return habits.filter { $0.isKnown(for: cat) }.map { GameStrings.text("outing.habit.\($0.key)") }
    }
}

/// The garden: a painted placeholder until `outing-garden-map` is delivered.
struct MacGardenScene: View {
    var highlight: OutingSpot?

    static func position(_ spot: OutingSpot) -> CGPoint {
        switch spot {
        case .flowerBed: CGPoint(x: 0.2, y: 0.6)
        case .treeShade: CGPoint(x: 0.52, y: 0.36)
        case .path: CGPoint(x: 0.8, y: 0.64)
        }
    }
    static func symbol(_ spot: OutingSpot) -> String {
        switch spot {
        case .flowerBed: "camera.macro"
        case .treeShade: "tree.fill"
        case .path: "point.bottomleft.forward.to.point.topright.scurvepath.fill"
        }
    }
    static func tint(_ spot: OutingSpot) -> Color {
        switch spot {
        case .flowerBed: RoomTheme.friendship
        case .treeShade: RoomTheme.darkMint
        case .path: RoomTheme.gold
        }
    }
    static func isEvening(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 17 || hour < 6
    }

    var body: some View {
        if UIImage(named: "outing-garden-map") != nil {
            Image("outing-garden-map").resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        } else {
            TimelineView(.periodic(from: .now, by: 300)) { clock in
                placeholder(evening: Self.isEvening(clock.date))
            }
        }
    }

    private func placeholder(evening: Bool) -> some View {
        Canvas { context, size in
            let w = size.width, h = size.height, unit = min(w, h)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            var seed: UInt64 = 0x6A7D_E115
            func random() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.80, green: 0.92, blue: 0.97), Color(red: 0.93, green: 0.96, blue: 0.88)]),
                startPoint: .zero, endPoint: p(0, 0.3)))
            var lawn = Path()
            lawn.move(to: p(0, 0.24))
            lawn.addCurve(to: p(1, 0.22), control1: p(0.3, 0.18), control2: p(0.7, 0.28))
            lawn.addLine(to: p(1, 1)); lawn.addLine(to: p(0, 1)); lawn.closeSubpath()
            context.fill(lawn, with: .linearGradient(Gradient(colors: [Color(red: 0.74, green: 0.87, blue: 0.64), Color(red: 0.66, green: 0.82, blue: 0.56)]),
                                                     startPoint: p(0, 0.2), endPoint: p(0, 1)))
            for _ in 0..<70 {
                let c = p(random(), 0.3 + random() * 0.7), r = unit * 0.005
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(Color(red: 0.52, green: 0.72, blue: 0.46).opacity(0.7)))
            }
            // The winding path to the right.
            var path = Path()
            path.move(to: p(0.62, 1.02))
            path.addCurve(to: p(0.8, 0.62), control1: p(0.68, 0.85), control2: p(0.88, 0.76))
            path.addCurve(to: p(0.58, 0.3), control1: p(0.72, 0.5), control2: p(0.6, 0.42))
            context.stroke(path, with: .color(Color(red: 0.93, green: 0.85, blue: 0.68)), style: StrokeStyle(lineWidth: unit * 0.09, lineCap: .round))
            for index in 0..<9 {
                let t = CGFloat(index) / 9
                let c = p(0.64 + 0.18 * sin(t * 3.0), 0.95 - t * 0.6), r = unit * 0.012
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4)),
                             with: .color(Color(red: 0.80, green: 0.74, blue: 0.62)))
            }
            // The flower bed on the left.
            let bed = CGRect(x: 0.05 * w, y: 0.5 * h, width: 0.3 * w, height: 0.22 * h)
            context.fill(Path(ellipseIn: bed), with: .color(Color(red: 0.62, green: 0.47, blue: 0.33)))
            context.fill(Path(ellipseIn: bed.insetBy(dx: unit * 0.012, dy: unit * 0.012)), with: .color(Color(red: 0.56, green: 0.74, blue: 0.45)))
            let flowers = [Color(red: 0.98, green: 0.72, blue: 0.80), Color(red: 1, green: 0.88, blue: 0.48), .white, Color(red: 0.78, green: 0.70, blue: 0.96)]
            for index in 0..<34 {
                let c = CGPoint(x: bed.minX + bed.width * (0.12 + random() * 0.76), y: bed.minY + bed.height * (0.18 + random() * 0.64))
                let r = unit * 0.011
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(flowers[index % 4]))
            }
            // The big tree and its shade.
            context.fill(Path(ellipseIn: CGRect(x: 0.36 * w, y: 0.44 * h, width: 0.32 * w, height: 0.12 * h)),
                         with: .color(Color(red: 0.45, green: 0.64, blue: 0.40).opacity(0.55)))
            context.fill(Path(CGRect(x: 0.505 * w, y: 0.26 * h, width: 0.03 * w, height: 0.24 * h)), with: .color(Color(red: 0.55, green: 0.38, blue: 0.24)))
            for (x, y, r) in [(0.44, 0.2, 0.11), (0.6, 0.2, 0.1), (0.52, 0.11, 0.12), (0.5, 0.26, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
                context.fill(Path(ellipseIn: CGRect(x: x * w - r * unit, y: y * h - r * unit, width: r * unit * 2, height: r * unit * 2)),
                             with: .color(Color(red: 0.36, green: 0.60, blue: 0.38)))
            }
            // A bench under the tree.
            context.fill(Path(roundedRect: CGRect(x: 0.6 * w, y: 0.42 * h, width: 0.1 * w, height: 0.025 * h), cornerRadius: 3),
                         with: .color(Color(red: 0.70, green: 0.50, blue: 0.30)))
            if evening {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.98, green: 0.62, blue: 0.40).opacity(0.16)))
            }
        }
        .overlay {
            if let highlight {
                GeometryReader { proxy in
                    Circle().fill(Self.tint(highlight).opacity(0.18)).frame(width: proxy.size.height * 0.36, height: proxy.size.height * 0.36)
                        .position(x: Self.position(highlight).x * proxy.size.width, y: (Self.position(highlight).y + 0.08) * proxy.size.height)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
#endif
