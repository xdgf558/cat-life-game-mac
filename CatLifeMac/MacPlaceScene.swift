#if os(macOS)
import SwiftUI
import CatGameCore

/// Scene art for a town place, shown above that place's page or sheet so entering a place
/// feels like walking in rather than opening a table.
///
/// Every place reads `place-<rawValue>-scene` (a wide 3:1 illustration). Until that art is
/// delivered, a placeholder built from the place's town-map building stands in. New places
/// should get their scene art before their UI.
enum MacPlaceSceneArt {
    static func asset(for place: TownPlace) -> String { "place-\(place.rawValue)-scene" }
    static func isDelivered(_ place: TownPlace) -> Bool { UIImage(named: asset(for: place)) != nil }
}

@MainActor
struct MacPlaceBanner: View {
    let store: GameStore
    let place: TownPlace
    var height: CGFloat = 150
    /// Pages reached from the town show a way back to the map; sheets already have Done.
    var onTown: (() -> Void)? = nil

    private var status: TownMapStatus { TownMapStatus(snapshot: store.snapshot) }
    private var description: String {
        place == .home ? GameStrings.format("town.homeDescription", store.homeDisplayName) : GameStrings.text(place.descriptionKey)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            backdrop
            // Keeps the text readable over any illustration.
            LinearGradient(stops: [.init(color: RoomTheme.cream.opacity(0.94), location: 0),
                                   .init(color: RoomTheme.cream.opacity(0.72), location: 0.38),
                                   .init(color: RoomTheme.cream.opacity(0), location: 0.62)],
                           startPoint: .leading, endPoint: .trailing)
                .allowsHitTesting(false)
            HStack(alignment: .center, spacing: 14) {
                // With the scene art in place the illustration already shows the building.
                if !MacPlaceSceneArt.isDelivered(place) {
                    GameIcon(asset: place.asset, symbol: place.symbol, size: 62, tint: place.tint)
                        .frame(width: 78, height: 78)
                        .background(RoomTheme.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white, lineWidth: 3))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(GameStrings.text(place.titleKey)).font(.system(size: 24, weight: .heavy, design: .rounded))
                        if let badge = status.badge(for: place, now: store.now) {
                            Text(badge).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(status.badgeTint(for: place), in: Capsule())
                        }
                    }
                    Text(description).font(.system(size: 13, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(2).frame(maxWidth: 420, alignment: .leading)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .overlay(alignment: .topTrailing) {
            if let onTown {
                Button(action: onTown) {
                    Label(GameStrings.text("place.backToTown"), systemImage: "map.fill")
                        .font(.system(size: 12.5, weight: .heavy)).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoomTheme.paper.opacity(0.95), in: Capsule())
                }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).padding(12)
                    .accessibilityIdentifier("macPlaceBackToTown")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
        .compositingGroup().shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macPlaceBanner_\(place.rawValue)")
    }

    @ViewBuilder private var backdrop: some View {
        if MacPlaceSceneArt.isDelivered(place) {
            Image(MacPlaceSceneArt.asset(for: place)).resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        } else {
            placeholder
        }
    }

    /// Placeholder: the place's own colours, a lawn and its town-map building on the right.
    private var placeholder: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [place.tile.opacity(0.9), RoomTheme.paleMint.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                Ellipse().fill(Color(red: 0.74, green: 0.86, blue: 0.62).opacity(0.75))
                    .frame(width: proxy.size.width * 0.9, height: proxy.size.height * 0.55)
                    .offset(x: proxy.size.width * 0.2, y: proxy.size.height * 0.3)
                HStack(alignment: .bottom, spacing: 0) {
                    tree(size: proxy.size.height * 0.34)
                    GameIcon(asset: place.asset, symbol: place.symbol, size: proxy.size.height * 1.05, tint: place.tint)
                        .offset(y: proxy.size.height * 0.08)
                    tree(size: proxy.size.height * 0.42)
                }.padding(.trailing, proxy.size.width * 0.04)
            }
        }
    }
    private func tree(size: CGFloat) -> some View {
        Image(systemName: "tree.fill").resizable().scaledToFit().frame(width: size, height: size)
            .foregroundStyle(Color(red: 0.42, green: 0.66, blue: 0.43)).padding(.bottom, size * 0.15)
            .accessibilityHidden(true)
    }
}
#endif
