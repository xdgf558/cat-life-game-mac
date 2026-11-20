#if os(macOS)
import SwiftUI
import CatGameCore

/// 3.2 猫町集市: E1 swap with a neighbour, E2 sell to the shop. Pieces on the left, today's requests
/// (or the shop's price) in the middle, the deal and its confirm button on the right. Every number
/// comes from `BazaarCatalog`, so what the page shows is what the trade gives.
@MainActor
struct MacBazaarView: View {
    let store: GameStore
    var town: () -> Void = {}
    var wardrobe: () -> Void = {}
    var magic: () -> Void = {}

    enum Tab: Hashable { case trade, sell }
    @State private var tab: Tab = .trade
    @State private var itemID: String?
    @State private var neighborID: String?
    @State private var working = false
    @FocusState private var focused: Bool

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }
    private var today: String? { store.snapshot?.tasks.dailyDayKey }
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

    var body: some View {
        VStack(spacing: 14) {
            MacPlaceBanner(store: store, place: .bazaar, height: 110, onTown: town) {
                MacSegmented(selection: Binding(get: { tab }, set: { tab = $0; store.playNavigationSound() }), options: [
                    (Tab.trade, GameStrings.text("bazaar.tab.trade")), (Tab.sell, GameStrings.text("bazaar.tab.sell"))
                ]).fixedSize().disabled(working).accessibilityIdentifier("bazaarTabs")
            }
            HStack(alignment: .top, spacing: 14) {
                piecesColumn.frame(width: 290)
                Group { if tab == .trade { requestsColumn } else { priceColumn } }.frame(maxWidth: .infinity)
                Group { if tab == .trade { tradePanel } else { sellPanel } }.frame(width: 300)
            }
            .frame(maxHeight: .infinity)
            .disabled(working)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear { focused = true; settleSelection() }
        .onChange(of: craft.handmade.map(\.id)) { _, _ in settleSelection() }
        .onChange(of: itemID) { _, _ in settleNeighbor() }
        .onChange(of: today) { _, _ in settleNeighbor() }
        .accessibilityIdentifier("macBazaar")
    }

    // MARK: Columns

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white, lineWidth: 2))
    }

    private var piecesColumn: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(GameStrings.text("bazaar.pick")).font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                if pieces.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(GameStrings.text("bazaar.empty")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: magic) { Label(GameStrings.text("bazaar.empty.go"), systemImage: "wand.and.stars") }
                            .buttonStyle(.bordered).tint(RoomTheme.lilac)
                    }.padding(.top, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 8) { ForEach(pieces) { pieceRow($0) } }.padding(2)
                    }.scrollIndicators(.never)
                }
                Spacer(minLength: 0)
                Text(GameStrings.text("bazaar.rule")).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            .background(picked ? RoomTheme.paleMint.opacity(0.6) : RoomTheme.cream.opacity(blocker == nil ? 0.8 : 0.45),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(picked ? RoomTheme.gold : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("bazaarPiece_\(piece.id)")
    }

    private var requestsColumn: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(GameStrings.text("bazaar.requests.title")).font(.system(size: 18, weight: .heavy, design: .rounded))
                    Spacer(minLength: 8)
                    Text(GameStrings.text("bazaar.requests.note")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                ScrollView {
                    VStack(spacing: 9) { ForEach(requests) { requestCard($0) } }.padding(2)
                }.scrollIndicators(.never)
                Spacer(minLength: 0)
                note(GameStrings.text("bazaar.trade.footer"))
            }
        }
    }

    private func requestCard(_ request: BazaarRequest, compact: Bool = false) -> some View {
        let isTraded = traded(request)
        let fits = wants(request, item)
        let picked = neighborID == request.neighborID && !compact
        return Button { if !isTraded { neighborID = request.neighborID } } label: {
            HStack(alignment: .top, spacing: 11) {
                portrait(request.neighborID, size: compact ? 42 : 50)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(neighborName(request.neighborID)).font(.system(size: 14.5, weight: .heavy))
                        Text(GameStrings.text(request.lineKey)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    offerLine(request)
                    if !compact { statusLine(request, isTraded: isTraded, fits: fits) }
                }
                Spacer(minLength: 0)
            }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(picked ? RoomTheme.paleMint.opacity(0.55) : RoomTheme.cream.opacity(isTraded ? 0.4 : 0.85),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(picked ? RoomTheme.mint : fits ? RoomTheme.mint.opacity(0.45) : .clear,
                                                                     lineWidth: picked ? 2.5 : 1.5))
            .opacity(isTraded ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(compact || isTraded)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("bazaarRequest_\(request.neighborID)")
    }

    private func offerLine(_ request: BazaarRequest) -> some View {
        HStack(spacing: 6) {
            Text(GameStrings.text("bazaar.wants")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            chip(GameStrings.text(request.want.key), tint: RoomTheme.wood.opacity(0.35), text: RoomTheme.ink)
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.mint)
            Text(GameStrings.text("bazaar.gives")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            ForEach(request.materials, id: \.material) { cost in materialChip(cost.material, cost.count) }
            if request.gold > 0 { chip(GameStrings.format("bazaar.gold", request.gold), symbol: "dollarsign.circle.fill", tint: RoomTheme.gold.opacity(0.22), text: RoomTheme.ink) }
            if let id = request.blueprintID, let definition = CraftCatalog.blueprint(id: id) {
                chip(GameStrings.format("bazaar.blueprint", GameStrings.text(definition.nameKey)), symbol: "scroll.fill",
                     tint: RoomTheme.gold.opacity(0.35), text: RoomTheme.ink)
            }
        }.lineLimit(1).minimumScaleFactor(0.75)
    }

    @ViewBuilder private func statusLine(_ request: BazaarRequest, isTraded: Bool, fits: Bool) -> some View {
        if isTraded {
            Label(GameStrings.text("bazaar.traded"), systemImage: "checkmark.circle.fill").font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(RoomTheme.secondary)
        } else if let item, itemOpen {
            if fits {
                Text(fitText(request, item)).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var priceColumn: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    GameIcon(asset: "shopkeeper-chestnut", symbol: "person.fill", size: 44, tint: RoomTheme.gold)
                        .frame(width: 58, height: 58).background(RoomTheme.gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
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
                    Text(GameStrings.text("bazaar.sell.how")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    breakdown(item)
                    Text(GameStrings.text("bazaar.sell.compare")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    if let best = bestRequest(for: item) { requestCard(best, compact: true) }
                    else { Text(GameStrings.text("bazaar.sell.noCompare")).font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary) }
                    Text(GameStrings.text("bazaar.sell.compareNote")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(GameStrings.text("bazaar.sell.pick")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                }
                Spacer(minLength: 0)
                note(GameStrings.text("bazaar.sell.footer"))
            }
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
                    .foregroundStyle(Color(red: 0.70, green: 0.45, blue: 0.10))
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

    // MARK: Right panels

    private var tradePanel: some View {
        card {
            VStack(alignment: .leading, spacing: 11) {
                Label(request.map { GameStrings.format("bazaar.trade.title", neighborName($0.neighborID)) } ?? GameStrings.text("bazaar.tab.trade"),
                      systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(RoomTheme.darkMint)
                if let item, let request, dealReady {
                    let deal = BazaarCatalog.deal(request, for: item)
                    Text(GameStrings.text("bazaar.give")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                    pieceCard(item)
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(RoomTheme.mint)
                        .frame(maxWidth: .infinity)
                    Text(GameStrings.text("bazaar.get")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    VStack(spacing: 8) {
                        ForEach(deal.materials, id: \.material) { cost in
                            let before = craft.count(of: cost.material)
                            gainRow(MacMaterialArt(material: cost.material, size: 26), GameStrings.text(cost.material.titleKey) + " ×\(cost.count)",
                                    "\(before) → \(min(CraftCatalog.maximumMaterial, before + cost.count))")
                        }
                        if deal.gold > 0 {
                            let gold = store.snapshot?.player.gold ?? 0
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
                    Text(GameStrings.text("bazaar.trade.pick")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(progressText).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { confirm() } label: {
                    Label { Text(GameStrings.text("bazaar.trade.confirm")) } icon: { Image(systemName: "arrow.left.arrow.right") }
                        .font(.system(size: 15, weight: .heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(RoomTheme.mint).controlSize(.large)
                .disabled(!dealReady || working).help("↩").accessibilityIdentifier("bazaarConfirmTrade")
            }
        }
    }

    private var sellPanel: some View {
        card {
            VStack(alignment: .leading, spacing: 11) {
                Label(GameStrings.text("bazaar.sell.title"), systemImage: "storefront.fill")
                    .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.70, green: 0.45, blue: 0.10))
                if let item, itemOpen {
                    let quote = BazaarCatalog.saleQuote(for: item)
                    let gold = store.snapshot?.player.gold ?? 0
                    Text(GameStrings.text("bazaar.sell.give")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                    pieceCard(item)
                    Text(GameStrings.text("bazaar.get")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    HStack(spacing: 12) {
                        coin(40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(GameStrings.format("bazaar.gold", quote.price)).font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 0.70, green: 0.45, blue: 0.10))
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
                    Text(GameStrings.text("bazaar.sell.pick")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    if let item, let best = bestRequest(for: item) { neighborID = best.neighborID }
                    tab = .trade
                } label: {
                    Label(GameStrings.text("bazaar.sell.toTrade"), systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(item.flatMap { bestRequest(for: $0) } == nil)
                Button { confirm() } label: {
                    Text(GameStrings.format("bazaar.sell.confirm", item.map { BazaarCatalog.saleQuote(for: $0).price } ?? 0))
                        .font(.system(size: 15, weight: .heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(RoomTheme.gold).controlSize(.large)
                .disabled(!itemOpen || working).help("↩").accessibilityIdentifier("bazaarConfirmSell")
            }
        }
    }

    private var wornPicked: Bool { item.map { BazaarCatalog.blocker($0, in: craft) == .worn } ?? false }
    /// A worn piece was picked: say why it can't go, and offer the wardrobe to take it off.
    private var wornHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item { pieceCard(item).opacity(0.7) }
            warning(GameStrings.text("bazaar.error.worn"))
            Button(action: wardrobe) { Label(GameStrings.text("bazaar.toWardrobe"), systemImage: "hanger").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private var progressText: String {
        let total = craft.bazaar.totalTrades
        if let charm = CraftCatalog.blueprints.first(where: { $0.source.key == "bazaarTrades" }),
           case .bazaarTrades(let goal) = charm.source, !craft.grantedSources.contains(charm.id), total < goal {
            return GameStrings.format("bazaar.progress", total, goal, goal - total, GameStrings.text(charm.nameKey))
        }
        return GameStrings.format("bazaar.progress.done", total)
    }

    // MARK: Pieces of UI

    private func pieceCard(_ item: HandmadeItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            pieceArt(item, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { Text(name(item)).font(.system(size: 14, weight: .heavy)).lineLimit(1); qualityChip(item.quality) }
                Text(item.attributes.map { GameStrings.text($0.attribute.titleKey) + " " + MacCraftStyle.valueText($0.attribute, $0.value) }
                    .joined(separator: " · "))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 0.70, green: 0.45, blue: 0.10))
                    .fixedSize(horizontal: false, vertical: true)
                MacDurabilityBar(durability: item.durability, cap: item.durabilityCap, compact: true)
            }
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.cream.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.gold.opacity(0.7), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private func gainRow<Icon: View>(_ icon: Icon, _ title: String, _ change: String?) -> some View {
        HStack(spacing: 9) {
            icon
            Text(title).font(.system(size: 13, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if let change { Text(change).font(.system(size: 11.5, weight: .bold).monospacedDigit()).foregroundStyle(RoomTheme.secondary) }
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
        let asset = CommunityCatalog.neighbor(id: neighborID)?.portraitAssetName ?? ""
        return GameIcon(asset: asset, symbol: "person.crop.circle.fill", size: size, tint: RoomTheme.friendship)
            .frame(width: size, height: size).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: size * 0.32))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.32))
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

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .heavy))
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

    private func confirm() {
        guard !working, let item else { return }
        let id = item.id
        if tab == .trade {
            guard dealReady, let neighbor = neighborID else { return }
            working = true
            Task {
                if await store.tradeHandmade(neighborID: neighbor, itemID: id) { itemID = nil; settleSelection() }
                working = false
            }
        } else {
            guard itemOpen else { return }
            working = true
            Task {
                if await store.sellHandmade(id) { itemID = nil; settleSelection() }
                working = false
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !working else { return .ignored }
        switch press.key {
        case .upArrow, .downArrow:
            let ids = pieces.map(\.id)
            guard !ids.isEmpty else { return .handled }
            let index = itemID.flatMap { ids.firstIndex(of: $0) } ?? 0
            itemID = ids[min(ids.count - 1, max(0, index + (press.key == .downArrow ? 1 : -1)))]
            return .handled
        case .leftArrow, .rightArrow:
            guard tab == .trade else { return .ignored }
            let open = requests.filter { !traded($0) }.map(\.neighborID)
            guard !open.isEmpty else { return .handled }
            let index = neighborID.flatMap { open.firstIndex(of: $0) } ?? 0
            neighborID = open[min(open.count - 1, max(0, index + (press.key == .rightArrow ? 1 : -1)))]
            return .handled
        case .tab:
            tab = tab == .trade ? .sell : .trade
            store.playNavigationSound()
            return .handled
        case .return:
            confirm()
            return .handled
        default:
            return .ignored
        }
    }
}
#endif
