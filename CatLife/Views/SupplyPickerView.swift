import SwiftUI
import CatGameCore

@MainActor
struct SupplyPickerView: View {
    @Bindable var store: GameStore
    let kind: SupplyKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: SupplyKind?
    @State private var isWorking = false
    @State private var failed = false

    private var isFood: Bool { kind == .food || kind == .premiumFood }
    private var choices: [SupplyKind] { isFood ? [.food, .premiumFood] : [.litter, .premiumLitter] }
    private var required: Int { isFood ? store.foodRequired : 1 }
    private var canConfirm: Bool {
        selected.map { count($0) >= required } == true && !store.isBusy && !isWorking && store.cat != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(GameStrings.text(isFood ? "supply.picker.foodTitle" : "supply.picker.litterTitle"))
                            .font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
                        Text(GameStrings.format("supply.picker.forCat", store.cat.map(GameStrings.catName) ?? ""))
                            .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { store.supplyPicker = nil } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).background(RoomTheme.paper, in: Circle())
                    .accessibilityLabel(GameStrings.text("common.cancel"))
                    .accessibilityIdentifier("supplyPickerCancelButton").disabled(store.isBusy || isWorking)
                }
                ForEach(choices, id: \.self) { option in choice(option) }
                Text(GameStrings.format("supply.picker.servingsHint", required))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("supplyPickerServings").accessibilityValue("\(required)")
                if failed {
                    Label(GameStrings.text("supply.picker.failed"), systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                        .accessibilityIdentifier("supplyPickerFailure")
                }
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("supplyPicker")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                guard canConfirm, let selected else { return }
                isWorking = true; failed = false
                Task {
                    defer { isWorking = false }
                    if !(await store.useSupplyFromPicker(selected)) { failed = true }
                }
            } label: {
                Text(isWorking ? GameStrings.text("common.saving") : selected.map {
                    GameStrings.format("supply.picker.use", GameStrings.text($0.nameKey), required)
                } ?? GameStrings.text("supply.picker.chooseFirst"))
                    .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(MintButtonStyle()).disabled(!canConfirm)
            .accessibilityIdentifier("supplyPickerConfirmButton")
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14).background(RoomTheme.cream)
        }
        .background(RoomTheme.cream).fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .interactiveDismissDisabled(isWorking || store.isBusy)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(480), .large])
        .presentationDragIndicator(.visible)
    }

    private func choice(_ supply: SupplyKind) -> some View {
        let available = count(supply) >= required
        let isSelected = selected == supply
        return Button {
            guard !store.isBusy, !isWorking else { return }
            if available { selected = supply; failed = false; store.playNavigationSound() }
            else {
                store.supplyPicker = nil
                store.shopCategory = .supplies
                store.activeSheet = .shop
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(isSelected ? RoomTheme.mint : RoomTheme.track)
                    .accessibilityHidden(true)
                SupplyArt(kind: supply, size: 46)
                VStack(alignment: .leading, spacing: 7) {
                    Text(GameStrings.text(supply.nameKey)).font(.subheadline.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(GameStrings.format("supply.picker.stock", count(supply)))
                        .font(.caption.weight(.heavy)).foregroundStyle(available ? RoomTheme.darkMint : RoomTheme.coralDeep)
                        .accessibilityIdentifier("supplyPickerStock_\(supply.rawValue)").accessibilityValue("\(count(supply))")
                    SupplyEffectChips(kind: supply)
                    if !available {
                        Label(GameStrings.text("supply.picker.shop"), systemImage: "chevron.right")
                            .font(.caption.weight(.heavy)).foregroundStyle(PremiumSupplyStyle.effectText)
                            .accessibilityIdentifier("supplyPickerShop_\(supply.rawValue)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? RoomTheme.mint.opacity(0.06) : RoomTheme.paper,
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(isSelected ? RoomTheme.mint : .white,
                                                                               lineWidth: isSelected ? 3 : 2))
            .opacity(available ? 1 : 0.55).contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain).disabled(store.isBusy || isWorking)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("supplyOption_\(supply.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func count(_ supply: SupplyKind) -> Int { store.snapshot?.inventory.count(supply) ?? 0 }
}
