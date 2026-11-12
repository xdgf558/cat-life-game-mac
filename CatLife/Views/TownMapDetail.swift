import SwiftUI
import CatGameCore

struct TownMapDetail: View {
    let store: GameStore
    let place: TownPlace
    let status: TownMapStatus
    let primaryKey: String
    let primaryIdentifier: String
    let enter: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        statusChip
                        Text(description).font(.subheadline.weight(.semibold))
                            .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                        if place == .street { neighbors }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 10) {
                            GameIconTile(asset: place.asset, symbol: place.symbol, tint: place.tint,
                                         background: place.tile, size: 52, iconScale: 0.96).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 7) { title; statusChip }
                                    VStack(alignment: .leading, spacing: 5) { title; statusChip }
                                }
                                Text(description).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if place == .street { neighbors }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .id(place)
            .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("townDetailScroll")
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 80 : place == .street ? 118 : 85)
            if dynamicTypeSize.isAccessibilitySize {
                primaryButton.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            } else { primaryButton }
        }
        .padding(12)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white, lineWidth: 3))
        .shadow(color: RoomTheme.ink.opacity(0.15), radius: 12, y: 3)
        .accessibilityElement(children: .contain).accessibilityIdentifier("townPlaceDetail")
        .accessibilityValue(place.rawValue)
    }

    private var primaryButton: some View {
        Group {
            if place.isFuture || place.isEmpty {
                Button(action: {}) { buttonLabel }.buttonStyle(SoftButtonStyle()).disabled(true)
            } else { Button(action: enter) { buttonLabel }.buttonStyle(MintButtonStyle()) }
        }.accessibilityIdentifier(primaryIdentifier)
    }

    private var title: some View {
        Text(GameStrings.text(place.titleKey)).font(.headline.weight(.heavy))
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    private var statusChip: some View {
        Text((place == .board || place == .plaza) ? status.badge(for: place, now: store.now) ?? GameStrings.text("town.open")
             : GameStrings.text(place == .adoption && !status.availableAdoptions.isEmpty
                              ? "cat.adoptionAvailable" : place.statusKey(sickCount: status.sickCount)))
            .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(place.isFuture ? RoomTheme.lilac : place == .hospital && status.sickCount > 0 ? RoomTheme.coral : RoomTheme.darkMint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(place.isFuture ? TownPalette.community : RoomTheme.paleMint, in: Capsule())
    }
    private var description: String {
        if place == .hospital, status.sickCount > 0 { return GameStrings.format("town.hospitalAttention", status.sickCount) }
        if place == .home { return GameStrings.format("town.homeDescription", store.homeDisplayName) }
        return GameStrings.text(place.descriptionKey)
    }
    @ViewBuilder private var buttonLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(GameStrings.text(primaryKey)).font(.body.weight(.heavy)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
        } else {
            Label(GameStrings.text(primaryKey), systemImage: place.symbol)
                .font(.body.weight(.heavy)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var neighbors: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                ForEach(CommunityCatalog.neighbors) { neighbor in
                    let unvisited = status.unvisitedNeighbors.contains { $0.id == neighbor.id }
                    CommunityPortrait(neighbor: neighbor, size: 32).opacity(unvisited ? 1 : 0.65)
                        .overlay(alignment: .topTrailing) {
                            if unvisited { Circle().fill(RoomTheme.mint).frame(width: 9, height: 9).overlay(Circle().stroke(.white, lineWidth: 2)) }
                        }
                        .accessibilityHidden(false)
                        .accessibilityLabel(GameStrings.text(neighbor.nameKey))
                        .accessibilityValue(GameStrings.text(unvisited ? "townMap.notVisited" : "townMap.visited"))
                }
                Spacer(minLength: 0)
            }
            Text(GameStrings.text("townMap.visitDots")).font(.caption2.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
        }
    }
}
