import SwiftUI
import CatGameCore

@MainActor
struct ExchangeConfirmationView: View {
    let offer: ExchangeOffer
    let snapshot: GameSnapshot
    let isWorking: Bool
    let failed: Bool
    let hasSaveFailure: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var eligible: Bool { ExchangeCatalog.eligibility(of: offer, in: snapshot) == nil }
    private var friendship: Int { snapshot.community.relationship(for: offer.neighborID).friendship }
    private var afterFriendship: Int { ExchangePresentation.friendshipAfterTrade(friendship) }
    private var remaining: Int { snapshot.community.exchangeCount(for: offer.neighborID).remainingToday }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let neighbor = CommunityCatalog.neighbor(id: offer.neighborID) {
                    HStack(spacing: 12) {
                        CommunityPortrait(neighbor: neighbor, size: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(GameStrings.text("market.confirmTitle")).font(.title3.weight(.heavy))
                            Text(GameStrings.format("market.withNeighbor", GameStrings.text(neighbor.nameKey)) + " · " + GameStrings.text(offer.nameKey))
                                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    items(offer.inputs, receiving: false)
                    Divider().overlay(RoomTheme.track)
                    items(offer.outputs, receiving: true)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 24)
                friendshipPreview
                if !eligible {
                    Text(ExchangePresentation.status(offer, snapshot: snapshot))
                        .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("marketConfirmationStatus")
                }
                Text(GameStrings.text("market.confirmHint"))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                if failed {
                    Label(GameStrings.text(hasSaveFailure ? "market.saveFailed" : "market.actionFailed"), systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("marketFailure")
                }
            }.padding(16).padding(.top, 12).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("marketConfirmation")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 9) {
                Button(action: confirm) {
                    Label(GameStrings.text(isWorking ? "common.saving" : "market.confirm"), systemImage: "arrow.left.arrow.right")
                        .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).disabled(isWorking || !eligible).accessibilityIdentifier("marketConfirmButton")
                Button(GameStrings.text("market.reconsider"), action: cancel)
                    .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).buttonStyle(SoftButtonStyle())
                    .disabled(isWorking).accessibilityIdentifier("marketCancelButton")
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6).background(RoomTheme.cream)
            .accessibilityElement(children: .contain).accessibilityIdentifier("marketConfirmationBar")
        }
    }

    private func items(_ stacks: [ExchangeStack], receiving: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(GameStrings.text(receiving ? "market.receive" : "market.give"),
                  systemImage: receiving ? "plus.circle.fill" : "minus.circle.fill")
                .font(.subheadline.weight(.heavy)).foregroundStyle(receiving ? RoomTheme.darkMint : RoomTheme.coralDeep)
            ForEach(Array(stacks.enumerated()), id: \.offset) { _, stack in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { itemLabel(stack); change(stack.item, receiving: receiving) }
                } else {
                    HStack(spacing: 8) { itemLabel(stack); Spacer(minLength: 0); change(stack.item, receiving: receiving) }
                }
            }
        }
    }
    private func itemLabel(_ stack: ExchangeStack) -> some View {
        HStack(spacing: 9) {
            ExchangeItemIcon(item: stack.item, size: 34)
            Text(ExchangePresentation.quantity(stack)).font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func change(_ item: ExchangeItem, receiving: Bool) -> some View {
        let before = item.count(in: snapshot.inventory)
        let after = ExchangePresentation.countAfterTrade(item, offer: offer, inventory: snapshot.inventory)
        return HStack(spacing: 4) {
            Text(GameStrings.format("market.bagBefore", before))
                .accessibilityIdentifier("marketStock_\(ExchangePresentation.stockID(item))").accessibilityValue("\(before)")
            Image(systemName: "arrow.right").font(.caption2).accessibilityHidden(true)
            Text("\(after)").foregroundStyle(receiving ? RoomTheme.darkMint : RoomTheme.coralDeep)
                .accessibilityLabel(GameStrings.format("market.bagAfter", after))
                .accessibilityIdentifier("marketBagAfter_\(ExchangePresentation.stockID(item))").accessibilityValue("\(after)")
        }.font(.caption.weight(.heavy)).monospacedDigit().foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var friendshipPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { friendshipLabel; Spacer(minLength: 8); remainingLabel }
                VStack(alignment: .leading, spacing: 6) { friendshipLabel; remainingLabel }
            }
            ExchangeFriendshipBar(friendship: friendship, preview: afterFriendship)
        }
        .padding(13).background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 2))
    }
    private var friendshipLabel: some View {
        Label(GameStrings.format("market.friendshipPreview", friendship, afterFriendship), systemImage: "heart.fill")
            .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
            .accessibilityIdentifier("marketFriendshipPreview").accessibilityValue("\(friendship):\(afterFriendship)")
    }
    private var remainingLabel: some View {
        Text(GameStrings.format("market.remainingPreview", remaining, max(0, remaining - 1)))
            .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
            .accessibilityIdentifier("marketRemaining").accessibilityValue("\(remaining)/\(ExchangeCatalog.dailyLimit)")
    }
}

struct ExchangeFriendshipBar: View {
    let friendship: Int
    var preview: Int? = nil
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(RoomTheme.friendshipBorder.opacity(0.55))
                .overlay(alignment: .leading) {
                    Capsule().fill(RoomTheme.friendshipBorder)
                        .frame(width: geometry.size.width * CGFloat(min(100, max(0, preview ?? friendship))) / 100)
                }
                .overlay(alignment: .leading) {
                    Capsule().fill(RoomTheme.friendship)
                        .frame(width: geometry.size.width * CGFloat(min(100, max(0, friendship))) / 100)
                }
        }.frame(height: 8).accessibilityHidden(true)
    }
}
