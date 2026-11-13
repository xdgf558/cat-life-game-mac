import SwiftUI
import CatGameCore

@MainActor
struct ShopView: View {
    @Bindable var store: GameStore
    @State private var showsGifts = false
    @State private var filter: ShopBrowser.Filter = .all
    @State private var page = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var movingForward = true
    private var products: [ShopListing] { ShopBrowser.products(in: store.shopCategory, filter: filter) }
    private var pageSize: Int { ShopBrowser.pageSize(accessibility: dynamicTypeSize.isAccessibilitySize) }
    private var pageCount: Int { ShopBrowser.pageCount(for: products.count, pageSize: pageSize) }
    private var currentPage: Int { ShopBrowser.clampedPage(page, count: products.count, pageSize: pageSize) }
    private var visibleProducts: [ShopListing] {
        Array(products[ShopBrowser.pageRange(page, count: products.count, pageSize: pageSize)])
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    categories.id("shopProductsTop")
                    browseFilters
                    Group {
                        switch store.shopCategory {
                        case .supplies: supplies
                        case .furniture: furniture
                        case .equipment:
                            productRows(visibleProducts) { equipmentCard($0) }
                        }
                    }.id("\(store.shopCategory.rawValue)-\(filter.rawValue)-\(currentPage)")
                        .transition(reduceMotion ? .identity : .asymmetric(
                            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .opacity))
                        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                            guard abs(value.translation.width) > max(60, abs(value.translation.height) * 1.5) else { return }
                            changePage(value.translation.width < 0 ? 1 : -1)
                        })
                    if store.shopCategory == .furniture || pageCount > 1 { pagination }
                    CommunityGiftEntry(store: store) { showsGifts = true }
                }
                .padding(16).padding(.bottom, 8).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("destinationScroll")
            .onChange(of: store.shopCategory) { _, _ in
                filter = .all
                page = 0
                proxy.scrollTo("shopProductsTop", anchor: .top)
            }
            .onChange(of: filter) { _, _ in
                page = 0
                proxy.scrollTo("shopProductsTop", anchor: .top)
            }
            .onChange(of: page) { _, _ in proxy.scrollTo("shopProductsTop", anchor: .top) }
            .onChange(of: pageSize) { _, _ in
                page = 0
                proxy.scrollTo("shopProductsTop", anchor: .top)
            }
        }
        .background(RoomTheme.cream)
        .safeAreaInset(edge: .bottom, spacing: 0) { FurniturePurchaseBanner(store: store) }
        .navigationDestination(for: ShopListing.self) { product in ShopDetailView(product: product, store: store) }
        .navigationDestination(isPresented: $showsGifts) {
            CommunityGiftView(store: store, onClose: { showsGifts = false })
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(GameStrings.text("shop.title"), systemImage: "storefront.fill")
                .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 17).fill(RoomTheme.wood)
                        .shadow(color: TownPalette.woodEdge, radius: 0, y: 4)
                        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(TownPalette.woodEdge, lineWidth: 2.5))
                }
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Label("\(store.snapshot?.player.gold ?? 0)", systemImage: "dollarsign.circle.fill")
                .font(.subheadline.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .foregroundStyle(RoomTheme.ink).padding(12).gameCard(cornerRadius: 24)
                .accessibilityLabel(GameStrings.text("resource.gold"))
                .accessibilityIdentifier("shopGoldCount").accessibilityValue("\(store.snapshot?.player.gold ?? 0)")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var categories: some View {
        HStack(spacing: 4) {
            ForEach(ShopCategory.allCases, id: \.self) { option in
                Button { store.shopCategory = option } label: {
                    Text(GameStrings.text("shop.category.\(option.rawValue)"))
                        .font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(store.shopCategory == option ? RoomTheme.darkMint : RoomTheme.secondary)
                        .background(store.shopCategory == option ? RoomTheme.paper : .clear, in: Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("shopCategory_\(option.rawValue)")
                .accessibilityAddTraits(store.shopCategory == option ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(4).background(RoomTheme.chipBg, in: Capsule())
    }

    private var supplies: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([true, false], id: \.self) { premium in
                let group = visibleProducts.filter { product in
                    if case .supply(let kind) = product.kind { return kind.isPremium == premium }
                    return false
                }
                if !group.isEmpty {
                    SupplySectionHeading(premium: premium)
                    ForEach(group) { product in
                        if case .supply(let kind) = product.kind { supplyCard(product, kind: kind) }
                    }
                }
            }
            SupplyManualUseHint()
        }
    }

    private var browseFilters: some View {
        VStack(alignment: .leading, spacing: 6) {
            let options = ShopBrowser.filters(for: store.shopCategory)
            if !options.isEmpty {
                ScrollViewReader { filterProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button { filter = option } label: {
                            Label(GameStrings.text("shop.browse.filter.\(option.rawValue)"), systemImage: filterSymbol(option))
                                .font(.caption.weight(.heavy)).fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10).frame(minHeight: 44)
                                .foregroundStyle(filter == option ? .white : RoomTheme.ink)
                                .background(filter == option ? option == .premium ? RoomTheme.gold : RoomTheme.mint : RoomTheme.paper, in: Capsule())
                                .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("shopFilter_\(option.rawValue)")
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                        .id(option)
                    }
                }.padding(.vertical, 2)
                }
                .accessibilityIdentifier("shopBrowseFilters")
                .onChange(of: filter) { _, value in filterProxy.scrollTo(value, anchor: .center) }
                .onChange(of: store.shopCategory) { _, _ in filterProxy.scrollTo(ShopBrowser.Filter.all, anchor: .leading) }
                }
            }
            HStack(alignment: .firstTextBaseline) {
            Text(GameStrings.format("shop.browse.total", products.count))
                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                .accessibilityIdentifier("shopResultCount").accessibilityValue("\(products.count)")
                Spacer(minLength: 4)
                Text(GameStrings.format("shop.browse.page", currentPage + 1, pageCount))
                    .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.secondary).monospacedDigit()
                    .accessibilityIdentifier("shopPageSummary").accessibilityValue("\(currentPage + 1)/\(pageCount)")
            }
        }
    }

    private func filterSymbol(_ filter: ShopBrowser.Filter) -> String {
        switch filter { case .all: "square.grid.2x2.fill"; case .floor: "sofa.fill"; case .wall: "photo.artframe"; case .standard: "circle.fill"; case .premium: "sparkles" }
    }

    private func changePage(_ delta: Int) {
        let next = min(pageCount - 1, max(0, currentPage + delta))
        guard next != currentPage else { return }
        movingForward = delta > 0
        store.playNavigationSound()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = next }
    }

    private var pagination: some View {
        HStack(spacing: 12) {
            Button { changePage(-1) } label: {
                Label(GameStrings.text("shop.browse.previous"), systemImage: "chevron.left")
                    .font(.caption.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(currentPage == 0).opacity(currentPage == 0 ? 0.4 : 1)
            .accessibilityLabel(GameStrings.text("shop.browse.previous"))
            .accessibilityIdentifier("shopPagePrevious")
            HStack(spacing: 4) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule().fill(index == currentPage ? RoomTheme.mint : RoomTheme.track)
                        .frame(width: index == currentPage ? 16 : 6, height: 6)
                }
            }.accessibilityHidden(true)
            Button { changePage(1) } label: {
                HStack(spacing: 4) { Text(GameStrings.text("shop.browse.next")); Image(systemName: "chevron.right") }
                    .font(.caption.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(currentPage + 1 >= pageCount).opacity(currentPage + 1 >= pageCount ? 0.4 : 1)
            .accessibilityLabel(GameStrings.text("shop.browse.next"))
            .accessibilityIdentifier("shopPageNext")
        }
        .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
        .padding(.horizontal, 12).background(RoomTheme.paper, in: Capsule())
        .accessibilityElement(children: .contain).accessibilityIdentifier("shopPaginationBar")
    }

    private func supplyCard(_ product: ShopListing, kind: SupplyKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    supplyContents(product, kind: kind)
                    buyButton(product, gold: kind.isPremium)
                }
            } else {
                HStack(spacing: 10) {
                    supplyContents(product, kind: kind)
                    buyButton(product, gold: kind.isPremium).fixedSize(horizontal: true, vertical: false)
                }
            }
            if (store.snapshot?.player.gold ?? 0) < product.price {
                Text(GameStrings.text("action.insufficientGold"))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                    .accessibilityIdentifier("shopInsufficientGold_\(product.id)")
            } else if product.count(in: store.snapshot) > GameSnapshot.maximumStock - SupplyCatalog.definition(for: kind).unitsPerPurchase {
                Text(GameStrings.text("action.inventoryFull"))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(kind.isPremium ? PremiumSupplyStyle.paper : RoomTheme.paper)
                .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 3)
        }
        .overlay {
            if kind.isPremium { PremiumSupplyShine().clipShape(RoundedRectangle(cornerRadius: 22)) }
        }
        .overlay(RoundedRectangle(cornerRadius: 22)
            .strokeBorder(kind.isPremium ? PremiumSupplyStyle.border : .white, lineWidth: 2))
        .opacity(product.unlockLevel > (store.snapshot?.player.level ?? 1) ? 0.7 : 1)
        .accessibilityElement(children: .contain)
    }

    private func supplyContents(_ product: ShopListing, kind: SupplyKind) -> some View {
        NavigationLink(value: product) {
            HStack(spacing: 10) {
                SupplyArt(kind: kind, size: 52)
                VStack(alignment: .leading, spacing: 7) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { supplyName(product); ownedPill(product) }
                        VStack(alignment: .leading, spacing: 5) { supplyName(product); ownedPill(product) }
                    }
                    SupplyEffectChips(kind: kind)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shopItem_\(product.id)")
        .accessibilityLabel(GameStrings.text(product.nameKey) + ", " + GameStrings.format("shop.buy", product.price))
        .accessibilityValue(product.status(in: store.snapshot))
    }

    private func supplyName(_ product: ShopListing) -> some View {
        Text(GameStrings.text(product.nameKey)).font(.subheadline.weight(.heavy))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ownedPill(_ product: ShopListing) -> some View {
        Text(GameStrings.format("shop.owned", product.count(in: store.snapshot)))
            .font(.caption2.weight(.heavy)).foregroundStyle(product.count(in: store.snapshot) > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(product.count(in: store.snapshot) > 0 ? RoomTheme.paleMint : RoomTheme.chipBg, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("shopOwned_\(product.id)").accessibilityValue("\(product.count(in: store.snapshot))")
    }

    private var furniture: some View {
        VStack(alignment: .leading, spacing: 12) {
            if products.isEmpty {
                ContentUnavailableView(GameStrings.text("shop.browse.empty"), systemImage: "shippingbox",
                                       description: Text(GameStrings.text("shop.browse.emptyHint")))
                    .accessibilityIdentifier("shopEmptyFilter")
            } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { newFurnitureHeading; Text(GameStrings.text("shop.design.storageHint")).font(.caption.weight(.bold)) }
                VStack(alignment: .leading, spacing: 6) { newFurnitureHeading; Text(GameStrings.text("shop.design.storageHint")).font(.caption.weight(.bold)) }
            }.foregroundStyle(RoomTheme.secondary)
            productRows(visibleProducts) { furnitureCard($0, isNew: ShopBrowser.newFurnitureIDs.contains($0.id)) }
            }
        }
    }

    private func productRows<Card: View>(_ products: [ShopListing], @ViewBuilder card: @escaping (ShopListing) -> Card) -> some View {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return LazyVStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: products.count, by: count)), id: \.self) { start in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(products[start..<min(start + count, products.count)]) { product in
                        card(product).frame(maxWidth: .infinity)
                    }
                    if count == 2 && start + 1 == products.count { Color.clear.frame(maxWidth: .infinity) }
                }
                // Share the tallest card's natural height; each footer stays at the row's bottom.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var newFurnitureHeading: some View {
        HStack(spacing: 7) {
            newBadge
            Text(GameStrings.format("shop.design.newCount", products.filter { ShopBrowser.newFurnitureIDs.contains($0.id) }.count))
                .font(.subheadline.weight(.heavy))
        }
    }

    private var newBadge: some View {
        Text(GameStrings.text("shop.design.new"))
            .font(.caption2.weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4).background(RoomTheme.friendship, in: Capsule())
    }

    private func furnitureCard(_ product: ShopListing, isNew: Bool) -> some View {
        let kind = ShopCatalog.furnitureOffer(id: product.id)?.kind
        let wall = kind.map { FurnitureCatalog.metadata(for: $0).isWall } ?? false
        let hasAny = product.count(in: store.snapshot) > 0
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: product) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        (wall ? RoomTheme.paleCoral : (product.id == "rattan_chair" ? RoomTheme.paleMint : RoomTheme.track))
                        if wall {
                            VStack(spacing: 17) { ForEach(0..<7) { _ in Rectangle().fill(.white.opacity(0.25)).frame(height: 2) } }
                        }
                        GameIcon(asset: product.asset, symbol: product.symbol, size: 80, tint: product.tint).padding(4)
                    }
                    .frame(height: 88).clipped()
                    .overlay(alignment: .topLeading) {
                        Label(GameStrings.text(wall ? "shop.browse.wallTag" : "shop.browse.floorTag"), systemImage: wall ? "photo.artframe" : "sofa.fill")
                            .font(.caption2.weight(.heavy)).foregroundStyle(wall ? RoomTheme.lilac : RoomTheme.darkMint)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(wall ? RoomTheme.lilac.opacity(0.13) : RoomTheme.paleMint, in: Capsule()).padding(7)
                    }
                    .overlay(alignment: .topTrailing) {
                        if hasAny { ownedPill(product).padding(8) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(GameStrings.text(product.nameKey)).font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                        Text(GameStrings.text(product.detailKey)).font(.caption.weight(.bold))
                            .foregroundStyle(RoomTheme.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(GameStrings.text(wall ? "shop.design.wallTag" : "shop.design.mirrorTag"),
                              systemImage: wall ? "photo.artframe" : "arrow.left.arrow.right")
                            .font(.caption2.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(wall ? RoomTheme.lilac : RoomTheme.darkMint)
                             .background(wall ? RoomTheme.lilac.opacity(0.14) : RoomTheme.paleMint, in: Capsule())
                        if isNew { newBadge }
                    }.padding(10)
                }
            }
            .buttonStyle(.plain).accessibilityIdentifier("shopItem_\(product.id)")
            .accessibilityLabel(GameStrings.text(product.nameKey) + ", " + GameStrings.format("shop.buy", product.price))
            .accessibilityValue(product.status(in: store.snapshot))
            Spacer(minLength: 0)
            buyButton(product).padding(.horizontal, 10).padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .background {
            RoundedRectangle(cornerRadius: 24).fill(RoomTheme.paper)
                .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(hasAny ? Color(red: 207 / 255, green: 230 / 255, blue: 217 / 255) : .white, lineWidth: 2))
    }

    private func equipmentCard(_ product: ShopListing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: product) {
                VStack(alignment: .leading, spacing: 6) {
                    GameIcon(asset: product.asset, symbol: product.symbol, size: 70, tint: product.tint)
                        .frame(maxWidth: .infinity).frame(height: 84)
                        .background(product.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
                    Text(GameStrings.text(product.nameKey)).font(.subheadline.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(product.status(in: store.snapshot)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier((store.snapshot?.player.gold ?? 0) < product.price
                            ? "shopInsufficientGold_\(product.id)" : "shopItemStatus_\(product.id)")
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("shopItem_\(product.id)")
            .accessibilityLabel(GameStrings.text(product.nameKey) + ", " + GameStrings.format("shop.buy", product.price))
            .accessibilityValue(product.status(in: store.snapshot))
            Spacer(minLength: 0)
            buyButton(product)
        }.frame(maxHeight: .infinity, alignment: .top).padding(10).gameCard(cornerRadius: 24)
    }

    private func buyButton(_ product: ShopListing, gold: Bool = false) -> some View {
        let locked = product.unlockLevel > (store.snapshot?.player.level ?? 1)
        let capped = product.limit.map { product.count(in: store.snapshot) >= $0 } ?? false
        let owned = product.isOwned(in: store.snapshot) || capped
        return Button { product.purchase(in: store) } label: {
            HStack(spacing: 4) {
                Image(systemName: owned ? "checkmark.circle.fill" : (locked ? "lock.fill" : "dollarsign.circle.fill"))
                    .accessibilityHidden(true)
                Text(owned ? GameStrings.text("gear.owned") : locked ? GameStrings.format(
                    dynamicTypeSize.isAccessibilitySize ? "shop.design.unlock" : "shop.design.unlockShort", product.unlockLevel)
                     : product.kind == .furniture && product.count(in: store.snapshot) > 0
                     ? GameStrings.format("shop.browse.buyAgain", product.price) : product.price.formatted())
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.75)
            }.font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
        }
        .buttonStyle(ShopPriceButtonStyle(gold: gold))
        .disabled(store.isBusy || !product.canPurchase(in: store.snapshot))
        .accessibilityLabel(owned ? GameStrings.text("gear.owned") : locked ? GameStrings.format("shop.design.unlock", product.unlockLevel)
                            : GameStrings.format("shop.buy", product.price))
        .accessibilityIdentifier(product.purchaseIdentifier(prefix: "shopQuickBuy_"))
    }
}
