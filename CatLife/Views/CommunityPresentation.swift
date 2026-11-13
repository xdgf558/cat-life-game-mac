import SwiftUI
import CatGameCore

enum CommunityPalette {
    static func tint(_ neighbor: NeighborDefinition) -> Color {
        switch neighbor.id {
        case "neighbor_mira": RoomTheme.coralDeep
        case "neighbor_ken": Color(red: 0.23, green: 0.51, blue: 0.66)
        case "neighbor_luna": RoomTheme.lilac
        default: RoomTheme.darkMint
        }
    }
    static func background(_ neighbor: NeighborDefinition) -> Color {
        tint(neighbor).opacity(0.16)
    }
    static func giftTint(_ gift: CommunityGift) -> Color {
        switch gift.id {
        case "flower": RoomTheme.coral
        case "drink": RoomTheme.sky
        case "dessert": RoomTheme.lilac
        default: RoomTheme.gold
        }
    }
}

struct CommunityPortrait: View {
    let neighbor: NeighborDefinition
    var size: CGFloat = 64
    var body: some View {
        Image(neighbor.portraitAssetName).resizable().scaledToFill()
            .frame(width: size, height: size).clipped()
            .background(CommunityPalette.background(neighbor))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(.white, lineWidth: 3))
            .accessibilityHidden(true)
    }
}

struct CommunityHeader: View {
    let title: String
    let backTitle: String
    let gold: Int
    var symbol = "house.fill"
    var backID = "communityBackButton"
    var disabled = false
    let back: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { backButton; Spacer(minLength: 8); wallet }
                    plaque
                }
            } else {
                HStack(spacing: 10) { backButton; plaque; Spacer(minLength: 0); wallet }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        .foregroundStyle(RoomTheme.ink).background(RoomTheme.cream)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    private var backButton: some View {
        Button(action: back) {
            Label(GameStrings.text(backTitle), systemImage: "chevron.left")
                .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).frame(minHeight: 44).gameCard(cornerRadius: 24)
        }.buttonStyle(.plain).disabled(disabled).accessibilityIdentifier(backID)
    }
    private var plaque: some View {
        Label(title, systemImage: symbol)
            .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(RoomTheme.wood)
                    .shadow(color: TownPalette.woodEdge, radius: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(TownPalette.woodEdge, lineWidth: 2.5))
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
    private var wallet: some View {
        Label("\(gold)", systemImage: "dollarsign.circle.fill")
            .font(.subheadline.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            .padding(.horizontal, 11).frame(minHeight: 36).gameCard(cornerRadius: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.text("resource.gold")).accessibilityValue("\(gold)")
            .accessibilityIdentifier("communityGiftBalance")
    }
}

struct CommunityStagePill: View {
    let neighbor: NeighborDefinition
    let stage: FriendshipStage
    var body: some View {
        Text(GameStrings.text(stage.nameKey)).font(.caption.weight(.heavy))
            .foregroundStyle(CommunityPalette.tint(neighbor))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(CommunityPalette.background(neighbor), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CommunityGiftIcon: View {
    let gift: CommunityGift
    var size: CGFloat = 32
    var body: some View {
        GameIcon(asset: gift.assetName, symbol: gift.symbol, size: size * 0.72,
                 tint: CommunityPalette.giftTint(gift))
            .frame(width: size, height: size)
            .background(CommunityPalette.giftTint(gift).opacity(0.17), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct CommunityFriendshipSegments: View {
    let friendship: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                GeometryReader { geometry in
                    Capsule().fill(RoomTheme.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: geometry.size.width
                                * CGFloat(min(20, max(0, friendship - index * 20))) / 20)
                        }
                }.frame(height: 8)
            }
        }.accessibilityHidden(true)
    }
}

struct CommunityFriendshipTrack: View {
    let friendship: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(CommunityCatalog.stages) { stage in
                        Label(GameStrings.text(stage.nameKey),
                              systemImage: friendship >= stage.minimumPoints ? "heart.fill" : "lock.fill")
                            .foregroundStyle(friendship >= stage.minimumPoints ? RoomTheme.friendshipDeep : RoomTheme.secondary)
                    }
                }.font(.caption.weight(.heavy))
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(CommunityCatalog.stages) { stage in
                        let reached = friendship >= stage.minimumPoints
                        VStack(spacing: 6) {
                            Image(systemName: reached ? "heart.fill" : "lock.fill")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(reached ? .white : RoomTheme.secondary)
                                .frame(width: 30, height: 30)
                                .background(reached ? RoomTheme.friendship : RoomTheme.track, in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            Text(GameStrings.text(stage.nameKey)).font(.caption2.weight(.heavy))
                                .foregroundStyle(reached ? RoomTheme.friendshipDeep : RoomTheme.secondary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity)
                    }
                }
                .background(alignment: .top) {
                    GeometryReader { geometry in
                        Capsule().fill(RoomTheme.track).overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [RoomTheme.friendshipBorder, RoomTheme.friendship],
                                                          startPoint: .leading, endPoint: .trailing))
                                .frame(width: geometry.size.width * CGFloat(min(friendship, 80)) / 80)
                        }
                    }.frame(height: 10).padding(.horizontal, 25).padding(.top, 10)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct FriendshipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 22).fill(RoomTheme.friendship)
                    .shadow(color: RoomTheme.friendshipDeep.opacity(isEnabled ? 1 : 0.15), radius: 0,
                            y: configuration.isPressed ? 1 : 4)
            }
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 2))
            .offset(y: configuration.isPressed ? 3 : 0).opacity(isEnabled ? 1 : 0.45)
    }
}

struct CommunityRewardChips: View {
    let gold: Int
    let food: Int
    let litter: Int
    let toys: Int
    private var rewards: [(String, String, Int)] {
        [("community.rewardGold", "dollarsign.circle.fill", gold), ("community.rewardFood", "takeoutbag.and.cup.and.straw.fill", food),
         ("community.rewardLitter", "sparkles", litter), ("community.rewardToys", "tennisball.fill", toys)].filter { $0.2 > 0 }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { chips }
            VStack(alignment: .leading, spacing: 5) { chips }
        }
    }
    @ViewBuilder private var chips: some View {
        ForEach(rewards, id: \.0) { item in
            Label(GameStrings.format(item.0, item.2), systemImage: item.1)
                .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoomTheme.gold.opacity(0.16), in: Capsule())
        }
    }
}
