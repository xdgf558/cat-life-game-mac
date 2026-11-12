import SwiftUI
import CatGameCore

@MainActor
struct CommunityView: View {
    @Bindable var store: GameStore
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsGifts = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    todayCard
                    CommunityGiftEntry(store: store) { store.playNavigationSound(); showsGifts = true }
                    LazyVStack(spacing: 14) {
                        ForEach(CommunityCatalog.neighbors) { neighbor in
                            NavigationLink(value: neighbor.id) { card(neighbor) }
                                .buttonStyle(.plain).accessibilityIdentifier("neighborCard_\(neighbor.id)")
                        }
                    }
                }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize).background(RoomTheme.cream)
            .accessibilityIdentifier("communityDirectory")
            .safeAreaInset(edge: .top, spacing: 0) {
                CommunityHeader(title: GameStrings.text("community.title"), backTitle: "tab.town",
                                gold: store.snapshot?.player.gold ?? 0, back: onClose)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                NeighborDetailView(store: store, neighborID: id).toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(isPresented: $showsGifts) {
                CommunityGiftView(store: store, onClose: { showsGifts = false })
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
    }

    private var todayCard: some View {
        let count = store.snapshot?.community.dailyVisitCount ?? 0
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(RoomTheme.track, lineWidth: 7)
                Circle().trim(from: 0, to: CGFloat(count) / CGFloat(max(1, CommunityCatalog.neighbors.count)))
                    .stroke(RoomTheme.friendship, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(count)/\(CommunityCatalog.neighbors.count)").font(.system(size: 17, weight: .heavy))
                    Text(GameStrings.text("community.visitsShort")).font(.system(size: 10, weight: .bold))
                }
            }.frame(width: 52, height: 52).padding(4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(GameStrings.text("community.subtitle")).font(.subheadline.weight(.heavy))
                Text(GameStrings.format("community.dailyHintShort", CommunityCatalog.visitFriendship,
                                        CommunityCatalog.dailyGiftLimit))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 26)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GameStrings.format("community.visitsToday", count, CommunityCatalog.neighbors.count)
                            + ". " + GameStrings.text("community.subtitle") + " " + GameStrings.text("community.dailyHint"))
        .accessibilityIdentifier("communityVisitsToday")
    }

    private func card(_ neighbor: NeighborDefinition) -> some View {
        let relationship = store.snapshot?.community.relationship(for: neighbor.id) ?? NeighborRelationship()
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { portrait(neighbor, relationship); cardDetails(neighbor, relationship) }
            } else {
                HStack(spacing: 12) { portrait(neighbor, relationship); cardDetails(neighbor, relationship) }
            }
        }
        .padding(13).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .gameCard(cornerRadius: 25)
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(
            relationship.visitedToday ? .clear : Color(red: 0.81, green: 0.90, blue: 0.85), lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityValue(status(relationship).value)
    }

    private func portrait(_ neighbor: NeighborDefinition, _ relationship: NeighborRelationship) -> some View {
        CommunityPortrait(neighbor: neighbor).overlay(alignment: .topTrailing) {
            if !relationship.visitedToday {
                Circle().fill(RoomTheme.mint).frame(width: 19, height: 19)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3)).offset(x: 3, y: -3)
            }
        }.accessibilityHidden(true)
    }

    private func cardDetails(_ neighbor: NeighborDefinition, _ relationship: NeighborRelationship) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.text(neighbor.nameKey)).font(.headline.weight(.heavy))
                    CommunityStagePill(neighbor: neighbor, stage: relationship.stage)
                }
                Spacer(minLength: 0)
                Text("\(relationship.friendship)/100").font(.caption.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(RoomTheme.secondary)
                    .accessibilityLabel(GameStrings.format("community.friendshipValue", relationship.friendship))
            }
            CommunityFriendshipSegments(friendship: relationship.friendship, tint: CommunityPalette.tint(neighbor))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { visitStatus(relationship, id: neighbor.id); favorites(neighbor) }
            } else {
                HStack(spacing: 4) {
                    visitStatus(relationship, id: neighbor.id)
                    Spacer(minLength: 0)
                    favorites(neighbor)
                }
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func status(_ relationship: NeighborRelationship) -> (key: String, symbol: String, tint: Color, value: String) {
        if !relationship.visitedToday { return ("community.readyToVisit", "door.left.hand.open", RoomTheme.darkMint, "ready") }
        if relationship.remainingGiftsToday > 0 { return ("community.visitedCanGift", "gift.fill", RoomTheme.gold, "canGift") }
        return ("community.visitedToday", "checkmark.circle.fill", RoomTheme.secondary, "done")
    }
    private func visitStatus(_ relationship: NeighborRelationship, id: String) -> some View {
        let state = status(relationship)
        return Label(GameStrings.text(state.key), systemImage: state.symbol)
            .font(.caption2.weight(.bold)).foregroundStyle(state.tint)
            .accessibilityIdentifier("neighborVisitStatus_\(id)").accessibilityValue(state.value)
    }
    private func favorites(_ neighbor: NeighborDefinition) -> some View {
        HStack(spacing: 3) {
            Text(GameStrings.text("community.likesShort")).font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            ForEach(neighbor.favoriteGiftIDs.compactMap(CommunityCatalog.gift)) { gift in
                CommunityGiftIcon(gift: gift, size: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text("community.favoriteGifts") + ": " + neighbor.favoriteGiftIDs
            .compactMap(CommunityCatalog.gift).map { GameStrings.text($0.nameKey) }.joined(separator: ", "))
    }
}
