import SwiftUI
import CatGameCore

@MainActor
struct ExchangeResultView: View {
    let offer: ExchangeOffer
    let receipt: NeighborActionReceipt
    let friendship: Int
    let continueBrowsing: () -> Void
    let openBag: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false
    @AccessibilityFocusState private var titleFocused: Bool
    private var neighbor: NeighborDefinition? { CommunityCatalog.neighbor(id: receipt.neighborID) }
    private var hasRewards: Bool { receipt.goldAwarded + receipt.foodAwarded + receipt.litterAwarded + receipt.toyUsesAwarded > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark").font(.system(size: 38, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    .frame(width: 76, height: 76).background(RoomTheme.paleMint, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 4)).accessibilityHidden(true)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
                Text(GameStrings.text("market.successTitle")).font(.title2.weight(.heavy))
                    .accessibilityFocused($titleFocused).accessibilityAddTraits(.isHeader)
                Text(GameStrings.text("market.suppliesDeposited")).font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { outputs }
                    VStack(spacing: 8) { outputs }
                }
                if let neighbor { relationship(neighbor) }
                if let neighbor, let stage = receipt.stageReached {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(GameStrings.format("community.stageSuccessTitle", GameStrings.text(neighbor.nameKey), GameStrings.text(stage.nameKey)),
                              systemImage: "heart.fill")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                            .accessibilityIdentifier("communityStageSuccess").accessibilityValue("\(neighbor.id):\(stage.level)")
                        if hasRewards {
                            Text(GameStrings.text("community.rewardsDeposited")).font(.caption.weight(.bold))
                            CommunityRewardChips(gold: receipt.goldAwarded, food: receipt.foodAwarded,
                                litter: receipt.litterAwarded, toys: receipt.toyUsesAwarded)
                                .accessibilityElement(children: .combine).accessibilityIdentifier("communityStageRewards")
                                .accessibilityValue("\(receipt.goldAwarded):\(receipt.foodAwarded):\(receipt.litterAwarded):\(receipt.toyUsesAwarded)")
                        } else {
                            Text(GameStrings.text("community.rewardAtCapacity")).font(.caption.weight(.bold))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 2))
                }
            }.padding(16).padding(.top, 18).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("marketResult")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(spacing: 10) { actions }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(16).background(RoomTheme.cream)
            .accessibilityElement(children: .contain).accessibilityIdentifier("marketResultBar")
        }
        .onAppear {
            titleFocused = true
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.12)) { appeared = true }
        }
    }

    private var outputs: some View {
        ForEach(Array(offer.outputs.enumerated()), id: \.offset) { _, stack in
            HStack(spacing: 7) {
                ExchangeItemIcon(item: stack.item, size: 28)
                Text(ExchangePresentation.quantity(stack)).font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(ExchangePalette.receive, in: Capsule()).overlay(Capsule().strokeBorder(ExchangePalette.goldBorder, lineWidth: 2))
            .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
            .accessibilityElement(children: .combine).accessibilityIdentifier("marketReceived_\(ExchangePresentation.stockID(stack.item))")
            .accessibilityValue("\(stack.quantity)")
        }
    }
    private func relationship(_ neighbor: NeighborDefinition) -> some View {
        HStack(spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize { CommunityPortrait(neighbor: neighbor, size: 44) }
            VStack(alignment: .leading, spacing: 8) {
                Text(GameStrings.text(neighbor.nameKey) + " · " + GameStrings.text(CommunityCatalog.stage(friendship: friendship).nameKey))
                    .font(.subheadline.weight(.heavy))
                Text(receipt.friendshipGained > 0 ? GameStrings.format("market.friendshipResult", receipt.friendshipGained, friendship)
                     : GameStrings.text("community.closestStage"))
                    .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                    .accessibilityIdentifier("marketResultFriendship").accessibilityValue("\(receipt.friendshipGained):\(friendship)")
                ExchangeFriendshipBar(friendship: friendship)
                if let next = CommunityCatalog.nextStage(friendship: friendship) {
                    Text(GameStrings.format("community.nextStage", GameStrings.text(next.nameKey), next.minimumPoints - friendship))
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                }
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 20)
    }
    @ViewBuilder private var actions: some View {
        Button(GameStrings.text("market.continue"), action: continueBrowsing)
            .font(.headline.weight(.heavy)).frame(maxWidth: .infinity).buttonStyle(MintButtonStyle())
            .accessibilityIdentifier("marketResultContinue")
        Button(action: openBag) {
            Label(GameStrings.text("market.openBag"), systemImage: "backpack.fill")
                .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
        }.buttonStyle(ExchangeActionStyle()).accessibilityIdentifier("marketResultBag")
    }
}
