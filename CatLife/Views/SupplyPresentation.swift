import SwiftUI
import CatGameCore

extension SupplyKind {
    var asset: String { SupplyCatalog.definition(for: self).assetName }
    var isPremium: Bool { self == .premiumFood || self == .premiumLitter }
    var symbol: String { SupplyCatalog.definition(for: self).symbol }
    var nameKey: String { SupplyCatalog.definition(for: self).nameKey }
    var tint: Color {
        switch self {
        case .food, .premiumFood: RoomTheme.gold
        case .litter: RoomTheme.sky
        case .premiumLitter: RoomTheme.lilac
        case .toy: RoomTheme.coral
        }
    }
    var countID: String {
        switch self {
        case .food: "inventoryFoodCount"
        case .litter: "inventoryLitterCount"
        case .toy: "inventoryToyUses"
        case .premiumFood: "inventoryPremiumFoodCount"
        case .premiumLitter: "inventoryPremiumLitterCount"
        }
    }
    var countKey: String { nameKey }
    var actionKey: String {
        switch self { case .food, .premiumFood: "care.feed"; case .litter, .premiumLitter: "care.clean"; case .toy: "care.play" }
    }
    private var identifierName: String {
        switch self { case .food: "Food"; case .litter: "Litter"; case .toy: "Toy"; case .premiumFood: "PremiumFood"; case .premiumLitter: "PremiumLitter" }
    }
    var useID: String { "use\(identifierName)Button" }
    var restockID: String { "restock\(identifierName)Button" }
    var buyID: String { "buy\(identifierName)Button" }
}

enum PremiumSupplyStyle {
    static let paper = Color(red: 1, green: 248 / 255, blue: 232 / 255)
    static let border = Color(red: 240 / 255, green: 201 / 255, blue: 145 / 255)
    static let effect = Color(red: 1, green: 231 / 255, blue: 166 / 255)
    static let effectText = Color(red: 143 / 255, green: 90 / 255, blue: 10 / 255)
}

struct SupplyArt: View {
    let kind: SupplyKind
    var size: CGFloat = 52
    var body: some View {
        GameIcon(asset: kind.asset, symbol: kind.symbol, size: size * 0.8, tint: kind.tint)
            .frame(width: size, height: size)
            .background(kind.isPremium ? PremiumSupplyStyle.effect : kind.tint.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: size * 0.28))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(.white, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if kind.isPremium {
                    Image(systemName: "sparkle").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 23, height: 23).background(RoomTheme.gold, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2)).offset(x: 4, y: -4)
                }
            }
            .accessibilityHidden(true)
    }
}

@MainActor
struct SupplyEffectChips: View {
    let kind: SupplyKind
    private var effects: [String] {
        let detail = GameStrings.text(SupplyCatalog.definition(for: kind).detailKey)
        let summary = detail.components(separatedBy: "。").first?.components(separatedBy: ". ").first ?? detail
        return summary.components(separatedBy: " · ")
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { chips }
            VStack(alignment: .leading, spacing: 4) { chips }
        }
    }
    private var chips: some View {
        ForEach(Array(effects.enumerated()), id: \.offset) { _, effect in
            Text(effect).font(.caption2.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .foregroundStyle(kind.isPremium ? PremiumSupplyStyle.effectText : RoomTheme.secondary)
                .background(kind.isPremium ? PremiumSupplyStyle.effect : RoomTheme.chipBg, in: Capsule())
        }
    }
}

@MainActor
struct SupplySectionHeading: View {
    let premium: Bool
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { title; subtitle }
            VStack(alignment: .leading, spacing: 5) { title; subtitle }
        }.accessibilityAddTraits(.isHeader)
    }
    private var title: some View {
        Label(GameStrings.text(premium ? "supply.group.premium" : "supply.group.daily"),
              systemImage: premium ? "sparkle" : "basket.fill")
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(premium ? PremiumSupplyStyle.effectText : RoomTheme.darkMint)
    }
    private var subtitle: some View {
        Text(GameStrings.text(premium ? "supply.group.premiumHint" : "supply.group.dailyHint"))
            .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
struct SupplyManualUseHint: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "info.circle.fill").accessibilityHidden(true)
                    Text(GameStrings.text("supply.manualUseHint"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Label(GameStrings.text("supply.manualUseHint"), systemImage: "info.circle.fill")
            }
        }
        .font(.caption.weight(.bold)).foregroundStyle(PremiumSupplyStyle.effectText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(PremiumSupplyStyle.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(PremiumSupplyStyle.border, lineWidth: 2))
    }
}

struct PremiumSupplyShine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = false
    var body: some View {
        GeometryReader { geometry in
            if !reduceMotion {
                Rectangle().fill(.white.opacity(0.28)).frame(width: 25, height: geometry.size.height * 2)
                    .rotationEffect(.degrees(24)).blur(radius: 7)
                    .offset(x: swept ? geometry.size.width + 50 : -70, y: -geometry.size.height / 2)
                    .task {
                        withAnimation(.easeInOut(duration: 1.2).delay(0.25)) { swept = true }
                    }
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct SupplyUseButtonStyle: ButtonStyle {
    let available: Bool
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(available ? .white : PremiumSupplyStyle.effectText)
            .padding(.horizontal, 13).padding(.vertical, 10).frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 18).fill(available ? RoomTheme.mint : PremiumSupplyStyle.paper)
                    .shadow(color: available ? RoomTheme.darkMint : .clear, radius: 0, y: configuration.isPressed ? 1 : 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(
                available ? .white.opacity(0.35) : PremiumSupplyStyle.border, lineWidth: 2))
            .offset(y: configuration.isPressed ? 2 : 0).opacity(isEnabled ? 1 : 0.5)
    }
}
