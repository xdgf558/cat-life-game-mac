import SwiftUI
import CatGameCore

/// The picker selects first; only its confirmation consumes inventory.
@MainActor
struct CommunityGiftView: View {
    @Bindable var store: GameStore
    var neighborID: String? = nil
    var onGift: ((String, NeighborActionReceipt) -> Bool)? = nil
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isWorking = false
    @State private var failed = false
    @State private var purchasedID: String?
    @State private var selectedID: String?
    @State private var restocking = false
    @State private var isVisible = false

    private var neighbor: NeighborDefinition? { neighborID.flatMap(CommunityCatalog.neighbor) }
    private var gold: Int { store.snapshot?.player.gold ?? 0 }
    private var isShop: Bool { neighbor == nil || restocking }
    private var remainingGifts: Int {
        guard let neighborID else { return 0 }
        return store.snapshot?.community.relationship(for: neighborID).remainingGiftsToday ?? 0
    }
    private var selectedGift: CommunityGift? { selectedID.flatMap(CommunityCatalog.gift) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isShop {
                    Label(GameStrings.text("community.giftShelfHint"), systemImage: "info.circle.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.friendshipDeep)
                        .fixedSize(horizontal: false, vertical: true).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 2))
                }
                if failed {
                    Text(GameStrings.text(store.hasSaveFailure ? "save.writeTitle" : "community.actionFailed"))
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                        .accessibilityIdentifier("communityGiftFailure")
                }
                if let gift = purchasedID.flatMap(CommunityCatalog.gift) {
                    Label(GameStrings.format("community.purchaseSuccess", GameStrings.text(gift.nameKey)),
                          systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                        .accessibilityIdentifier("communityGiftPurchased")
                }
                if isShop {
                    LazyVStack(spacing: 14) {
                        ForEach(CommunityCatalog.gifts) { gift in shopCard(gift) }
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 16) {
                        ForEach(CommunityCatalog.gifts) { gift in pickerCard(gift) }
                    }.padding(.top, 8)
                }
            }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize).background(RoomTheme.cream)
        .accessibilityIdentifier("communityGiftShelf")
        .safeAreaInset(edge: .top, spacing: 0) {
            if isShop {
                CommunityHeader(title: GameStrings.text("community.giftShop"), backTitle: shopBackTitle,
                                gold: gold, symbol: "gift.fill",
                                backID: restocking ? "communityGiftRestockBackButton" : "communityGiftCloseButton",
                                disabled: isWorking) {
                    if restocking { restocking = false; purchasedID = nil; failed = false }
                    else { close() }
                }
            } else { pickerHeader }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isShop { confirmBar }
        }
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(isWorking || store.isBusy)
        .onChange(of: isShop, initial: true) { _, visible in store.isShowingCommunityGiftShop = visible }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; store.isShowingCommunityGiftShop = false }
    }

    private var shopBackTitle: String {
        if restocking { return "community.chooseGift" }
        switch store.activeSheet {
        case .shop: return "tab.shop"
        case .inventory: return "tab.inventory"
        default: return "community.title"
        }
    }

    private var pickerHeader: some View {
        HStack(spacing: 10) {
            if let neighbor {
                CommunityPortrait(neighbor: neighbor, size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(GameStrings.format("community.giftFor", GameStrings.text(neighbor.nameKey)))
                        .font(.headline.weight(.heavy)).accessibilityAddTraits(.isHeader)
                    Text(GameStrings.format("community.giftPickerHint", remainingGifts, CommunityCatalog.dailyGiftLimit))
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                        .accessibilityIdentifier("communityGiftDailyLimit")
                }.fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: close) { Image(systemName: "xmark").font(.subheadline.weight(.heavy)).frame(width: 44, height: 44) }
                .buttonStyle(.plain).disabled(isWorking || store.isBusy)
                .accessibilityLabel(GameStrings.text("common.done")).accessibilityIdentifier("communityGiftCloseButton")
        }.padding(16).padding(.top, 6).background(RoomTheme.cream)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func stockPill(_ gift: CommunityGift) -> some View {
        let stock = store.snapshot?.inventory.giftCount(gift.id) ?? 0
        return Text(GameStrings.format("community.stockShort", stock)).font(.caption.weight(.heavy))
            .foregroundStyle(stock > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(stock > 0 ? RoomTheme.paleMint : RoomTheme.chipBg, in: Capsule())
            .accessibilityIdentifier("communityGiftStock_\(gift.id)").accessibilityValue("\(stock)")
    }

    private func shopCard(_ gift: CommunityGift) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CommunityGiftIcon(gift: gift, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(GameStrings.text(gift.nameKey)).font(.headline.weight(.heavy))
                    stockPill(gift)
                    Text(GameStrings.text(gift.detailKey)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { whoLikes(gift); Spacer(minLength: 0); purchaseButton(gift) }
                VStack(alignment: .leading, spacing: 12) { whoLikes(gift); purchaseButton(gift) }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 26)
            .accessibilityElement(children: .contain).accessibilityIdentifier("communityGiftCard_\(gift.id)")
    }

    private func whoLikes(_ gift: CommunityGift) -> some View {
        let fans = CommunityCatalog.neighbors.filter { $0.favoriteGiftIDs.contains(gift.id) }
        return HStack(spacing: 7) {
            Text(GameStrings.text("community.whoLikes")).font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            HStack(spacing: -6) { ForEach(fans) { CommunityPortrait(neighbor: $0, size: 26) } }
            Text(fans.map { GameStrings.text($0.nameKey) }.joined(separator: " · "))
                .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }

    private func purchaseButton(_ gift: CommunityGift) -> some View {
        Button { buy(gift) } label: {
            Label(GameStrings.format("community.priceBuy", gift.price), systemImage: "dollarsign.circle.fill")
                .font(.subheadline.weight(.heavy)).fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(MintButtonStyle()).disabled(isWorking || store.isBusy)
        .opacity(gold < gift.price ? 0.45 : 1)
        .accessibilityLabel(GameStrings.text("shop.purchase") + " · " + GameStrings.text(gift.nameKey)
                            + " · " + GameStrings.format("shop.buy", gift.price))
        .accessibilityIdentifier("buyCommunityGift_\(gift.id)")
    }

    private func pickerCard(_ gift: CommunityGift) -> some View {
        let stock = store.snapshot?.inventory.giftCount(gift.id) ?? 0
        let favorite = neighbor?.favoriteGiftIDs.contains(gift.id) == true
        let gain = min(CommunityCatalog.giftFriendship(neighborID: neighborID ?? "", giftID: gift.id),
                       100 - (store.snapshot?.community.relationship(for: neighborID ?? "").friendship ?? 0))
        return Button {
            guard !isWorking, !store.isBusy else { return }
            store.playNavigationSound()
            if stock > 0 { selectedID = gift.id }
            else { restocking = true; purchasedID = nil; failed = false }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if favorite && dynamicTypeSize.isAccessibilitySize { favoriteBadge }
                HStack(alignment: .top, spacing: 8) {
                    CommunityGiftIcon(gift: gift, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(GameStrings.text(gift.nameKey)).font(.subheadline.weight(.heavy))
                        stockPill(gift)
                    }
                }
                Text(gain > 0 ? GameStrings.format("community.ordinaryGain", gain) : GameStrings.text("community.closestShort"))
                    .font(.caption.weight(.heavy)).foregroundStyle(favorite ? RoomTheme.friendshipDeep : RoomTheme.secondary)
                if stock == 0 {
                    Label(GameStrings.text("community.restock"), systemImage: "chevron.right")
                        .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.gold)
                }
            }.fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(selectedID == gift.id ? RoomTheme.friendship : .white,
                                                                         lineWidth: selectedID == gift.id ? 3 : 2))
                .overlay(alignment: .topTrailing) {
                    if favorite && !dynamicTypeSize.isAccessibilitySize {
                        favoriteBadge.offset(x: -10, y: -8)
                    }
                }
                .opacity(stock == 0 ? 0.55 : 1)
        }
        .buttonStyle(.plain).disabled(isWorking || store.isBusy)
        .accessibilityAddTraits(selectedID == gift.id ? .isSelected : [])
        .accessibilityIdentifier(stock == 0 ? "restockCommunityGift_\(gift.id)" : "selectCommunityGift_\(gift.id)")
    }

    private var favoriteBadge: some View {
        Label(GameStrings.text("community.likesShort"), systemImage: "heart.fill")
            .font(.caption2.weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoomTheme.friendship, in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            Button { if let gift = selectedGift { give(gift) } } label: {
                Label(selectedGift.map { GameStrings.format("community.sendNamedGift", GameStrings.text($0.nameKey)) }
                      ?? GameStrings.text("community.selectGiftFirst"), systemImage: "gift.fill")
                    .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            }
            .buttonStyle(FriendshipButtonStyle())
            .disabled(isWorking || store.isBusy || remainingGifts == 0 || selectedGift == nil
                      || (selectedID.map { store.snapshot?.inventory.giftCount($0) ?? 0 } ?? 0) == 0)
            .accessibilityIdentifier("confirmCommunityGiftButton")
        }
        .padding(16).background(RoomTheme.cream)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain).accessibilityIdentifier("communityGiftConfirmBar")
    }

    private func give(_ gift: CommunityGift) {
        guard !isWorking, !store.isBusy, let neighborID else { return }
        isWorking = true; failed = false
        let generation = store.saveSceneGeneration
        Task {
            defer { isWorking = false }
            let receipt = await store.giveNeighborGiftWithReceipt(neighborID: neighborID, giftID: gift.id, presentResult: { receipt in
                guard isVisible, generation == store.saveSceneGeneration else { return false }
                let handled = onGift?(gift.id, receipt) ?? false
                close()
                return handled
            })
            if receipt == nil { failed = true }
        }
    }

    private func buy(_ gift: CommunityGift) {
        guard !isWorking, !store.isBusy else { return }
        isWorking = true; failed = false; purchasedID = nil
        Task {
            defer { isWorking = false }
            if await store.buyCommunityGift(id: gift.id) { purchasedID = gift.id }
            else { failed = true }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}
