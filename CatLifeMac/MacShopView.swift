import SwiftUI
import CatGameCore

@MainActor
struct MacShopView: View {
    let store: GameStore
    var onHome: () -> Void = {}
    var preferences: MacPreferences? = nil
    var onTown: (() -> Void)? = nil
    @State private var category = MacShopCategory.furniture
    @State private var search = ""
    @State private var placement = 0
    @State private var quality = 0
    @State private var hidesOwned = false
    @State private var audience = 0
    @State private var quantity = 1
    @State private var page = 0
    @State private var selectedID: String?
    @State private var isVisible = false
    @State private var previewFacing: FurnitureOrientation = .front
    @State private var pendingArrange: (id: String, count: Int, generation: UUID)?
    @State private var showsInspiration = false
    /// Columns × rows that fit the grid area, so one page is exactly one screen (no scrolling inside a page).
    @State private var gridFit = (columns: 4, rows: 2)
    @FocusState private var searchFocused: Bool
    private static let cardHeight: CGFloat = 236
    private static let cardMinWidth: CGFloat = 172
    private static let gridSpacing: CGFloat = 12
    private var pageSize: Int { max(1, gridFit.columns * gridFit.rows) }

    private var products: [MacShopProduct] {
        category.products.filter { product in
            let matchesText = search.isEmpty || product.name.localizedCaseInsensitiveContains(search)
                || product.detail.localizedCaseInsensitiveContains(search)
            let matchesPlacement = placement == 0 || product.wall == (placement == 2)
            let matchesQuality = quality == 0 || product.premium == (quality == 2)
            let matchesAudience = category != .supplies || audience == 0 || product.isForPlayer == (audience == 1)
            return matchesText && matchesPlacement && matchesQuality && matchesAudience && (!hidesOwned || product.count(in: store.snapshot) == 0)
        }
    }
    private var selected: MacShopProduct? { products.first { $0.id == selectedID } ?? products.first }
    private var pages: Int { max(1, (products.count + pageSize - 1) / pageSize) }
    private var visible: [MacShopProduct] { Array(products.dropFirst(min(page, pages - 1) * pageSize).prefix(pageSize)) }

    var body: some View {
        VStack(spacing: 14) {
            MacPlaceBanner(store: store, place: .shop, height: 132, onTown: onTown) { categoryTabs }
            HStack(alignment: .top, spacing: 16) {
                browser.frame(maxWidth: .infinity, maxHeight: .infinity)
                detail.frame(width: 292)
            }
        }.font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
            .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macShopPage")
            .onAppear { isVisible = true; followSharedCategory() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacContentCommand"))) { note in
                guard isVisible, let raw = note.object as? String, let command = MacCommand(rawValue: raw) else { return }
                switch command {
                case .listUp: moveSelection(-gridFit.columns)
                case .listDown: moveSelection(gridFit.columns)
                case .previousPage: movePage(-1)
                case .nextPage: movePage(1)
                case .search: searchFocused = true
                case .confirm: if let product = selected { purchase(product, arrange: false) }
                default: break
                }
            }
            .onDisappear { isVisible = false; pendingArrange = nil }
            .onChange(of: category) { _, value in
                resetBrowser()
                if let shared = ShopCategory(rawValue: value.rawValue), store.shopCategory != shared { store.shopCategory = shared }
            }
            .onChange(of: store.shopCategory) { _, _ in followSharedCategory() }
            .onChange(of: store.activeSheet) { _, value in if value == .shop { followSharedCategory() } }
            .onChange(of: search) { _, _ in page = 0 }
            .onChange(of: placement) { _, _ in page = 0 }
            .onChange(of: quality) { _, _ in page = 0 }
            .onChange(of: hidesOwned) { _, _ in page = 0 }
            .onChange(of: audience) { _, _ in page = 0; selectedID = nil }
            .onChange(of: selected?.id) { _, _ in quantity = 1 }
            .onChange(of: store.isBusy) { _, busy in if !busy { finishPurchase() } }
            .onChange(of: store.saveSceneGeneration) { _, _ in pendingArrange = nil }
    }

    /// Shop categories live on the scene banner.
    private var categoryTabs: some View {
        HStack(spacing: 6) {
            ForEach(MacShopCategory.allCases) { value in
                let isOn = category == value
                Button { category = value } label: {
                    HStack(spacing: 5) {
                        Image(systemName: value.symbol)
                        Text(GameStrings.text(value.titleKey))
                        Text("\(value.products.count)").font(.system(size: 10.5, weight: .heavy)).opacity(0.7)
                    }.font(.system(size: 12.5, weight: .heavy)).padding(.horizontal, 11).padding(.vertical, 6)
                        .background(isOn ? RoomTheme.mint : RoomTheme.paper.opacity(0.95), in: Capsule())
                        .foregroundStyle(isOn ? .white : RoomTheme.ink).contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("macShopCategory_\(value.rawValue)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(RoomTheme.secondary)
            TextField(GameStrings.text("mac.shop.search"), text: $search).textFieldStyle(.plain)
                .focused($searchFocused).accessibilityIdentifier("macShopSearch")
            Button { searchFocused = true } label: { Text(keyLabel(.search)).font(.caption.monospaced()) }
                .buttonStyle(.plain)
                .accessibilityLabel(GameStrings.text("mac.shop.search"))
        }.padding(.horizontal, 14).padding(.vertical, 10).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white, lineWidth: 2))
    }

    /// Category-specific filters, quality, "hide owned" and the decorating tip, in one compact row.
    @ViewBuilder private var filterChips: some View {
        if category == .supplies {
            chipGroup("supply.player.audience", symbol: "person.2.fill", selection: $audience,
                      titles: ["mac.content.all", "supply.player.forMe", "supply.player.forCat"])
        }
        if category == .furniture {
            chipGroup("mac.shop.placement", symbol: "square.split.bottomrightquarter", selection: $placement,
                      titles: ["mac.content.all", "build68.filter.floor", "build68.filter.wall"])
        }
        chipGroup("mac.shop.quality", symbol: "sparkle", selection: $quality,
                  titles: ["mac.content.all", "mac.shop.standard", "mac.shop.premium"])
        Toggle(GameStrings.text("mac.shop.hideOwned"), isOn: $hidesOwned).toggleStyle(.switch).controlSize(.mini)
            .font(.caption.weight(.bold)).fixedSize().accessibilityIdentifier("macShopHideOwned")
        Button { showsInspiration.toggle() } label: {
            Image(systemName: "lightbulb.fill").foregroundStyle(RoomTheme.friendshipDeep).padding(7)
                .background(RoomTheme.friendshipPaper, in: Circle())
        }.buttonStyle(.plain).help(GameStrings.text("habit67.shop.goalTitle"))
            .accessibilityLabel(GameStrings.text("habit67.shop.goalTitle"))
            .popover(isPresented: $showsInspiration) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(GameStrings.text("habit67.shop.goalTitle"), systemImage: "lightbulb.fill").foregroundStyle(RoomTheme.friendshipDeep)
                    Text(GameStrings.text("mac.shop.inspiration")).font(.caption).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(14).frame(width: 280).background(RoomTheme.friendshipPaper)
            }
    }

    private func chipGroup(_ title: String, symbol: String, selection: Binding<Int>, titles: [String]) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary).padding(.trailing, 2)
                .help(GameStrings.text(title)).accessibilityLabel(GameStrings.text(title))
            ForEach(titles.indices, id: \.self) { index in
                Button { selection.wrappedValue = index } label: {
                    Text(GameStrings.text(titles[index])).font(.caption.weight(.bold)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(selection.wrappedValue == index ? RoomTheme.mint : RoomTheme.cream, in: Capsule())
                        .foregroundStyle(selection.wrappedValue == index ? .white : RoomTheme.ink)
                }.buttonStyle(.plain)
            }
        }.fixedSize()
    }

    private var browser: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { searchField.frame(width: 230); filterChips; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 8) {
                    searchField
                    HStack(spacing: 10) { filterChips; Spacer(minLength: 0) }
                }
            }
            // One page is exactly what fits; the grid never scrolls inside a page.
            Group {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: search).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing), count: gridFit.columns),
                              spacing: Self.gridSpacing) {
                        ForEach(visible) { product in productCard(product) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { GeometryReader { proxy in
                Color.clear.onAppear { fit(proxy.size) }.onChange(of: proxy.size) { _, size in fit(size) }
            } }
            .clipped()
            HStack(spacing: 16) {
                Text(GameStrings.format("mac.shop.pageCount", products.count, min(page, pages - 1) + 1, pages))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                Spacer(minLength: 0)
                Button { movePage(-1) } label: {
                    Label(GameStrings.text("career.page.previous") + " " + keyLabel(.previousPage), systemImage: "chevron.left")
                }.disabled(page == 0)
                    .accessibilityIdentifier("macShopPrevious")
                Button { movePage(1) } label: {
                    Label(GameStrings.text("career.page.next") + " " + keyLabel(.nextPage), systemImage: "chevron.right")
                }.disabled(page + 1 >= pages)
                    .accessibilityIdentifier("macShopNext")
            }.buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func fit(_ size: CGSize) {
        let columns = max(2, min(6, Int((size.width + Self.gridSpacing) / (Self.cardMinWidth + Self.gridSpacing))))
        let rows = max(1, Int((size.height + Self.gridSpacing) / (Self.cardHeight + Self.gridSpacing)))
        guard columns != gridFit.columns || rows != gridFit.rows else { return }
        // Keep the selected product on screen when the page size changes.
        let index = products.firstIndex { $0.id == selected?.id } ?? 0
        let size = max(1, columns * rows)
        gridFit = (columns, rows)
        page = min(index / size, max(0, (products.count + size - 1) / size - 1))
    }

    private func productCard(_ product: MacShopProduct) -> some View {
        let selected = self.selected?.id == product.id
        return Button { selectedID = product.id; previewFacing = .front } label: {
            VStack(alignment: .leading, spacing: 10) {
                GameIcon(asset: product.asset, symbol: product.symbol, size: 112, tint: product.tint)
                    .frame(maxWidth: .infinity).frame(height: 130)
                    .background(product.premium ? RoomTheme.gold.opacity(0.13) : RoomTheme.track.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .topLeading) {
                        if product.isForPlayer {
                            Text(GameStrings.text("supply.player.new")).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(RoomTheme.coral, in: Capsule()).padding(7)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if product.premium {
                            Image(systemName: "sparkle").foregroundStyle(.white).padding(6)
                                .background(RoomTheme.gold, in: Circle()).padding(6).accessibilityHidden(true)
                        }
                    }
                Text(product.name).font(.system(size: 14, weight: .heavy)).lineLimit(2).frame(minHeight: 34, alignment: .topLeading)
                HStack(alignment: .bottom, spacing: 4) {
                    Text(product.footprintText ?? GameStrings.format("shop.owned", product.count(in: store.snapshot)))
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    Label("\(product.price)", systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.gold)
                }.frame(minHeight: 30, alignment: .bottom)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? RoomTheme.mint : .white, lineWidth: selected ? 3 : 2))
                .frame(height: Self.cardHeight).contentShape(RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).accessibilityIdentifier("macShopProduct_\(product.id)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var detail: some View {
        if let product = selected {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        preview(product)
                        Text(product.name).font(.system(size: 24, weight: .heavy)).accessibilityIdentifier("macShopDetailName")
                        if let footprint = product.dimensions(facing: previewFacing) {
                            Text(footprint).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                        }
                        Text(product.detail).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                        if case .player(let supply) = product { playerInfo(supply) } else { ownership(product) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                if case .player(let supply) = product { playerPurchaseBar(supply) } else { purchaseBar(product) }
            }.macContentCard69().frame(maxHeight: .infinity)
        } else {
            ContentUnavailableView(GameStrings.text("mac.shop.empty"), systemImage: "magnifyingglass")
                .macContentCard69().frame(maxHeight: .infinity)
        }
    }

    private func preview(_ product: MacShopProduct) -> some View {
        VStack(spacing: 12) {
            GameIcon(asset: product.previewAsset(facing: previewFacing), symbol: product.symbol, size: 206, tint: product.tint)
            if let furniture = product.furniture, furniture.kind.supportsRotation {
                HStack(spacing: 16) {
                    Button { previewFacing = previewFacing.turnedLeft } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel(GameStrings.text("build68.rotateLeft"))
                    Text(GameStrings.text("build68.facing.\(previewFacing.rawValue)")).font(.caption.weight(.bold))
                        .help(GameStrings.text("mac.shop.rotatePreview"))
                    Button { previewFacing = previewFacing.turnedRight } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(GameStrings.text("build68.rotateRight"))
                }.buttonStyle(.bordered).foregroundStyle(RoomTheme.darkMint)
            }
        }.padding(12).frame(maxWidth: .infinity).background(RoomTheme.track.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
    }

    private func ownership(_ product: MacShopProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(GameStrings.text("gear.owned"))
                Spacer()
                Text("\(product.count(in: store.snapshot))").fontWeight(.heavy)
            }
            if product.furniture != nil {
                HStack {
                    Text(GameStrings.text("mac.shop.floorSpace"))
                    Spacer()
                    Text(GameStrings.format("mac.shop.slots", store.availableFurnitureSlots(on: store.visibleHomeFloor)))
                        .foregroundStyle(RoomTheme.darkMint).fontWeight(.heavy)
                }
            }
        }.padding(13).font(.caption).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 17))
    }

    private func purchaseBar(_ product: MacShopProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(product.status(in: store.snapshot)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            HStack(alignment: .bottom) {
                Label("\(product.price)", systemImage: "dollarsign.circle.fill").font(.system(size: 26, weight: .heavy))
                Spacer()
                Text(GameStrings.format("mac.shop.afterBalance", max(0, (store.snapshot?.player.gold ?? 0) - product.price)))
                    .font(.caption).foregroundStyle(RoomTheme.secondary)
            }
            Button { purchase(product, arrange: false) } label: {
                HStack { Text(GameStrings.text("mac.shop.buy")); Text(keyLabel(.confirm)).font(.caption.monospaced()) }.frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).disabled(store.isBusy || !product.canPurchase(in: store.snapshot))
                .accessibilityIdentifier("macShopBuy")
            if product.furniture != nil {
                Button(GameStrings.text("mac.shop.buyArrange")) { purchase(product, arrange: true) }
                    .buttonStyle(SoftButtonStyle()).disabled(store.isBusy || !product.canPurchase(in: store.snapshot))
                    .accessibilityIdentifier("macShopBuyArrange")
            }
        }
    }

    private func playerInfo(_ supply: PlayerSupplyDefinition) -> some View {
        let carried = store.snapshot?.player.carried(supply.kind) ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                MacEffectChips(effect: supply.effect)
                Text(GameStrings.text("supply.player.instant")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }
            HStack {
                Text(GameStrings.text("gear.owned"))
                Spacer()
                Text(GameStrings.format("recover.carried", carried, PlayerSupplyCatalog.maxCarried)).fontWeight(.heavy)
            }.font(.caption)
            Label(GameStrings.format("supply.player.dailyNote", PlayerSupplyCatalog.dailyLimit), systemImage: "info.circle")
                .font(.caption).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(13).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 17))
    }
    private func playerPurchaseBar(_ supply: PlayerSupplyDefinition) -> some View {
        let gold = store.snapshot?.player.gold ?? 0
        let room = max(0, PlayerSupplyCatalog.maxCarried - (store.snapshot?.player.carried(supply.kind) ?? 0))
        let count = max(1, min(quantity, max(1, room)))
        let total = supply.price * count
        return VStack(alignment: .leading, spacing: 12) {
            Stepper(value: Binding(get: { count }, set: { quantity = $0 }), in: 1...max(1, room)) {
                Text(GameStrings.format("supply.player.quantity", count)).font(.caption.weight(.bold))
            }.disabled(room <= 1)
            HStack(alignment: .bottom) {
                Label("\(total)", systemImage: "dollarsign.circle.fill").font(.system(size: 26, weight: .heavy))
                Spacer()
                Text(GameStrings.format("mac.shop.afterBalance", max(0, gold - total))).font(.caption).foregroundStyle(RoomTheme.secondary)
            }
            Button { guard !store.isBusy else { return }; store.buyPlayerSupply(supply.kind, quantity: count) } label: {
                HStack {
                    Text(room == 0 ? GameStrings.format("supply.player.carryLimit", PlayerSupplyCatalog.maxCarried)
                         : gold < total ? GameStrings.format("supply.player.goldShort", total - gold)
                         : GameStrings.format("supply.player.buyN", count))
                    Text(keyLabel(.confirm)).font(.caption.monospaced())
                }.frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).disabled(store.isBusy || room == 0 || gold < total)
                .accessibilityIdentifier("macShopBuy")
        }
    }

    private func purchase(_ product: MacShopProduct, arrange: Bool) {
        if case .player(let supply) = product {
            let room = PlayerSupplyCatalog.maxCarried - (store.snapshot?.player.carried(supply.kind) ?? 0)
            guard !store.isBusy, room > 0 else { return }
            store.buyPlayerSupply(supply.kind, quantity: max(1, min(quantity, room)))
            return
        }
        guard !store.isBusy, product.canPurchase(in: store.snapshot) else { return }
        if arrange { pendingArrange = (product.id, product.count(in: store.snapshot), store.saveSceneGeneration) }
        product.purchase(in: store)
    }
    private func finishPurchase() {
        guard let pending = pendingArrange else { return }
        pendingArrange = nil
        guard isVisible, pending.generation == store.saveSceneGeneration, !store.hasSaveFailure,
              store.furniturePurchaseNotice == pending.id,
              ShopCatalog.ownedFurnitureCount(offerID: pending.id, in: store.snapshot?.inventory.furniture ?? []) > pending.count else { return }
        Task {
            guard isVisible, pending.generation == store.saveSceneGeneration else { return }
            await store.decoratePurchasedFurniture()
            if isVisible, pending.generation == store.saveSceneGeneration { onHome() }
        }
    }
    private func keyLabel(_ command: MacCommand) -> String { (preferences?.binding(for: command) ?? command.defaultBinding).label }
    private func movePage(_ delta: Int) {
        page = min(pages - 1, max(0, page + delta))
        selectedID = visible.first?.id
        previewFacing = .front
    }
    private func moveSelection(_ delta: Int) {
        guard !products.isEmpty else { return }
        let index = products.firstIndex { $0.id == selected?.id } ?? 0
        let next = min(products.count - 1, max(0, index + delta))
        selectedID = products[next].id
        page = next / pageSize
        previewFacing = .front
    }
    private func followSharedCategory() {
        guard let requested = MacShopCategory(rawValue: store.shopCategory.rawValue), category != requested else { return }
        category = requested
    }
    private func resetBrowser() { page = 0; selectedID = nil; previewFacing = .front; search = ""; placement = 0; quality = 0; audience = 0 }
}

private enum MacShopCategory: String, CaseIterable, Identifiable {
    case furniture, equipment, supplies, gifts
    var id: String { rawValue }
    var titleKey: String { self == .gifts ? "community.giftShop" : "shop.category.\(rawValue)" }
    var symbol: String {
        switch self { case .furniture: "sofa.fill"; case .equipment: "tshirt.fill"; case .supplies: "shippingbox.fill"; case .gifts: "gift.fill" }
    }
    @MainActor var products: [MacShopProduct] {
        switch self {
        case .furniture: ShopListing.list(.furniture).map(MacShopProduct.item)
        case .equipment: ShopListing.list(.equipment).map(MacShopProduct.item)
        case .supplies: PlayerSupplyCatalog.all.map(MacShopProduct.player) + ShopListing.list(.supplies).map(MacShopProduct.item)
        case .gifts: CommunityCatalog.gifts.map(MacShopProduct.gift)
        }
    }
}

private enum MacShopProduct: Identifiable {
    case item(ShopListing), gift(CommunityGift), player(PlayerSupplyDefinition)
    var id: String { switch self { case .item(let p): p.id; case .gift(let p): p.id; case .player(let p): "player_\(p.kind.rawValue)" } }
    var price: Int { switch self { case .item(let p): p.price; case .gift(let p): p.price; case .player(let p): p.price } }
    var isForPlayer: Bool { if case .player = self { return true }; return false }
    @MainActor var name: String { switch self { case .item(let p): GameStrings.text(p.nameKey); case .gift(let p): GameStrings.text(p.nameKey); case .player(let p): GameStrings.text(p.nameKey) } }
    @MainActor var detail: String { switch self { case .item(let p): GameStrings.text(p.detailKey); case .gift(let p): GameStrings.text(p.detailKey); case .player(let p): GameStrings.text(p.detailKey) } }
    var asset: String { switch self { case .item(let p): p.asset; case .gift(let p): p.assetName; case .player(let p): p.assetName } }
    var symbol: String { switch self { case .item(let p): p.symbol; case .gift(let p): p.symbol; case .player(let p): p.symbol } }
    var tint: Color { switch self { case .item(let p): p.tint; case .gift: RoomTheme.gold; case .player: RoomTheme.coral } }
    var furniture: FurnitureOffer? {
        if case .item(let p) = self, p.kind == .furniture { return ShopCatalog.furnitureOffer(id: p.id) }
        return nil
    }
    var wall: Bool { furniture.map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false }
    var premium: Bool {
        if case .item(let p) = self {
            if case .supply(let kind) = p.kind { return kind.isPremium }
            return p.kind == .equipment && p.id.hasPrefix("advanced_")
        }
        return false
    }
    @MainActor var footprintText: String? {
        guard let furniture else { return nil }
        let metadata = FurnitureCatalog.metadata(for: furniture.kind)
        return metadata.isWall ? GameStrings.text("build68.wallPlacement")
            : GameStrings.format("mac.shop.footprint", metadata.footprint.width, metadata.footprint.depth)
    }
    @MainActor func dimensions(facing: FurnitureOrientation) -> String? {
        guard let furniture else { return nil }
        let metadata = FurnitureCatalog.metadata(for: furniture.kind)
        let footprint = metadata.footprint(for: facing)
        return metadata.isWall ? GameStrings.text("build68.wallPlacement")
            : GameStrings.format("build68.dimensions", footprint.width, footprint.depth, metadata.height)
    }
    @MainActor func previewAsset(facing: FurnitureOrientation) -> String {
        furniture.map { FurnitureArtwork68.assetName(for: .init(id: $0.id, kind: $0.kind, orientation: facing)) } ?? asset
    }
    func count(in state: GameSnapshot?) -> Int {
        switch self {
        case .item(let p): p.count(in: state); case .gift(let gift): state?.inventory.gifts[gift.id] ?? 0
        case .player(let p): state?.player.carried(p.kind) ?? 0
        }
    }
    func canPurchase(in state: GameSnapshot?) -> Bool {
        guard let state else { return false }
        switch self {
        case .item(let p): return p.canPurchase(in: state)
        case .gift(let gift): return state.player.gold >= gift.price && count(in: state) < GameSnapshot.maximumStock
        case .player(let p): return state.player.gold >= p.price && count(in: state) < PlayerSupplyCatalog.maxCarried
        }
    }
    @MainActor func status(in state: GameSnapshot?) -> String {
        switch self {
        case .item(let p): return p.status(in: state)
        case .gift:
            return count(in: state) >= GameSnapshot.maximumStock ? GameStrings.text("action.inventoryFull")
                : canPurchase(in: state) ? detail : GameStrings.text("action.insufficientGold")
        case .player: return detail
        }
    }
    @MainActor func purchase(in store: GameStore) {
        switch self {
        case .item(let p): p.purchase(in: store); case .gift(let p): Task { _ = await store.buyCommunityGift(id: p.id) }
        case .player(let p): store.buyPlayerSupply(p.kind, quantity: 1)
        }
    }
}
