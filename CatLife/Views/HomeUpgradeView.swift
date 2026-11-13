import SwiftUI
import CatGameCore

@MainActor
struct HomeUpgradeView: View {
    @Bindable var store: GameStore
    @State private var confirming = false
    @State private var requestedLevel: Int?

    private var level: Int { store.snapshot?.home.roomLevel ?? 1 }
    private var current: HomeLevel? { HomeCatalog.level(level) }
    private var next: HomeLevel? { HomeCatalog.nextLevel(after: level) }
    private var request: HomeLevel? { requestedLevel.flatMap { HomeCatalog.level($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(GameStrings.text("homeUpgrade.title"), systemImage: "house.fill")
                    .font(.title2.bold()).foregroundStyle(RoomTheme.darkMint)
                Text(GameStrings.text("homeUpgrade.preserve")).font(.subheadline)
                    .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                if let current { levelCard(current, title: "homeUpgrade.current", prefix: "Current") }
                if let next {
                    Image(systemName: "arrow.down").font(.title3.bold()).foregroundStyle(RoomTheme.darkMint)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                    levelCard(next, title: "homeUpgrade.next", prefix: "Next")
                    VStack(alignment: .leading, spacing: 10) {
                        Text(GameStrings.format("shop.buy", next.upgradeCost)).font(.title2.bold())
                            .accessibilityIdentifier("homeUpgradeCost").accessibilityValue("\(next.upgradeCost)")
                        Text(GameStrings.format("home.levelRequired", next.requiredPlayerLevel)).font(.subheadline)
                            .foregroundStyle(RoomTheme.secondary)
                            .accessibilityIdentifier("homeUpgradeRequirement")
                        Text(GameStrings.format("shop.balance", store.snapshot?.player.gold ?? 0))
                            .font(.footnote).foregroundStyle(RoomTheme.secondary)
                            .accessibilityIdentifier("homeUpgradeGold").accessibilityValue("\(store.snapshot?.player.gold ?? 0)")
                    }
                    if (store.snapshot?.player.gold ?? 0) < next.upgradeCost {
                        Text(GameStrings.text("action.insufficientGold")).font(.subheadline)
                            .foregroundStyle(RoomTheme.secondary)
                    }
                    Button {
                        requestedLevel = next.level
                        confirming = true
                    } label: {
                        Text(GameStrings.text("homeUpgrade.action")).font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MintButtonStyle()).disabled(!canUpgrade(next)).opacity(canUpgrade(next) ? 1 : 0.45)
                    .accessibilityIdentifier("homeUpgradeAction")
                } else {
                    Label(GameStrings.text("homeUpgrade.maxed"), systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(RoomTheme.darkMint)
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityIdentifier("homeUpgradeMaxed")
                }
            }
            .padding(20).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("homeUpgradeScroll")
        .alert(GameStrings.text("homeUpgrade.confirmTitle"), isPresented: $confirming) {
            Button(GameStrings.text("homeUpgrade.confirm")) {
                if let requestedLevel { store.upgradeHome(toLevel: requestedLevel) }
            }.accessibilityIdentifier("homeUpgradeConfirm")
            Button(GameStrings.text("layout.cancel"), role: .cancel) { requestedLevel = nil }
        } message: {
            if let request {
                Text(GameStrings.format("homeUpgrade.confirmMessage", request.upgradeCost, request.level,
                                        area(request), store.totalFurnitureCapacity(for: request)))
            }
        }
    }

    private func canUpgrade(_ next: HomeLevel) -> Bool {
        store.snapshot != nil && !store.isBusy && !store.isSavingLayout && !store.isResolvingLayout
            && store.placingFurnitureID == nil
            && (store.snapshot?.player.gold ?? 0) >= next.upgradeCost
            && (store.snapshot?.player.level ?? 1) >= next.requiredPlayerLevel
    }

    private func levelCard(_ home: HomeLevel, title: String, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GameStrings.text(title)).font(.subheadline).foregroundStyle(RoomTheme.secondary)
            Text(GameStrings.format("homeUpgrade.level", home.level)).font(.title3.bold())
                .accessibilityIdentifier("homeUpgrade\(prefix)Level").accessibilityValue("\(home.level)")
            Label(GameStrings.format("homeUpgrade.areaValue", area(home)), systemImage: "square.dashed")
                .font(.headline).accessibilityIdentifier("homeUpgrade\(prefix)Area")
                .accessibilityValue(area(home))
            Text(GameStrings.format("homeUpgrade.dimensions", number(home.worldScale)))
                .font(.footnote).foregroundStyle(RoomTheme.secondary)
            if home.floors.count > 1 {
                Label(GameStrings.format("homeUpgrade.floorCapacity", store.floorFurnitureCapacity(for: home)), systemImage: "stairs")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
            }
            if home.level >= RoomResidentCats.unlockLevel {
                Label(GameStrings.text("catDirectory.sharedHomeUnlocked"), systemImage: "pawprint.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(GameStrings.format("homeUpgrade.capacity", store.totalFurnitureCapacity(for: home)), systemImage: "sofa.fill")
                .font(.subheadline).accessibilityIdentifier("homeUpgrade\(prefix)Capacity")
                .accessibilityValue("\(store.totalFurnitureCapacity(for: home))")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(prefix == "Current" ? RoomTheme.paper : RoomTheme.paleMint.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 24))
    }

    private func area(_ home: HomeLevel) -> String { number(home.worldScale * home.worldScale * Double(home.floors.count)) }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))
            .locale(Locale(identifier: store.language.rawValue)))
    }
}
