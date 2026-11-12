import SwiftUI

struct TownPlot: View {
    let place: TownPlace
    let selected: Bool
    let inLayer: Bool
    let badge: String?
    let badgeTint: Color
    var showsActivityDot = false
    let animates: Bool
    let action: () -> Void
    @State private var lift: CGFloat = 0
    @State private var pulse = false
    private var size: CGFloat { TownMapLayout.frame(for: place).width }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                if selected {
                    Ellipse().fill(RoomTheme.gold.opacity(0.28))
                        .frame(width: size * 0.82, height: 28)
                        .blur(radius: 8).offset(y: -24)
                }
                GameIcon(asset: place.asset, symbol: place.symbol, size: size, tint: place.tint)
                    .saturation(place.isFuture ? 0.4 : 1).opacity(place.isFuture ? 0.63 : 1)
                    .offset(y: -24 + lift)
                if place.isFuture { constructionFence.offset(y: -33) }
                Label(GameStrings.text(place.titleKey), systemImage: place.symbol)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .foregroundStyle(place.isFuture ? RoomTheme.lilac : RoomTheme.ink)
                    .background(selected ? Color(red: 1, green: 0.91, blue: 0.65)
                                : place.isFuture ? TownPalette.community : RoomTheme.paper,
                                in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(selected ? RoomTheme.gold : .white, lineWidth: 2))
                    .shadow(color: TownPalette.woodEdge.opacity(0.5), radius: 0, y: 3)
                    .padding(.horizontal, 2)
                if let badge {
                    HStack(spacing: 4) {
                        if showsActivityDot {
                            Circle().fill(RoomTheme.coralDeep).frame(width: 7, height: 7)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5)).accessibilityHidden(true)
                        }
                        Text(badge)
                    }.font(.system(size: 11, weight: .heavy, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(badgeTint, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                        .background {
                            if place == .hospital, animates {
                                Capsule().stroke(badgeTint.opacity(pulse ? 0 : 0.5), lineWidth: 3)
                                    .scaleEffect(pulse ? 1.15 : 1)
                            }
                        }
                        .frame(maxWidth: size - 8, maxHeight: .infinity,
                               alignment: TownMapLayout.frame(for: place).midX > 200 ? .topLeading : .topTrailing)
                        .offset(y: -2)
                }
            }
            .frame(width: size, height: size + 24)
            .opacity(inLayer ? 1 : 0.35).saturation(inLayer ? 1 : 0.2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(place.accessibilityIdentifier)
        .accessibilityLabel(GameStrings.text(place.titleKey))
        .accessibilityValue(badge ?? GameStrings.text(place.statusKey(sickCount: 0)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: selected && animates) {
            guard selected && animates else { lift = 0; return }
            withAnimation(.easeOut(duration: 0.18)) { lift = -7 }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { lift = 0; return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { lift = 0 }
        }
        .onChange(of: animates && place == .hospital && badge != nil, initial: true) { _, active in
            if active {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            } else { var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { pulse = false; lift = 0 }
            }
        }
    }

    private var constructionFence: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(RoomTheme.gold)
            ForEach(0..<6) { _ in
                Rectangle().fill(RoomTheme.lilac.opacity(0.65)).frame(width: 9, height: 15)
                    .rotationEffect(.degrees(25))
            }
        }
        .font(.system(size: 17)).padding(.horizontal, 4)
        .frame(height: 19).background(RoomTheme.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}
