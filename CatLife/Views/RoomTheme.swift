import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

extension EquipmentItem {
    /// The first upgrade tier shares the existing slot artwork.
    var displayAssetName: String {
        switch slot {
        case .head: "gear-starter-cap"
        case .body: "gear-starter-jacket"
        case .feet: "gear-starter-sneakers"
        case .accessory: "gear-starter-charm"
        }
    }
}

enum RoomTheme {
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.89)
    static let paper = Color(red: 1.0, green: 0.98, blue: 0.94)
    static let mint = Color(red: 0.20, green: 0.68, blue: 0.54)
    static let darkMint = Color(red: 0.08, green: 0.48, blue: 0.37)
    static let paleMint = Color(red: 0.86, green: 0.92, blue: 0.82)
    static let ink = Color(red: 0.38, green: 0.24, blue: 0.15)
    static let secondary = Color(red: 0.51, green: 0.38, blue: 0.27)
    static let wood = Color(red: 0.94, green: 0.79, blue: 0.57)
    static let coral = Color(red: 0.85, green: 0.44, blue: 0.31)
    static let coralDeep = Color(red: 0.75, green: 0.34, blue: 0.23)
    static let paleCoral = Color(red: 0.97, green: 0.85, blue: 0.78)
    static let coralBorder = Color(red: 0.95, green: 0.73, blue: 0.65)
    static let rewardPaper = Color(red: 1, green: 0.96, blue: 0.89)
    static let rewardBorder = Color(red: 0.94, green: 0.79, blue: 0.57)
    static let sky = Color(red: 0.36, green: 0.66, blue: 0.84)
    static let lilac = Color(red: 0.54, green: 0.36, blue: 0.65)
    static let track = Color(red: 0.94, green: 0.88, blue: 0.78)
    static let chipBg = Color(red: 0.95, green: 0.89, blue: 0.80)
    static let gold = Color(red: 0.89, green: 0.61, blue: 0.12)
    static let friendship = Color(red: 232 / 255, green: 112 / 255, blue: 138 / 255)
    static let friendshipDeep = Color(red: 192 / 255, green: 79 / 255, blue: 104 / 255)
    static let friendshipPaper = Color(red: 253 / 255, green: 238 / 255, blue: 241 / 255)
    static let friendshipBorder = Color(red: 245 / 255, green: 195 / 255, blue: 206 / 255)
    static let cork = Color(red: 215 / 255, green: 180 / 255, blue: 136 / 255)
    static let letterPaper = Color(red: 1, green: 248 / 255, blue: 230 / 255)
}

struct GameIcon: View {
    var asset: String
    var symbol: String
    var size: CGFloat = 28
    var tint: Color = RoomTheme.ink

    var body: some View {
        Group {
            if !asset.isEmpty, UIImage(named: asset) != nil {
                Image(asset).resizable().scaledToFit()
                    .scaleEffect(asset == "icon-home" ? 1.2 : 1)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.8, weight: .semibold, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Keep the label inside the actual artwork, which is narrower than the space
/// available in the header. Longer names use two lines without resizing the room.
struct HomeNamePlaque: View {
    let name: String
    var height: CGFloat = 66

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, height * 1983 / 793)
            Image("wood-plaque")
                .resizable().scaledToFit()
                .frame(width: width, height: height)
                .overlay {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            Text(name)
                                .font(.system(size: 25, weight: .heavy, design: .rounded))
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 12)).foregroundStyle(RoomTheme.gold)
                        }
                        Text(name)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .lineLimit(2).minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: width * 0.76, height: height * 0.60)
                    .offset(y: height * 0.045)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

struct MintButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RoomTheme.mint)
                    .shadow(color: RoomTheme.darkMint.opacity(isEnabled ? 1 : 0.15), radius: 0, y: configuration.isPressed ? 1 : 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 2)
            }
.contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RoomTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RoomTheme.paper)
                    .shadow(color: RoomTheme.ink.opacity(0.12), radius: 0, y: configuration.isPressed ? 1 : 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.95), lineWidth: 2)
            }
.contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
