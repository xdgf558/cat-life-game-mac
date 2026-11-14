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
        HStack(alignment: .top, spacing: 14) {
            directory.frame(width: 250)
            if let cat = selected {
                ownedDetail(cat).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(GameStrings.format("mac.cats.ownedCount", cats.count)).font(.system(size: 14, weight: .heavy))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cats) { cat in ownedRow(cat) }
                    Label(GameStrings.text((store.snapshot?.home.roomLevel ?? 1) >= 4 ? "mac.cats.sharedUnlocked" : "mac.cats.sharedLocked"), systemImage: "house.fill")
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    if !offers.isEmpty {
                        Text(GameStrings.format("mac.cats.availableCount", offers.count)).font(.system(size: 11.5, weight: .heavy))
                            .foregroundStyle(RoomTheme.secondary).padding(.top, 6)
                        ForEach(offers) { offer in offerRow(offer) }
                    }
                }
            }
            HStack(spacing: 6) {
                Button { moveSelection(-1) } label: { Text(keyLabel(.listUp)) }
                    .accessibilityLabel(GameStrings.text("mac.content.previous"))
                Button { moveSelection(1) } label: { Text(keyLabel(.listDown)) }
                    .accessibilityLabel(GameStrings.text("mac.content.next"))
                Text(GameStrings.text("mac.cats.choose")).font(.caption).foregroundStyle(RoomTheme.secondary)
            }.controlSize(.small)
        }.macContentCard69(padding: 12).frame(maxHeight: .infinity)
    }

    private func ownedRow(_ cat: CatState) -> some View {
        let active = store.cat?.id == cat.id
        return Button { selectedID = cat.id } label: {
            HStack(spacing: 9) {
                CatCollectionPortrait(appearance: cat.appearance, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(GameStrings.catName(cat)).font(.system(size: 14, weight: .heavy)).lineLimit(1)
                        if active { Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(RoomTheme.mint) }
                    }
                    Text(CatProfileView.status(for: cat)).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                    if active {
                        Text(GameStrings.text("mac.cats.companion") + " · " + GameStrings.text("homeFloor.\(store.visibleHomeFloor.rawValue)"))
                            .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.darkMint).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected?.id == cat.id ? RoomTheme.paleMint.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected?.id == cat.id ? RoomTheme.mint : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("macCat_\(cat.id)")
            .accessibilityAddTraits(selected?.id == cat.id ? .isSelected : [])
    }

    private func offerRow(_ offer: CatAdoptionOffer) -> some View {
        let available = store.snapshot.map { CatAdoptionView.conditionsMet(offer, in: $0) == 3 } ?? false
        return Button { selectedID = offer.id } label: {
            HStack(spacing: 9) {
                CatCollectionPortrait(appearance: offer.appearance, size: 42, faded: !available)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.catAdoptionName(offer)).font(.system(size: 14, weight: .heavy)).lineLimit(1)
                    Text(available ? GameStrings.format("cat.adoptionPrice", offer.price)
                         : GameStrings.format("cat.adoptionSummary", offer.requiredPlayerLevel, offer.requiredRoomLevel, offer.price))
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(available ? RoomTheme.darkMint : RoomTheme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: available ? "heart.circle.fill" : "lock.fill").font(.system(size: 13))
                    .foregroundStyle(available ? RoomTheme.mint : RoomTheme.secondary.opacity(0.7))
            }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedID == offer.id ? RoomTheme.paleMint.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selectedID == offer.id ? RoomTheme.mint : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("macAdoption_\(offer.id)")
    }

    // MARK: Owned cat

    /// Identity strip on top, then a 2 × 2 grid (growth · bond, habits · memories) in one scroll
    /// instead of three columns that each scrolled on their own.
    private func ownedDetail(_ cat: CatState) -> some View {
        VStack(spacing: 12) {
            identity(cat)
            ScrollView {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow { growthCard(cat); bondCard(cat) }
                    GridRow { habits(cat); memories(cat) }
                }.padding(.bottom, 6)
            }
        }
    }

    private func identity(_ cat: CatState) -> some View {
        HStack(spacing: 14) {
            CatCollectionPortrait(appearance: cat.appearance, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(GameStrings.catName(cat)).font(.system(size: 24, weight: .heavy)).lineLimit(1)
                        .accessibilityIdentifier("macCatName")
                    Button { renameCat = cat } label: {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                            .frame(width: 26, height: 26).background(RoomTheme.paleMint.opacity(0.75), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(saving || store.isBusy).help(GameStrings.text("catName.edit"))
                    .accessibilityLabel(GameStrings.text("catName.edit")).accessibilityIdentifier("macRenameCat")
                }
                HStack(spacing: 5) { badges(cat) }
                if let definition = CatHabitCatalog.definition(for: cat.id) {
                    Label(GameStrings.text("catHabits.style.\(definition.style.rawValue)"), systemImage: "quote.opening")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Button { bringHome(cat) } label: {
                    Label(GameStrings.text("catGrowth.goHome") + "  " + keyLabel(.confirm), systemImage: "house.fill")
                        .font(.system(size: 14, weight: .heavy))
                }.buttonStyle(MintButtonStyle()).fixedSize()
                    .disabled(saving || store.isBusy).accessibilityIdentifier("macBringCatHome")
                Text(GameStrings.text("catGrowth.goHomeHint")).font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.trailing).lineLimit(2)
            }.frame(width: 210, alignment: .trailing)
        }.macContentCard69(padding: 14)
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
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.1), in: Capsule()).lineLimit(1).fixedSize()
    }

    private func cardTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 14, weight: .heavy))
    }

    private func gridCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .macContentCard69(padding: 14)
    }

    private func growthCard(_ cat: CatState) -> some View {
        gridCard {
            HStack {
                cardTitle(GameStrings.text("catGrowth.growth"), symbol: "leaf.fill")
                Spacer(minLength: 0)
                Image(systemName: "info.circle").font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .help(GameStrings.format("catGrowth.clockHint", CatGrowthCatalog.ageMultiplier))
                    .accessibilityLabel(GameStrings.format("catGrowth.clockHint", CatGrowthCatalog.ageMultiplier))
            }
            if let growth = cat.growthState {
                Text(CatGrowthPresentation.age(growth.ageDays(at: date)))
                    .font(.system(size: 24, weight: .heavy)).foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("macCatAge")
                CatGrowthTimeline(age: growth.ageDays(at: date), stage: growth.stage(at: date))
                Text(CatGrowthPresentation.nextGrowth(growth, at: date)).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RoomTheme.darkMint).fixedSize(horizontal: false, vertical: true)
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    /// Bond progress plus the "time together" record that used to be its own card.
    private func bondCard(_ cat: CatState) -> some View {
        gridCard {
            HStack {
                cardTitle(GameStrings.text("catGrowth.bond"), symbol: "heart.fill")
                Spacer(minLength: 0)
                Text("\(cat.intimacy) / 100").foregroundStyle(RoomTheme.friendshipDeep).font(.system(size: 12, weight: .heavy)).monospacedDigit()
            }
            HStack(spacing: 4) {
                ForEach(CatBondStage.allCases, id: \.self) { stage in bondStep(stage, intimacy: cat.intimacy) }
            }
            Text(CatGrowthPresentation.nextBond(cat.intimacy)).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.friendshipDeep)
                .fixedSize(horizontal: false, vertical: true)
                .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 12))
            if let growth = cat.growthState {
                Divider().padding(.vertical, 2)
                HStack(alignment: .firstTextBaseline) {
                    Label(GameStrings.text("catGrowth.memory"), systemImage: "calendar").font(.system(size: 12.5, weight: .heavy))
                    Spacer(minLength: 6)
                    Text(GameStrings.format("mac.cats.days", growth.companionshipDays(at: date)))
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                }
                Text(GameStrings.text("catGrowth.joined") + " · "
                     + (growth.adoptedAt.map(CatGrowthPresentation.date) ?? GameStrings.text("catGrowth.joinedEarlier")))
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .help(GameStrings.text(growth.isLegacyRecord ? "catGrowth.legacyHint" : "catGrowth.newHint"))
            }
        }
    }

    private func bondStep(_ stage: CatBondStage, intimacy: Int) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                Capsule().fill(RoomTheme.friendshipPaper).overlay(alignment: .leading) {
                    Capsule().fill(RoomTheme.friendship).frame(width: geometry.size.width * CGFloat(min(25, max(0, intimacy - stage.minimumIntimacy))) / 25)
                }
            }.frame(height: 7).accessibilityHidden(true)
            Text(GameStrings.text("catGrowth.bond.\(stage.rawValue)"))
                .font(.system(size: 10, weight: .bold)).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(CatBondStage.stage(for: intimacy) == stage ? RoomTheme.friendshipDeep : RoomTheme.secondary)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private func habits(_ cat: CatState) -> some View {
        if let definition = CatHabitCatalog.definition(for: cat.id) {
            gridCard {
                cardTitle(GameStrings.text("catHabits.title"), symbol: "magnifyingglass")
                habitRow("catHabits.rest", value: cat.habits.restConfirmed ? "catHabits.restConfirmed.\(definition.rest.rawValue)" : "catHabits.learning",
                         count: cat.habits.restClueSessionIDs.count, confirmed: cat.habits.restConfirmed, symbol: "moon.stars.fill", tint: RoomTheme.lilac)
                habitRow("catHabits.play", value: cat.habits.playConfirmed ? "catHabits.playConfirmed.\(definition.play.rawValue)" : "catHabits.learning",
                         count: cat.habits.playClueSessionIDs.count, confirmed: cat.habits.playConfirmed, symbol: "tennisball.fill", tint: RoomTheme.friendship)
                corner(cat)
            }
        } else {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        }
    }

    private func habitRow(_ key: String, value: String, count: Int, confirmed: Bool, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(GameStrings.text(key)).font(.system(size: 10.5, weight: .bold)).foregroundStyle(tint)
                Text(GameStrings.text(value)).font(.system(size: 13, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                Text(confirmed ? GameStrings.text("habit68.clues.confirmed") : GameStrings.format("catHabits.clues", count))
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<CatHabitCatalog.cluesToConfirm, id: \.self) { i in
                    Circle().fill(i < count ? tint : RoomTheme.track).frame(width: 8, height: 8)
                }
            }.accessibilityHidden(true)
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityElement(children: .combine)
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
        gridCard {
            cardTitle(GameStrings.format("habit68.memories.count", cat.habits.memories.count, CatMemoryKind.allCases.count), symbol: "photo.fill")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                ForEach(CatMemoryKind.allCases, id: \.self) { kind in memoryTile(HabitMemorySlot68(kind: kind, cat: cat)) }
            }
            pinnedGuide(cat)
        }
    }

    private func memoryTile(_ slot: HabitMemorySlot68) -> some View {
        let tint = HabitMemorySlot68.tint(for: slot.kind), empty = slot.memory == nil
        return Button { memory = slot.memory } label: {
            HStack(spacing: 7) {
                Image(systemName: empty ? "questionmark" : HabitMemorySlot68.symbol(for: slot.kind))
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(empty ? RoomTheme.track : tint)
                    .frame(width: 26, height: 26)
                    .background(empty ? RoomTheme.track.opacity(0.25) : tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                Text(slot.title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(empty ? RoomTheme.secondary : RoomTheme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }.padding(5).frame(maxWidth: .infinity)
                .background(empty ? .clear : .white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(empty ? RoomTheme.track : .clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: empty ? [4, 3] : [])))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(empty).accessibilityIdentifier("macMemory_\(slot.kind.rawValue)")
            .accessibilityLabel(slot.title)
    }

    private func pinnedGuide(_ cat: CatState) -> some View {
        Button { showsGuide = true } label: {
            HStack(spacing: 9) {
                Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(RoomTheme.sky)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.text("habit67.pinTitle")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    Text(cat.habits.pinnedMemory.map { GameStrings.text(CompanionshipPresentation.guideKey(for: $0)) }
                         ?? GameStrings.text("habit68.guide.none")).font(.system(size: 12, weight: .heavy)).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }.padding(9).background(RoomTheme.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
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

    // MARK: Adoption

    /// Portrait on the left, name, conditions and the adopt button on the right, centred in the card.
    private func adoption(_ offer: CatAdoptionOffer) -> some View {
        let ready = store.snapshot.map { CatAdoptionView.conditionsMet(offer, in: $0) == 3 } ?? false
        return HStack(spacing: 32) {
            CatCollectionPortrait(appearance: offer.appearance, size: 180, faded: !ready)
            VStack(alignment: .leading, spacing: 12) {
                Text(GameStrings.catAdoptionName(offer)).font(.system(size: 30, weight: .heavy))
                Text(GameStrings.catDescription(offer.appearance)).font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    requirement("cat.adoptionWorkLevelTitle", have: store.snapshot?.player.level ?? 1, need: offer.requiredPlayerLevel, symbol: "briefcase.fill")
                    requirement("cat.adoptionRoomLevelTitle", have: store.snapshot?.home.roomLevel ?? 1, need: offer.requiredRoomLevel, symbol: "house.fill")
                    requirement("cat.adoptionFeeTitle", have: store.snapshot?.player.gold ?? 0, need: offer.price, symbol: "dollarsign.circle.fill")
                }
                Button { confirmsAdoption = true } label: {
                    Label(GameStrings.format("cat.adoptionPrice", offer.price) + "  " + keyLabel(.confirm), systemImage: "heart.fill")
                        .font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).disabled(!ready || saving || store.isBusy)
                    .accessibilityIdentifier("macConfirmAdoption")
                Text(GameStrings.text("cat.adoptionHint")).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .macContentCard69(padding: 24)
    }

    private func requirement(_ key: String, have: Int, need: Int, symbol: String) -> some View {
        let met = have >= need
        return VStack(spacing: 5) {
            Label(GameStrings.text(key), systemImage: met ? "checkmark.circle.fill" : symbol).font(.system(size: 11, weight: .bold))
                .foregroundStyle(met ? RoomTheme.darkMint : RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.75)
            Text("\(have) / \(need)").font(.system(size: 16, weight: .heavy)).monospacedDigit()
                .foregroundStyle(met ? RoomTheme.darkMint : RoomTheme.ink).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(.vertical, 9).padding(.horizontal, 6).frame(maxWidth: .infinity)
            .background(met ? RoomTheme.mint.opacity(0.1) : RoomTheme.track.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
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
