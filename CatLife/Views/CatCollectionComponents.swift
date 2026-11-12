import SwiftUI
import CatGameCore

enum CatCollectionPalette {
    static let ready = Color(red: 0.95, green: 0.98, blue: 0.96)
    static let readyBorder = Color(red: 0.62, green: 0.84, blue: 0.75)
    static func tint(_ appearance: CatAppearance) -> Color {
        switch appearance {
        case .orange: RoomTheme.gold
        case .cow: RoomTheme.ink
        case .blue: Color(red: 0.37, green: 0.50, blue: 0.62)
        case .siamese: Color(red: 107 / 255, green: 74 / 255, blue: 54 / 255)
        case .silver: Color(red: 140 / 255, green: 152 / 255, blue: 164 / 255)
        }
    }
    static func background(_ appearance: CatAppearance) -> Color {
        switch appearance {
        case .orange: RoomTheme.gold.opacity(0.20)
        case .cow: RoomTheme.track
        case .blue: Color(red: 0.86, green: 0.90, blue: 0.94)
        case .siamese: Color(red: 243 / 255, green: 230 / 255, blue: 214 / 255)
        case .silver: Color(red: 230 / 255, green: 234 / 255, blue: 238 / 255)
        }
    }

}

enum CatCollectionBadge: Equatable {
    case available, newCompanion

    var textKey: String { self == .available ? "cat.adoptionAvailable" : "cat.adoptionNewFriend" }
    var tint: Color { self == .available ? RoomTheme.mint : RoomTheme.coral }

    static func adoption(appearance: CatAppearance, isOwned: Bool, isAvailable: Bool,
                         version: String = AppVersion.current.version) -> Self? {
        guard !isOwned else { return nil }
        if isAvailable { return .available }
        let releaseSeries = version.split(separator: ".", omittingEmptySubsequences: false).prefix(2)
        // New-companion promotion ends with the release series that introduced these coats.
        return releaseSeries == ["0", "14"] && (appearance == .siamese || appearance == .silver)
            ? .newCompanion : nil
    }
}

struct CatCollectionPortrait: View {
    let appearance: CatAppearance
    var size: CGFloat = 76
    var faded = false
    var badge: String? = nil

    var body: some View {
        GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: appearance), symbol: "cat.fill", size: size * 0.88)
            .frame(width: size, height: size)
            .background(CatCollectionPalette.background(appearance), in: Circle())
            .overlay(Circle().strokeBorder(faded ? RoomTheme.track : .white,
                                           style: StrokeStyle(lineWidth: faded ? 2 : 3, dash: faded ? [5, 4] : [])))
            .opacity(faded ? 0.6 : 1)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Image(systemName: badge).font(.system(size: size > 60 ? 14 : 11, weight: .bold))
                        .foregroundStyle(.white).frame(width: size > 60 ? 28 : 23, height: size > 60 ? 28 : 23)
                        .background(badge == "lock.fill" ? RoomTheme.secondary.opacity(0.55) : RoomTheme.mint, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2)).offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

struct CatCollectionSegments: View {
    let appearances: Set<CatAppearance>
    var body: some View {
        HStack(spacing: 6) {
            ForEach(CatAppearance.allCases, id: \.self) { appearance in
                Capsule().fill(appearances.contains(appearance) ? RoomTheme.mint : RoomTheme.track).frame(height: 8)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text("town.title"))
        .accessibilityValue("\(appearances.count)/\(CatAppearance.allCases.count)")
    }
}

struct CatCollectionCoatPill: View {
    let appearance: CatAppearance
    var body: some View {
        Text(GameStrings.text("hospital.coat.\(appearance.rawValue)"))
            .font(.system(size: 10, weight: .heavy)).foregroundStyle(CatCollectionPalette.tint(appearance))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(CatCollectionPalette.background(appearance), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CatCollectionHeader: View {
    let title: String
    let backTitle: String
    let gold: Int
    var disabled = false
    var backID = "closeSheetButton"
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(GameStrings.text(backTitle)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(.system(size: 12, weight: .heavy)).padding(.horizontal, 12)
                .frame(minHeight: 44).gameCard(cornerRadius: 24)
            }
            .buttonStyle(.plain).disabled(disabled).accessibilityIdentifier(backID)
            HStack(spacing: 5) {
                Image(systemName: "book.closed.fill").foregroundStyle(RoomTheme.darkMint)
                Text(GameStrings.text(title)).lineLimit(1).minimumScaleFactor(0.65)
            }
            .font(.system(size: 17, weight: .heavy)).padding(.horizontal, 11).frame(minHeight: 46)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(RoomTheme.wood)
                    .shadow(color: TownPalette.woodEdge, radius: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(TownPalette.woodEdge, lineWidth: 2.5))
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text(title))
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("catCollectionTitle")
            Spacer(minLength: 0)
            Label("\(gold)", systemImage: "dollarsign.circle.fill")
                .font(.system(size: 14, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 10).frame(minHeight: 36).gameCard(cornerRadius: 22)
                .accessibilityLabel(GameStrings.text("resource.gold")).accessibilityValue("\(gold)")
                .accessibilityIdentifier("catCollectionWallet")
        }
        .foregroundStyle(RoomTheme.ink).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 16)
        .background(RoomTheme.cream)
    }
}
