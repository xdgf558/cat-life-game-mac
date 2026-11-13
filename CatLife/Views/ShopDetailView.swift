import SwiftUI
import CatGameCore

@MainActor
struct ShopDetailView: View {
    let product: ShopListing
    @Bindable var store: GameStore
    @Environment(\.dismiss) private var dismiss

    private var count: Int { product.count(in: store.snapshot) }
    private var alreadyOwned: Bool { product.isOwned(in: store.snapshot) }
    private var atLimit: Bool { product.limit.map { count >= $0 } ?? false }
    private var levelLocked: Bool { (store.snapshot?.player.level ?? 1) < product.unlockLevel }
    private var lacksGold: Bool { (store.snapshot?.player.gold ?? 0) < product.price }
    private var canBuy: Bool { !store.isBusy && product.canPurchase(in: store.snapshot) }
    private var premium: Bool {
        if case .supply(let kind) = product.kind { return kind.isPremium }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 16) {
                    GameIcon(asset: product.asset, symbol: product.symbol, size: 112, tint: RoomTheme.darkMint)
                    Text(GameStrings.text(product.nameKey)).font(.title2.bold()).multilineTextAlignment(.center)
                        .accessibilityIdentifier("shopDetailName")
                }.frame(maxWidth: .infinity)
                Text(GameStrings.text(product.detailKey)).font(.body).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let goal = CompanionshipPresentation.shopGoal(for: product, cat: store.cat) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(GameStrings.text("habit67.shop.goalTitle"), systemImage: "heart.fill")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                        Text(styledGoal(goal)).font(.subheadline).foregroundStyle(RoomTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 1.5))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("shopHabitGoal")
                }
                VStack(alignment: .leading, spacing: 14) {
                    detail("shop.price", value: GameStrings.format("shop.buy", product.price), id: "shopDetailPrice")
                    detail("shop.requirements", value: GameStrings.format("career.unlock", product.unlockLevel), id: "shopDetailRequirement")
                    Text(GameStrings.format(product.kind == .supply(.toy) ? "inventory.playUses" : "shop.owned", count))
                        .font(.subheadline).foregroundStyle(RoomTheme.secondary)
                        .accessibilityIdentifier("shopOwned_\(product.id)").accessibilityValue("\(count)")
                    if let limit = product.limit {
                        Text(GameStrings.format("shop.limit", limit)).font(.footnote).foregroundStyle(RoomTheme.secondary)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
                if product.kind == .equipment, let item = PlayerCatalog.item(id: product.id) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(GameStrings.text("shop.effects")).font(.headline)
                        Text(GameStrings.text("gear.slot.\(item.slot.rawValue)")).font(.subheadline)
                        if item.bonuses.durationReductionPercent > 0 {
                            Text(GameStrings.format("player.bonus.duration", item.bonuses.durationReductionPercent))
                        }
                        if item.bonuses.staminaReductionPercent > 0 {
                            Text(GameStrings.format("player.bonus.stamina", item.bonuses.staminaReductionPercent))
                        }
                        if item.bonuses.moodReductionPercent > 0 {
                            Text(GameStrings.format("player.bonus.mood", item.bonuses.moodReductionPercent))
                        }
                    }.font(.subheadline).foregroundStyle(RoomTheme.darkMint)
                }
                Text(GameStrings.text(product.kind == .equipment ? "shop.equipmentHint" :
                    (product.kind == .furniture ? "shop.furnitureHint" : "shop.suppliesHint")))
                    .font(.footnote).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = unavailableMessage {
                    Text(message).font(.subheadline).foregroundStyle(RoomTheme.secondary)
                        .accessibilityIdentifier("shopPurchaseStatus")
                }
                Button { product.purchase(in: store) } label: {
                    HStack(spacing: 5) {
                        if !alreadyOwned {
                            Image(systemName: "dollarsign.circle.fill").accessibilityHidden(true)
                        }
                        Text(alreadyOwned ? GameStrings.text("gear.owned") : GameStrings.format("shop.buy", product.price))
                    }
                    .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(ShopPriceButtonStyle(gold: premium)).disabled(!canBuy)
                .accessibilityIdentifier(product.purchaseIdentifier())
                Label(GameStrings.format("shop.balance", store.snapshot?.player.gold ?? 0), systemImage: "dollarsign.circle.fill")
                    .font(.footnote).foregroundStyle(RoomTheme.secondary)
                    .accessibilityIdentifier("shopGoldCount").accessibilityValue("\(store.snapshot?.player.gold ?? 0)")
            }
            .padding(20).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("shopDetailScroll").background(RoomTheme.cream)
        .safeAreaInset(edge: .bottom, spacing: 0) { FurniturePurchaseBanner(store: store) }
        .navigationTitle(GameStrings.text("shop.detail.title")).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: { Label(GameStrings.text("common.back"), systemImage: "chevron.left") }
                    .foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("shopDetailBackButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(GameStrings.text("common.done")) { store.activeSheet = nil }
                    .foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("closeSheetButton")
            }
        }
    }

    private func styledGoal(_ body: String) -> AttributedString {
        var text = AttributedString(body)
        let note = GameStrings.text("design68.shop.noExtraPurchase")
        if let range = text.range(of: note) {
            text[range].font = .subheadline.weight(.heavy)
        } else {
            var emphasis = AttributedString("\n" + note)
            emphasis.font = .subheadline.weight(.heavy)
            text.append(emphasis)
        }
        return text
    }

    private var unavailableMessage: String? {
        if alreadyOwned { return GameStrings.text("shop.equipmentPurchased") }
        if case .supply(let supply) = product.kind,
           count > GameSnapshot.maximumStock - SupplyCatalog.definition(for: supply).unitsPerPurchase {
            return GameStrings.text("action.inventoryFull")
        }
        if atLimit { return GameStrings.format("shop.furnitureLimit", product.limit ?? 0) }
        if levelLocked { return GameStrings.format("shop.levelRequired", product.unlockLevel) }
        if lacksGold { return GameStrings.text("action.insufficientGold") }
        return nil
    }

    private func detail(_ key: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(GameStrings.text(key)).font(.caption).foregroundStyle(RoomTheme.secondary)
            Text(value).font(.headline)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }
}
