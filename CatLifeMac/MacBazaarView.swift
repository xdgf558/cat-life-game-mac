#if os(macOS)
import SwiftUI
import CatGameCore

/// Where a link into the bazaar lands: a tab and, for supplies, the neighbour's stall.
struct MacBazaarOpening: Equatable {
    var tab: MacBazaarView.Tab
    var neighborID: String? = nil
}

/// 3.2 猫町集市. One place for every swap in town: supplies with neighbours (the old swap market,
/// same offers and daily limits), handmade clothes with neighbours, and handmade clothes sold to the
/// shop. Every tab reads left to right: 1 pick, 2 choose, 3 confirm. Every number comes from
/// `ExchangeCatalog` / `BazaarCatalog`, so what the page shows is what the trade gives.
@MainActor
struct MacBazaarView: View {
    let store: GameStore
    @Binding var opening: MacBazaarOpening?
    var town: () -> Void = {}
    var wardrobe: () -> Void = {}
    var magic: () -> Void = {}
    var visit: (String) -> Void = { _ in }
    var shop: () -> Void = {}

    enum Tab: String, Hashable, CaseIterable {
        case supplies, trade, sell
        var titleKey: String { "bazaar.tab.\(rawValue)" }
        var symbol: String {
            switch self { case .supplies: "shippingbox.fill"; case .trade: "arrow.left.arrow.right"; case .sell: "storefront.fill" }
        }
        var tint: Color {
            switch self { case .supplies: RoomTheme.darkMint; case .trade: RoomTheme.friendshipDeep; case .sell: Color(red: 0.70, green: 0.45, blue: 0.10) }
        }
    }
    static let goldInk = Color(red: 0.70, green: 0.45, blue: 0.10)

    @State private var tab: Tab = .supplies
    @State private var itemID: String?
    @State private var neighborID: String?
    @State private var stallID: String?
    @State private var offerID: String?
    @State private var working = false
    @State private var started = false
    @FocusState private var focused: Bool

    private var snapshot: GameSnapshot? { store.snapshot }
    private var craft: CraftState { snapshot?.craft ?? CraftState() }
    private var today: String? { snapshot?.tasks.dailyDayKey }
    private var requests: [BazaarRequest] { today.map { BazaarCatalog.requests(day: $0) } ?? [] }
    /// Handmade clothes: tradable first, newest first.
    private var pieces: [HandmadeItem] {
        craft.handmade.filter { $0.blueprint?.product.slot != nil }.sorted { a, b in
            let aOpen = BazaarCatalog.blocker(a, in: craft) == nil, bOpen = BazaarCatalog.blocker(b, in: craft) == nil
            return aOpen != bOpen ? aOpen : a.madeAt > b.madeAt
        }
    }
    private var item: HandmadeItem? { itemID.flatMap { craft.item(id: $0) } }
    private var itemOpen: Bool { item.map { BazaarCatalog.blocker($0, in: craft) == nil } ?? false }
    private var request: BazaarRequest? { neighborID.flatMap { id in requests.first { $0.neighborID == id } } }
    private func traded(_ request: BazaarRequest) -> Bool { craft.bazaar.hasTraded(request.neighborID, today: today) }
    private func wants(_ request: BazaarRequest, _ item: HandmadeItem?) -> Bool {
        guard let item, BazaarCatalog.blocker(item, in: craft) == nil else { return false }
        return !traded(request) && request.want.accepts(item)
    }
    private var dealReady: Bool { request.map { wants($0, item) } ?? false }

    // Supplies
    private var stallOffers: [ExchangeOffer] { ExchangeCatalog.offers.filter { $0.neighborID == stallID } }
    private var offer: ExchangeOffer? { offerID.flatMap(ExchangeCatalog.offer) }
    private func failure(_ offer: ExchangeOffer) -> ActionFailure? {
        snapshot.map { ExchangeCatalog.eligibility(of: offer, in: $0) } ?? .exchangeMissing
    }
    private func remaining(_ neighborID: String) -> Int {
        snapshot?.community.exchangeCount(for: neighborID).remainingToday ?? 0
    }
    private func readyOffers(_ neighborID: String?) -> Int {
        ExchangeCatalog.offers.filter { (neighborID == nil || $0.neighborID == neighborID) && failure($0) == nil }.count
    }
    private var openRequests: Int { requests.filter { request in pieces.contains { wants(request, $0) } }.count }

    var body: some View {
        VStack(spacing: 14) {
            MacPlaceBanner(store: store, place: .bazaar, height: 110, onTown: town) { tabBar }
            HStack(alignment: .top, spacing: 14) {
                Group {
                    switch tab {
                    case .supplies: stallsColumn
                    case .trade, .sell: piecesColumn
                    }
                }.frame(width: 290)
                Group {
                    switch tab {
                    case .supplies: offersColumn
                    case .trade: requestsColumn
                    case .sell: priceColumn
                    }
                }.frame(maxWidth: .infinity)
                Group {
                    switch tab {
                    case .supplies: suppliesPanel
                    case .trade: tradePanel
                    case .sell: sellPanel
                    }
                }.frame(width: 300)
            }
            .frame(maxHeight: .infinity)
            .disabled(working)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear { focused = true; start() }
        .onChange(of: opening) { _, value in apply(value) }
        .onChange(of: craft.handmade.map(\.id)) { _, _ in settleSelection() }
        .onChange(of: itemID) { _, _ in settleNeighbor() }
        .onChange(of: today) { _, _ in settleNeighbor() }
        .accessibilityIdentifier("macBazaar")
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 2) { ForEach(Tab.allCases, id: \.self) { tabButton($0) } }
            .padding(4).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(RoomTheme.track.opacity(0.6)))
            .fixedSize().disabled(working)
            .accessibilityElement(children: .contain).accessibilityIdentifier("bazaarTabs")
    }

    private func tabButton(_ value: Tab) -> some View {
        let selected = tab == value
        let count = value == .supplies ? readyOffers(nil) : value == .trade ? openRequests : 0
        return Button { switchTab(to: value) } label: {
            HStack(spacing: 6) {
                Image(systemName: value.symbol).font(.system(size: 11.5, weight: .heavy))
                Text(GameStrings.text(value.titleKey)).font(.system(size: 13.5, weight: .heavy, design: .rounded)).lineLimit(1)
                if count > 0 {
                    Text("\(count)").font(.system(size: 10.5, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1.5).background(value.tint, in: Capsule())
                }
            }
            .foregroundStyle(selected ? value.tint : RoomTheme.ink)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(selected ? RoomTheme.paper : .clear, in: RoundedRectangle(cornerRadius: 11))
            .shadow(color: selected ? RoomTheme.ink.opacity(0.08) : .clear, radius: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GameStrings.text(value.titleKey))
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("bazaarTab_\(value.rawValue)")
    }

    // MARK: Column frame

    /// Every column: a numbered step, a title, an optional note on the right, then its content.
    private func column<Content: View>(step: Int, _ title: String, trailing: String? = nil,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(step)").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(tab.tint, in: Circle()).accessibilityHidden(true)
                Text(title).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                if let trailing {
                    Text(trailing).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white, lineWidth: 2))
        .compositingGroup().shadow(color: RoomTheme.ink.opacity(0.07), radius: 0, y: 3)
    }

    private func keysHint(_ key: String) -> some View {
        Label(GameStrings.text(key), systemImage: "keyboard").font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(RoomTheme.secondary.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.75)
            .accessibilityHidden(true)
    }

    // MARK: Supplies (the old swap market)

    private var stallsColumn: some View {
        column(step: 1, GameStrings.text("bazaar.step.neighbor")) {
            VStack(spacing: 8) { ForEach(CommunityCatalog.neighbors) { stallRow($0) } }
            Spacer(minLength: 0)
            note(GameStrings.format("market.dailyHint130", ExchangeCatalog.dailyLimit))
            keysHint("bazaar.keys.supplies")
        }
    }

    private func stallRow(_ neighbor: NeighborDefinition) -> some View {
        let picked = stallID == neighbor.id
        let left = remaining(neighbor.id)
        let ready = readyOffers(neighbor.id)
        let stage = snapshot?.community.relationship(for: neighbor.id).stage ?? CommunityCatalog.stages[0]
        return Button { stallID = neighbor.id; settleOffer() } label: {
            HStack(spacing: 10) {
                CommunityPortrait(neighbor: neighbor, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.text(neighbor.nameKey)).font(.system(size: 13.5, weight: .heavy)).lineLimit(1)
                    Label(GameStrings.text(stage.nameKey), systemImage: "heart.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RoomTheme.friendshipDeep).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    dots(left)
                    if ready > 0 {
                        Text(GameStrings.format("market.availableCount", ready)).font(.system(size: 10.5, weight: .heavy))
                            .foregroundStyle(RoomTheme.darkMint)
                    }
                }
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? RoomTheme.paleMint.opacity(0.6) : RoomTheme.cream.opacity(left > 0 ? 0.8 : 0.45),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(picked ? RoomTheme.mint : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(GameStrings.format("market.remaining", left, ExchangeCatalog.dailyLimit))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("bazaarStall_\(neighbor.id)")
    }

    private func dots(_ left: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<ExchangeCatalog.dailyLimit, id: \.self) { index in
                Circle().fill(index < left ? RoomTheme.mint : RoomTheme.track).frame(width: 7, height: 7)
            }
            Text("\(left)/\(ExchangeCatalog.dailyLimit)").font(.system(size: 11, weight: .heavy).monospacedDigit())
                .foregroundStyle(left > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
        }
    }

    private var offersColumn: some View {
        column(step: 2, GameStrings.format("market.withNeighbor", stallID.map { neighborName($0) } ?? ""),
               trailing: stallID.map { GameStrings.format("market.remaining", remaining($0), ExchangeCatalog.dailyLimit) }) {
            ScrollView {
                VStack(spacing: 10) { ForEach(stallOffers) { offerCard($0) } }.padding(2)
            }.scrollIndicators(.never)
            Spacer(minLength: 0)
        }
    }

    private func offerCard(_ offer: ExchangeOffer) -> some View {
        let problem = failure(offer)
        let picked = offerID == offer.id
        let tint = statusTint(problem)
        return Button { offerID = offer.id } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: statusSymbol(problem)).font(.system(size: 13, weight: .heavy)).foregroundStyle(tint)
                    Text(GameStrings.text(offer.nameKey)).font(.system(size: 14.5, weight: .heavy)).lineLimit(1)
                    Spacer(minLength: 6)
                    if let snapshot {
                        Text(ExchangePresentation.status(offer, snapshot: snapshot)).font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(tint).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(tint.opacity(0.12), in: Capsule())
                    }
                }
                ViewThatFits(in: .horizontal) { tradeRow(offer, named: true); tradeRow(offer, named: false) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? RoomTheme.paleMint.opacity(0.55) : RoomTheme.cream.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(picked ? RoomTheme.mint : problem == nil ? RoomTheme.mint.opacity(0.4) : .clear,
                                                                     lineWidth: picked ? 2.5 : 1.5))
            .opacity(problem == .exchangeStageRequired || problem == .exchangeDailyLimit ? 0.68 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("bazaarOffer_\(offer.id)")
    }

    private func tradeRow(_ offer: ExchangeOffer, named: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(offer.inputs.enumerated()), id: \.offset) { _, stack in stackTile(stack, receiving: false, named: named) }
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(RoomTheme.mint, in: Circle()).accessibilityHidden(true)
            ForEach(Array(offer.outputs.enumerated()), id: \.offset) { _, stack in stackTile(stack, receiving: true, named: named) }
        }.fixedSize()
    }

    private func stackTile(_ stack: ExchangeStack, receiving: Bool, named: Bool) -> some View {
        let owned = snapshot.map { stack.item.count(in: $0.inventory) } ?? 0
        let short = !receiving && owned < stack.quantity
        return HStack(spacing: 6) {
            ExchangeItemIcon(item: stack.item, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(named ? ExchangePresentation.quantity(stack) : "×\(stack.quantity)").font(.system(size: 12, weight: .heavy)).lineLimit(1)
                if !receiving {
                    Text(GameStrings.format("market.stockShort", owned)).font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(short ? RoomTheme.coralDeep : RoomTheme.secondary)
                }
            }
        }
        .padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 5)
        .background(receiving ? ExchangePalette.receive : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(receiving ? ExchangePalette.goldBorder : short ? RoomTheme.coralBorder : RoomTheme.track,
                                                                 lineWidth: 1.5))
        .help(ExchangePresentation.quantity(stack))
    }

    private func statusTint(_ failure: ActionFailure?) -> Color {
        switch failure {
        case nil: RoomTheme.darkMint
        case .exchangeMaterialsRequired?, .shopInventoryFull?: ExchangePalette.goldInk
        case .exchangeStageRequired?: RoomTheme.friendshipDeep
        default: RoomTheme.secondary
        }
    }
    private func statusSymbol(_ failure: ActionFailure?) -> String {
        switch failure {
        case nil: "checkmark.circle.fill"
        case .exchangeStageRequired?: "lock.fill"
        case .exchangeDailyLimit?: "moon.fill"
        default: "exclamationmark.circle.fill"
        }
    }

    private var suppliesPanel: some View {
        column(step: 3, offer.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("bazaar.step.confirm")) {
            if let offer, let snapshot {
                let problem = failure(offer)
                VStack(alignment: .leading, spacing: 8) {
                    Text(GameStrings.text("bazaar.give")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                    ForEach(Array(offer.inputs.enumerated()), id: \.offset) { _, stack in
                        let have = stack.item.count(in: snapshot.inventory)
                        gainRow(ExchangeItemIcon(item: stack.item, size: 26), ExchangePresentation.quantity(stack),
                                "\(have) → \(max(0, have - stack.quantity))", alert: have < stack.quantity)
                    }
                }
                .padding(12).background(RoomTheme.cream.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(RoomTheme.mint)
                    .frame(maxWidth: .infinity).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(GameStrings.text("bazaar.get")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    ForEach(Array(offer.outputs.enumerated()), id: \.offset) { _, stack in
                        let have = stack.item.count(in: snapshot.inventory)
                        gainRow(ExchangeItemIcon(item: stack.item, size: 26), ExchangePresentation.quantity(stack),
                                "\(have) → \(ExchangePresentation.countAfterTrade(stack.item, offer: offer, inventory: snapshot.inventory))")
                    }
                }
                .padding(12).background(RoomTheme.paleMint.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                if let problem { supplyFix(offer, problem) }
            } else {
                hint(GameStrings.text("bazaar.supplies.pick"))
            }
            Spacer(minLength: 0)
            if let stallID {
                Text(GameStrings.format("bazaar.supplies.left", neighborName(stallID), remaining(stallID)))
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            confirmButton(GameStrings.text("bazaar.trade.confirm"), symbol: "arrow.left.arrow.right", tint: RoomTheme.mint,
                          enabled: offer.map { failure($0) == nil } ?? false, id: "bazaarConfirmSupplies")
        }
    }

    /// Why this swap can't happen yet, and the one place that fixes it.
    @ViewBuilder private func supplyFix(_ offer: ExchangeOffer, _ failure: ActionFailure) -> some View {
        switch failure {
        case .exchangeStageRequired:
            let stage = ExchangePresentation.requiredStage(offer)
            let points = snapshot?.community.relationship(for: offer.neighborID).friendship ?? 0
            warning(GameStrings.format("market.stageRequired", GameStrings.text(stage.nameKey)), symbol: "lock.fill")
            fixButton(GameStrings.format("market.visitForFriendship", max(0, stage.minimumPoints - points)), symbol: "house.fill") {
                visit(offer.neighborID)
            }
        case .exchangeMaterialsRequired:
            warning(GameStrings.text("market.error.materials"))
            fixButton(GameStrings.text("market.restock"), symbol: "cart.fill", action: shop)
        case .shopInventoryFull:
            warning(GameStrings.text("market.bagFull"))
            fixButton(GameStrings.text("market.openBag"), symbol: "backpack.fill") { store.openInventory() }
        case .exchangeDailyLimit:
            warning(GameStrings.text("market.error.limit"), symbol: "moon.fill")
        default:
            warning(GameStrings.text("market.error.missing"))
        }
    }

    // MARK: Handmade pieces

    private var piecesColumn: some View {
        column(step: 1, GameStrings.text("bazaar.pick"), trailing: pieces.isEmpty ? nil : "\(pieces.count)") {
            if pieces.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    hint(GameStrings.text("bazaar.empty"))
                    Button(action: magic) { Label(GameStrings.text("bazaar.empty.go"), systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered).tint(RoomTheme.lilac)
                }.padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 8) { ForEach(pieces) { pieceRow($0) } }.padding(2)
                }.scrollIndicators(.never)
            }
            Spacer(minLength: 0)
            note(GameStrings.text("bazaar.rule"))
            keysHint(tab == .trade ? "bazaar.keys" : "bazaar.keys.sell")
        }
    }

    private func pieceRow(_ piece: HandmadeItem) -> some View {
        let blocker = BazaarCatalog.blocker(piece, in: craft)
        let picked = itemID == piece.id
        return Button { itemID = piece.id } label: {
            HStack(spacing: 10) {
                pieceArt(piece, size: 40).opacity(blocker == nil ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name(piece)).font(.system(size: 13, weight: .heavy)).lineLimit(1)
                        qualityChip(piece.quality)
                    }
                    if blocker == .worn {
                        Text(GameStrings.text("bazaar.blocked.worn")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.coralDeep)
                    } else {
                        MacDurabilityBar(durability: piece.durability, cap: piece.durabilityCap, compact: true)
                    }
                }
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? tab.tint.opacity(0.12) : RoomTheme.cream.opacity(blocker == nil ? 0.8 : 0.45),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(picked ? tab.tint.opacity(0.8) : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("bazaarPiece_\(piece.id)")
    }

    // MARK: Swap handmade

    private var requestsColumn: some View {
        column(step: 2, GameStrings.text("bazaar.requests.title"), trailing: GameStrings.text("bazaar.requests.note")) {
            ScrollView {
                VStack(spacing: 10) { ForEach(requests) { requestCard($0) } }.padding(2)
            }.scrollIndicators(.never)
            Spacer(minLength: 0)
            note(GameStrings.text("bazaar.trade.footer"))
        }
    }

    private func requestCard(_ request: BazaarRequest, compact: Bool = false) -> some View {
        let isTraded = traded(request)
        let fits = wants(request, item)
        let picked = neighborID == request.neighborID && !compact
        return Button { if !isTraded { neighborID = request.neighborID } } label: {
            HStack(alignment: .top, spacing: 12) {
                portrait(request.neighborID, size: compact ? 42 : 48)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(neighborName(request.neighborID)).font(.system(size: 14.5, weight: .heavy)).lineLimit(1)
                        Text(GameStrings.text(request.lineKey)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    labelled("bazaar.wants") { chip(GameStrings.text(request.want.key), tint: RoomTheme.wood.opacity(0.35), text: RoomTheme.ink) }
                    labelled("bazaar.gives") { rewardChips(request) }
                    if !compact { statusLine(request, isTraded: isTraded, fits: fits) }
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? RoomTheme.friendshipPaper : RoomTheme.cream.opacity(isTraded ? 0.4 : 0.85),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(picked ? RoomTheme.friendship : fits ? RoomTheme.friendshipBorder : .clear,
                                                                     lineWidth: picked ? 2.5 : 1.5))
            .opacity(isTraded ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(compact || isTraded)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("bazaarRequest_\(request.neighborID)")
    }

    private func labelled<Content: View>(_ key: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(GameStrings.text(key)).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .frame(minWidth: 34, alignment: .leading)
            content()
        }.lineLimit(1).minimumScaleFactor(0.8)
    }

    private func rewardChips(_ request: BazaarRequest) -> some View {
        HStack(spacing: 5) {
            ForEach(request.materials, id: \.material) { cost in materialChip(cost.material, cost.count) }
            if request.gold > 0 {
                chip(GameStrings.format("bazaar.gold", request.gold), symbol: "dollarsign.circle.fill", tint: RoomTheme.gold.opacity(0.22), text: RoomTheme.ink)
            }
            if let id = request.blueprintID, let definition = CraftCatalog.blueprint(id: id) {
                chip(GameStrings.format("bazaar.blueprint", GameStrings.text(definition.nameKey)), symbol: "scroll.fill",
                     tint: RoomTheme.gold.opacity(0.35), text: RoomTheme.ink)
            }
        }
    }

    @ViewBuilder private func statusLine(_ request: BazaarRequest, isTraded: Bool, fits: Bool) -> some View {
        if isTraded {
            Label(GameStrings.text("bazaar.tradedToday"), systemImage: "checkmark.circle.fill").font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(RoomTheme.secondary)
        } else if let item, itemOpen {
            if fits {
                Label(fitText(request, item), systemImage: "sparkles").font(.system(size: 11.5, weight: .heavy))
                    .foregroundStyle(RoomTheme.friendshipDeep).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(GameStrings.text("bazaar.notWanted")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            }
        }
    }

    private func fitText(_ request: BazaarRequest, _ item: HandmadeItem) -> String {
        let deal = BazaarCatalog.deal(request, for: item)
        let piece = name(item) + "（" + GameStrings.text(item.quality.titleKey) + "）"
        var extras: [String] = []
        if deal.materialChange > 0, let first = request.materials.first {
            extras.append(GameStrings.text(first.material.titleKey) + " ×\(deal.materialChange)")
        }
        if deal.goldChange > 0 { extras.append(GameStrings.format("bazaar.gold", deal.goldChange)) }
        if !extras.isEmpty {
            return GameStrings.format("bazaar.fits.more", piece, neighborName(request.neighborID),
                                      extras.joined(separator: " " + GameStrings.text("bazaar.and") + " "))
        }
        if deal.goldChange < 0 { return GameStrings.format("bazaar.fits.less", piece, -deal.goldChange) }
        return GameStrings.format("bazaar.fits.same", piece)
    }

    private var tradePanel: some View {
        column(step: 3, request.map { GameStrings.format("bazaar.trade.title", neighborName($0.neighborID)) } ?? GameStrings.text("bazaar.step.confirm")) {
            if let item, let request, dealReady {
                let deal = BazaarCatalog.deal(request, for: item)
                Text(GameStrings.text("bazaar.give")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                pieceCard(item)
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(RoomTheme.friendship)
                    .frame(maxWidth: .infinity).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(GameStrings.text("bazaar.get")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    ForEach(deal.materials, id: \.material) { cost in
                        let before = craft.count(of: cost.material)
                        gainRow(MacMaterialArt(material: cost.material, size: 26), GameStrings.text(cost.material.titleKey) + " ×\(cost.count)",
                                "\(before) → \(min(CraftCatalog.maximumMaterial, before + cost.count))")
                    }
                    if deal.gold > 0 {
                        let gold = snapshot?.player.gold ?? 0
                        gainRow(coin(26), GameStrings.format("bazaar.gold", deal.gold), "\(gold) → \(gold + deal.gold)")
                    }
                    if let id = deal.blueprintID, let definition = CraftCatalog.blueprint(id: id) {
                        let uses = craft.usesLeft(id)
                        gainRow(Image(systemName: "scroll.fill").foregroundStyle(RoomTheme.gold).frame(width: 26, height: 26),
                                GameStrings.format("bazaar.blueprint", GameStrings.text(definition.nameKey)),
                                GameStrings.format("bazaar.uses", uses, min(definition.tier.maximumUses, uses + definition.tier.usesPerCopy)))
                    }
                    gainRow(Image(systemName: "heart.fill").foregroundStyle(RoomTheme.coral).frame(width: 26, height: 26),
                            GameStrings.format("bazaar.friendship", neighborName(request.neighborID), BazaarCatalog.tradeFriendship), nil)
                }
                .padding(12).background(RoomTheme.paleMint.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                warning(GameStrings.text("bazaar.trade.warning"))
            } else if wornPicked {
                wornHint
            } else {
                hint(GameStrings.text("bazaar.trade.pick"))
            }
            Spacer(minLength: 0)
            progress
            confirmButton(GameStrings.text("bazaar.trade.confirm"), symbol: "arrow.left.arrow.right", tint: RoomTheme.friendship,
                          enabled: dealReady, id: "bazaarConfirmTrade")
        }
    }

    // MARK: Sell handmade

    private var priceColumn: some View {
        column(step: 2, GameStrings.text("bazaar.sell.how")) {
            HStack(spacing: 12) {
                GameIcon(asset: "shopkeeper-chestnut", symbol: "person.fill", size: 58, tint: RoomTheme.gold)
                    .frame(width: 58, height: 58).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(GameStrings.text("bazaar.shop.name")).font(.system(size: 16, weight: .heavy))
                        Text(GameStrings.text("bazaar.shop.role")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    }
                    Text(GameStrings.text("bazaar.shop.line")).font(.system(size: 12.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            if let item, itemOpen {
                breakdown(item)
                Text(GameStrings.text("bazaar.sell.compare")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                if let best = bestRequest(for: item) { requestCard(best, compact: true) }
                else { hint(GameStrings.text("bazaar.sell.noCompare")) }
                Text(GameStrings.text("bazaar.sell.compareNote")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                hint(GameStrings.text("bazaar.sell.pick"))
            }
            Spacer(minLength: 0)
            note(GameStrings.text("bazaar.sell.footer"))
        }
    }

    private func breakdown(_ item: HandmadeItem) -> some View {
        let quote = BazaarCatalog.saleQuote(for: item)
        let tier = item.blueprint.map { GameStrings.text($0.tier.titleKey) } ?? ""
        return VStack(spacing: 9) {
            if quote.isFragile {
                priceRow(GameStrings.text("bazaar.sell.materials"), "\(quote.materialValue)")
                priceRow(GameStrings.text("bazaar.sell.fragile"), "× 0.5")
            } else {
                priceRow(GameStrings.format("bazaar.sell.base", name(item), tier), "\(quote.basePrice)")
                priceRow(GameStrings.format("bazaar.sell.quality", GameStrings.text(item.quality.titleKey)), "× " + ratio(quote.qualityPercent))
                priceRow(GameStrings.format("bazaar.sell.attributes", item.attributes.count), "+ \(quote.attributeBonus)")
                priceRow(GameStrings.format("bazaar.sell.durability", item.durability, item.durabilityCap, GameStrings.text(item.stage.titleKey)),
                         "× " + ratio(quote.durabilityPercent))
            }
            Divider()
            HStack {
                Text(GameStrings.text("bazaar.sell.total")).font(.system(size: 13.5, weight: .heavy))
                Spacer()
                Text(GameStrings.format("bazaar.gold", quote.price)).font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Self.goldInk)
            }
        }
        .padding(14).background(RoomTheme.cream.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func priceRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: .heavy).monospacedDigit())
        }
    }
    private func ratio(_ percent: Int) -> String { String(format: "%.2f", Double(percent) / 100) }

    private var sellPanel: some View {
        column(step: 3, GameStrings.text("bazaar.sell.title")) {
            if let item, itemOpen {
                let quote = BazaarCatalog.saleQuote(for: item)
                let gold = snapshot?.player.gold ?? 0
                Text(GameStrings.text("bazaar.sell.give")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                pieceCard(item)
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(RoomTheme.gold)
                    .frame(maxWidth: .infinity).accessibilityHidden(true)
                HStack(spacing: 12) {
                    coin(40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(GameStrings.format("bazaar.gold", quote.price)).font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Self.goldInk)
                        Text("\(gold) → \(gold + quote.price)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(RoomTheme.secondary)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                warning(GameStrings.text("bazaar.sell.warning"))
            } else if wornPicked {
                wornHint
            } else {
                hint(GameStrings.text("bazaar.sell.pick"))
            }
            Spacer(minLength: 0)
            Button {
                if let item, let best = bestRequest(for: item) { neighborID = best.neighborID }
                switchTab(to: .trade)
            } label: {
                Label(GameStrings.text("bazaar.sell.toTrade"), systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(item.flatMap { bestRequest(for: $0) } == nil)
            confirmButton(GameStrings.format("bazaar.sell.confirm", item.map { BazaarCatalog.saleQuote(for: $0).price } ?? 0),
                          symbol: "dollarsign.circle.fill", tint: RoomTheme.gold, enabled: itemOpen, id: "bazaarConfirmSell")
        }
    }

    private var wornPicked: Bool { item.map { BazaarCatalog.blocker($0, in: craft) == .worn } ?? false }
    /// A worn piece was picked: say why it can't go, and offer the wardrobe to take it off.
    @ViewBuilder private var wornHint: some View {
        if let item { pieceCard(item).opacity(0.7) }
        warning(GameStrings.text("bazaar.error.worn"))
        fixButton(GameStrings.text("bazaar.toWardrobe"), symbol: "hanger", action: wardrobe)
    }

    private var progress: some View {
        let total = craft.bazaar.totalTrades
        let charm = CraftCatalog.blueprints.first { $0.source.key == "bazaarTrades" }
        var goal = 0
        if let charm, case .bazaarTrades(let count) = charm.source { goal = count }
        let learning = charm.map { !craft.grantedSources.contains($0.id) && total < goal } ?? false
        return VStack(alignment: .leading, spacing: 5) {
            Text(learning ? GameStrings.format("bazaar.progress", total, goal, goal - total, GameStrings.text(charm?.nameKey ?? ""))
                          : GameStrings.format("bazaar.progress.done", total))
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if learning {
                ProgressView(value: Double(total), total: Double(max(goal, 1))).tint(RoomTheme.friendship)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Pieces of UI

    private func confirmButton(_ title: String, symbol: String, tint: Color, enabled: Bool, id: String) -> some View {
        Button { confirm() } label: {
            Label(title, systemImage: symbol).font(.system(size: 15, weight: .heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).tint(tint).controlSize(.large)
        .disabled(!enabled || working).help("↩").accessibilityIdentifier(id)
    }

    private func fixButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.large)
    }

    private func pieceCard(_ item: HandmadeItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            pieceArt(item, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { Text(name(item)).font(.system(size: 14, weight: .heavy)).lineLimit(1); qualityChip(item.quality) }
                Text(item.attributes.map { GameStrings.text($0.attribute.titleKey) + " " + MacCraftStyle.valueText($0.attribute, $0.value) }
                    .joined(separator: " · "))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Self.goldInk)
                    .fixedSize(horizontal: false, vertical: true)
                MacDurabilityBar(durability: item.durability, cap: item.durabilityCap, compact: true)
            }
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.cream.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.gold.opacity(0.7), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private func gainRow<Icon: View>(_ icon: Icon, _ title: String, _ change: String?, alert: Bool = false) -> some View {
        HStack(spacing: 9) {
            icon
            Text(title).font(.system(size: 13, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if let change {
                Text(change).font(.system(size: 11.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(alert ? RoomTheme.coralDeep : RoomTheme.secondary)
            }
        }
    }

    private func pieceArt(_ item: HandmadeItem, size: CGFloat) -> some View {
        Group {
            if let definition = item.blueprint { MacPieceArt(definition: definition, size: size * 0.85) }
            else { Image(systemName: "questionmark") }
        }
        .frame(width: size, height: size)
        .background(MacCraftStyle.tint(item.quality).opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3))
    }

    private func portrait(_ neighborID: String, size: CGFloat) -> some View {
        Group {
            if let neighbor = CommunityCatalog.neighbor(id: neighborID) { CommunityPortrait(neighbor: neighbor, size: size) }
            else { Image(systemName: "person.crop.circle.fill").frame(width: size, height: size) }
        }
    }

    private func qualityChip(_ quality: OutingDecorQuality) -> some View {
        Text(GameStrings.text(quality.titleKey)).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 2).background(MacCraftStyle.tint(quality), in: Capsule())
    }

    private func chip(_ title: String, symbol: String? = nil, tint: Color, text: Color) -> some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)) }
            Text(title)
        }
        .font(.system(size: 11, weight: .heavy)).foregroundStyle(text)
        .padding(.horizontal, 8).padding(.vertical, 3).background(tint, in: Capsule())
    }

    private func materialChip(_ material: CraftMaterial, _ count: Int) -> some View {
        HStack(spacing: 3) {
            MacMaterialArt(material: material, size: 15)
            Text(GameStrings.text(material.titleKey) + " ×\(count)")
        }
        .font(.system(size: 11, weight: .heavy)).foregroundStyle(MacCraftStyle.tint(material))
        .padding(.horizontal, 7).padding(.vertical, 3).background(MacCraftStyle.tint(material).opacity(0.14), in: Capsule())
    }

    private func coin(_ size: CGFloat) -> some View {
        GameIcon(asset: "icon-coin", symbol: "dollarsign.circle.fill", size: size, tint: RoomTheme.gold)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ text: String, symbol: String = "exclamationmark.triangle.fill") -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12, weight: .heavy))
            .foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RoomTheme.gold.opacity(0.35), lineWidth: 1))
    }

    private func name(_ item: HandmadeItem) -> String { item.blueprint.map { GameStrings.text($0.nameKey) } ?? item.blueprintID }
    private func neighborName(_ id: String) -> String { CommunityCatalog.neighbor(id: id).map { GameStrings.text($0.nameKey) } ?? id }

    // MARK: Selection and actions

    /// First visit: a link's tab, else the handmade swap when a neighbour wants one of your pieces, else supplies.
    private func start() {
        guard !started else { apply(opening); return }
        started = true
        settleSelection()
        tab = openRequests > 0 ? .trade : .supplies
        settleStall()
        apply(opening)
    }

    private func apply(_ value: MacBazaarOpening?) {
        guard let value else { return }
        tab = value.tab
        if let id = value.neighborID, CommunityCatalog.neighbor(id: id) != nil { stallID = id; settleOffer() }
        opening = nil
    }

    private func switchTab(to value: Tab) {
        guard tab != value else { return }
        tab = value
        store.playNavigationSound()
    }

    /// The neighbour (not yet traded with today) who gives the most gold for this piece.
    private func bestRequest(for item: HandmadeItem) -> BazaarRequest? {
        requests.filter { wants($0, item) }.max { BazaarCatalog.deal($0, for: item).gold < BazaarCatalog.deal($1, for: item).gold }
    }

    private func settleSelection() {
        if itemID == nil || item == nil {
            itemID = pieces.first { BazaarCatalog.blocker($0, in: craft) == nil }?.id ?? pieces.first?.id
        }
        settleNeighbor()
    }

    /// Keep the chosen neighbour if they still want the piece; otherwise the best match.
    private func settleNeighbor() {
        if let request, wants(request, item) { return }
        neighborID = item.flatMap { bestRequest(for: $0)?.neighborID } ?? neighborID.flatMap { id in
            requests.contains { $0.neighborID == id && !traded($0) } ? id : nil
        }
    }

    /// Supplies: start on a stall with a swap ready, else the first stall.
    private func settleStall() {
        if stallID == nil {
            stallID = CommunityCatalog.neighbors.first { readyOffers($0.id) > 0 }?.id ?? CommunityCatalog.neighbors.first?.id
        }
        settleOffer()
    }

    /// Keep the chosen offer if it belongs to this stall; otherwise its first ready one.
    private func settleOffer() {
        let offers = stallOffers
        if let offerID, offers.contains(where: { $0.id == offerID }) { return }
        offerID = (offers.first { failure($0) == nil } ?? offers.first)?.id
    }

    private func confirm() {
        guard !working else { return }
        switch tab {
        case .supplies:
            guard let offer, failure(offer) == nil else { return }
            working = true
            Task {
                _ = await store.exchange(offerID: offer.id)
                working = false
            }
        case .trade:
            guard let item, dealReady, let neighbor = neighborID else { return }
            let id = item.id
            working = true
            Task {
                if await store.tradeHandmade(neighborID: neighbor, itemID: id) { itemID = nil; settleSelection() }
                working = false
            }
        case .sell:
            guard let item, itemOpen else { return }
            let id = item.id
            working = true
            Task {
                if await store.sellHandmade(id) { itemID = nil; settleSelection() }
                working = false
            }
        }
    }

    private func step<T: Equatable>(_ list: [T], from current: T?, forward: Bool) -> T? {
        guard !list.isEmpty else { return current }
        let index = current.flatMap { list.firstIndex(of: $0) } ?? (forward ? -1 : list.count)
        return list[min(list.count - 1, max(0, index + (forward ? 1 : -1)))]
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !working else { return .ignored }
        let forward = press.key == .downArrow || press.key == .rightArrow
        switch (press.key, tab) {
        case (.upArrow, .supplies), (.downArrow, .supplies):
            stallID = step(CommunityCatalog.neighbors.map(\.id), from: stallID, forward: forward)
            settleOffer()
        case (.leftArrow, .supplies), (.rightArrow, .supplies):
            offerID = step(stallOffers.map(\.id), from: offerID, forward: forward)
        case (.upArrow, _), (.downArrow, _):
            itemID = step(pieces.map(\.id), from: itemID, forward: forward)
        case (.leftArrow, .trade), (.rightArrow, .trade):
            neighborID = step(requests.filter { !traded($0) }.map(\.neighborID), from: neighborID, forward: forward)
        case (.tab, _):
            let all = Tab.allCases
            let index = all.firstIndex(of: tab) ?? 0
            let back = press.modifiers.contains(.shift)
            switchTab(to: all[(index + (back ? all.count - 1 : 1)) % all.count])
        case (.return, _):
            confirm()
        default:
            return .ignored
        }
        return .handled
    }
}
#endif
