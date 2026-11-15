import SwiftUI
import CatGameCore

@MainActor
struct ExchangeMarketView: View {
    @Bindable var store: GameStore
    var initialNeighborID: String? = nil
    /// The Mac sheet already has Done on its scene banner, so it hides the duplicate back pill.
    var showsBack = true
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var neighborID: String?
    @State private var showsHint = false
    @State private var selectedID: String?
    @State private var result: NeighborActionReceipt?
    @State private var isWorking = false
    @State private var failed = false
    @State private var isVisible = false
    @State private var initialized = false
    @State private var visitID: String?
    @State private var showsGiftShop = false
    private var stalls: [NeighborDefinition] {
        CommunityCatalog.neighbors.filter { neighborID == nil || $0.id == neighborID }
    }
    private var selectedOffer: ExchangeOffer? { selectedID.flatMap(ExchangeCatalog.offer) }
    private var confirmationVisible: Binding<Bool> {
        Binding(get: { selectedOffer != nil }, set: { if !$0 { closeConfirmation() } })
    }

    var body: some View {
        listings
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
            .environment(\.locale, Locale(identifier: store.language.rawValue))
            .toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
            .background(RoomTheme.cream)
            .sheet(isPresented: confirmationVisible, onDismiss: { store.isPresentingExchange = false }) {
                if let offer = selectedOffer, let snapshot = store.snapshot {
                    Group {
                        if let result {
                            ExchangeResultView(offer: offer, receipt: result,
                                friendship: snapshot.community.relationship(for: offer.neighborID).friendship,
                                continueBrowsing: closeConfirmation, openBag: {
                                    closeConfirmation(); store.openInventory()
                                })
                        } else {
                            ExchangeConfirmationView(offer: offer, snapshot: snapshot, isWorking: isWorking || store.isBusy,
                                failed: failed, hasSaveFailure: store.hasSaveFailure,
                                confirm: { exchange(offer) }, cancel: closeConfirmation)
                        }
                    }
                    .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
                    .environment(\.locale, Locale(identifier: store.language.rawValue))
                    .presentationBackground(RoomTheme.cream).presentationCornerRadius(30)
                    .presentationDragIndicator(.visible)
                    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.fraction(0.72), .large])
                    .interactiveDismissDisabled(isWorking || store.isBusy)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if store.hasSaveFailure { SaveStatusBanner(store: store) }
                    }
                    .saveRecoveryAlert(store: store)
                    .onAppear { store.isPresentingExchange = true }
                }
            }
            .navigationDestination(isPresented: Binding(get: { visitID != nil }, set: { if !$0 { visitID = nil } })) {
                if let visitID { NeighborDetailView(store: store, neighborID: visitID, showsExchangeEntry: false) }
            }
            .navigationDestination(isPresented: $showsGiftShop) {
                CommunityGiftView(store: store, onClose: { showsGiftShop = false })
            }
            .onAppear {
                isVisible = true
                if !initialized { neighborID = initialNeighborID; initialized = true }
            }
            .onDisappear { isVisible = false; store.isPresentingExchange = false }
            .onChange(of: selectedID) { _, id in store.isPresentingExchange = id != nil }
            .onChange(of: store.saveSceneGeneration) { _, _ in
                selectedID = nil; result = nil; failed = false; visitID = nil; showsGiftShop = false
            }
    }

    /// One slim row: (back), the stall filter, a hint and the bag. The scene banner above names the place.
    private var header: some View {
        HStack(spacing: 8) {
            if showsBack {
                Button(action: onClose) {
                    Label(GameStrings.text(initialNeighborID == nil ? "tab.town" : "community.title"), systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .heavy)).lineLimit(1)
                        .padding(.horizontal, 11).frame(height: 32).gameCard(cornerRadius: 16)
                }.buttonStyle(.plain).accessibilityIdentifier("marketBackButton")
            }
            filters
            Spacer(minLength: 0)
            Button { showsHint.toggle() } label: {
                Image(systemName: "info.circle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                    .frame(width: 32, height: 32).gameCard(cornerRadius: 16)
            }.buttonStyle(.plain)
                .help(GameStrings.format("market.dailyHint130", ExchangeCatalog.dailyLimit))
                .accessibilityLabel(GameStrings.text("market.subtitle"))
                .accessibilityHint(GameStrings.format("market.dailyHint130", ExchangeCatalog.dailyLimit))
                .accessibilityIdentifier("marketHintButton")
                .popover(isPresented: $showsHint, arrowEdge: .bottom) { hint }
            Button { store.openInventory() } label: {
                Image(systemName: "backpack.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(RoomTheme.gold)
                    .frame(width: 32, height: 32).gameCard(cornerRadius: 16)
            }.buttonStyle(.plain).accessibilityLabel(GameStrings.text("market.openBag"))
                .help(GameStrings.text("market.openBag"))
                .accessibilityIdentifier("marketBagButton")
        }
        .disabled(isWorking || store.isBusy)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8).background(RoomTheme.cream)
        .accessibilityElement(children: .contain).accessibilityIdentifier("marketHeader")
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(GameStrings.text("market.subtitle"), systemImage: "storefront.fill")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            Text(GameStrings.format("market.dailyHint130", ExchangeCatalog.dailyLimit))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(width: 300, alignment: .leading)
        .fontDesign(.rounded).background(RoomTheme.cream)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
    }

    private var listings: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let snapshot = store.snapshot {
                    ForEach(stalls) { neighbor in
                        ExchangeStallCard(neighbor: neighbor,
                                          offers: ExchangeCatalog.offers.filter { $0.neighborID == neighbor.id },
                                          snapshot: snapshot, disabled: isWorking || store.isBusy) { offer in
                            activate(offer, in: snapshot)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("exchangeMarketScroll")
    }

    /// Every stall fits on one line; if a long name would overflow, chips drop to avatar + count, then scroll.
    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            filterRow(named: true)
            filterRow(named: false)
            ScrollView(.horizontal, showsIndicators: false) { filterRow(named: false) }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("marketFilters")
    }

    private func filterRow(named: Bool) -> some View {
        HStack(spacing: 6) {
            filter(nil, named: named)
            ForEach(CommunityCatalog.neighbors) { neighbor in filter(neighbor, named: named) }
        }.fixedSize()
    }

    private func filter(_ neighbor: NeighborDefinition?, named: Bool) -> some View {
        let id = neighbor?.id
        let selected = neighborID == id
        let name = GameStrings.text(neighbor?.nameKey ?? "market.all")
        let remaining = id.map { store.snapshot?.community.exchangeCount(for: $0).remainingToday ?? ExchangeCatalog.dailyLimit }
        return Button { store.playNavigationSound(); neighborID = id } label: {
            HStack(spacing: 5) {
                if let neighbor { CommunityPortrait(neighbor: neighbor, size: 24).clipShape(Circle()) }
                else { Image(systemName: "square.grid.2x2.fill").font(.system(size: 11, weight: .bold)) }
                if named || neighbor == nil { Text(name).font(.system(size: 12.5, weight: .heavy)).lineLimit(1) }
                if let remaining {
                    Text("\(remaining)/\(ExchangeCatalog.dailyLimit)").font(.system(size: 10.5, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(selected ? .white : remaining > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(selected ? .white.opacity(0.25) : remaining > 0 ? RoomTheme.paleMint : RoomTheme.track, in: Capsule())
                }
            }
            .padding(.leading, neighbor == nil ? 10 : 4).padding(.trailing, 9).frame(height: 32)
            .foregroundStyle(selected ? .white : RoomTheme.ink)
            .background(selected ? RoomTheme.mint : RoomTheme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? RoomTheme.mint : .white, lineWidth: 2))
        }.buttonStyle(.plain).disabled(store.isBusy)
            .help(name)
            .accessibilityLabel(name)
            .accessibilityIdentifier("marketFilter_\(id ?? "all")")
            .accessibilityValue(remaining.map { GameStrings.format("market.remaining", $0, ExchangeCatalog.dailyLimit) } ?? "")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func activate(_ offer: ExchangeOffer, in snapshot: GameSnapshot) {
        store.playNavigationSound()
        switch ExchangeCatalog.eligibility(of: offer, in: snapshot) {
        case .exchangeStageRequired: visitID = offer.neighborID
        case .exchangeMaterialsRequired:
            let missingGift = offer.inputs.contains { stack in
                if case .gift = stack.item { return stack.item.count(in: snapshot.inventory) < stack.quantity }
                return false
            }
            if missingGift { showsGiftShop = true }
            else { store.shopCategory = .supplies; store.activeSheet = .shop }
        case .shopInventoryFull: store.openInventory()
        case .exchangeDailyLimit, .exchangeMissing: break
        default: selectedID = offer.id; result = nil; failed = false
        }
    }

    private func closeConfirmation() {
        guard !isWorking else { return }
        selectedID = nil; result = nil; failed = false; store.isPresentingExchange = false
    }

    private func exchange(_ offer: ExchangeOffer) {
        guard !isWorking, !store.isBusy else { return }
        isWorking = true; failed = false
        Task {
            defer { isWorking = false }
            let receipt = await store.exchange(offerID: offer.id, presentResult: { receipt in
                guard isVisible, scenePhase == .active, store.activeSheet == .town,
                      selectedID == offer.id, receipt.saveSceneGeneration == store.saveSceneGeneration else { return false }
                result = receipt
                return true
            })
            if receipt == nil, selectedID == offer.id { failed = true }
        }
    }
}
