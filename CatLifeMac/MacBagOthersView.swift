#if os(macOS)
import SwiftUI
import CatGameCore

/// Bag › Other items, laid out like the player-supplies page: compact tiles in the middle,
/// the chosen item and its action on the right. Replaces the phone inventory list here.
@MainActor
struct MacBagOthersView: View {
    let store: GameStore
    let exits: MacRecoveryExits

    private enum Page: String, CaseIterable { case supplies, furniture, equipment }
    private enum Selection: Equatable { case supply(SupplyKind), furniture(String), equipment(String) }

    @State private var page = Page.supplies
    @State private var selection: Selection = .supply(.premiumFood)

    private var furniture: [FurnitureItem] { store.snapshot?.inventory.furniture ?? [] }
    private var equipment: [EquipmentItem] {
        (store.snapshot?.player.profile.ownedEquipmentIDs ?? []).compactMap(PlayerCatalog.item(id:))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                tabs
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) { content }
                        .padding(.bottom, 6)
                }.scrollBounceBehavior(.basedOnSize)
            }.frame(maxWidth: .infinity)
            ScrollView { detail }.frame(width: 300).scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            if store.inventoryCategory == .furniture { choose(.furniture) }
            else { selection = .supply(store.selectedInventorySupply) }
        }
        .accessibilityIdentifier("macBagOthers")
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Page.allCases, id: \.self) { option in
                Button { store.playNavigationSound(); choose(option) } label: {
                    Text(GameStrings.text(option == .equipment ? "bag.equipment" : "inventory.\(option.rawValue)"))
                        .font(.system(size: 13, weight: .heavy)).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(page == option ? RoomTheme.darkMint : RoomTheme.secondary)
                        .background(page == option ? RoomTheme.paper : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityAddTraits(page == option ? .isSelected : [])
                .accessibilityIdentifier("macBagOthersTab_\(option.rawValue)")
            }
        }.padding(3).background(RoomTheme.chipBg, in: Capsule())
    }

    private func choose(_ option: Page) {
        page = option
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
    }

    // MARK: Middle column

    @ViewBuilder private var content: some View {
        switch page {
        case .supplies:
            groupTitle(premium: true)
            tileRow([.premiumFood, .premiumLitter])
            groupTitle(premium: false)
            tileRow([.food, .litter, .toy])
        case .furniture:
            HStack {
                Text(GameStrings.format("inventory.furnitureStoredCount", store.storedFurniture.count))
                Spacer(minLength: 6)
                Text(GameStrings.format("inventory.furniturePlacedCount", store.totalPlacedFurnitureCount))
            }.font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            if furniture.isEmpty { empty("inventory.furnitureEmpty") }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(furniture) { item in
                        tile(name: GameStrings.furnitureName(item), asset: FurnitureArtwork68.assetName(for: item),
                             symbol: "sofa.fill", tint: RoomTheme.mint, badge: furnitureStatus(item.id, badge: true),
                             selected: selection == .furniture(item.id)) { selection = .furniture(item.id) }
                    }
                }
            }
        case .equipment:
            if equipment.isEmpty { empty("mac.bag.noEquipment") }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(equipment) { item in
                        let worn = store.snapshot?.player.profile.equipped[item.slot] == item.id
                        tile(name: GameStrings.text(item.nameKey), asset: item.displayAssetName, symbol: "tshirt.fill",
                             tint: RoomTheme.lilac, badge: worn ? GameStrings.text("bag.equippedBadge") : nil,
                             selected: selection == .equipment(item.id)) { selection = .equipment(item.id) }
                    }
                }
            }
        }
    }

    private func groupTitle(premium: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(GameStrings.text(premium ? "supply.group.premium" : "supply.group.daily"),
                  systemImage: premium ? "sparkle" : "basket.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(premium ? PremiumSupplyStyle.effectText : RoomTheme.darkMint)
            Text(GameStrings.text(premium ? "supply.group.premiumHint" : "supply.group.dailyHint"))
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
        }
    }

    private func tileRow(_ kinds: [SupplyKind]) -> some View {
        HStack(spacing: 10) {
            ForEach(kinds, id: \.self) { supplyTile($0) }
            // Keep premium tiles the same width as the three daily ones.
            ForEach(0..<max(0, 3 - kinds.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
        }
    }

    private func supplyTile(_ kind: SupplyKind) -> some View {
        let selected = selection == .supply(kind)
        return Button { selection = .supply(kind); store.selectedInventorySupply = kind } label: {
            VStack(alignment: .leading, spacing: 6) {
                SupplyArt(kind: kind, size: 46).frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) { countBadge(kind) }
                Text(GameStrings.text(kind.nameKey)).font(.system(size: 13, weight: .heavy)).lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(firstEffect(kind)).font(.system(size: 11, weight: .heavy)).lineLimit(1)
                    .foregroundStyle(kind.isPremium ? PremiumSupplyStyle.effectText : RoomTheme.secondary)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(kind.isPremium ? PremiumSupplyStyle.paper : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? RoomTheme.mint
                : kind.isPremium ? PremiumSupplyStyle.border : .white, lineWidth: selected ? 3 : 2))
            .opacity(count(kind) == 0 ? 0.62 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).accessibilityLabel(GameStrings.text(kind.nameKey)).accessibilityValue("\(count(kind))")
        .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("macBagSupply_\(kind.rawValue)")
    }

    private func countBadge(_ kind: SupplyKind) -> some View {
        Text("×\(count(kind))").font(.system(size: 11, weight: .heavy)).monospacedDigit()
            .foregroundStyle(count(kind) > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(count(kind) > 0 ? RoomTheme.paleMint : RoomTheme.chipBg, in: Capsule())
    }

    private func tile(name: String, asset: String, symbol: String, tint: Color, badge: String?,
                      selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                GameIcon(asset: asset, symbol: symbol, size: 40, tint: tint).frame(height: 46)
                Text(name).font(.system(size: 12, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(8).frame(maxWidth: .infinity)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? RoomTheme.mint : .white, lineWidth: selected ? 3 : 2))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(tint, in: Capsule())
                        .padding(5).accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func empty(_ key: String) -> some View {
        Text(GameStrings.text(key)).font(.system(size: 13, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoomTheme.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Right column

    @ViewBuilder private var detail: some View {
        switch selection {
        case .supply(let kind):
            detailCard(art: AnyView(SupplyArt(kind: kind, size: 76)), name: GameStrings.text(kind.nameKey),
                       line: GameStrings.format(kind == .toy ? "inventory.playUses" : "mac.bag.carried", count(kind)),
                       text: GameStrings.text(SupplyCatalog.definition(for: kind).detailKey)) {
                SupplyEffectChips(kind: kind)
            } action: {
                Button { canUse(kind) ? use(kind) : exits.shop() } label: {
                    Label(GameStrings.text(canUse(kind) ? "supply.use" : "inventory.restock"),
                          systemImage: canUse(kind) ? "hand.tap.fill" : "storefront.fill")
                        .font(.system(size: 13.5, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(SupplyUseButtonStyle(available: canUse(kind))).disabled(store.isBusy || store.isDecorating)
                .accessibilityIdentifier(canUse(kind) ? kind.useID : kind.restockID)
            }
        case .furniture(let id):
            if let item = furniture.first(where: { $0.id == id }) { furnitureDetail(item) } else { pickHint }
        case .equipment(let id):
            if let item = PlayerCatalog.item(id: id) {
                detailCard(art: AnyView(GameIcon(asset: item.displayAssetName, symbol: "tshirt.fill", size: 70, tint: RoomTheme.lilac)),
                           name: GameStrings.text(item.nameKey),
                           line: GameStrings.text(store.snapshot?.player.profile.equipped[item.slot] == item.id ? "bag.equipped" : "bag.owned"),
                           text: GameStrings.text(item.detailKey)) { EmptyView() } action: {
                    Button { exits.profile() } label: {
                        Label(GameStrings.text("bag.dressUp"), systemImage: "tshirt.fill")
                            .font(.system(size: 13.5, weight: .heavy)).frame(maxWidth: .infinity)
                    }.buttonStyle(SupplyUseButtonStyle(available: true)).disabled(store.isBusy || store.isDecorating)
                }
            } else { pickHint }
        }
    }

    private func furnitureDetail(_ item: FurnitureItem) -> some View {
        let floor = store.furnitureFloor(for: item.id)
        let onOtherFloor = floor != nil && floor != store.visibleHomeFloor
        let key = floor.map { $0 == store.visibleHomeFloor ? "inventory.arrangeRoom" : "homeInventory.arrange.\($0.rawValue)" }
            ?? "inventory.placeFurniture"
        let note = onOtherFloor && !store.roomFloorTravelReady ? GameStrings.text("homeFloor.waitCare")
            : floor == nil && !store.canPlaceMoreFurniture ? store.furnitureCapacityNotice : nil
        return detailCard(art: AnyView(GameIcon(asset: FurnitureArtwork68.assetName(for: item), symbol: "sofa.fill", size: 76, tint: RoomTheme.mint)),
                          name: GameStrings.furnitureName(item), line: furnitureStatus(item.id), text: note) { EmptyView() } action: {
            Button { arrange(item.id, placed: floor != nil) } label: {
                Label(GameStrings.text(key), systemImage: "sofa.fill").font(.system(size: 13.5, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(SupplyUseButtonStyle(available: true))
            .disabled(store.isBusy || store.isDecorating || store.isResolvingLayout || store.isChangingHomeFloor
                      || (onOtherFloor && !store.canChangeHomeFloor) || (floor == nil && !store.canPlaceMoreFurniture))
        }
    }

    private func detailCard<Extra: View, Action: View>(art: AnyView, name: String, line: String, text: String?,
                                                        @ViewBuilder extra: () -> Extra,
                                                        @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            art.frame(maxWidth: .infinity).frame(height: 116)
                .background(RoomTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            Text(name).font(.system(size: 19, weight: .heavy, design: .rounded))
            Text(line).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            extra()
            if let text, !text.isEmpty {
                Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action().padding(.top, 4)
            if store.isDecorating {
                Text(GameStrings.text("inventory.finishLayoutForCare")).font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 2))
    }

    private var pickHint: some View {
        Text(GameStrings.text("mac.bag.pickItem")).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RoomTheme.secondary).frame(maxWidth: .infinity, minHeight: 160)
            .background(RoomTheme.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Rules (same as the phone inventory)

    private func count(_ kind: SupplyKind) -> Int { store.snapshot?.inventory.count(kind) ?? 0 }
    private func canUse(_ kind: SupplyKind) -> Bool {
        count(kind) >= ((kind == .food || kind == .premiumFood) ? store.foodRequired : 1)
    }
    private func firstEffect(_ kind: SupplyKind) -> String {
        let detail = GameStrings.text(SupplyCatalog.definition(for: kind).detailKey)
        let summary = detail.components(separatedBy: "。").first?.components(separatedBy: ". ").first ?? detail
        return summary.components(separatedBy: " · ").first ?? summary
    }
    /// Using an item opens another window (picker, play choices) or the room; close the bag first,
    /// because macOS cannot show a second sheet on top of this one.
    private func use(_ kind: SupplyKind) {
        exits.close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            switch kind {
            case .food, .premiumFood, .litter, .premiumLitter: store.openSupplyPicker(for: kind)
            case .toy: store.presentPlayChoices()
            }
        }
    }
    private func arrange(_ id: String, placed: Bool) {
        exits.close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if placed { _ = await store.arrangeInventoryFurniture(id: id) } else { store.placeFurniture(id: id) }
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
#endif
