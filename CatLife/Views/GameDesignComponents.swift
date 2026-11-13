import SwiftUI

extension View {
    func gameCard(cornerRadius: CGFloat = 24) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius).fill(RoomTheme.paper)
                .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
        }
        .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white, lineWidth: 2) }
    }
}

struct GameIconTile: View {
    var asset: String = ""
    let symbol: String
    let tint: Color
    let background: Color
    var size: CGFloat = 48
    var iconScale: CGFloat = 0.58

    var body: some View {
        GameIcon(asset: asset, symbol: symbol, size: size * iconScale, tint: tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.32))
            .accessibilityHidden(true)
    }
}

struct GamePageHeading: View {
    let title: String
    var subtitle: String? = nil
    var asset: String = ""
    let symbol: String
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 10) {
            GameIconTile(asset: asset, symbol: symbol, tint: tint, background: background)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 26, weight: .heavy, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12, weight: .bold))
                        .foregroundStyle(RoomTheme.secondary)
                }
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct GameStatRing: View {
    let value: Int
    let title: String
    var size: CGFloat = 48

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(RoomTheme.track, lineWidth: 7)
                Circle().trim(from: 0, to: CGFloat(min(100, max(0, value))) / 100)
                    .stroke(value < 50 ? RoomTheme.coral : RoomTheme.mint,
                            style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Text("\(value)").font(.system(size: 17, weight: .heavy)).monospacedDigit()
            }
            .frame(width: size, height: size)
            Text(title).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue("\(value)/100")
    }
}
