#if os(macOS)
import SwiftUI
import CatGameCore

/// Where the magic cottage can send the player.
struct MacMagicExits {
    var town: () -> Void = {}
    var wardrobe: () -> Void = {}
    var garden: () -> Void = {}
    var work: () -> Void = {}
}

/// 3.0 魔法小屋: the cottage hub (M1), the wheel (M2–M5), the crafting table (C1–C4) and the blueprint
/// book (C5). Every number on these screens comes from Core (`CraftCatalog`, `CraftState`).
@MainActor
struct MacMagicCottage: View {
    let store: GameStore
    var exits = MacMagicExits()
    /// 3.1: a blueprint to open on (a goodbye card's "去再做一件"); `opened` tells the caller it was used.
    var opening: String? = nil
    var opened: () -> Void = {}

    enum Mode: Hashable { case hub, wheel, craft, book }
    enum Overlay: Equatable { case spin, exchange, attempt, grants }

    @State private var mode: Mode = .hub
    @State private var overlay: Overlay?
    /// The blueprint shown in the crafting table and the book.
    @State private var selected: String?
    @State private var exchangePick: String?
    @State private var wheelAngle: Double = 0
    @State private var landingAngle: Double = 0
    @State private var spinning = false
    @State private var spinTask: Task<Void, Never>?
    @State private var working = false
    @FocusState private var focused: Bool
    @Environment(\.gameReduceMotionOverride) private var reduceMotion

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }
    private var today: String? { store.snapshot?.tasks.dailyDayKey }

    var body: some View {
        VStack(spacing: 14) {
            MacPlaceBanner(store: store, place: .magic, height: 110, onTown: exits.town) {
                MacSegmented(selection: Binding(get: { mode }, set: { open($0) }), options: [
                    (Mode.hub, GameStrings.text("craft.tab.hub")), (Mode.wheel, GameStrings.text("craft.tab.wheel")),
                    (Mode.craft, GameStrings.text("craft.tab.craft")), (Mode.book, GameStrings.text("craft.tab.book"))
                ]).fixedSize().disabled(spinning || overlay != nil).accessibilityIdentifier("magicTabs")
            }
            Group {
                switch mode {
                case .hub: hub
                case .wheel: MacMagicWheelPage(store: store, angle: wheelAngle, spinning: spinning, spin: spinOrSkip,
                                               exchange: openExchange, back: { open(.hub) })
                case .craft: MacCraftTable(store: store, selected: $selected, working: working, craft: attemptCraft,
                                           exits: exits, openWheel: { open(.wheel) }, openBook: { open(.book) })
                case .book: MacBlueprintBook(store: store, selected: $selected, openCraft: { id in selected = id; open(.craft) },
                                             openWheel: { open(.wheel) }, exchange: openExchange, wardrobe: exits.wardrobe)
                }
            }
            .disabled(overlay != nil).accessibilityHidden(overlay != nil)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .overlay { overlayView }
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear {
            focused = true
            if !craft.unseenGrants.isEmpty { overlay = .grants }
        }
        .onDisappear { spinTask?.cancel() }
        .onChange(of: opening, initial: true) { _, id in
            guard let id else { return }
            opened()
            guard !spinning else { return }
            overlay = nil
            selected = id
            // Uses left: the crafting table. Used up: the book, which lists where to find another copy.
            open(craft.usesLeft(id) > 0 && CraftCatalog.blueprint(id: id)?.isCraftable == true ? .craft : .book)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macMagicEscape)) { _ in back() }
        .onChange(of: store.saveSceneGeneration) { _, _ in
            spinTask?.cancel(); spinning = false; overlay = nil; mode = .hub; selected = nil
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macMagicCottage")
    }

    // MARK: Hub (M1)

    private var hub: some View {
        HStack(alignment: .top, spacing: 16) {
            hubScene.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 14) {
                MacMaterialBag(craft: craft)
                goalCard
                bookPreview
                Spacer(minLength: 0)
            }.frame(width: 320)
        }
    }

    private var hubScene: some View {
        GeometryReader { geometry in
            // The stations shrink with the scene, so a small window still shows all three and the loop strip.
            let icon = max(64, min(112, geometry.size.height * 0.17))
            ZStack(alignment: .bottom) {
                MacCottageBackdrop()
                hubContent(icon: icon)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white, lineWidth: 3))
    }

    private func hubContent(icon: CGFloat) -> some View {
            VStack(spacing: 0) {
                HStack {
                    Label(GameStrings.format("craft.hub.summary", craft.blueprints.values.filter { $0.usesLeft > 0 }.count,
                                             CraftCatalog.craftableBlueprints.count, craft.handmade.count),
                          systemImage: "scroll.fill")
                        .font(.system(size: 12.5, weight: .heavy)).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoomTheme.paper.opacity(0.95), in: Capsule())
                    Spacer()
                }.padding(16)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 14) {
                    station(title: "craft.station.wheel", detail: "craft.station.wheel.detail", key: "W", symbol: "circle.dashed.inset.filled",
                            tint: RoomTheme.lilac, tag: wheelTag, id: "magicStationWheel", icon: icon) { open(.wheel) }
                    station(title: "craft.station.table", detail: "craft.station.table.detail", key: "C", symbol: "hammer.fill",
                            tint: RoomTheme.gold, tag: craft.readyCount > 0 ? GameStrings.format("craft.tag.ready", craft.readyCount) : nil,
                            id: "magicStationTable", icon: icon) { open(.craft) }
                    station(title: "craft.station.wardrobe", detail: "craft.station.wardrobe.detail", key: "R", symbol: "hanger",
                            tint: RoomTheme.friendship, tag: newClothesTag, id: "magicStationWardrobe", icon: icon, action: exits.wardrobe)
                }.padding(.horizontal, 16)
                loopStrip.padding(16)
            }
    }

    private var wheelTag: String? {
        let free = craft.wheel.freeLeft(today: today)
        return free > 0 ? GameStrings.format("craft.tag.free", free) : nil
    }
    private var newClothesTag: String? {
        let unworn = craft.handmade.filter { !craft.isWorn($0.id) && $0.blueprint?.product.slot != nil }.count
        return unworn > 0 ? GameStrings.format("craft.tag.clothes", unworn) : nil
    }

    private func station(title: String, detail: String, key: String, symbol: String, tint: Color, tag: String?, id: String,
                         icon: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(tag ?? " ").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(RoomTheme.coral, in: Capsule()).overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    .opacity(tag == nil ? 0 : 1)
                Image(systemName: symbol).font(.system(size: icon * 0.48, weight: .bold)).foregroundStyle(tint)
                    .frame(width: icon, height: icon)
                    .background(RoomTheme.paper.opacity(0.95), in: Circle())
                    .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 4))
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(tint, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(GameStrings.text(title)).font(.system(size: 16, weight: .black))
                            MacKeyCap(value: key)
                        }
                        Text(GameStrings.text(detail)).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(MacMagicPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GameStrings.text(title)).accessibilityValue(tag ?? "")
        .accessibilityIdentifier(id)
    }

    private var loopStrip: some View {
        let steps: [(String, String)] = [("briefcase.fill", "craft.loop.work"), ("pawprint.fill", "craft.loop.outing"),
                                         ("hammer.fill", "craft.loop.craft"), ("hanger", "craft.loop.wear"), ("pin.fill", "craft.loop.goal")]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    if index > 0 { Image(systemName: "arrow.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.secondary) }
                    Label(GameStrings.text(steps[index].1), systemImage: steps[index].0).font(.system(size: 12, weight: .heavy)).lineLimit(1)
                }
            }
            Text(GameStrings.text("craft.loop.short")).font(.system(size: 12, weight: .heavy))
        }
        .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: .infinity)
        .background(RoomTheme.paper.opacity(0.95), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func goalBlockedText(_ goal: BlueprintDefinition) -> String? {
        switch craft.readiness(for: goal) {
        case .ready, .lacksMaterials: nil
        case .usedUp: GameStrings.text("craft.usedUp")
        case .skillTooLow(let level): GameStrings.format("craft.lockedSkill", level)
        case .neverHeld: GameStrings.text("craft.status.notLearned")
        case .notYetOpen: GameStrings.text("craft.status.decorLater")
        }
    }

    private var goalCard: some View {
        let goal = craft.goalBlueprintID.flatMap(CraftCatalog.blueprint(id:))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(GameStrings.text("craft.goal.title"), systemImage: "pin.fill").font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(RoomTheme.coralDeep)
                Spacer()
                Button { open(.book) } label: {
                    Text(GameStrings.text(goal == nil ? "craft.goal.pick" : "craft.goal.change") + " ›").font(.system(size: 12, weight: .heavy))
                }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("magicGoalChange")
            }
            if let goal {
                HStack(spacing: 10) {
                    MacBlueprintIcon(definition: goal, size: 46, asItem: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(GameStrings.text(goal.nameKey)).font(.system(size: 15, weight: .black))
                        MacBlueprintTags(definition: goal)
                    }
                }
                MacCostRow(definition: goal, craft: craft)
                let missing = craft.shortfall(for: goal)
                if let first = missing.first {
                    Text(GameStrings.format("craft.goal.missing", GameStrings.text(first.material.titleKey), first.count)
                         + " " + GameStrings.text(MacCraftStyle.materialHintKey(first.material)))
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(ExchangePalette.goldInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                } else if craft.readiness(for: goal) == .ready {
                    Button { selected = goal.id; open(.craft) } label: {
                        Label(GameStrings.text("craft.goal.ready"), systemImage: "hammer.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("magicGoalCraft")
                } else if let blocked = goalBlockedText(goal) {
                    // Materials are there but something else stands in the way: say what.
                    Label(blocked, systemImage: "info.circle.fill")
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Text(GameStrings.text("craft.goal.empty")).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.macContentCard69(padding: 16)
    }

    private var bookPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(GameStrings.text("craft.book.title"), systemImage: "book.closed.fill").font(.system(size: 15, weight: .heavy))
                Spacer()
                Button { open(.book) } label: {
                    HStack(spacing: 4) { Text(GameStrings.text("craft.book.open")); MacKeyCap(value: "B") }.font(.system(size: 12, weight: .heavy))
                }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("magicOpenBook")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(CraftCatalog.blueprints) { definition in
                    let held = craft.hasEverHeld(definition.id)
                    MacBlueprintIcon(definition: definition, size: 34, dim: !held)
                        .overlay(alignment: .topTrailing) {
                            if craft.readiness(for: definition) == .ready {
                                Circle().fill(RoomTheme.coral).frame(width: 9, height: 9).overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            }
                        }
                }
            }.accessibilityHidden(true)
        }.macContentCard69(padding: 16)
    }

    // MARK: Overlays

    @ViewBuilder private var overlayView: some View {
        if let overlay {
            ZStack {
                RoomTheme.ink.opacity(0.24).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { if !working { back() } }.accessibilityHidden(true)
                switch overlay {
                case .spin:
                    MacWheelResultCard(store: store, back: { self.overlay = nil; open(.hub) }, again: { self.overlay = nil; spinOrSkip() },
                                       goCraft: { id in self.overlay = nil; selected = id; open(.craft) },
                                       pickBlueprint: { self.overlay = nil; openExchange() })
                case .exchange:
                    MacStardustExchange(store: store, pick: $exchangePick, working: working, confirm: confirmExchange,
                                        cancel: { self.overlay = nil })
                case .attempt:
                    MacCraftResultCard(store: store, working: working, wear: wearCrafted, keep: { self.overlay = nil },
                                       retry: { id in self.overlay = nil; attemptCraft(id) })
                case .grants:
                    grantsCard
                }
            }
            .transition(.opacity)
        }
    }

    private var grantsCard: some View {
        let grants = craft.unseenGrants.compactMap { CraftCatalog.blueprint(id: $0.blueprintID) }
        return VStack(spacing: 14) {
            Image(systemName: "scroll.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(RoomTheme.gold)
                .frame(width: 72, height: 72).background(RoomTheme.gold.opacity(0.14), in: Circle())
            Text(GameStrings.text("craft.grants.title")).font(.system(size: 21, weight: .heavy)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(grants) { definition in
                    HStack(spacing: 10) {
                        MacBlueprintIcon(definition: definition, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GameStrings.format("craft.grants.line", GameStrings.text(definition.nameKey))).font(.system(size: 14, weight: .heavy))
                            Text(MacCraftStyle.sourceText(definition.source, store: store)).font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(RoomTheme.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }.padding(10).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            HStack(spacing: 10) {
                Button { dismissGrants(open: nil) } label: {
                    HStack(spacing: 8) { Text(GameStrings.text("craft.grants.ok")); MacKeyCap(value: "esc") }
                }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
                Button { dismissGrants(open: grants.first?.id) } label: {
                    HStack(spacing: 8) { Image(systemName: "book.closed.fill"); Text(GameStrings.text("craft.grants.look")); MacKeyCap(value: "↩") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("magicGrantsLook")
            }
        }
        .padding(22).frame(width: 420).modifier(MacMagicCardChrome())
        .accessibilityIdentifier("magicGrants")
    }

    // MARK: Actions

    private func open(_ next: Mode) {
        guard !spinning else { return }
        if next == .craft, selected == nil || !(craft.hasEverHeld(selected ?? "")) {
            selected = MacCraftTable.list(craft).first?.id
        }
        if next == .book, selected == nil { selected = craft.goalBlueprintID ?? CraftCatalog.blueprints.first?.id }
        mode = next
        focused = true
    }

    private func back() {
        if spinning { skipSpin(); return }
        if let overlay {
            guard !working else { return }
            if overlay == .grants { dismissGrants(open: nil) } else { self.overlay = nil }
        } else if mode != .hub {
            mode = .hub
        } else {
            exits.town()
        }
        focused = true
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard overlay == nil else { return .ignored }
        if press.key == .space || press.characters == " " {
            guard mode == .wheel else { return .ignored }
            spinOrSkip(); return .handled
        }
        switch press.characters.lowercased() {
        case "w": open(.wheel); return .handled
        case "c": open(.craft); return .handled
        case "b": open(.book); return .handled
        case "r": exits.wardrobe(); return .handled
        default: break
        }
        if mode == .craft || mode == .book, press.key == .upArrow || press.key == .downArrow || press.key == .leftArrow || press.key == .rightArrow {
            let ids = mode == .craft ? MacCraftTable.list(craft).map(\.id) : CraftCatalog.blueprints.map(\.id)
            guard !ids.isEmpty else { return .handled }
            let index = selected.flatMap { ids.firstIndex(of: $0) } ?? 0
            let step = mode == .book && (press.key == .upArrow || press.key == .downArrow) ? 3 : 1
            let forward = press.key == .downArrow || press.key == .rightArrow
            selected = ids[min(ids.count - 1, max(0, index + (forward ? step : -step)))]
            return .handled
        }
        return .ignored
    }

    private func spinOrSkip() {
        if spinning { skipSpin(); return }
        guard !working, overlay == nil || overlay == .spin else { return }
        mode = .wheel
        working = true
        let before = craft.lastSpin?.id
        Task {
            let spun = await store.spinWheel()
            working = false
            guard spun, let result = store.snapshot?.craft.lastSpin, result.id != before else { return }
            let center = MacMagicWheelPage.centerAngle(for: result.prize, seed: result.id)
            let current = wheelAngle.truncatingRemainder(dividingBy: 360)
            let delta = ((360 - center) - current + 720).truncatingRemainder(dividingBy: 360)
            landingAngle = wheelAngle + 360 * 4 + delta
            if reduceMotion {
                wheelAngle = landingAngle; overlay = .spin
                return
            }
            spinning = true
            withAnimation(.timingCurve(0.12, 0.7, 0.2, 1, duration: 2.0)) { wheelAngle = landingAngle }
            spinTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.05))
                guard !Task.isCancelled, spinning else { return }
                spinning = false; overlay = .spin
            }
        }
    }

    /// A second Space (or Esc) jumps straight to the result.
    private func skipSpin() {
        spinTask?.cancel()
        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) { wheelAngle = landingAngle + 360 }
        landingAngle = wheelAngle
        spinning = false
        overlay = .spin
    }

    private func openExchange() {
        exchangePick = MacStardustExchange.options(craft).first { craft.count(of: .stardust) >= $0.tier.stardustPrice }?.id
            ?? MacStardustExchange.options(craft).first?.id
        overlay = .exchange
    }

    private func confirmExchange() {
        guard let id = exchangePick, !working else { return }
        working = true
        Task {
            let done = await store.exchangeStardust(blueprintID: id)
            working = false
            if done { overlay = nil; selected = id }
        }
    }

    private func attemptCraft(_ blueprintID: String) {
        guard !working else { return }
        working = true
        Task {
            let done = await store.craftBlueprint(blueprintID)
            working = false
            if done { overlay = .attempt }
        }
    }

    private func wearCrafted(_ item: HandmadeItem) {
        guard let slot = item.blueprint?.product.slot, !working else { return }
        working = true
        Task {
            let worn = await store.setAppearance(slot: slot, itemID: item.id)
            working = false
            if worn { overlay = nil; exits.wardrobe() }
        }
    }

    private func dismissGrants(open blueprintID: String?) {
        overlay = nil
        Task { await store.markBlueprintGrantsSeen() }
        if let blueprintID { selected = blueprintID; open(.book) }
    }
}

// MARK: - Shared pieces

/// Colours and words shared by the cottage, the crafting table and the wardrobe.
@MainActor
enum MacCraftStyle {
    static func tint(_ material: CraftMaterial) -> Color {
        switch material {
        case .fabric: RoomTheme.coral
        case .thread: RoomTheme.friendship
        case .wood: Color(red: 0.62, green: 0.42, blue: 0.24)
        case .dye: RoomTheme.sky
        case .stardust: RoomTheme.lilac
        }
    }
    static func tint(_ theme: CraftTheme) -> Color {
        switch theme {
        case .garden: RoomTheme.darkMint
        case .cafe: Color(red: 0.70, green: 0.45, blue: 0.20)
        case .starMoon: RoomTheme.lilac
        case .rainy: RoomTheme.sky
        case .winter: Color(red: 0.36, green: 0.52, blue: 0.70)
        case .bazaar: RoomTheme.coralDeep
        }
    }
    static func tint(_ tier: CraftTier) -> Color {
        switch tier {
        case .basic: RoomTheme.secondary
        case .mid: RoomTheme.sky
        case .advanced: RoomTheme.gold
        }
    }
    static func tint(_ quality: OutingDecorQuality) -> Color {
        switch quality {
        case .common: RoomTheme.secondary
        case .fine: RoomTheme.sky
        case .treasured: RoomTheme.gold
        }
    }
    static func materialHintKey(_ material: CraftMaterial) -> String { "craft.material.\(material.rawValue).where" }

    static func productName(_ definition: BlueprintDefinition) -> String {
        if let slot = definition.product.slot { return GameStrings.text("craft.slot.\(slot.rawValue)") }
        return GameStrings.text("craft.slot.decor")
    }

    static func valueText(_ attribute: HandmadeAttribute, _ value: Int) -> String {
        (attribute.isReduction ? "−" : "+") + "\(value)" + (attribute.isPercent ? "%" : "")
    }
    static func rangeText(_ attribute: HandmadeAttribute) -> String {
        let range = attribute.range
        guard range.count > 1 else { return valueText(attribute, range.lowerBound) }
        return (attribute.isReduction ? "−" : "+") + "\(range.lowerBound)~\(range.upperBound)" + (attribute.isPercent ? "%" : "")
    }

    /// How the first copy of a blueprint is earned, with progress where the save knows it.
    static func sourceText(_ source: BlueprintSource, store: GameStore) -> String {
        let snapshot = store.snapshot
        switch source {
        case .gardenWalk: return GameStrings.format("craft.source.gardenWalk", OutingCatalog.footprints)
        case .keepsake(let id):
            return GameStrings.format("craft.source.keepsake", OutingCatalog.keepsake(id: id).map { GameStrings.text($0.nameKey) } ?? id)
        case .friendship(let neighborID, let stage):
            let name = CommunityCatalog.neighbor(id: neighborID).map { GameStrings.text($0.nameKey) } ?? neighborID
            return GameStrings.format("craft.source.friendship", name, GameStrings.text("community.stage.\(stage)"))
        case .cafeNaps(let count):
            return GameStrings.format("craft.source.cafeNaps", count, min(count, snapshot?.craft.cafeNaps ?? 0))
        case .townEvent(let id): return GameStrings.format("craft.source.townEvent", GameStrings.text("townEvents.event.\(id).title"))
        case .rainyOuting: return GameStrings.text("craft.source.rainyOuting")
        case .craftLevel(let level): return GameStrings.format("craft.source.craftLevel", level)
        case .bazaarTrades(let count): return GameStrings.format("craft.source.bazaar", count)
        case .shares(let count): return GameStrings.format("craft.source.shares", count)
        case .shopShelf: return GameStrings.text("craft.source.shop")
        case .luck: return GameStrings.text("craft.source.luck")
        }
    }
}

/// A blueprint drawn as blueprint paper: a blue grid with the item sketched on it in white, so the book and
/// the wheel show the pattern rather than the finished piece. `asItem` shows the finished piece instead
/// (crafting result, wardrobe, the goal you are making). Art is `blueprint-<id>`; the symbol stands in without it.
struct MacBlueprintIcon: View {
    let definition: BlueprintDefinition
    var size: CGFloat = 44
    var dim = false
    var asItem = false
    private var asset: String { "blueprint-\(definition.id)" }
    private var hasArt: Bool { UIImage(named: asset) != nil }

    var body: some View {
        Group {
            if asItem { item } else { paper }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var item: some View {
        GameIcon(asset: asset, symbol: dim ? "questionmark" : definition.symbol, size: size * 0.5,
                 tint: dim ? RoomTheme.secondary.opacity(0.45) : MacCraftStyle.tint(definition.theme))
            .frame(width: size, height: size)
            .background((dim ? RoomTheme.track : MacCraftStyle.tint(definition.theme)).opacity(dim ? 0.5 : 0.16),
                        in: RoundedRectangle(cornerRadius: size * 0.3))
    }

    private var paper: some View {
        let corner = size * 0.24
        let top = dim ? Color(red: 0.55, green: 0.62, blue: 0.72) : Color(red: 0.30, green: 0.55, blue: 0.86)
        let bottom = dim ? Color(red: 0.45, green: 0.52, blue: 0.62) : Color(red: 0.17, green: 0.37, blue: 0.70)
        return ZStack {
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            BlueprintGrid(step: max(4, size / 8)).stroke(.white.opacity(0.17), lineWidth: max(0.5, size / 120))
            if hasArt {
                // A pale silhouette for the shape, then the art in greys screened on top for the pen lines.
                Image(asset).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.white.opacity(0.28)).padding(size * 0.15)
                Image(asset).resizable().scaledToFit().padding(size * 0.15)
                    .grayscale(1).contrast(1.25).brightness(0.12).blendMode(.screen)
            } else {
                Image(systemName: definition.symbol).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }
            RoundedRectangle(cornerRadius: corner * 0.6)
                .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: max(0.8, size * 0.018), dash: [max(2, size * 0.05), max(2, size * 0.035)]))
                .padding(size * 0.06)
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(.white.opacity(0.85), lineWidth: max(1, size * 0.03)))
        .shadow(color: .black.opacity(0.12), radius: 0, y: max(1, size * 0.03))
        .opacity(dim ? 0.6 : 1)
    }
}

/// Faint squares on blueprint paper.
private struct BlueprintGrid: Shape {
    let step: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX + step
        while x < rect.maxX { path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
        var y = rect.minY + step
        while y < rect.maxY { path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
        return path
    }
}

/// Theme · slot · tier chips.
struct MacBlueprintTags: View {
    let definition: BlueprintDefinition
    var body: some View {
        HStack(spacing: 5) {
            tag(GameStrings.text(definition.theme.titleKey), tint: MacCraftStyle.tint(definition.theme))
            tag(MacCraftStyle.productName(definition), tint: RoomTheme.secondary)
            tag(GameStrings.text(definition.tier.titleKey), tint: MacCraftStyle.tint(definition.tier))
        }
    }
    private func tag(_ text: String, tint: Color) -> some View {
        Text(text).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(tint).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3).background(tint.opacity(0.13), in: Capsule())
    }
}

/// Have / need per material, red where short.
struct MacCostRow: View {
    let definition: BlueprintDefinition
    let craft: CraftState
    var body: some View {
        HStack(spacing: 6) {
            ForEach(definition.costs) { cost in
                let have = craft.count(of: cost.material), enough = have >= cost.count
                HStack(spacing: 4) {
                    Image(systemName: cost.material.symbol).font(.system(size: 10, weight: .bold))
                    Text(verbatim: "\(have)/\(cost.count)").font(.system(size: 12, weight: .heavy)).monospacedDigit()
                }
                .foregroundStyle(enough ? RoomTheme.darkMint : RoomTheme.coralDeep)
                .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity)
                .background((enough ? RoomTheme.paleMint : RoomTheme.paleCoral).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(GameStrings.text(cost.material.titleKey) + " \(have) / \(cost.count)")
            }
        }
    }
}

/// The five materials and how many are in the bag. `highlight` marks a missing one.
struct MacMaterialBag: View {
    let craft: CraftState
    var highlight: Set<CraftMaterial> = []
    var picked: CraftMaterial? = nil
    var pick: ((CraftMaterial) -> Void)? = nil
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Label(GameStrings.text("craft.bag.title"), systemImage: "shippingbox.fill").font(.system(size: 15, weight: .heavy))
            HStack(spacing: 6) {
                ForEach(CraftMaterial.allCases) { material in
                    let tile = VStack(spacing: 4) {
                        MacMaterialArt(material: material, size: compact ? 28 : 34)
                        Text(GameStrings.text(material.titleKey)).font(.system(size: 10.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(craft.count(of: material))").font(.system(size: 15, weight: .black)).monospacedDigit()
                    }
                    .padding(.vertical, compact ? 6 : 8).frame(maxWidth: .infinity)
                    .background(highlight.contains(material) ? RoomTheme.paleCoral : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                        picked == material ? RoomTheme.gold : highlight.contains(material) ? RoomTheme.coral : .clear, lineWidth: 2))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(GameStrings.text(material.titleKey)).accessibilityValue("\(craft.count(of: material))")
                    if let pick {
                        Button { pick(material) } label: { tile }.buttonStyle(.plain)
                    } else {
                        tile
                    }
                }
            }
        }.macContentCard69(padding: compact ? 12 : 16).accessibilityIdentifier("magicMaterialBag")
    }
}

/// The cottage room behind the hub and the wheel: `magic-cottage-interior`, or a drawn night sky if the
/// art is missing. Nothing in it moves.
struct MacCottageBackdrop: View {
    var body: some View {
        if UIImage(named: "magic-cottage-interior") != nil {
            // A fill-mode image reports its own (huge) size; hosting it in an overlay of an empty view keeps
            // the backdrop exactly the size it is given, so the page shrinks with the window.
            Color.clear
                .overlay { Image("magic-cottage-interior").resizable().scaledToFill() }
                .clipped()
                .accessibilityHidden(true)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LinearGradient(colors: [Color(red: 0.19, green: 0.15, blue: 0.33), Color(red: 0.33, green: 0.27, blue: 0.53)],
                               startPoint: .top, endPoint: .bottom)
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    Image(systemName: star.2 > 9 ? "star.fill" : "circle.fill").font(.system(size: star.2))
                        .foregroundStyle(star.2 > 9 ? RoomTheme.gold : .white.opacity(0.5))
                        .position(x: size.width * star.0, y: size.height * 0.62 * star.1)
                }
                Circle().fill(Color(red: 0.98, green: 0.93, blue: 0.70).opacity(0.18)).frame(width: 160, height: 160).blur(radius: 18)
                    .position(x: size.width * 0.5, y: size.height * 0.2)
                Image(systemName: "moon.fill").font(.system(size: 46)).foregroundStyle(Color(red: 0.99, green: 0.93, blue: 0.70))
                    .position(x: size.width * 0.5, y: size.height * 0.2)
                LinearGradient(colors: [RoomTheme.wood, Color(red: 0.84, green: 0.64, blue: 0.42)], startPoint: .top, endPoint: .bottom)
                    .frame(height: size.height * 0.36).frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle().fill(Color(red: 0.55, green: 0.36, blue: 0.20)).frame(height: 6)
                    .position(x: size.width / 2, y: size.height * 0.64)
            }
        }
        .accessibilityHidden(true)
    }
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.2, 12), (0.18, 0.55, 4), (0.27, 0.15, 5), (0.36, 0.42, 4), (0.62, 0.32, 5), (0.71, 0.12, 13),
        (0.83, 0.48, 4), (0.9, 0.22, 11), (0.95, 0.6, 4), (0.44, 0.7, 3), (0.12, 0.8, 3), (0.78, 0.78, 3)
    ]
}

/// The paper card with a white rim the cottage's pop-up cards share.
struct MacMagicCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white, lineWidth: 3))
            .compositingGroup()
            .shadow(color: RoomTheme.ink.opacity(0.14), radius: 0, y: 7)
            .shadow(color: RoomTheme.ink.opacity(0.2), radius: 26, y: 14)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}

/// Station buttons sink a little when pressed.
struct MacMagicPressStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(hovering ? 0.02 : 0)
            .onHover { hovering = $0 }
    }
}

extension Notification.Name { static let macMagicEscape = Notification.Name("MacMagicEscape") }
#endif
