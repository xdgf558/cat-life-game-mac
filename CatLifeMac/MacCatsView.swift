import SwiftUI
import CatGameCore

@MainActor
struct MacCatsView: View {
    let store: GameStore
    var onHome: () -> Void = {}
    var preferences: MacPreferences? = nil
    @State private var selectedID: String?
    @State private var renameCat: CatState?
    @State private var memory: CatMemory?
    @State private var showsGuide = false
    @State private var confirmsAdoption = false
    @State private var saving = false
    @State private var isVisible = false

    private var cats: [CatState] { store.snapshot?.cats ?? [] }
    private var selected: CatState? { cats.first { $0.id == selectedID } ?? (selectedID == nil ? store.cat : nil) }
    private var offers: [CatAdoptionOffer] { CatCatalog.adoptionOffers.filter { offer in !cats.contains { $0.id == offer.id } } }
    private var offer: CatAdoptionOffer? { offers.first { $0.id == selectedID } }
    private var date: Date { store.snapshot?.meta.lastSyncAt ?? store.now }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            directory.frame(width: 270)
            if let cat = selected {
                VStack(spacing: 14) {
                    identity(cat)
                    HStack(alignment: .top, spacing: 14) {
                        growthColumn(cat).frame(maxWidth: .infinity, maxHeight: .infinity)
                        bondColumn(cat).frame(maxWidth: .infinity, maxHeight: .infinity)
                        memories(cat).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let offer { adoption(offer).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macCatsPage")
        .sheet(item: $renameCat) { cat in MacCatNameEditor69(store: store, cat: cat) }
        .sheet(item: $memory) { value in if let cat = selected { memoryDetail(value, cat: cat) } }
        .sheet(isPresented: $showsGuide) { if let cat = selected { HabitGuidePicker68(store: store, cat: cat).frame(width: 560, height: 620) } }
        .confirmationDialog(GameStrings.format("cat.adoptionConfirmTitle", offer.map(GameStrings.catAdoptionName) ?? ""), isPresented: $confirmsAdoption) {
            if let offer {
                Button(GameStrings.text("cat.adoptionConfirm")) { adopt(offer) }
            }
        } message: {
            Text(GameStrings.format("cat.adoptionConfirmBody", offer?.price ?? 0))
        }
        .onAppear { isVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacContentCommand"))) { note in
            guard isVisible, renameCat == nil, memory == nil, !showsGuide, !confirmsAdoption,
                  let raw = note.object as? String, let command = MacCommand(rawValue: raw) else { return }
            switch command {
            case .listUp: moveSelection(-1)
            case .listDown: moveSelection(1)
            case .confirm:
                if let cat = selected { bringHome(cat) }
                else if let offer, let snapshot = store.snapshot, !saving, !store.isBusy,
                        CatAdoptionView.conditionsMet(offer, in: snapshot) == 3 { confirmsAdoption = true }
            default: break
            }
        }
        .onDisappear { isVisible = false }
        .onChange(of: store.saveSceneGeneration) { _, _ in selectedID = nil; memory = nil; renameCat = nil; showsGuide = false; confirmsAdoption = false }
    }

    private var directory: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GameStrings.format("mac.cats.ownedCount", cats.count)).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cats) { cat in ownedRow(cat) }
                    Label(GameStrings.text((store.snapshot?.home.roomLevel ?? 1) >= 4 ? "mac.cats.sharedUnlocked" : "mac.cats.sharedLocked"), systemImage: "house.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    if !offers.isEmpty {
                        Text(GameStrings.format("mac.cats.availableCount", offers.count)).font(.caption.weight(.bold))
                            .foregroundStyle(RoomTheme.secondary).padding(.top, 8)
                        ForEach(offers) { offer in offerRow(offer) }
                    }
                }
            }
            HStack {
                Button { moveSelection(-1) } label: { Text(keyLabel(.listUp)) }
                    .accessibilityLabel(GameStrings.text("mac.content.previous"))
                Button { moveSelection(1) } label: { Text(keyLabel(.listDown)) }
                    .accessibilityLabel(GameStrings.text("mac.content.next"))
                Text(GameStrings.text("mac.cats.choose")).font(.caption).foregroundStyle(RoomTheme.secondary)
            }
        }.macContentCard69(padding: 16).frame(maxHeight: .infinity)
    }

    private func ownedRow(_ cat: CatState) -> some View {
        Button { selectedID = cat.id } label: {
            HStack(spacing: 10) {
                CatCollectionPortrait(appearance: cat.appearance, size: 50)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(GameStrings.catName(cat)).font(.system(size: 15, weight: .heavy))
                        if store.cat?.id == cat.id { Image(systemName: "heart.fill").foregroundStyle(RoomTheme.mint) }
                    }
                    Text(CatProfileView.status(for: cat)).font(.caption).foregroundStyle(RoomTheme.secondary)
                    if store.cat?.id == cat.id {
                        Text(GameStrings.text("mac.cats.companion") + " · " + GameStrings.text("homeFloor.\(store.visibleHomeFloor.rawValue)"))
                            .font(.caption2).foregroundStyle(RoomTheme.darkMint)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected?.id == cat.id ? RoomTheme.paleMint.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected?.id == cat.id ? RoomTheme.mint : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("macCat_\(cat.id)")
            .accessibilityAddTraits(selected?.id == cat.id ? .isSelected : [])
    }

    private func offerRow(_ offer: CatAdoptionOffer) -> some View {
        let available = store.snapshot.map { CatAdoptionView.conditionsMet(offer, in: $0) == 3 } ?? false
        return Button { selectedID = offer.id } label: {
            HStack(spacing: 10) {
                CatCollectionPortrait(appearance: offer.appearance, size: 50)
                VStack(alignment: .leading, spacing: 6) {
                    Text(GameStrings.catAdoptionName(offer)).font(.system(size: 15, weight: .heavy))
                    Text(available ? GameStrings.format("cat.adoptionPrice", offer.price)
                         : GameStrings.format("cat.adoptionSummary", offer.requiredPlayerLevel, offer.requiredRoomLevel, offer.price))
                        .font(.caption).foregroundStyle(available ? RoomTheme.darkMint : RoomTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !available { Image(systemName: "lock.fill").foregroundStyle(RoomTheme.secondary) }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedID == offer.id ? RoomTheme.paleMint.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selectedID == offer.id ? RoomTheme.mint : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("macAdoption_\(offer.id)")
    }

    private func identity(_ cat: CatState) -> some View {
        HStack(spacing: 22) {
            CatCollectionPortrait(appearance: cat.appearance, size: 116)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(GameStrings.catName(cat)).font(.system(size: 30, weight: .heavy)).accessibilityIdentifier("macCatName")
                    Button { renameCat = cat } label: { Label(GameStrings.text("catName.edit"), systemImage: "pencil") }
                        .buttonStyle(.plain).foregroundStyle(RoomTheme.secondary).disabled(saving || store.isBusy)
                        .accessibilityIdentifier("macRenameCat")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) { badges(cat) }
                    VStack(alignment: .leading, spacing: 5) { badges(cat) }
                }
                if let definition = CatHabitCatalog.definition(for: cat.id) {
                    Label(GameStrings.text("catHabits.style.\(definition.style.rawValue)"), systemImage: "quote.opening")
                        .font(.caption).foregroundStyle(RoomTheme.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 8) {
                Button { bringHome(cat) } label: {
                    Label(GameStrings.text("catGrowth.goHome") + "  " + keyLabel(.confirm), systemImage: "house.fill")
                }.buttonStyle(MintButtonStyle())
                    .disabled(saving || store.isBusy).accessibilityIdentifier("macBringCatHome")
                Text(GameStrings.text("catGrowth.goHomeHint")).font(.caption2).foregroundStyle(RoomTheme.secondary)
            }.frame(width: 200)
        }.macContentCard69(padding: 20)
    }

    @ViewBuilder private func badges(_ cat: CatState) -> some View {
        badge(GameStrings.text("hospital.coat.\(cat.appearance.rawValue)"), tint: RoomTheme.secondary)
        if let growth = cat.growthState {
            badge(GameStrings.text("catGrowth.sex.\(growth.sex.rawValue)"), tint: RoomTheme.sky)
            badge(GameStrings.text("catGrowth.stage.\(growth.stage(at: date).rawValue)"), tint: RoomTheme.darkMint)
        }
        badge(GameStrings.text("catGrowth.bond.\(CatBondStage.stage(for: cat.intimacy).rawValue)"), tint: RoomTheme.friendshipDeep)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(tint).padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.1), in: Capsule())
    }

    private func growthColumn(_ cat: CatState) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if let growth = cat.growthState {
                    growthCard(growth)
                    historyCard(growth)
                }
            }
        }
    }

    private func growthCard(_ growth: CatGrowthState) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(GameStrings.text("catGrowth.growth"), systemImage: "leaf.fill").font(.headline)
            Text(CatGrowthPresentation.age(growth.ageDays(at: date)))
                .font(.system(size: 27, weight: .heavy)).foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("macCatAge")
            CatGrowthTimeline(age: growth.ageDays(at: date), stage: growth.stage(at: date))
            Text(CatGrowthPresentation.nextGrowth(growth, at: date)).foregroundStyle(RoomTheme.darkMint)
                .padding(12).background(RoomTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            Text(GameStrings.format("catGrowth.clockHint", CatGrowthCatalog.ageMultiplier)).font(.caption).foregroundStyle(RoomTheme.secondary)
        }.macContentCard69(padding: 15)
    }

    private func historyCard(_ growth: CatGrowthState) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(GameStrings.text("catGrowth.memory"), systemImage: "calendar").font(.headline)
            Text(GameStrings.text("catGrowth.joined")).font(.caption).foregroundStyle(RoomTheme.secondary)
            Text(growth.adoptedAt.map(CatGrowthPresentation.date) ?? GameStrings.text("catGrowth.joinedEarlier")).font(.headline)
            Text(GameStrings.format("mac.cats.days", growth.companionshipDays(at: date))).font(.headline).foregroundStyle(RoomTheme.darkMint)
            Text(GameStrings.text(growth.isLegacyRecord ? "catGrowth.legacyHint" : "catGrowth.newHint"))
                .font(.caption).foregroundStyle(RoomTheme.secondary)
        }.macContentCard69(padding: 15)
    }

    private func bondColumn(_ cat: CatState) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label(GameStrings.text("catGrowth.bond"), systemImage: "heart.fill").font(.headline)
                        Spacer(minLength: 0)
                        Text("\(cat.intimacy) / 100").foregroundStyle(RoomTheme.friendshipDeep).font(.caption.weight(.heavy))
                    }
                    HStack(spacing: 4) {
                        ForEach(CatBondStage.allCases, id: \.self) { stage in bondStep(stage, intimacy: cat.intimacy) }
                    }
                    Text(CatGrowthPresentation.nextBond(cat.intimacy)).font(.caption).foregroundStyle(RoomTheme.friendshipDeep)
                        .padding(12).background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 14))
                }.macContentCard69(padding: 15)
                habits(cat)
            }
        }
    }

    private func bondStep(_ stage: CatBondStage, intimacy: Int) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                Capsule().fill(RoomTheme.friendshipPaper).overlay(alignment: .leading) {
                    Capsule().fill(RoomTheme.friendship).frame(width: geometry.size.width * CGFloat(min(25, max(0, intimacy - stage.minimumIntimacy))) / 25)
                }
            }.frame(height: 8).accessibilityHidden(true)
            Text(GameStrings.text("catGrowth.bond.\(stage.rawValue)"))
                .font(.system(size: 10, weight: .bold)).multilineTextAlignment(.center)
                .foregroundStyle(CatBondStage.stage(for: intimacy) == stage ? RoomTheme.friendshipDeep : RoomTheme.secondary)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private func habits(_ cat: CatState) -> some View {
        if let definition = CatHabitCatalog.definition(for: cat.id) {
            VStack(alignment: .leading, spacing: 14) {
                Label(GameStrings.text("catHabits.title"), systemImage: "magnifyingglass").font(.headline)
                habitRow("catHabits.rest", value: cat.habits.restConfirmed ? "catHabits.restConfirmed.\(definition.rest.rawValue)" : "catHabits.learning",
                         count: cat.habits.restClueSessionIDs.count, confirmed: cat.habits.restConfirmed, symbol: "moon.stars.fill", tint: RoomTheme.lilac)
                habitRow("catHabits.play", value: cat.habits.playConfirmed ? "catHabits.playConfirmed.\(definition.play.rawValue)" : "catHabits.learning",
                         count: cat.habits.playClueSessionIDs.count, confirmed: cat.habits.playConfirmed, symbol: "tennisball.fill", tint: RoomTheme.friendship)
                corner(cat)
            }.macContentCard69(padding: 15)
        }
    }

    private func habitRow(_ key: String, value: String, count: Int, confirmed: Bool, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(GameStrings.text(key), systemImage: symbol).font(.caption).foregroundStyle(tint)
            Text(GameStrings.text(value)).font(.system(size: 14, weight: .heavy))
            HStack {
                Text(confirmed ? GameStrings.text("habit68.clues.confirmed") : GameStrings.format("catHabits.clues", count))
                    .font(.caption2).foregroundStyle(RoomTheme.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(0..<CatHabitCatalog.cluesToConfirm, id: \.self) { i in
                        Circle().fill(i < count ? tint : RoomTheme.track).frame(width: 9, height: 9)
                    }
                }.accessibilityHidden(true)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func corner(_ cat: CatState) -> some View {
        if let id = cat.habits.cornerFurnitureID,
           let item = store.snapshot?.inventory.furniture.first(where: { $0.id == id }),
           let placement = store.snapshot?.home.furniture.first(where: { $0.itemID == id }) {
            Button { visitCorner(cat, placement: placement) } label: {
                Label(GameStrings.format("habit68.corner", GameStrings.furnitureName(item), GameStrings.text("homeFloor.\(placement.floor.rawValue)")), systemImage: "flag.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.friendshipDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy || saving)
                .accessibilityIdentifier("macVisitCorner")
        } else {
            Label(GameStrings.text("habit68.corner.empty"), systemImage: "flag.fill").font(.caption).foregroundStyle(RoomTheme.secondary)
        }
        if let receipt = cat.habits.lastRestObservation,
           cat.habits.cornerFurnitureID != receipt.furnitureID,
           store.snapshot?.home.furniture.contains(where: { $0.itemID == receipt.furnitureID && $0.floor == receipt.location.floor && $0.position == receipt.location.position }) == true {
            Button(GameStrings.text("catHabits.chooseCorner")) {
                saving = true
                Task { _ = await store.chooseHabitCorner(catID: cat.id, observationID: receipt.id); saving = false }
            }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy || saving)
        }
    }

    private func memories(_ cat: CatState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(GameStrings.format("habit68.memories.count", cat.habits.memories.count, CatMemoryKind.allCases.count), systemImage: "photo.fill").font(.headline)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 2), spacing: 12) {
                    ForEach(CatMemoryKind.allCases, id: \.self) { kind in memoryTile(HabitMemorySlot68(kind: kind, cat: cat)) }
                }.padding(4)
            }
            pinnedGuide(cat)
        }.macContentCard69(padding: 15)
    }

    private func memoryTile(_ slot: HabitMemorySlot68) -> some View {
        Button { memory = slot.memory } label: {
            VStack(spacing: 8) {
                Image(systemName: slot.memory == nil ? "questionmark.circle.fill" : HabitMemorySlot68.symbol(for: slot.kind))
                    .font(.system(size: 25, weight: .semibold)).foregroundStyle(slot.memory == nil ? RoomTheme.track : HabitMemorySlot68.tint(for: slot.kind))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(slot.memory == nil ? .clear : HabitMemorySlot68.tint(for: slot.kind).opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                Text(slot.title).font(.system(size: 11, weight: .bold)).multilineTextAlignment(.center).frame(minHeight: 30)
            }.padding(8).frame(maxWidth: .infinity)
                .background(slot.memory == nil ? .clear : .white, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(slot.memory == nil ? RoomTheme.track : .clear,
                    style: StrokeStyle(lineWidth: 2, dash: slot.memory == nil ? [5, 4] : [])))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).disabled(slot.memory == nil).accessibilityIdentifier("macMemory_\(slot.kind.rawValue)")
            .accessibilityLabel(slot.title)
    }

    private func pinnedGuide(_ cat: CatState) -> some View {
        Button { showsGuide = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill").foregroundStyle(RoomTheme.sky)
                VStack(alignment: .leading, spacing: 7) {
                    Text(GameStrings.text("habit67.pinTitle")).font(.caption).foregroundStyle(RoomTheme.secondary)
                    Text(cat.habits.pinnedMemory.map { GameStrings.text(CompanionshipPresentation.guideKey(for: $0)) }
                         ?? GameStrings.text("habit68.guide.none")).font(.caption.weight(.heavy))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(RoomTheme.darkMint)
            }.padding(12).background(RoomTheme.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(store.isBusy).accessibilityIdentifier("macCatGuide")
    }

    private func memoryDetail(_ value: CatMemory, cat: CatState) -> some View {
        VStack(spacing: 20) {
            Image(systemName: HabitMemorySlot68.symbol(for: value.kind)).font(.system(size: 52)).foregroundStyle(HabitMemorySlot68.tint(for: value.kind))
            Text(GameStrings.text(value.kind.titleKey)).font(.title2.weight(.heavy))
            Text(CompanionshipPresentation.memoryBody(for: value.kind, cat: cat)).multilineTextAlignment(.center)
            Text(CatGrowthPresentation.date(value.createdAt)).font(.caption).foregroundStyle(RoomTheme.secondary)
            Button(GameStrings.text("common.close")) { memory = nil }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
        }.padding(32).frame(width: 460).background(RoomTheme.paper)
    }

    private func adoption(_ offer: CatAdoptionOffer) -> some View {
        let ready = store.snapshot.map { CatAdoptionView.conditionsMet(offer, in: $0) == 3 } ?? false
        return VStack(spacing: 24) {
            Spacer(minLength: 0)
            CatCollectionPortrait(appearance: offer.appearance, size: 230)
            Text(GameStrings.catAdoptionName(offer)).font(.system(size: 34, weight: .heavy))
            Text(GameStrings.catDescription(offer.appearance)).foregroundStyle(RoomTheme.secondary)
            HStack(spacing: 14) {
                requirement("cat.adoptionWorkLevelTitle", have: store.snapshot?.player.level ?? 1, need: offer.requiredPlayerLevel, symbol: "briefcase.fill")
                requirement("cat.adoptionRoomLevelTitle", have: store.snapshot?.home.roomLevel ?? 1, need: offer.requiredRoomLevel, symbol: "house.fill")
                requirement("cat.adoptionFeeTitle", have: store.snapshot?.player.gold ?? 0, need: offer.price, symbol: "dollarsign.circle.fill")
            }
            Text(GameStrings.text("cat.adoptionHint")).font(.caption).foregroundStyle(RoomTheme.secondary).frame(maxWidth: 600).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button { confirmsAdoption = true } label: {
                Label(GameStrings.format("cat.adoptionPrice", offer.price) + "  " + keyLabel(.confirm), systemImage: "heart.fill").frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).disabled(!ready || saving || store.isBusy)
                .accessibilityIdentifier("macConfirmAdoption")
        }.macContentCard69(padding: 30)
    }

    private func requirement(_ key: String, have: Int, need: Int, symbol: String) -> some View {
        VStack(spacing: 12) {
            Label(GameStrings.text(key), systemImage: symbol).font(.caption)
            Text("\(have) / \(need)").font(.title3.weight(.heavy)).monospacedDigit()
        }.padding(16).frame(maxWidth: .infinity)
            .background(have >= need ? RoomTheme.mint.opacity(0.1) : RoomTheme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
    }

    private func bringHome(_ cat: CatState) {
        guard !saving, !store.isBusy else { return }
        let generation = store.saveSceneGeneration
        saving = true
        Task {
            let saved: Bool
            if store.cat?.id == cat.id { saved = true } else { saved = await store.selectCompanion(catID: cat.id) }
            saving = false
            if saved, isVisible, generation == store.saveSceneGeneration { onHome() }
        }
    }

    private func visitCorner(_ cat: CatState, placement: FurniturePlacement) {
        guard !saving, !store.isBusy else { return }
        let generation = store.saveSceneGeneration
        saving = true
        Task {
            guard await store.selectCompanion(catID: cat.id), isVisible, generation == store.saveSceneGeneration else { saving = false; return }
            await store.changeHomeFloor(to: placement.floor)
            saving = false
            guard isVisible, generation == store.saveSceneGeneration, store.visibleHomeFloor == placement.floor,
                  store.snapshot?.home.furniture.first(where: { $0.itemID == placement.itemID }) == placement else { return }
            onHome()
        }
    }

    private func adopt(_ offer: CatAdoptionOffer) {
        guard !saving, !store.isBusy else { return }
        let generation = store.saveSceneGeneration
        saving = true
        Task {
            let saved = await store.adoptCat(catID: offer.id)
            saving = false
            if saved, isVisible, generation == store.saveSceneGeneration { selectedID = offer.id }
        }
    }

    private func keyLabel(_ command: MacCommand) -> String { (preferences?.binding(for: command) ?? command.defaultBinding).label }

    private func moveSelection(_ delta: Int) {
        let ids = cats.map(\.id) + offers.map(\.id)
        guard !ids.isEmpty else { return }
        let index = ids.firstIndex(of: selectedID ?? store.cat?.id ?? "") ?? 0
        selectedID = ids[min(ids.count - 1, max(0, index + delta))]
    }
}

@MainActor
private struct MacCatNameEditor69: View {
    let store: GameStore
    let cat: CatState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var saving = false
    @State private var failed = false
    @State private var generation: UUID

    init(store: GameStore, cat: CatState) {
        self.store = store; self.cat = cat
        _draft = State(initialValue: GameStrings.catName(cat)); _generation = State(initialValue: store.saveSceneGeneration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(GameStrings.text("catName.title")).font(.title2.weight(.heavy))
            Text(GameStrings.text("catName.hint")).foregroundStyle(RoomTheme.secondary)
            TextField(GameStrings.text("catName.placeholder"), text: $draft).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("macCatNameField")
            if failed { Text(GameStrings.text("catName.saveFailed")).foregroundStyle(RoomTheme.coralDeep) }
            HStack {
                Button(GameStrings.text("common.cancel")) { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction)
                Button(GameStrings.text("catName.reset")) { save(nil) }.disabled(saving || store.isBusy)
                Spacer()
                Button(GameStrings.text("catName.save")) { save(draft) }
                    .disabled(saving || store.isBusy || CatNameRules.normalized(draft) == nil).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("macCatNameSave")
            }
        }.padding(26).frame(width: 510).background(RoomTheme.paper).foregroundStyle(RoomTheme.ink)
            .interactiveDismissDisabled(saving).onChange(of: store.saveSceneGeneration) { _, _ in dismiss() }
    }

    private func save(_ value: String?) {
        guard !saving, !store.isBusy, generation == store.saveSceneGeneration else { return }
        saving = true
        Task {
            let saved = await store.renameCat(id: cat.id, to: value)
            saving = false; failed = !saved
            if saved, generation == store.saveSceneGeneration { dismiss() }
        }
    }
}
