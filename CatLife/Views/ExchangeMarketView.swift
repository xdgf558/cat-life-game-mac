import SwiftUI
import CatGameCore

@MainActor
struct ExchangeMarketView: View {
    @Bindable var store: GameStore
    var initialNeighborID: String? = nil
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var neighborID: String?
    @State private var page = 0
    @State private var selectedID: String?
    @State private var result: NeighborActionReceipt?
    @State private var isWorking = false
    @State private var failed = false
    @State private var isVisible = false
    @State private var initialized = false
    @State private var visitID: String?
    @State private var showsGiftShop = false
    private var pageSize: Int { dynamicTypeSize.isAccessibilitySize ? 2 : 4 }
    private var offers: [ExchangeOffer] {
        ExchangeCatalog.offers.filter { neighborID == nil || $0.neighborID == neighborID }
    }
    private var pageCount: Int { max(1, (offers.count + pageSize - 1) / pageSize) }
    private var visibleOffers: [ExchangeOffer] { Array(offers.dropFirst(page * pageSize).prefix(pageSize)) }
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
            .onChange(of: dynamicTypeSize) { _, _ in page = min(page, pageCount - 1) }
            .onChange(of: store.saveSceneGeneration) { _, _ in
                selectedID = nil; result = nil; failed = false; page = 0; visitID = nil; showsGiftShop = false
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Label(GameStrings.text(initialNeighborID == nil ? "tab.town" : "community.title"), systemImage: "chevron.left")
                    .font(.caption.weight(.heavy)).padding(.horizontal, 12).frame(minHeight: 44).gameCard(cornerRadius: 24)
            }.buttonStyle(.plain).accessibilityIdentifier("marketBackButton")
            Label(GameStrings.text("market.shortTitle"), systemImage: "arrow.left.arrow.right.square")
                .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 13).padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 16).fill(RoomTheme.wood)
                        .shadow(color: TownPalette.woodEdge, radius: 0, y: 4)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(TownPalette.woodEdge, lineWidth: 2.5))
                }.accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { store.openInventory() } label: {
                Image(systemName: "backpack.fill").font(.title3.weight(.bold)).foregroundStyle(RoomTheme.gold)
                    .frame(width: 44, height: 44).gameCard(cornerRadius: 24)
            }.buttonStyle(.plain).accessibilityLabel(GameStrings.text("market.openBag"))
                .accessibilityIdentifier("marketBagButton")
        }
        .disabled(isWorking || store.isBusy)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16).background(RoomTheme.cream)
        .accessibilityElement(children: .contain).accessibilityIdentifier("marketHeader")
    }

    private var listings: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro.id("marketTop")
                    filters
                    LazyVStack(spacing: 14) {
                        ForEach(visibleOffers) { offer in
                            if let snapshot = store.snapshot {
                                ExchangeOfferCard(offer: offer, snapshot: snapshot, disabled: isWorking || store.isBusy) {
                                    activate(offer, in: snapshot)
                                }
                            }
                        }
                    }
                }.padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("exchangeMarketScroll")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if pageCount > 1 {
                    HStack(spacing: 12) {
                        Button { page -= 1; proxy.scrollTo("marketTop", anchor: .top) } label: {
                            Label(GameStrings.text("market.previous"), systemImage: "chevron.left")
                        }.buttonStyle(SoftButtonStyle()).disabled(page == 0 || store.isBusy)
                            .accessibilityIdentifier("marketPreviousPage")
                        Text(GameStrings.format("market.page", page + 1, pageCount)).font(.caption.weight(.heavy)).monospacedDigit()
                            .accessibilityIdentifier("marketPage").accessibilityValue("\(page + 1)/\(pageCount)")
                        Button { page += 1; proxy.scrollTo("marketTop", anchor: .top) } label: {
                            Label(GameStrings.text("market.next"), systemImage: "chevron.right")
                        }.buttonStyle(SoftButtonStyle()).disabled(page + 1 >= pageCount || store.isBusy)
                            .accessibilityIdentifier("marketNextPage")
                    }
                    .font(.caption.weight(.heavy)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(12).background(RoomTheme.cream)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("marketPaginationBar")
                }
            }
        }
    }

    private var intro: some View {
        HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "storefront.fill").font(.title2).foregroundStyle(RoomTheme.darkMint)
                    .frame(width: 40, height: 40).background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(GameStrings.text("market.subtitle")).font(.subheadline.weight(.heavy))
                Text(GameStrings.format("market.dailyHint", ExchangeCatalog.dailyLimit, ExchangeCatalog.friendship))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 24)
    }

    private var filters: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filter(nil)
                    ForEach(CommunityCatalog.neighbors) { neighbor in filter(neighbor) }
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("marketFilters")
            .onChange(of: neighborID, initial: true) { _, id in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id ?? "all", anchor: .center) }
            }
        }
    }

    private func filter(_ neighbor: NeighborDefinition?) -> some View {
        let id = neighbor?.id
        let remaining = id.map { store.snapshot?.community.exchangeCount(for: $0).remainingToday ?? ExchangeCatalog.dailyLimit }
        return Button { store.playNavigationSound(); neighborID = id; page = 0 } label: {
            HStack(spacing: 7) {
                if let neighbor { CommunityPortrait(neighbor: neighbor, size: 30).clipShape(Circle()) }
                else { Image(systemName: "square.grid.2x2.fill").font(.caption) }
                Text(GameStrings.text(neighbor?.nameKey ?? "market.all")).font(.subheadline.weight(.heavy))
                if let remaining {
                    Text("\(remaining)/\(ExchangeCatalog.dailyLimit)").font(.caption.weight(.heavy))
                        .foregroundStyle(remaining > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(remaining > 0 ? RoomTheme.paleMint : RoomTheme.track, in: Capsule())
                }
            }.padding(.horizontal, 12).frame(minHeight: 44)
                .foregroundStyle(neighborID == id ? .white : RoomTheme.ink)
                .background(neighborID == id ? RoomTheme.mint : RoomTheme.paper, in: Capsule())
                .overlay(Capsule().strokeBorder(neighborID == id ? RoomTheme.mint : .white, lineWidth: 2))
        }.buttonStyle(.plain).disabled(store.isBusy).id(id ?? "all")
            .accessibilityIdentifier("marketFilter_\(id ?? "all")")
            .accessibilityValue(remaining.map { GameStrings.format("market.remaining", $0, ExchangeCatalog.dailyLimit) } ?? "")
            .accessibilityAddTraits(neighborID == id ? .isSelected : [])
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
