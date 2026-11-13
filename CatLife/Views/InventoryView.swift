import SwiftUI
import CatGameCore

/// Every tile reads the saved inventory; selecting one never consumes an item.
@MainActor
struct InventoryView: View {
    @Bindable var store: GameStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection: Selection = .supply(.food)
    @State private var showsGifts = false
    @State private var page = Page.supplies

    private enum Page: String, CaseIterable { case supplies, furniture, equipment }

    private enum Selection: Equatable {
        case supply(Supply), furniture(String), equipment(String)
    }
    private typealias Supply = SupplyKind
    private var furniture: [FurnitureItem] { store.snapshot?.inventory.furniture ?? [] }
    private var equipment: [EquipmentItem] {
        (store.snapshot?.player.profile.ownedEquipmentIDs ?? []).compactMap(PlayerCatalog.item(id:))
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                HStack(spacing: 4) {
                    ForEach(Page.allCases, id: \.self) { option in
                        Button {
                            store.playNavigationSound(); page = option
                            switch option {
                            case .supplies:
                                store.inventoryCategory = .supplies
                                selection = .supply(store.selectedInventorySupply)
                            case .furniture:
                                store.inventoryCategory = .furniture
                                if let first = store.storedFurniture.first ?? furniture.first { selection = .furniture(first.id) }
                            case .equipment:
                                if let first = equipment.first { selection = .equipment(first.id) }
                            }
                        } label: {
                            Text(GameStrings.text(option == .equipment ? "bag.equipment" : "inventory.\(option.rawValue)"))
                                .font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(page == option ? RoomTheme.darkMint : RoomTheme.secondary)
                                .background(page == option ? RoomTheme.paper : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(page == option ? .isSelected : [])
                        .accessibilityIdentifier("inventory\(option.rawValue.prefix(1).uppercased())\(option.rawValue.dropFirst())Tab")
                    }
                }.padding(4).background(RoomTheme.chipBg, in: Capsule())
                switch page {
                case .supplies:
                    SupplySectionHeading(premium: true)
                    ForEach([Supply.premiumFood, .premiumLitter], id: \.self) { supplyRow($0) }
                    SupplySectionHeading(premium: false).padding(.top, 3)
                    ForEach([Supply.food, .litter, .toy], id: \.self) { supplyRow($0) }
                    SupplyManualUseHint()
                    CommunityGiftEntry(store: store) { showsGifts = true }
                case .furniture:
                    furnitureSummary
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(furniture) { item in furnitureTile(item) }
                    }
                    if furniture.isEmpty {
                        Text(GameStrings.text("inventory.furnitureEmpty"))
                            .font(.subheadline).foregroundStyle(RoomTheme.secondary)
                            .accessibilityIdentifier("inventoryFurnitureEmpty")
                    }
                case .equipment:
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(equipment) { item in equipmentTile(item) }
                    }
                }
                Button { store.activeSheet = .shop } label: {
                    Label(GameStrings.text("inventory.visitShop"), systemImage: "basket.fill")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(SoftButtonStyle()).disabled(store.isBusy)
                .accessibilityIdentifier("inventoryShopButton")
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize).background(RoomTheme.cream)
        .navigationDestination(isPresented: $showsGifts) {
            CommunityGiftView(store: store, onClose: { showsGifts = false })
        }
        .accessibilityIdentifier("destinationScroll")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if page != .supplies {
                selectedItemBar.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
                    .background(RoomTheme.cream.opacity(0.96))
            }
        }
        .onAppear {
            selection = .supply(store.selectedInventorySupply)
            if store.inventoryCategory == .furniture {
                page = .furniture
                if let first = store.storedFurniture.first ?? furniture.first { selection = .furniture(first.id) }
            }
        }
        .onChange(of: store.inventoryCategory) { _, category in
            page = category == .furniture ? .furniture : .supplies
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(GameStrings.text(page == .supplies ? "supply.bagTitle" : "tab.inventory"), systemImage: "backpack.fill")
                .font(.title3.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(RoomTheme.wood, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RoomTheme.secondary.opacity(0.45), lineWidth: 2))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Label("\(store.snapshot?.player.gold ?? 0)", systemImage: "dollarsign.circle.fill")
                .font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                .padding(12).gameCard(cornerRadius: 24)
                .accessibilityLabel(GameStrings.text("resource.gold"))
        }
    }

    private func supplyRow(_ supply: Supply) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    supplyIdentity(supply)
                    supplyAction(supply).frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 10) {
                    supplyIdentity(supply)
                    supplyAction(supply).fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(supply.isPremium ? PremiumSupplyStyle.paper : RoomTheme.paper,
                    in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(supply.isPremium ? PremiumSupplyStyle.border : .white,
                                                               lineWidth: 2))
        .overlay { if supply.isPremium { PremiumSupplyShine().clipShape(RoundedRectangle(cornerRadius: 24)) } }
        .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func supplyIdentity(_ supply: Supply) -> some View {
        Button { selection = .supply(supply); store.selectedInventorySupply = supply } label: {
            HStack(spacing: 12) {
                SupplyArt(kind: supply)
                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { supplyName(supply); supplyCount(supply) }
                        VStack(alignment: .leading, spacing: 4) { supplyName(supply); supplyCount(supply) }
                    }
                    SupplyEffectChips(kind: supply)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("inventoryItem_\(supply.rawValue)")
        .accessibilityElement(children: .contain)
    }

    private func supplyName(_ supply: Supply) -> some View {
        Text(GameStrings.text(supply.nameKey)).font(.subheadline.weight(.heavy))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func supplyCount(_ supply: Supply) -> some View {
        Text("× \(count(supply))").font(.caption.weight(.heavy))
            .foregroundStyle(count(supply) > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(count(supply) > 0 ? RoomTheme.paleMint : RoomTheme.chipBg, in: Capsule())
            .accessibilityLabel(GameStrings.text(supply.nameKey)).accessibilityValue("\(count(supply))")
            .accessibilityIdentifier(supply.countID)
    }

    private func supplyAction(_ supply: Supply) -> some View {
        Button {
            if canUse(supply) { use(supply) }
            else { store.shopCategory = .supplies; store.activeSheet = .shop }
        } label: {
            Label(GameStrings.text(canUse(supply) ? "supply.use" : "inventory.restock"),
                  systemImage: canUse(supply) ? "hand.tap.fill" : "storefront.fill")
                .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(SupplyUseButtonStyle(available: canUse(supply))).disabled(store.isBusy || store.isDecorating)
        .accessibilityIdentifier(canUse(supply) ? supply.useID : supply.restockID)
    }

    private func furnitureTile(_ item: FurnitureItem) -> some View {
        return tile(name: GameStrings.furnitureName(item), asset: FurnitureArtwork68.assetName(for: item), symbol: "sofa.fill",
                    badge: furnitureStatus(item.id, badge: true),
                    tint: RoomTheme.mint, selected: selection == .furniture(item.id)) {
            selection = .furniture(item.id)
        }
        .accessibilityIdentifier("inventoryFurniture_\(item.id)")
        .accessibilityValue(furnitureStatus(item.id))
    }

    private func equipmentTile(_ item: EquipmentItem) -> some View {
        let equipped = store.snapshot?.player.profile.equipped[item.slot] == item.id
        return tile(name: GameStrings.text(item.nameKey), asset: item.displayAssetName, symbol: "tshirt.fill",
                    badge: equipped ? GameStrings.text("bag.equippedBadge") : nil,
                    tint: RoomTheme.lilac, selected: selection == .equipment(item.id)) {
            selection = .equipment(item.id)
        }
        .accessibilityIdentifier("inventoryEquipment_\(item.id)")
        .accessibilityValue(GameStrings.text(equipped ? "bag.equipped" : "bag.owned"))
    }

    private func tile(name: String, asset: String, symbol: String, badge: String?, tint: Color,
                      selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                GameIcon(asset: asset, symbol: symbol, size: 40, tint: tint)
                Text(name).font(.system(size: 12, weight: .heavy, design: .rounded))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 122 : 100)
            .padding(.horizontal, 7).padding(.vertical, 7)
            .gameCard(cornerRadius: 20)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? RoomTheme.mint : .clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(minHeight: 25).background(tint, in: Capsule())
                        .overlay(Capsule().strokeBorder(RoomTheme.paper, lineWidth: 2))
                        .offset(x: 2, y: -2).accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var furnitureSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(GameStrings.format("inventory.furnitureStoredCount", store.storedFurniture.count))
                    .accessibilityValue("\(store.storedFurniture.count)")
                    .accessibilityIdentifier("inventoryStoredFurnitureCount")
                Spacer(minLength: 4)
                Text(GameStrings.format("inventory.furniturePlacedCount", store.totalPlacedFurnitureCount))
                    .accessibilityValue("\(store.totalPlacedFurnitureCount)")
                    .accessibilityIdentifier("inventoryPlacedFurnitureCount")
            }
            .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            if store.isDecorating {
                Text(GameStrings.text("inventory.layoutDraft")).font(.caption)
                    .foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("inventoryLayoutDraft")
            }
            if !store.canPlaceMoreFurniture && !store.storedFurniture.isEmpty {
                Text(store.furnitureCapacityNotice).font(.caption).foregroundStyle(RoomTheme.secondary)
                if let floor = store.availableFurnitureFloor, floor != store.visibleHomeFloor {
                    Button(GameStrings.text("homeInventory.arrange.\(floor.rawValue)")) {
                        if let item = store.storedFurniture.first { Task { _ = await store.arrangeInventoryFurniture(id: item.id) } }
                    }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy || store.isDecorating || !store.canChangeHomeFloor)
                        .accessibilityIdentifier("inventoryOtherFloorButton")
                } else if store.canUpgradeHome {
                    Button(GameStrings.text("homeUpgrade.entry")) { store.openHomeUpgrade() }
                        .buttonStyle(SoftButtonStyle()).disabled(store.isBusy || store.isResolvingLayout)
                        .accessibilityIdentifier("inventoryUpgradeButton")
                }
            }
        }
    }

    @ViewBuilder private var selectedItemBar: some View {
        switch selection {
        case .supply: EmptyView()
        case .furniture(let id):
            if let item = furniture.first(where: { $0.id == id }) {
                let floor = store.furnitureFloor(for: id)
                let onOtherFloor = floor != nil && floor != store.visibleHomeFloor
                let actionKey = floor.map { $0 == store.visibleHomeFloor
                    ? "inventory.arrangeRoom" : "homeInventory.arrange.\($0.rawValue)" } ?? "inventory.placeFurniture"
                actionBar(name: GameStrings.furnitureName(item), asset: FurnitureArtwork68.assetName(for: item),
                          symbol: "sofa.fill", detail: onOtherFloor && store.isDecorating
                              ? GameStrings.text("homeInventory.finishFloor")
                              : onOtherFloor && !store.roomFloorTravelReady
                              ? GameStrings.text("homeFloor.waitCare") : furnitureStatus(id),
                          tint: RoomTheme.mint) {
                    Button(GameStrings.text(actionKey)) {
                        if floor != nil {
                            Task { await store.arrangeInventoryFurniture(id: id) }
                        } else { store.placeFurniture(id: id) }
                    }
                    .buttonStyle(MintButtonStyle())
                    .disabled(store.isBusy || store.isResolvingLayout || store.isChangingHomeFloor
                              || (onOtherFloor && !store.canChangeHomeFloor) || (floor == nil && !store.canPlaceMoreFurniture))
                    .accessibilityIdentifier(onOtherFloor ? "inventoryGoToFloorButton"
                        : (floor != nil ? "inventoryArrangeButton" : "placeFurniture_\(id)"))
                }
            }
        case .equipment(let id):
            if let item = PlayerCatalog.item(id: id) {
                actionBar(name: GameStrings.text(item.nameKey), asset: item.displayAssetName, symbol: "tshirt.fill",
                          detail: GameStrings.text(item.detailKey), tint: RoomTheme.lilac) {
                    Button(GameStrings.text("bag.dressUp")) { store.activeSheet = .player }
                        .buttonStyle(MintButtonStyle()).disabled(store.isBusy || store.isDecorating)
                        .accessibilityIdentifier("inventoryDressUpButton")
                }
            }
        }
    }

    private func actionBar<Action: View>(name: String, asset: String, symbol: String, detail: String,
                                         tint: Color, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    actionDescription(name: name, asset: asset, symbol: symbol, detail: detail, tint: tint)
                    action().font(.system(size: 14, weight: .heavy, design: .rounded)).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    actionDescription(name: name, asset: asset, symbol: symbol, detail: detail, tint: tint)
                    action().font(.subheadline.weight(.bold)).frame(maxWidth: .infinity)
                }
            }
            if store.isDecorating {
                Text(GameStrings.text("inventory.finishLayoutForCare"))
                    .font(.caption).foregroundStyle(RoomTheme.secondary)
            }
        }
        .padding(14).gameCard(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventorySelectedItemBar")
    }

    private func actionDescription(name: String, asset: String, symbol: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            GameIconTile(asset: asset, symbol: symbol, tint: tint, background: tint.opacity(0.16), size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(2)
                Text(detail).font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func count(_ supply: Supply) -> Int { store.snapshot?.inventory.count(supply) ?? 0 }
    private func canUse(_ supply: Supply) -> Bool {
        count(supply) >= ((supply == .food || supply == .premiumFood) ? store.foodRequired : 1)
    }
    private func use(_ supply: Supply) {
        switch supply {
        case .food, .premiumFood, .litter, .premiumLitter: store.openSupplyPicker(for: supply)
        case .toy: store.play()
        }
    }
    private func furnitureStatus(_ id: String, badge: Bool = false) -> String {
        guard let floor = store.furnitureFloor(for: id) else {
            return GameStrings.text(badge ? "bag.storedBadge" : "bag.stored")
        }
        return GameStrings.text(store.snapshot?.home.availableFloors.count == 2
            ? "homeInventory.\(badge ? "badge" : "placed").\(floor.rawValue)" : (badge ? "bag.placedBadge" : "bag.placed"))
    }
}
