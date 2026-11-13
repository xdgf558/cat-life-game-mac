import SwiftUI
import CatGameCore

@MainActor
struct CommunityStageSuccessView: View {
    let neighbor: NeighborDefinition
    let receipt: NeighborActionReceipt
    var completionMessage: String? = nil
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @AccessibilityFocusState private var titleFocused: Bool
    private var hasRewards: Bool {
        receipt.goldAwarded + receipt.foodAwarded + receipt.litterAwarded + receipt.toyUsesAwarded > 0
    }

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            RoomTheme.ink.opacity(0.42).ignoresSafeArea().onTapGesture { }
            ScrollView {
                VStack(spacing: 18) {
                    CommunityPortrait(neighbor: neighbor, size: 110).padding(10)
                        .background(RoomTheme.friendshipBorder.opacity(0.6), in: RoundedRectangle(cornerRadius: 42))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "heart.fill").font(.title2).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(RoomTheme.friendship, in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: 3)).offset(x: 5, y: 3)
                        }.accessibilityHidden(true)
                    Text(GameStrings.text("community.relationshipUpgraded")).font(.subheadline.weight(.heavy))
                        .foregroundStyle(RoomTheme.friendshipDeep)
                    Text(GameStrings.format("community.stageSuccessTitle", GameStrings.text(neighbor.nameKey),
                                            GameStrings.text(receipt.stageReached?.nameKey ?? "community.stage.1")))
                        .font(.title2.weight(.heavy)).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                        .accessibilityIdentifier("communityStageSuccess")
                        .accessibilityValue("\(neighbor.id):\(receipt.stageReached?.level ?? 1)")
                    if let completionMessage {
                        Text(completionMessage).font(.subheadline.weight(.bold)).multilineTextAlignment(.center)
                            .accessibilityIdentifier("communityStageCompletionMessage")
                    }
                    if hasRewards {
                        CommunityRewardChips(gold: receipt.goldAwarded, food: receipt.foodAwarded,
                                             litter: receipt.litterAwarded, toys: receipt.toyUsesAwarded)
                            .accessibilityElement(children: .combine).accessibilityIdentifier("communityStageRewards")
                            .accessibilityValue("\(receipt.goldAwarded):\(receipt.foodAwarded):\(receipt.litterAwarded):\(receipt.toyUsesAwarded)")
                        Text(GameStrings.text("community.rewardsDeposited")).font(.caption.weight(.bold))
                            .foregroundStyle(RoomTheme.secondary)
                    } else {
                        Text(GameStrings.text("community.rewardAtCapacity")).font(.caption.weight(.bold))
                            .foregroundStyle(RoomTheme.secondary)
                    }
                    Button(action: close) {
                        Text(GameStrings.text("community.stageSuccessDone")).font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("communityStageSuccessDoneButton")
                }
                .fixedSize(horizontal: false, vertical: true).padding(24)
                .frame(maxWidth: 420).gameCard(cornerRadius: 30)
                .padding(22).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("communityStageSuccessScroll")
            .scaleEffect(appeared || reduceMotion ? 1 : 0.95)
        }
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            titleFocused = true
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.12)) { appeared = true }
        }
    }
}
