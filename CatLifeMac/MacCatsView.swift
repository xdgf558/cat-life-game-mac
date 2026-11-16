import SwiftUI
import CatGameCore

@MainActor
struct MacCatsView: View {
    let store: GameStore
    var onHome: () -> Void = {}
    var preferences: MacPreferences? = nil
    /// True while a card is open; the desktop root sends Escape here to close it.
    @Binding var isNested: Bool
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

    /// 2.52: one slot in the album. Every breed has a fixed numbered card; kittens born at home follow.
    private enum AlbumEntry: Identifiable {
        case owned(CatState), offer(CatAdoptionOffer), station
        var id: String {
            switch self { case .owned(let cat): cat.id; case .offer(let offer): offer.id; case .station: CatCatalog.stationCatID }
        }
    }

    /// Fixed order: the first cat, the adoptable breeds, the Station Cat, then any other cat living here.
    private var entries: [AlbumEntry] {
        func slot(_ id: String) -> CatState? { cats.first { $0.id == id } }
        var list: [AlbumEntry] = []
        if let first = slot(CatCatalog.initialCatID) { list.append(.owned(first)) }
        for offer in CatCatalog.adoptionOffers { list.append(slot(offer.id).map(AlbumEntry.owned) ?? .offer(offer)) }
        list.append(slot(CatCatalog.stationCatID).map(AlbumEntry.owned) ?? .station)
        let listed = Set(list.map(\.id))
        list += cats.filter { !listed.contains($0.id) }.map(AlbumEntry.owned)
        return list
    }
    private var focusedID: String? { selectedID ?? store.cat?.id }
    private var stationMet: Bool { (store.snapshot?.stationCat.timesCaught ?? 0) > 0 }

    var body: some View {
        // A stable container: on a Group the lifecycle modifiers below would attach to each branch, and the
        // detail's own onAppear would close it again the moment it opened.
        ZStack {
            if isNested, let entry = entries.first(where: { $0.id == focusedID }) {
                detail(entry).transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                album.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isNested)
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
        .onAppear { isVisible = true; isNested = false }
        .onReceive(NotificationCenter.default.publisher(for: .macCatsEscape)) { _ in isNested = false }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacContentCommand"))) { note in
            guard isVisible, renameCat == nil, memory == nil, !showsGuide, !confirmsAdoption,
                  let raw = note.object as? String, let command = MacCommand(rawValue: raw) else { return }
            switch command {
            case .listUp: moveSelection(-1)
            case .listDown: moveSelection(1)
            case .confirm:
                if !isNested { if focusedID != nil { isNested = true } }
                else if let cat = selected { bringHome(cat) }
                else if let offer, let snapshot = store.snapshot, !saving, !store.isBusy,
                        CatAdoptionView.conditionsMet(offer, in: snapshot) == 3 { confirmsAdoption = true }
            default: break
            }
        }
        .onDisappear { isVisible = false; isNested = false }
        .onChange(of: store.saveSceneGeneration) { _, _ in
            selectedID = nil; memory = nil; renameCat = nil; showsGuide = false; confirmsAdoption = false; isNested = false
        }
    }

    // MARK: Album

    private var album: some View {
        let all = entries
        let collected = all.filter { if case .owned = $0 { true } else { false } }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(GameStrings.format("mac.album.collected", collected, all.count), systemImage: "books.vertical.fill")
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                HStack(spacing: 4) {
                    ForEach(all) { entry in
                        Capsule().fill(isOwned(entry) ? RoomTheme.mint : RoomTheme.track).frame(width: 18, height: 6)
                    }
                }.accessibilityHidden(true)
                Spacer(minLength: 8)
                Label(GameStrings.text((store.snapshot?.home.roomLevel ?? 1) >= 4 ? "mac.cats.sharedUnlocked" : "mac.cats.sharedLocked"), systemImage: "house.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.darkMint).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(RoomTheme.mint.opacity(0.1), in: Capsule())
                Text(GameStrings.text("mac.album.tapHint")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .lineLimit(1)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)], spacing: 14) {
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, entry in card(entry, number: index + 1) }
                }
                .padding(.horizontal, 2).padding(.vertical, 4)
            }
        }
        .macContentCard69(padding: 16).frame(maxHeight: .infinity, alignment: .top)
    }

    private func isOwned(_ entry: AlbumEntry) -> Bool { if case .owned = entry { true } else { false } }

    private func offerReady(_ offer: CatAdoptionOffer) -> Bool {
        store.snapshot.map { CatAdoptionView.conditionsMet(offer, in: $0) == 3 } ?? false
    }

    /// A collector's card: number, art on the breed's colour, name and one line. Details open on click.
    private func card(_ entry: AlbumEntry, number: Int) -> some View {
        let appearance: CatAppearance, name: String, line: String, lineTint: Color, stamp: (String, Color)?
        var dim = false, silhouette = false
        switch entry {
        case .owned(let cat):
            appearance = cat.appearance; name = GameStrings.catName(cat)
            let companion = store.cat?.id == cat.id
            line = companion ? GameStrings.text("mac.album.companion") : GameStrings.text("hospital.coat.\(cat.appearance.rawValue)")
            lineTint = companion ? RoomTheme.darkMint : RoomTheme.secondary
            stamp = companion ? ("heart.fill", RoomTheme.coral) : ("checkmark.seal.fill", RoomTheme.mint)
        case .offer(let offer):
            let ready = offerReady(offer)
            appearance = offer.appearance; name = GameStrings.catAdoptionName(offer); dim = !ready
            line = ready ? GameStrings.format("mac.album.readyPrice", offer.price)
                : GameStrings.format("mac.album.locked", offer.requiredPlayerLevel, offer.requiredRoomLevel)
            lineTint = ready ? RoomTheme.darkMint : RoomTheme.secondary
            stamp = ready ? ("sparkles", RoomTheme.gold) : ("lock.fill", RoomTheme.secondary.opacity(0.6))
        case .station:
            appearance = .station; silhouette = !stationMet; dim = stationMet
            name = GameStrings.text(stationMet ? "cat.stationName" : "mac.album.unknown")
            line = GameStrings.text(stationMet ? "mac.album.stationAway" : "mac.album.stationRumor")
            lineTint = RoomTheme.secondary
            stamp = ("questionmark", RoomTheme.lilac)
        }
        let focused = focusedID == entry.id
        return Button {
            selectedID = entry.id; isNested = true
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [CatCollectionPalette.background(appearance), RoomTheme.paper],
                                   startPoint: .top, endPoint: .bottom)
                    GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: appearance), symbol: "cat.fill", size: 96)
                        .frame(width: 108, height: 108)
                        .colorMultiply(silhouette ? .black : .white).opacity(silhouette ? 0.55 : 1)
                        .saturation(dim ? 0 : 1).opacity(dim ? 0.55 : 1)
                        .padding(.top, 10)
                }
                .frame(height: 124).clipped()
                .overlay(alignment: .topLeading) {
                    Text("No." + String(format: "%02d", number)).font(.system(size: 10, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(RoomTheme.secondary).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.85), in: Capsule()).padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if let stamp {
                        Image(systemName: stamp.0).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(stamp.1, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2)).padding(8)
                    }
                }
                VStack(spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(line).font(.system(size: 10.5, weight: .bold)).foregroundStyle(lineTint).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 8).padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(RoomTheme.paper)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? RoomTheme.mint
                : isOwned(entry) ? CatCollectionPalette.tint(appearance).opacity(0.35) : .white,
                style: StrokeStyle(lineWidth: focused ? 3 : 2, dash: isOwned(entry) || focused ? [] : [5, 4])))
            .compositingGroup()
            .shadow(color: RoomTheme.ink.opacity(isOwned(entry) ? 0.1 : 0.05), radius: 0, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name).accessibilityValue(line)
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityIdentifier(isOwned(entry) ? "macCat_\(entry.id)" : entry.id == CatCatalog.stationCatID ? "macStationCard" : "macAdoption_\(entry.id)")
    }

    // MARK: Detail

    private func detail(_ entry: AlbumEntry) -> some View {
        let all = entries, index = all.firstIndex { $0.id == entry.id } ?? 0
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { isNested = false } label: {
                    Label(GameStrings.text("mac.album.back"), systemImage: "chevron.left").font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(RoomTheme.darkMint).padding(.horizontal, 11).frame(height: 26)
                        .background(RoomTheme.paper, in: Capsule()).overlay(Capsule().strokeBorder(RoomTheme.mint.opacity(0.3), lineWidth: 1.5))
                        .contentShape(Capsule())
                }.buttonStyle(.plain).fixedSize().help(keyLabel(.escape))
                    .accessibilityIdentifier("macAlbumBack")
                Spacer()
                Text(GameStrings.format("mac.album.position", index + 1, all.count))
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).monospacedDigit()
                Button { moveSelection(-1) } label: { Label(keyLabel(.listUp), systemImage: "chevron.left") }
                    .disabled(index == 0).accessibilityLabel(GameStrings.text("mac.content.previous"))
                Button { moveSelection(1) } label: { Label(keyLabel(.listDown), systemImage: "chevron.right") }
                    .disabled(index == all.count - 1).accessibilityLabel(GameStrings.text("mac.content.next"))
            }.controlSize(.small)
            switch entry {
            case .owned(let cat): ownedDetail(cat).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .offer(let offer): adoption(offer).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .station: stationDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The Station Cat before it lives here: a rumour until first caught, then where to find it again.
    private var stationDetail: some View {
        let hours = Int(StationCatRules.runAwayAfter / 3600)
        return HStack(spacing: 32) {
            GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: .station), symbol: "cat.fill", size: 160)
                .frame(width: 180, height: 180)
                .colorMultiply(stationMet ? .white : .black).opacity(stationMet ? 0.7 : 0.55)
                .background(CatCollectionPalette.background(.station), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(GameStrings.text(stationMet ? "cat.stationName" : "mac.album.unknown")).font(.system(size: 30, weight: .heavy))
                Text(GameStrings.text(stationMet ? "stationCat.card.body" : "mac.album.stationRumorBody"))
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Label(GameStrings.format("stationCat.perk.wage", StationCatRules.wageMultiplier), systemImage: "dollarsign.circle.fill")
                        .foregroundStyle(RoomTheme.darkMint)
                    Label(GameStrings.format("stationCat.perk.hunger", hours), systemImage: "fork.knife")
                        .foregroundStyle(RoomTheme.coralDeep)
                }.font(.system(size: 12.5, weight: .bold))
                Label(GameStrings.text("mac.album.stationHowTo"), systemImage: "leaf.fill")
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                if stationMet, let times = store.snapshot?.stationCat.timesCaught {
                    Text(GameStrings.format("mac.album.stationCaught", times)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RoomTheme.secondary)
                }
            }.frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .macContentCard69(padding: 24)
        .accessibilityIdentifier("macStationDetail")
    }

    // MARK: Owned cat

    /// 2.53: everything on one screen. A slim identity card, then growth · bond and habits · memories as a
    /// compact 2 × 2 grid. The scroll view only matters on very short windows.
    private func ownedDetail(_ cat: CatState) -> some View {
        VStack(spacing: 10) {
            identity(cat)
            ScrollView {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { growthCard(cat); bondCard(cat) }
                    GridRow { habits(cat); memories(cat) }
                }.padding(.bottom, 4)
            }.scrollBounceBehavior(.basedOnSize)
        }
    }

    private func identity(_ cat: CatState) -> some View {
        HStack(spacing: 12) {
            CatCollectionPortrait(appearance: cat.appearance, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(GameStrings.catName(cat)).font(.system(size: 20, weight: .heavy)).lineLimit(1)
                        .accessibilityIdentifier("macCatName")
                    Button { renameCat = cat } label: {
                        Image(systemName: "pencil").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                            .frame(width: 22, height: 22).background(RoomTheme.paleMint.opacity(0.75), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(saving || store.isBusy).help(GameStrings.text("catName.edit"))
                    .accessibilityLabel(GameStrings.text("catName.edit")).accessibilityIdentifier("macRenameCat")
                    HStack(spacing: 4) { badges(cat) }.padding(.leading, 2)
                }
                if let definition = CatHabitCatalog.definition(for: cat.id) {
                    Label(GameStrings.text("catHabits.style.\(definition.style.rawValue)"), systemImage: "quote.opening")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { bringHome(cat) } label: {
                Label(GameStrings.text("catGrowth.goHome") + "  " + keyLabel(.confirm), systemImage: "house.fill")
                    .font(.system(size: 13, weight: .heavy))
            }.buttonStyle(MintButtonStyle()).fixedSize()
                .help(GameStrings.text("catGrowth.goHomeHint"))
                .disabled(saving || store.isBusy).accessibilityIdentifier("macBringCatHome")
                .accessibilityHint(GameStrings.text("catGrowth.goHomeHint"))
        }.macContentCard69(padding: 12)
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
        Text(text).font(.system(size: 10.5, weight: .bold)).foregroundStyle(tint).padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.1), in: Capsule()).lineLimit(1).fixedSize()
    }

    private func cardTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 13, weight: .heavy)).lineLimit(1)
    }

    private func gridCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .macContentCard69(padding: 12)
    }

    private func growthCard(_ cat: CatState) -> some View {
        gridCard {
            HStack(spacing: 6) {
                cardTitle(GameStrings.text("catGrowth.growth"), symbol: "leaf.fill")
                Spacer(minLength: 4)
                if let growth = cat.growthState {
                    Text(CatGrowthPresentation.age(growth.ageDays(at: date)))
                        .font(.system(size: 15, weight: .heavy)).foregroundStyle(RoomTheme.darkMint).lineLimit(1)
                        .accessibilityIdentifier("macCatAge")
                }
                Image(systemName: "info.circle").font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .help(GameStrings.format("catGrowth.clockHint", CatGrowthCatalog.ageMultiplier))
                    .accessibilityLabel(GameStrings.format("catGrowth.clockHint", CatGrowthCatalog.ageMultiplier))
            }
            if let growth = cat.growthState {
                growthTrack(age: growth.ageDays(at: date), stage: growth.stage(at: date))
                Text(CatGrowthPresentation.nextGrowth(growth, at: date)).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RoomTheme.darkMint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The three stages on one thin track: a small node per stage with its name and starting day underneath.
    private func growthTrack(age: Int, stage: CatGrowthStage) -> some View {
        GeometryReader { geometry in
            let axis = CatGrowthTimelineGeometry(width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                Capsule().fill(RoomTheme.track).frame(width: axis.length, height: 4).offset(x: axis.startX, y: 9.5)
                Capsule().fill(RoomTheme.mint).frame(width: max(0, axis.x(forAge: age) - axis.startX), height: 4)
                    .offset(x: axis.startX, y: 9.5)
                ForEach(CatGrowthStage.allCases, id: \.self) { item in
                    let reached = age >= item.minimumAgeDays
                    VStack(spacing: 3) {
                        Image(systemName: item == .kitten ? "drop.fill" : item == .junior ? "pawprint.fill" : "crown.fill")
                            .font(.system(size: 9.5, weight: .bold)).foregroundStyle(reached ? .white : RoomTheme.secondary)
                            .frame(width: 23, height: 23).background(reached ? RoomTheme.mint : RoomTheme.paper, in: Circle())
                            .overlay(Circle().strokeBorder(stage == item ? RoomTheme.gold : RoomTheme.track, lineWidth: 2))
                        Text(GameStrings.text("catGrowth.stage.\(item.rawValue)") + " · \(item.minimumAgeDays)")
                            .font(.system(size: 9.5, weight: .heavy)).lineLimit(1)
                            .foregroundStyle(stage == item ? RoomTheme.darkMint : RoomTheme.secondary)
                    }
                    .fixedSize().position(x: axis.x(forAge: item.minimumAgeDays), y: 19)
                }
            }
        }
        .frame(height: 40).accessibilityHidden(true)
    }

    /// Bond progress plus the "time together" record, as one line at the bottom.
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
            Text(CatGrowthPresentation.nextBond(cat.intimacy)).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.friendshipDeep)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let growth = cat.growthState {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 10.5, weight: .bold))
                    Text(GameStrings.text("catGrowth.joined") + " · "
                         + (growth.adoptedAt.map(CatGrowthPresentation.date) ?? GameStrings.text("catGrowth.joinedEarlier")))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text(GameStrings.format("mac.cats.days", growth.companionshipDays(at: date)))
                        .foregroundStyle(RoomTheme.darkMint).lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .padding(.top, 2)
                .help(GameStrings.text(growth.isLegacyRecord ? "catGrowth.legacyHint" : "catGrowth.newHint"))
            }
        }
    }

    private func bondStep(_ stage: CatBondStage, intimacy: Int) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                Capsule().fill(RoomTheme.friendshipPaper).overlay(alignment: .leading) {
                    Capsule().fill(RoomTheme.friendship).frame(width: geometry.size.width * CGFloat(min(25, max(0, intimacy - stage.minimumIntimacy))) / 25)
                }
            }.frame(height: 6).accessibilityHidden(true)
            Text(GameStrings.text("catGrowth.bond.\(stage.rawValue)"))
                .font(.system(size: 9.5, weight: .bold)).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.75)
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
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 26, height: 26).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(GameStrings.text(key)).font(.system(size: 10, weight: .bold)).foregroundStyle(tint).fixedSize()
                    Text(GameStrings.text(value)).font(.system(size: 12, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                }
                Text(confirmed ? GameStrings.text("habit68.clues.confirmed") : GameStrings.format("catHabits.clues", count))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.75)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<CatHabitCatalog.cluesToConfirm, id: \.self) { i in
                    Circle().fill(i < count ? tint : RoomTheme.track).frame(width: 7, height: 7)
                }
            }.accessibilityHidden(true)
        }.padding(.horizontal, 7).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func corner(_ cat: CatState) -> some View {
        if let id = cat.habits.cornerFurnitureID,
           let item = store.snapshot?.inventory.furniture.first(where: { $0.id == id }),
           let placement = store.snapshot?.home.furniture.first(where: { $0.itemID == id }) {
            Button { visitCorner(cat, placement: placement) } label: {
                HStack(spacing: 5) {
                    Label(GameStrings.format("habit68.corner", GameStrings.furnitureName(item), GameStrings.text("homeFloor.\(placement.floor.rawValue)")), systemImage: "flag.fill")
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
                }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.friendshipDeep)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(store.isBusy || saving)
                .accessibilityIdentifier("macVisitCorner")
        } else {
            Label(GameStrings.text("habit68.corner.empty"), systemImage: "flag.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        if let receipt = cat.habits.lastRestObservation,
           cat.habits.cornerFurnitureID != receipt.furnitureID,
           store.snapshot?.home.furniture.contains(where: { $0.itemID == receipt.furnitureID && $0.floor == receipt.location.floor && $0.position == receipt.location.position }) == true {
            Button(GameStrings.text("catHabits.chooseCorner")) {
                saving = true
                Task { _ = await store.chooseHabitCorner(catID: cat.id, observationID: receipt.id); saving = false }
            }.buttonStyle(SoftButtonStyle()).controlSize(.small).disabled(store.isBusy || saving)
        }
    }

    private func memories(_ cat: CatState) -> some View {
        gridCard {
            cardTitle(GameStrings.format("habit68.memories.count", cat.habits.memories.count, CatMemoryKind.allCases.count), symbol: "photo.fill")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(CatMemoryKind.allCases, id: \.self) { kind in memoryTile(HabitMemorySlot68(kind: kind, cat: cat)) }
            }
            pinnedGuide(cat)
        }
    }

    private func memoryTile(_ slot: HabitMemorySlot68) -> some View {
        let tint = HabitMemorySlot68.tint(for: slot.kind), empty = slot.memory == nil
        return Button { memory = slot.memory } label: {
            HStack(spacing: 5) {
                Image(systemName: empty ? "questionmark" : HabitMemorySlot68.symbol(for: slot.kind))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(empty ? RoomTheme.track : tint)
                    .frame(width: 20, height: 20)
                    .background(empty ? RoomTheme.track.opacity(0.25) : tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                Text(slot.title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(empty ? RoomTheme.secondary : RoomTheme.ink)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }.padding(4).frame(maxWidth: .infinity)
                .background(empty ? .clear : .white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(empty ? RoomTheme.track : .clear,
                    style: StrokeStyle(lineWidth: 1.2, dash: empty ? [4, 3] : [])))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(empty).accessibilityIdentifier("macMemory_\(slot.kind.rawValue)")
            .accessibilityLabel(slot.title).help(slot.title)
    }

    private func pinnedGuide(_ cat: CatState) -> some View {
        Button { showsGuide = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "pin.fill").font(.system(size: 10.5)).foregroundStyle(RoomTheme.sky)
                Text(GameStrings.text("habit67.pinTitle")).font(.system(size: 10, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize()
                Text(cat.habits.pinnedMemory.map { GameStrings.text(CompanionshipPresentation.guideKey(for: $0)) }
                     ?? GameStrings.text("habit68.guide.none")).font(.system(size: 11.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }.padding(.horizontal, 8).padding(.vertical, 6).background(RoomTheme.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
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
        let ids = entries.map(\.id)
        guard !ids.isEmpty else { return }
        let index = ids.firstIndex(of: focusedID ?? "") ?? 0
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

extension Notification.Name { static let macCatsEscape = Notification.Name("MacCatsEscape") }
