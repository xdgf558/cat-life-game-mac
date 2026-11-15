import SwiftUI
import CatGameCore

enum ExchangePalette {
    static let receive = Color(red: 1, green: 0.965, blue: 0.886)
    static let goldBorder = Color(red: 0.941, green: 0.788, blue: 0.569)
    static let goldInk = Color(red: 0.561, green: 0.353, blue: 0.039)
    static let readyBorder = Color(red: 0.812, green: 0.902, blue: 0.851)
}

/// One neighbor's stall: a slim header with today's trades left, then one compact row per offer.
/// The daily limit is per neighbor, so it lives on the stall rather than on every offer.
@MainActor
struct ExchangeStallCard: View {
    let neighbor: NeighborDefinition
    let offers: [ExchangeOffer]
    let snapshot: GameSnapshot
    let disabled: Bool
    let select: (ExchangeOffer) -> Void
    private var remaining: Int { snapshot.community.exchangeCount(for: neighbor.id).remainingToday }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(offers) { offer in
                Rectangle().fill(RoomTheme.track.opacity(0.8)).frame(height: 1.5).accessibilityHidden(true)
                ExchangeOfferRow(offer: offer, snapshot: snapshot, disabled: disabled) { select(offer) }
            }
        }
        .background(RoomTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 2))
        .compositingGroup().shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 3)
        .accessibilityElement(children: .contain).accessibilityIdentifier("marketStall_\(neighbor.id)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            CommunityPortrait(neighbor: neighbor, size: 28)
            Text(GameStrings.format("market.withNeighbor", GameStrings.text(neighbor.nameKey)))
                .font(.system(size: 13.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Text(GameStrings.text("market.today"))
                ForEach(0..<ExchangeCatalog.dailyLimit, id: \.self) { index in
                    Circle().fill(index < remaining ? RoomTheme.mint : RoomTheme.track).frame(width: 7, height: 7)
                }
                Text("\(remaining)/\(ExchangeCatalog.dailyLimit)").monospacedDigit()
            }
            .font(.system(size: 11, weight: .heavy)).foregroundStyle(remaining > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.format("market.remaining", remaining, ExchangeCatalog.dailyLimit))
            .accessibilityIdentifier("marketStallRemaining_\(neighbor.id)")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(CommunityPalette.background(neighbor).opacity(0.5))
    }
}

/// One trade on a single line: status, name, what you give → what you get, and the next step.
/// Locked offers stay slim and muted; narrow widths or large text fall back to a stacked layout.
@MainActor
struct ExchangeOfferRow: View {
    let offer: ExchangeOffer
    let snapshot: GameSnapshot
    let disabled: Bool
    let select: () -> Void
    private var failure: ActionFailure? { ExchangeCatalog.eligibility(of: offer, in: snapshot) }
    private var locked: Bool { failure == .exchangeStageRequired }
    private var muted: Bool { locked || failure == .exchangeDailyLimit }
    private var statusTint: Color {
        failure == nil ? RoomTheme.darkMint : failure == .exchangeMaterialsRequired || failure == .shopInventoryFull
            ? ExchangePalette.goldInk : RoomTheme.secondary
    }
    private var statusSymbol: String {
        failure == nil ? "checkmark.circle.fill" : locked ? "lock.fill"
            : failure == .exchangeDailyLimit ? "moon.fill" : "exclamationmark.circle.fill"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { title(lineLimit: 1); Spacer(minLength: 6); trade(named: true); action(lineLimit: 1) }
            HStack(spacing: 10) { title(lineLimit: 1); Spacer(minLength: 6); trade(named: false); action(lineLimit: 1) }
            VStack(alignment: .leading, spacing: 8) {
                title(lineLimit: nil)
                ViewThatFits(in: .horizontal) {
                    trade(named: true)
                    trade(named: false)
                }
                action(lineLimit: nil)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, locked ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(failure == nil ? RoomTheme.paleMint.opacity(0.45) : .clear)
        .opacity(muted ? 0.74 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marketCard_\(offer.id)")
    }

    private func title(lineLimit: Int?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol).font(.system(size: locked ? 11 : 13, weight: .heavy))
                .foregroundStyle(statusTint).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(GameStrings.text(offer.nameKey)).font(.system(size: locked ? 12.5 : 13.5, weight: .heavy))
                    .foregroundStyle(locked ? RoomTheme.secondary : RoomTheme.ink)
                Text(ExchangePresentation.status(offer, snapshot: snapshot)).font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(statusTint).accessibilityIdentifier("marketStatus_\(offer.id)")
            }
            .lineLimit(lineLimit).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trade(named: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(offer.inputs.enumerated()), id: \.offset) { _, stack in chip(stack, receiving: false, named: named) }
            Image(systemName: "arrow.right").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(RoomTheme.mint, in: Circle()).accessibilityHidden(true)
            ForEach(Array(offer.outputs.enumerated()), id: \.offset) { _, stack in chip(stack, receiving: true, named: named) }
        }
        .fixedSize()
    }

    private func chip(_ stack: ExchangeStack, receiving: Bool, named: Bool) -> some View {
        let owned = receiving ? nil : stack.item.count(in: snapshot.inventory)
        let quantity = ExchangePresentation.quantity(stack)
        return HStack(spacing: 4) {
            ExchangeItemIcon(item: stack.item, size: locked ? 18 : 22)
            Text(named ? quantity : "×\(stack.quantity)").font(.system(size: 11.5, weight: .heavy)).lineLimit(1)
                .accessibilityLabel(GameStrings.text(receiving ? "market.receiveShort" : "market.giveShort") + " " + quantity)
            if let owned, !locked {
                Text(GameStrings.format("market.stockShort", owned)).font(.system(size: 9.5, weight: .heavy)).lineLimit(1)
                    .foregroundStyle(owned >= stack.quantity ? RoomTheme.secondary : .white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(owned >= stack.quantity ? RoomTheme.track : RoomTheme.coralDeep, in: Capsule())
                    .accessibilityIdentifier("marketInputStock_\(ExchangePresentation.stockID(stack.item))")
                    .accessibilityValue("\(owned)")
            }
        }
        .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 3)
        .background(receiving ? ExchangePalette.receive : RoomTheme.cream, in: Capsule())
        .overlay(Capsule().strokeBorder(receiving ? ExchangePalette.goldBorder : .clear, lineWidth: 1.5))
        .help(quantity)
        .accessibilityElement(children: .contain)
    }

    private func action(lineLimit: Int?) -> some View {
        Button(ExchangePresentation.actionTitle(offer, snapshot: snapshot), action: select)
            .font(.system(size: 11.5, weight: .heavy)).lineLimit(lineLimit)
            .fixedSize(horizontal: lineLimit != nil, vertical: true)
            .buttonStyle(ExchangeActionStyle(primary: failure == nil,
                tint: locked ? RoomTheme.friendshipDeep : ExchangePalette.goldInk, compact: true))
            .disabled(disabled || failure == .exchangeDailyLimit || failure == .exchangeMissing)
            .accessibilityIdentifier("marketOffer_\(offer.id)")
    }
}

struct ExchangeActionStyle: ButtonStyle {
    var primary = false
    var tint = ExchangePalette.goldInk
    /// Market rows use a short pill so a whole stall fits on screen.
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = compact ? 13 : 18
        configuration.label.padding(.horizontal, compact ? 11 : 12).padding(.vertical, compact ? 6 : 10)
            .frame(minHeight: compact ? 30 : 44)
            .foregroundStyle(primary ? .white : tint)
            .background {
                RoundedRectangle(cornerRadius: radius).fill(primary ? RoomTheme.mint : RoomTheme.paper)
                    .shadow(color: primary ? RoomTheme.darkMint : .clear, radius: 0, y: configuration.isPressed ? 1 : compact ? 2 : 3)
            }
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(primary ? RoomTheme.mint.opacity(0.45) : tint.opacity(0.3), lineWidth: compact ? 1.5 : 2))
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
    static func countAfterTrade(_ item: ExchangeItem, offer: ExchangeOffer, inventory: InventoryState) -> Int {
        let spent = offer.inputs.filter { $0.item == item }.reduce(0) { $0 + $1.quantity }
        let received = offer.outputs.filter { $0.item == item }.reduce(0) { $0 + $1.quantity }
        return item.count(in: inventory) - spent + received
    }
}
