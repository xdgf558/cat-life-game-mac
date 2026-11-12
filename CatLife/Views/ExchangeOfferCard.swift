import SwiftUI
import CatGameCore

enum ExchangePalette {
    static let receive = Color(red: 1, green: 0.965, blue: 0.886)
    static let goldBorder = Color(red: 0.941, green: 0.788, blue: 0.569)
    static let goldInk = Color(red: 0.561, green: 0.353, blue: 0.039)
    static let readyBorder = Color(red: 0.812, green: 0.902, blue: 0.851)
}

@MainActor
struct ExchangeOfferCard: View {
    let offer: ExchangeOffer
    let snapshot: GameSnapshot
    let disabled: Bool
    let select: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var neighbor: NeighborDefinition? { CommunityCatalog.neighbor(id: offer.neighborID) }
    private var failure: ActionFailure? { ExchangeCatalog.eligibility(of: offer, in: snapshot) }
    private var remaining: Int { snapshot.community.exchangeCount(for: offer.neighborID).remainingToday }
    private var muted: Bool { failure == .exchangeStageRequired || failure == .exchangeDailyLimit }
    private var statusTint: Color {
        failure == nil ? RoomTheme.darkMint : failure == .exchangeMaterialsRequired || failure == .shopInventoryFull
            ? ExchangePalette.goldInk : RoomTheme.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 8) { title; status } }
            else { HStack(alignment: .top, spacing: 8) { title; Spacer(minLength: 0); status } }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { items(offer.inputs, receiving: false); arrow("arrow.down"); items(offer.outputs, receiving: true) }
            } else {
                HStack(spacing: 7) { items(offer.inputs, receiving: false); arrow("arrow.right"); items(offer.outputs, receiving: true) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { dailyCount; Spacer(minLength: 0); action }
                VStack(alignment: .leading, spacing: 10) { dailyCount; action }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(RoomTheme.paper)
                .shadow(color: RoomTheme.ink.opacity(0.10), radius: 0, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(failure == nil ? ExchangePalette.readyBorder : .white, lineWidth: 2))
        .opacity(muted ? 0.72 : 1).accessibilityElement(children: .contain)
        .accessibilityIdentifier("marketCard_\(offer.id)")
    }

    private var title: some View {
        HStack(alignment: .top, spacing: 8) {
            if let neighbor { CommunityPortrait(neighbor: neighbor, size: 36) }
            VStack(alignment: .leading, spacing: 4) {
                Text(GameStrings.text(offer.nameKey)).font(.subheadline.weight(.heavy))
                if let neighbor {
                    Text(GameStrings.format("market.offerSubtitle", GameStrings.text(neighbor.nameKey),
                        offer.requiredStage == 1 ? GameStrings.text("market.basicOffer")
                            : GameStrings.format("market.requiresStage", GameStrings.text(ExchangePresentation.requiredStage(offer).nameKey))))
                        .font(.caption2.weight(.bold)).foregroundStyle(CommunityPalette.tint(neighbor))
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    private var status: some View {
        Label(ExchangePresentation.status(offer, snapshot: snapshot), systemImage: failure == nil ? "checkmark.circle.fill"
              : failure == .exchangeStageRequired ? "lock.fill" : failure == .exchangeDailyLimit ? "moon.fill" : "exclamationmark.circle.fill")
            .font(.caption2.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(statusTint).padding(.horizontal, 9).padding(.vertical, 6)
            .background(failure == nil ? RoomTheme.paleMint : muted ? RoomTheme.track : ExchangePalette.goldBorder.opacity(0.5), in: Capsule())
            .accessibilityIdentifier("marketStatus_\(offer.id)")
    }
    private func items(_ stacks: [ExchangeStack], receiving: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.text(receiving ? "market.receiveShort" : "market.giveShort"))
                .font(.caption2.weight(.heavy)).foregroundStyle(receiving ? ExchangePalette.goldInk : RoomTheme.secondary)
            ForEach(Array(stacks.enumerated()), id: \.offset) { _, stack in
                ExchangeItemRow(stack: stack, owned: receiving ? nil : stack.item.count(in: snapshot.inventory))
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(receiving ? ExchangePalette.receive : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(receiving ? ExchangePalette.goldBorder : .clear, lineWidth: 2))
    }
    private func arrow(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.subheadline.weight(.heavy)).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(RoomTheme.mint, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2)).accessibilityHidden(true)
    }
    private var dailyCount: some View {
        HStack(spacing: 4) {
            Text(GameStrings.text("market.today"))
            ForEach(0..<ExchangeCatalog.dailyLimit, id: \.self) { index in
                Circle().fill(index < remaining ? RoomTheme.mint : RoomTheme.track).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text("\(remaining)/\(ExchangeCatalog.dailyLimit)").monospacedDigit()
        }.font(.caption2.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.format("market.remaining", remaining, ExchangeCatalog.dailyLimit))
    }
    private var action: some View {
        Button(ExchangePresentation.actionTitle(offer, snapshot: snapshot), action: select)
            .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            .buttonStyle(ExchangeActionStyle(primary: failure == nil,
                tint: failure == .exchangeStageRequired ? RoomTheme.friendshipDeep : ExchangePalette.goldInk))
            .disabled(disabled || failure == .exchangeDailyLimit || failure == .exchangeMissing)
            .accessibilityIdentifier("marketOffer_\(offer.id)")
    }
}

struct ExchangeActionStyle: ButtonStyle {
    var primary = false
    var tint = ExchangePalette.goldInk
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(primary ? .white : tint)
            .background {
                RoundedRectangle(cornerRadius: 18).fill(primary ? RoomTheme.mint : RoomTheme.paper)
                    .shadow(color: primary ? RoomTheme.darkMint : .clear, radius: 0, y: configuration.isPressed ? 1 : 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(primary ? RoomTheme.mint.opacity(0.45) : tint.opacity(0.3), lineWidth: 2))
            .opacity(isEnabled ? 1 : 0.55)
    }
}

struct ExchangeItemIcon: View {
    let item: ExchangeItem
    var size: CGFloat = 28
    var body: some View {
        GameIcon(asset: item.assetName, symbol: item.symbol, size: size, tint: RoomTheme.gold)
            .overlay(alignment: .topTrailing) {
                if item == .supply(.premiumFood) || item == .supply(.premiumLitter) {
                    Image(systemName: "sparkle").font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.gold)
                        .offset(x: 3, y: -3)
                }
            }.accessibilityHidden(true)
    }
}

struct ExchangeItemRow: View {
    let stack: ExchangeStack
    var owned: Int? = nil
    var body: some View {
        HStack(spacing: 6) {
            ExchangeItemIcon(item: stack.item)
            VStack(alignment: .leading, spacing: 3) {
                Text(ExchangePresentation.quantity(stack)).font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                if let owned {
                    Text(GameStrings.format("market.stockShort", owned)).font(.caption2.weight(.bold))
                        .foregroundStyle(owned >= stack.quantity ? RoomTheme.secondary : RoomTheme.coralDeep)
                        .accessibilityIdentifier("marketInputStock_\(ExchangePresentation.stockID(stack.item))").accessibilityValue("\(owned)")
                }
            }
        }.accessibilityElement(children: .contain)
    }
}

@MainActor
enum ExchangePresentation {
    static func requiredStage(_ offer: ExchangeOffer) -> FriendshipStage {
        CommunityCatalog.stages.first { $0.level == offer.requiredStage } ?? CommunityCatalog.stages[0]
    }
    static func status(_ offer: ExchangeOffer, snapshot: GameSnapshot) -> String {
        switch ExchangeCatalog.eligibility(of: offer, in: snapshot) {
        case .exchangeStageRequired: GameStrings.format("market.stageRequired", GameStrings.text(requiredStage(offer).nameKey))
        case .exchangeMaterialsRequired: GameStrings.text("market.materialsShort")
        case .exchangeDailyLimit: GameStrings.text("market.usedToday")
        case .shopInventoryFull: GameStrings.text("market.bagFull")
        case nil: GameStrings.text("market.available")
        case let failure?: GameStrings.text(failure.rawValue)
        }
    }
    static func actionTitle(_ offer: ExchangeOffer, snapshot: GameSnapshot) -> String {
        switch ExchangeCatalog.eligibility(of: offer, in: snapshot) {
        case .exchangeStageRequired:
            GameStrings.format("market.visitForFriendship", max(0, requiredStage(offer).minimumPoints - snapshot.community.relationship(for: offer.neighborID).friendship))
        case .exchangeMaterialsRequired: GameStrings.text("market.restock")
        case .exchangeDailyLimit: GameStrings.text("market.tomorrow")
        case .shopInventoryFull: GameStrings.text("market.openBag")
        default: GameStrings.text("market.preview")
        }
    }
    static func quantity(_ stack: ExchangeStack) -> String {
        stack.item == .supply(.toy) ? GameStrings.format("market.toyUses", stack.quantity)
            : GameStrings.format("market.itemQuantity", GameStrings.text(stack.item.nameKey), stack.quantity)
    }
    static func stockID(_ item: ExchangeItem) -> String {
        switch item { case .supply(let kind): kind.rawValue; case .gift(let id): id }
    }
    static func friendshipAfterTrade(_ friendship: Int) -> Int {
        min(100, friendship + ExchangeCatalog.friendship)
    }
    static func countAfterTrade(_ item: ExchangeItem, offer: ExchangeOffer, inventory: InventoryState) -> Int {
        let spent = offer.inputs.filter { $0.item == item }.reduce(0) { $0 + $1.quantity }
        let received = offer.outputs.filter { $0.item == item }.reduce(0) { $0 + $1.quantity }
        return item.count(in: inventory) - spent + received
    }
}
