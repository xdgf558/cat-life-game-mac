import SwiftUI
import CatGameCore

@MainActor
struct CatCollectionView: View {
    @Bindable var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path: [Route]
    @State private var filter: Filter
    @State private var page = 0
    @State private var isSaving = false
    @State private var glowing = false
    let embedded: Bool
    var onClose: (() -> Void)?

    private enum Route: Hashable { case profile(String), name(String), adoption(String), health(String), growth(String) }
    enum Filter: String, CaseIterable { case all, owned, unowned }
    private enum Entry: Identifiable {
        case owned(CatState), adoption(CatAdoptionOffer)
        var id: String { switch self { case .owned(let cat): cat.id; case .adoption(let offer): offer.id } }
    }
    private let pageSize = 4
    private var cats: [CatState] { store.snapshot?.cats ?? [] }
    private var appearances: Set<CatAppearance> { Set(cats.map(\.appearance)) }
    private var offers: [CatAdoptionOffer] { CatCatalog.adoptionOffers.filter { offer in !cats.contains { $0.id == offer.id } } }
    private var entries: [Entry] {
        guard store.snapshot != nil else { return [] }
        switch filter {
        case .all: return cats.map(Entry.owned) + offers.map(Entry.adoption)
        case .owned: return cats.map(Entry.owned)
        case .unowned: return offers.map(Entry.adoption)
        }
    }
    private var pageCount: Int { max(1, (entries.count + pageSize - 1) / pageSize) }
    private var currentPage: Int { min(page, pageCount - 1) }
    private var visibleEntries: [Entry] { Array(entries.dropFirst(currentPage * pageSize).prefix(pageSize)) }

    init(store: GameStore, initialCatID: String? = nil, initialFilter: Filter = .all,
         embedded: Bool = false, initialAdoptionID: String? = nil, initialGrowth: Bool = false, onClose: (() -> Void)? = nil) {
        self.store = store
        self.embedded = embedded
        self.onClose = onClose
        _path = State(initialValue: initialAdoptionID.map { [.adoption($0)] }
            ?? initialCatID.map { initialGrowth ? [.growth($0)] : [.profile($0)] } ?? [])
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        NavigationStack(path: $path) {
            directory
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .profile(let id):
                        CatProfileView(store: store, catID: id, isSaving: $isSaving,
                                       health: { path.append(.health(id)) }, rename: { path.append(.name(id)) },
                                       growth: { path.append(.growth(id)) })
                            .navigationBarBackButtonHidden().toolbar(.visible, for: .navigationBar)
                            .toolbar { backButton("catProfileBackButton"); doneButton }
                    case .growth(let id):
                        CatGrowthView(store: store, catID: id, isSaving: $isSaving) {
                            close(); store.inspectedCatID = nil; store.activeSheet = nil
                        }
                        .navigationBarBackButtonHidden().toolbar(.visible, for: .navigationBar)
                        .toolbar { backButton("catGrowthBackButton"); doneButton }
                    case .health(let id):
                        HospitalCatDetailView(store: store, catID: id, isSaving: $isSaving) { go(.work) }
                            .navigationBarBackButtonHidden().toolbar(.visible, for: .navigationBar)
                            .toolbar { backButton("catHealthBackButton"); doneButton }
                    case .name(let id):
                        CatNameEditorView(store: store, catID: id, isSaving: $isSaving)
                            .navigationBarBackButtonHidden().toolbar(.visible, for: .navigationBar)
                            .toolbar { backButton("catNameBackButton"); doneButton }
                    case .adoption(let id):
                        CatAdoptionView(store: store, catID: id, isSaving: $isSaving,
                                        back: { if !path.isEmpty { path.removeLast() } },
                                        directory: { filter = .owned; path.removeAll() },
                                        go: go,
                                        home: { close(); store.inspectedCatID = nil; store.activeSheet = nil })
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            if !embedded {
                VStack(spacing: 0) {
                    SaveStatusBanner(store: store)
                    if let toast = store.toast, !toast.isEmpty {
                        Text(toast).font(.footnote).multilineTextAlignment(.center)
                            .padding(12).frame(maxWidth: .infinity)
                            .background(RoomTheme.paper).accessibilityIdentifier("sheetToast")
                    }
                }
            }
        }
        .saveRecoveryAlert(store: store, isActive: !embedded && !store.isPresentingAdoptionConfirmation
                           && !store.isPresentingHabitGuide && !store.isPresentingHabitMemory)
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .presentationBackground(RoomTheme.cream).interactiveDismissDisabled(isSaving)
        .onChange(of: cats.count) { _, _ in page = currentPage }
        .onChange(of: filter) { _, _ in page = 0 }
        .task(id: reduceMotion) {
            glowing = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glowing = true }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) { AudioDiagnosticsView(store: store) }
        #endif
    }

    private var directory: some View {
        VStack(spacing: 0) {
            CatCollectionHeader(title: "town.title", backTitle: "tab.town", gold: store.snapshot?.player.gold ?? 0,
                                disabled: isSaving, back: close)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    collectionCard.id("collectionTop")
                    filters
                    if entries.isEmpty { emptyState }
                    else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                                 count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 14) {
                            ForEach(visibleEntries) { entry in
                                switch entry { case .owned(let cat): catCard(cat); case .adoption(let offer): adoptionCard(offer) }
                            }
                        }
                        .padding(.top, 4).id("collectionCards")
                        if pageCount > 1 { pagination }
                    }
                    Text(GameStrings.text("catDirectory.pageHint")).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("catCollectionScroll")
            .onChange(of: currentPage) { _, _ in proxy.scrollTo("collectionCards", anchor: .top) }
            .onChange(of: filter) { _, _ in proxy.scrollTo("collectionTop", anchor: .top) }
            }
        }
        .background(RoomTheme.cream)
    }

    private var collectionCard: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) { collectedTitle; Spacer(minLength: 0); ownedCount }
                VStack(alignment: .leading, spacing: 6) { collectedTitle; ownedCount }.frame(maxWidth: .infinity, alignment: .leading)
            }
            CatCollectionSegments(appearances: appearances).accessibilityIdentifier("catCollectionProgress")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                    count: min(CatAppearance.allCases.count, dynamicTypeSize.isAccessibilitySize ? 2 : 5)), spacing: 12) {
                ForEach(CatAppearance.allCases, id: \.self) { appearance in
                    VStack(spacing: 8) {
                        CatCollectionPortrait(appearance: appearance, size: 44, faded: !appearances.contains(appearance),
                                              badge: appearances.contains(appearance) ? "checkmark" : nil)
                        Text(GameStrings.text("hospital.coat.\(appearance.rawValue)"))
                            .font(.caption.weight(.heavy)).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(appearances.contains(appearance) ? RoomTheme.ink : RoomTheme.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("catCollectionCoat_\(appearance.rawValue)")
                }
            }
            Label((store.snapshot?.home.roomLevel ?? 1) >= RoomResidentCats.unlockLevel
                 ? GameStrings.text("catDirectory.sharedHomeUnlocked")
                 : GameStrings.format("catDirectory.sharedHomeLocked", RoomResidentCats.unlockLevel),
                  systemImage: (store.snapshot?.home.roomLevel ?? 1) >= RoomResidentCats.unlockLevel ? "house.fill" : "lock.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle((store.snapshot?.home.roomLevel ?? 1) >= RoomResidentCats.unlockLevel ? RoomTheme.darkMint : RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("catCollectionSharedHomeHint")
        }.padding(16).gameCard(cornerRadius: 28)
    }

    private var collectedTitle: some View {
        var title = AttributedString(GameStrings.format("catDirectory.collected", appearances.count, CatAppearance.allCases.count))
        title.font = .system(size: 16, weight: .heavy)
        title.foregroundColor = RoomTheme.ink
        if let number = title.range(of: "\(appearances.count)") {
            title[number].font = .system(size: 22, weight: .heavy)
            title[number].foregroundColor = RoomTheme.darkMint
        }
        return Text(title).fixedSize(horizontal: false, vertical: true)
    }
    private var ownedCount: some View {
        Text(GameStrings.format("catDirectory.count", cats.count)).font(.system(size: 12, weight: .bold))
            .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("catCount").accessibilityValue("\(cats.count)")
    }
    private var filters: some View {
        HStack(spacing: 4) {
            ForEach(Filter.allCases, id: \.self) { option in
                Button { filter = option; store.playNavigationSound() } label: {
                    HStack(spacing: 4) {
                        Text(GameStrings.text("catDirectory.filter.\(option.rawValue)"))
                            .lineLimit(2).minimumScaleFactor(0.75)
                        Text("\(count(for: option))").font(.system(size: 11, weight: .heavy)).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(filter == option ? .white.opacity(0.23) : RoomTheme.track, in: Capsule())
                    }
                    .font(.system(size: 13, weight: .heavy)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 3)
                    .foregroundStyle(filter == option ? .white : RoomTheme.secondary)
                    .background(filter == option ? RoomTheme.mint : .clear, in: Capsule())
                }
                .buttonStyle(.plain).accessibilityAddTraits(filter == option ? .isSelected : [])
                .accessibilityValue("\(count(for: option))").accessibilityIdentifier("catFilter_\(option.rawValue)")
            }
        }.padding(4).background(RoomTheme.chipBg, in: Capsule())
    }
    private func count(for filter: Filter) -> Int {
        switch filter { case .all: cats.count + offers.count; case .owned: cats.count; case .unowned: offers.count }
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: "party.popper.fill").font(.system(size: 38)).foregroundStyle(RoomTheme.gold).accessibilityHidden(true)
            Text(GameStrings.text(filter == .unowned ? "catDirectory.allAdoptedTitle" : "catDirectory.empty"))
                .font(.system(size: 20, weight: .heavy)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("catCollectionEmpty")
            Text(GameStrings.text(filter == .unowned ? "catDirectory.allAdopted" : "cat.adoptionHint"))
                .font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center)
            if filter == .unowned {
                Button { filter = .owned } label: {
                    Text(GameStrings.text("catDirectory.seeOwned")).font(.headline).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("catCollectionSeeOwned")
            }
        }.padding(24).frame(maxWidth: .infinity).gameCard(cornerRadius: 28)
            .accessibilityElement(children: .contain)
    }

    private func catCard(_ cat: CatState) -> some View {
        let active = cat.id == store.cat?.id
        return Button { path.append(.profile(cat.id)) } label: {
            VStack(spacing: 12) {
                CatCollectionPortrait(appearance: cat.appearance)
                cardIdentity(GameStrings.catName(cat), appearance: cat.appearance)
                Text(CatProfileView.status(for: cat)).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RoomTheme.darkMint).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14).padding(.top, 3).frame(maxWidth: .infinity, minHeight: 206)
            .gameCard(cornerRadius: 24)
            .overlay(alignment: .top) {
                if active { ribbon("catDirectory.inRoom", tint: RoomTheme.mint) }
            }
        }
        .buttonStyle(.plain).accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: GameStrings.catName(cat)))
        .accessibilityValue(GameStrings.text(active ? "cat.companionActive" : "cat.adoptionOwned") + " · " + CatProfileView.status(for: cat))
        .accessibilityIdentifier("catProfile_\(cat.id)")
    }

    private func adoptionCard(_ offer: CatAdoptionOffer) -> some View {
        let snapshot = store.snapshot
        let available = snapshot.map { CatAdoptionView.conditionsMet(offer, in: $0) == 3 } ?? false
        let badge = CatCollectionBadge.adoption(appearance: offer.appearance, isOwned: false, isAvailable: available)
        return Button { path.append(.adoption(offer.id)) } label: {
            VStack(spacing: 10) {
                CatCollectionPortrait(appearance: offer.appearance, faded: !available, badge: available ? nil : "lock.fill")
                cardIdentity(GameStrings.catAdoptionName(offer), appearance: offer.appearance)
                if available {
                    Text(GameStrings.text("cat.adoptionAvailable")).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                    HStack(spacing: 5) {
                        Text(GameStrings.text("cat.adoptionCompactAction"))
                        Label("\(offer.price)", systemImage: "dollarsign.circle.fill")
                    }
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 34)
                    .background(RoomTheme.mint, in: Capsule())
                } else if let snapshot {
                    miniCondition("cat.adoptionLevelShort", have: snapshot.player.level, need: offer.requiredPlayerLevel)
                    miniCondition("cat.adoptionRoomShort", have: snapshot.home.roomLevel, need: offer.requiredRoomLevel)
                    miniCondition("resource.gold", have: snapshot.player.gold, need: offer.price)
                }
                Spacer(minLength: 0)
            }
            .padding(12).padding(.top, 5).frame(maxWidth: .infinity, minHeight: 206)
            .background(available ? CatCollectionPalette.ready : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(available ? CatCollectionPalette.readyBorder : .white, lineWidth: 2))
            .shadow(color: available ? RoomTheme.mint.opacity(!reduceMotion && glowing ? 0.22 : 0.05) : RoomTheme.ink.opacity(0.08),
                    radius: available && !reduceMotion && glowing ? 8 : 0, y: 4)
            .overlay(alignment: .top) {
                if let badge {
                    ribbon(badge.textKey, tint: badge.tint)
                        .accessibilityIdentifier("catAdoptionBadge_\(offer.id)")
                }
            }
        }
        .buttonStyle(.plain).accessibilityElement(children: .combine)
        .accessibilityValue(GameStrings.text(available ? "cat.adoptionAvailable" : "cat.adoptionRequirements"))
        .accessibilityIdentifier("catAdoption_\(offer.id)")
    }
    private func cardIdentity(_ name: String, appearance: CatAppearance) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { Text(verbatim: name).font(.system(size: 17, weight: .heavy)); CatCollectionCoatPill(appearance: appearance) }
            VStack(spacing: 4) { Text(verbatim: name).font(.system(size: 17, weight: .heavy)); CatCollectionCoatPill(appearance: appearance) }
        }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
    private func miniCondition(_ key: String, have: Int, need: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: have >= need ? "checkmark.circle.fill" : "circle.dashed").font(.system(size: 10))
            Text(GameStrings.text(key))
            Spacer(minLength: 0)
            Text("\(have) / \(need)").monospacedDigit()
        }
        .font(.system(size: 11, weight: .heavy)).foregroundStyle(have >= need ? RoomTheme.darkMint : RoomTheme.secondary)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(have >= need ? RoomTheme.paleMint.opacity(0.6) : RoomTheme.chipBg.opacity(0.6), in: Capsule())
    }
    private func ribbon(_ key: String, tint: Color) -> some View {
        Text(GameStrings.text(key)).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5).background(tint, in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2)).offset(y: -9)
    }

    private var pagination: some View {
        HStack(spacing: 10) {
            Button { page = max(0, currentPage - 1) } label: {
                Label(GameStrings.text("catDirectory.previous"), systemImage: "chevron.left")
                    .font(.footnote.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(SoftButtonStyle()).disabled(currentPage == 0).opacity(currentPage == 0 ? 0.4 : 1).accessibilityIdentifier("catPagePrevious")
            Text(GameStrings.format("catDirectory.page", currentPage + 1, pageCount)).font(.footnote.monospacedDigit()).fixedSize()
                .accessibilityIdentifier("catPageSummary").accessibilityValue("\(currentPage + 1)/\(pageCount)")
            Button { page = min(pageCount - 1, currentPage + 1) } label: {
                HStack(spacing: 5) { Text(GameStrings.text("catDirectory.next")); Image(systemName: "chevron.right") }
                    .font(.footnote.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(SoftButtonStyle()).disabled(currentPage == pageCount - 1).opacity(currentPage == pageCount - 1 ? 0.4 : 1)
                .accessibilityIdentifier("catPageNext")
        }.foregroundStyle(RoomTheme.darkMint)
    }
    private func close() { guard !isSaving else { return }; if let onClose { onClose() } else { dismiss() } }
    private func go(_ destination: HomeSheet) { close(); store.inspectedCatID = nil; store.activeSheet = destination }
    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(GameStrings.text("common.done"), action: close).foregroundStyle(RoomTheme.darkMint)
                .disabled(isSaving).accessibilityIdentifier("closeSheetButton")
        }
    }
    private func backButton(_ identifier: String) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { guard !isSaving, !path.isEmpty else { return }; path.removeLast() } label: {
                Label(GameStrings.text("common.back"), systemImage: "chevron.left").frame(minHeight: 44)
            }.foregroundStyle(RoomTheme.darkMint).disabled(isSaving).accessibilityIdentifier(identifier)
        }
    }
}
